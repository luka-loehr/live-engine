import Foundation

// MARK: - Download Service

actor DownloadService {
    static let shared = DownloadService()
    
    private init() {}
    
    enum DownloadError: LocalizedError {
        case ytdlpNotFound
        case downloadFailed
        case parsingFailed
        case videoTooLong
        case invalidURL
        
        var errorDescription: String? {
            switch self {
            case .ytdlpNotFound:
                return "yt-dlp not found. Please install yt-dlp to download videos."
            case .downloadFailed:
                return "Download failed"
            case .parsingFailed:
                return "Failed to parse video information"
            case .videoTooLong:
                return "Video too long"
            case .invalidURL:
                return "Invalid URL"
            }
        }
    }
    
    func checkYTDLPInstalled() async -> Bool {
        return await findYTDLPPath() != nil
    }
    
    func fetchBestFormat(url: String) async throws -> (formatId: String, width: Int, height: Int, filesize: Int64?) {
        guard let ytdlpPath = await findYTDLPPath() else {
            throw DownloadError.ytdlpNotFound
        }
        
        // Get format list
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        process.arguments = ["-F", "--no-warnings", url]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw DownloadError.parsingFailed
        }
        
        // Parse format list
        // Look for best video+audio combination or best single format
        // Prefer: 2160p > 1440p > 1080p > 720p
        let lines = output.components(separatedBy: .newlines)
        var bestFormat: (id: String, width: Int, height: Int, size: Int64?)? = nil
        var bestHeight = 0
        
        for line in lines {
            // Format line looks like: "701  mp4  3840x2160 2160p60  HDR   |  364.32MiB"
            if line.contains("mp4") || line.contains("webm") {
                let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 4 {
                    let formatId = parts[0]
                    
                    // Try to extract resolution
                    if let resolutionPart = parts.first(where: { $0.contains("x") }),
                       let xIndex = resolutionPart.firstIndex(of: "x"),
                       let width = Int(resolutionPart[..<xIndex]),
                       let height = Int(resolutionPart[resolutionPart.index(after: xIndex)...]) {
                        
                        // Prefer higher resolution
                        if height > bestHeight {
                            // Try to extract file size
                            var size: Int64? = nil
                            if let sizePart = parts.first(where: { $0.contains("MiB") || $0.contains("GiB") }) {
                                size = parseFileSize(sizePart)
                            }
                            
                            bestFormat = (id: formatId, width: width, height: height, size: size)
                            bestHeight = height
                        }
                    }
                }
            }
        }
        
        guard let format = bestFormat else {
            // Fallback: try to get best available format
            return try await fetchBestFormatFallback(url: url, ytdlpPath: ytdlpPath)
        }
        
        return (formatId: format.id, width: format.width, height: format.height, filesize: format.size)
    }
    
    private func fetchBestFormatFallback(url: String, ytdlpPath: String) async throws -> (formatId: String, width: Int, height: Int, filesize: Int64?) {
        // Use --dump-json to get format info
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        process.arguments = ["--dump-json", "--no-warnings", url]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let formats = json["formats"] as? [[String: Any]] else {
            throw DownloadError.parsingFailed
        }
        
        // Find best format (highest resolution)
        var bestFormat: (id: String, width: Int, height: Int, size: Int64?)? = nil
        var bestHeight = 0
        
        for format in formats {
            guard let formatId = format["format_id"] as? String,
                  let width = format["width"] as? Int,
                  let height = format["height"] as? Int else {
                continue
            }
            
            if height > bestHeight {
                let size = format["filesize"] as? Int64 ?? format["filesize_approx"] as? Int64
                bestFormat = (id: formatId, width: width, height: height, size: size)
                bestHeight = height
            }
        }
        
        guard let format = bestFormat else {
            throw DownloadError.parsingFailed
        }
        
        return (formatId: format.id, width: format.width, height: format.height, filesize: format.size)
    }
    
    private func parseFileSize(_ sizeString: String) -> Int64? {
        if let match = try? NSRegularExpression(pattern: "(\\d+\\.?\\d*)\\s*(MiB|GiB)", options: []).firstMatch(
            in: sizeString,
            options: [],
            range: NSRange(sizeString.startIndex..., in: sizeString)
        ),
        match.numberOfRanges > 2,
        let sizeRange = Range(match.range(at: 1), in: sizeString),
        let unitRange = Range(match.range(at: 2), in: sizeString),
        let sizeValue = Double(sizeString[sizeRange]) {
            let unit = String(sizeString[unitRange])
            if unit == "MiB" {
                return Int64(sizeValue * 1024 * 1024)
            } else if unit == "GiB" {
                return Int64(sizeValue * 1024 * 1024 * 1024)
            }
        }
        return nil
    }
    
    func downloadVideo(url: String, formatID: String, outputURL: URL, _ onProgress: @escaping (Double) -> Void) async throws -> URL {
        print("[DOWNLOAD] Starting download: url=\(url), format=\(formatID), output=\(outputURL.path)")
        guard let ytdlpPath = await findYTDLPPath() else {
            print("[DOWNLOAD] ERROR: yt-dlp not found")
            throw DownloadError.ytdlpNotFound
        }
        
        print("[DOWNLOAD] Using yt-dlp at: \(ytdlpPath)")
        
        // Ensure output directory exists
        try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        // Build yt-dlp command
        // Use format ID and merge video+audio if needed
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        
        // Use format selector: best video + best audio, merge to mp4
        // Limit to first 60 seconds only
        process.arguments = [
            "-f", "\(formatID)+bestaudio/best",
            "--merge-output-format", "mp4",
            "--download-sections", "*0:00-1:00",
            "--force-keyframes-at-cuts",
            "-o", outputURL.path,
            "--no-warnings",
            "--progress",
            url
        ]
        
        // Set up pipes for progress tracking
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Start process
        print("[DOWNLOAD] Executing yt-dlp command...")
        try process.run()
        
        // Monitor progress
        let fileHandle = errorPipe.fileHandleForReading
        var buffer = Data()
        
        // Read progress in background
        let progressTask = Task {
            while process.isRunning {
                let availableData = fileHandle.availableData
                if !availableData.isEmpty {
                    buffer.append(availableData)
                    if let string = String(data: buffer, encoding: .utf8) {
                        // Parse progress: [download] X.X% of YYY at ZZZ
                        if let progress = parseProgress(from: string) {
                            print("[DOWNLOAD] Progress: \(String(format: "%.1f", progress * 100))%")
                            await MainActor.run {
                                onProgress(progress)
                            }
                        }
                        // Keep only last part of buffer (in case of incomplete lines)
                        if let lastNewline = string.lastIndex(of: "\n") {
                            buffer = Data(string[string.index(after: lastNewline)...].utf8)
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            
            // Read final data
            let finalData = fileHandle.readDataToEndOfFile()
            if !finalData.isEmpty {
                buffer.append(finalData)
                if let string = String(data: buffer, encoding: .utf8),
                   let progress = parseProgress(from: string) {
                    await MainActor.run {
                        onProgress(progress)
                    }
                }
            }
        }
        
        process.waitUntilExit()
        progressTask.cancel()
        
        print("[DOWNLOAD] yt-dlp process exited with status: \(process.terminationStatus)")
        
        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            if let errorString = String(data: errorData, encoding: .utf8) {
                print("[DOWNLOAD] ERROR: yt-dlp error: \(errorString)")
            }
            throw DownloadError.downloadFailed
        }
        
        // Verify output file exists
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            print("[DOWNLOAD] ERROR: Output file not found: \(outputURL.path)")
            throw DownloadError.downloadFailed
        }
        
        // Final progress update
        await MainActor.run {
            onProgress(1.0)
        }
        
        print("[DOWNLOAD] Download completed successfully: \(outputURL.path)")
        return outputURL
    }
    
    private func parseProgress(from output: String) -> Double? {
        // Look for: [download] X.X% of YYY at ZZZ
        // Or: [download] X.X%
        let patterns = [
            "\\[download\\]\\s*(\\d+\\.?\\d*)%",
            "\\[download\\]\\s*(\\d+\\.?\\d*)%\\s*of"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.matches(in: output, options: [], range: NSRange(output.startIndex..., in: output)).last,
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: output),
               let progress = Double(output[range]) {
                return min(max(progress / 100.0, 0.0), 1.0)
            }
        }
        
        return nil
    }
    
    private func findYTDLPPath() async -> String? {
        // Check common locations
        let possiblePaths = [
            "/usr/local/bin/yt-dlp",
            "/opt/homebrew/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        // Try to find in PATH
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["yt-dlp"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty,
               FileManager.default.fileExists(atPath: path) {
                return path
            }
        } catch {
            // which command failed, continue
        }
        
        return nil
    }
}
