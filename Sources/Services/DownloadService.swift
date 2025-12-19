import Foundation

actor DownloadService {
    static let shared = DownloadService()
    
    private init() {}
    
    struct YTDLFormat: Decodable {
        let format_id: String
        let vcodec: String?
        let width: Int?
        let height: Int?
        let tbr: Double?
        let fps: Double?
        let filesize: Int64?
        
        var isVideo: Bool {
            return vcodec != "none" && width != nil
        }
    }
    
    struct YTDLInfo: Decodable {
        let formats: [YTDLFormat]
        let title: String
    }
    
    enum DownloadError: LocalizedError {
        case ytdlpNotFound
        case downloadFailed(String)
        case parsingFailed
        
        var errorDescription: String? {
            switch self {
            case .ytdlpNotFound: return "yt-dlp executable not found"
            case .downloadFailed(let msg): return "Download failed: \(msg)"
            case .parsingFailed: return "Failed to parse video information"
            }
        }
    }
    
    func findYtDlp() -> String? {
        let paths = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp",
            "\(NSHomeDirectory())/.local/bin/yt-dlp"
        ]
        
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["yt-dlp"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            return path
        }
        
        return nil
    }
    
    func fetchBestFormat(url: String) async throws -> (id: String, height: Int, width: Int, size: Int64?) {
        guard let ytdlp = findYtDlp() else { throw DownloadError.ytdlpNotFound }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlp)
        process.arguments = ["-J", url]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw DownloadError.parsingFailed
        }
        
        let info = try JSONDecoder().decode(YTDLInfo.self, from: data)
        let videoFormats = info.formats.filter { $0.isVideo }
        
        guard let best = videoFormats.max(by: { a, b in
            let resA = (a.width ?? 0) * (a.height ?? 0)
            let resB = (b.width ?? 0) * (b.height ?? 0)
            if resA != resB { return resA < resB }
            let fpsA = a.fps ?? 0
            let fpsB = b.fps ?? 0
            if fpsA != fpsB { return fpsA < fpsB }
            return (a.tbr ?? 0) < (b.tbr ?? 0)
        }) else {
            throw DownloadError.parsingFailed
        }
        
        // Calculate total size: video format + best audio format
        var totalSize = best.filesize ?? 0
        
        // Find best audio format
        let audioFormats = info.formats.filter { $0.vcodec == "none" }
        if let bestAudio = audioFormats.max(by: { ($0.tbr ?? 0) < ($1.tbr ?? 0) }) {
            totalSize += (bestAudio.filesize ?? 0)
        }
        
        return (best.format_id, best.height ?? 0, best.width ?? 0, totalSize > 0 ? totalSize : nil)
    }
    
    func downloadVideo(
        url: String,
        formatID: String,
        outputURL: URL,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {
        guard let ytdlp = findYtDlp() else { throw DownloadError.ytdlpNotFound }
        
        // Get the directory where temporary files might be created
        let tempDirectory = outputURL.deletingLastPathComponent()
        let initialFiles = (try? FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)) ?? []
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlp)
        process.environment = ["PYTHONUNBUFFERED": "1"]
        
        // Use format specification that ensures proper merging
        // The format string ensures video+audio are merged into mp4
        process.arguments = [
            "-f", "\(formatID)+bestaudio/best",
            "--merge-output-format", "mp4",
            "--no-mtime",  // Don't set file modification time
            "--no-playlist",
            "--newline",
            "--progress",
            "--no-warnings",  // Reduce noise in output
            "-o", outputURL.path,
            url
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        
        let fileHandle = pipe.fileHandleForReading
        var lastReportedProgress: Double = -1.0
        
        for try await line in fileHandle.bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            if trimmed.hasPrefix("[download]") {
                let pattern = #"\[download\]\s+([\d.]+)%"#
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                   match.numberOfRanges > 1,
                   let percentRange = Range(match.range(at: 1), in: trimmed) {
                    
                    let percentString = String(trimmed[percentRange])
                    if let progressValue = Double(percentString) {
                        let normalized = min(progressValue / 100.0, 1.0)
                        
                        if abs(normalized - lastReportedProgress) >= 0.01 || normalized >= 1.0 {
                            lastReportedProgress = normalized
                            onProgress(normalized)
                        }
                    }
                }
            }
        }
        
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            // Clean up any partial files
            let finalFiles = (try? FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)) ?? []
            let newFiles = finalFiles.filter { file in
                !initialFiles.contains(file) && file.lastPathComponent.contains(outputURL.deletingPathExtension().lastPathComponent)
            }
            for file in newFiles {
                try? FileManager.default.removeItem(at: file)
            }
            
            throw DownloadError.downloadFailed("Process exited with code \(process.terminationStatus)")
        }
        
        // Check if the exact output file exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            return outputURL
        }
        
        // yt-dlp might have created a file with a slightly different name
        // Check for files in the same directory that match the pattern
        let directory = outputURL.deletingLastPathComponent()
        let baseName = outputURL.deletingPathExtension().lastPathComponent
        let expectedExtension = outputURL.pathExtension
        
        if let directoryContents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            // Look for files that start with the base name and have the expected extension
            if let matchingFile = directoryContents.first(where: { file in
                let fileName = file.deletingPathExtension().lastPathComponent
                return fileName.hasPrefix(baseName) && file.pathExtension == expectedExtension
            }) {
                // If the name differs, rename it to match expected name
                if matchingFile.path != outputURL.path {
                    try? FileManager.default.moveItem(at: matchingFile, to: outputURL)
                }
                return outputURL
            }
        }
        
        throw DownloadError.downloadFailed("Output file missing after download")
    }
    
    // Helper to find temporary files created during download
    func findTemporaryFiles(in directory: URL, matching videoId: String) -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        
        // yt-dlp temporary files often have extensions like .webm, .f137, .f140, etc.
        // or are in the format videoId.extension.part
        return files.filter { file in
            let fileName = file.lastPathComponent
            // Check if it's a temporary file related to this video
            return (fileName.hasPrefix(videoId) || fileName.contains(videoId)) &&
                   (file.pathExtension == "webm" || 
                    file.pathExtension == "f137" || 
                    file.pathExtension == "f140" ||
                    file.pathExtension == "part" ||
                    fileName.contains(".part"))
        }
    }
}

