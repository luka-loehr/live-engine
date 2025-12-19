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
    
    func fetchBestFormat(url: String) async throws -> (id: String, height: Int, width: Int) {
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
        
        return (best.format_id, best.height ?? 0, best.width ?? 0)
    }
    
    func downloadVideo(
        url: String,
        formatID: String,
        outputURL: URL,
        onProgress: @escaping (Double) -> Void
    ) async throws {
        guard let ytdlp = findYtDlp() else { throw DownloadError.ytdlpNotFound }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlp)
        process.environment = ["PYTHONUNBUFFERED": "1"]
        
        process.arguments = [
            "-f", "\(formatID)+bestaudio/best",
            "--merge-output-format", "mp4",
            "-o", outputURL.path,
            "--no-playlist",
            "--newline",
            "--progress",
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
            throw DownloadError.downloadFailed("Process exited with code \(process.terminationStatus)")
        }
        
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw DownloadError.downloadFailed("Output file missing")
        }
    }
}

