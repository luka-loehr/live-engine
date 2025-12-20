import Foundation

// MARK: - Download Service (UI-only prototype)

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
                return "yt-dlp not found"
            case .downloadFailed:
                return "Download failed"
            case .parsingFailed:
                return "Parsing failed"
            case .videoTooLong:
                return "Video too long"
            case .invalidURL:
                return "Invalid URL"
            }
        }
    }
    
    func fetchBestFormat(url: String) async throws -> (formatId: String, width: Int, height: Int, filesize: Int64) {
        // No-op: UI prototype doesn't fetch formats
        throw DownloadError.ytdlpNotFound
    }
    
    func downloadVideo(url: String, formatId: String, outputPath: String, onProgress: @escaping (Double) -> Void) async throws -> URL {
        // No-op: UI prototype doesn't download videos
        throw DownloadError.ytdlpNotFound
    }

    // Legacy signature for compatibility
    func downloadVideo(url: String, formatID: String, outputURL: URL, _ onProgress: @escaping (Double) -> Void) async throws -> URL {
        // No-op: UI prototype doesn't download videos
        throw DownloadError.ytdlpNotFound
    }
    
    func checkYTDLPInstalled() async -> Bool {
        // No-op: UI prototype doesn't check for yt-dlp
        return false
    }
}
