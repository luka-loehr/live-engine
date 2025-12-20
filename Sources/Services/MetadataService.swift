import Foundation
import AppKit

// MARK: - Metadata Service

class MetadataService {
    static let shared = MetadataService()
    
    private init() {}
    
    func extractVideoID(from url: String) -> String? {
        // Handle various YouTube URL formats
        let patterns = [
            "youtube\\.com/watch\\?v=([a-zA-Z0-9_-]{11})",
            "youtu\\.be/([a-zA-Z0-9_-]{11})",
            "youtube\\.com/embed/([a-zA-Z0-9_-]{11})",
            "youtube\\.com/v/([a-zA-Z0-9_-]{11})"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: url, options: [], range: NSRange(url.startIndex..., in: url)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: url) {
                return String(url[range])
            }
        }
        
        return nil
    }
    
    func fetchTitle(for youtubeURL: String) async -> String? {
        guard let ytdlpPath = await findYTDLPPath() else {
            print("yt-dlp not found")
            return nil
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        process.arguments = ["--get-title", "--no-warnings", youtubeURL]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // Suppress errors
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let title = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty {
                return title
            }
        } catch {
            print("Error fetching title: \(error)")
        }
        
        return nil
    }
    
    func fetchThumbnail(for youtubeURL: String) async -> NSImage? {
        guard let ytdlpPath = await findYTDLPPath() else {
            print("yt-dlp not found")
            return nil
        }
        
        // Extract video ID first
        guard let videoID = extractVideoID(from: youtubeURL) else {
            return nil
        }
        
        // Create temp directory for thumbnail
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("MacLiveWallpaperThumbnails")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let thumbnailPath = tempDir.appendingPathComponent("\(videoID).jpg")
        
        // Download thumbnail using yt-dlp
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        process.arguments = [
            "--skip-download",
            "--write-thumbnail",
            "--convert-thumbnails", "jpg",
            "--thumbnail-quality", "high",
            "-o", thumbnailPath.path,
            "--no-warnings",
            youtubeURL
        ]
        
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            // Try to load the thumbnail
            if FileManager.default.fileExists(atPath: thumbnailPath.path),
               let image = NSImage(contentsOf: thumbnailPath) {
                return image
            }
            
            // Sometimes yt-dlp saves with different extension, try alternatives
            let alternatives = [
                thumbnailPath.deletingPathExtension().appendingPathExtension("webp"),
                thumbnailPath.deletingPathExtension().appendingPathExtension("png")
            ]
            
            for altPath in alternatives {
                if FileManager.default.fileExists(atPath: altPath.path),
                   let image = NSImage(contentsOf: altPath) {
                    return image
                }
            }
        } catch {
            print("Error fetching thumbnail: \(error)")
        }
        
        return nil
    }
    
    func fetchDownloadSize(for youtubeURL: String) async -> Int64? {
        guard let ytdlpPath = await findYTDLPPath() else {
            print("yt-dlp not found")
            return nil
        }
        
        // First, get available formats
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        process.arguments = ["-F", "--no-warnings", youtubeURL]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return nil
            }
            
            // Parse format list to find best quality
            // Look for format lines like: "701  mp4  3840x2160 2160p60  HDR   |  364.32MiB"
            let lines = output.components(separatedBy: .newlines)
            var bestSize: Int64? = nil
            
            for line in lines {
                // Look for lines with file size (MiB or GiB)
                if line.contains("MiB") || line.contains("GiB") {
                    // Try to extract size
                    if let sizeMatch = try? NSRegularExpression(pattern: "(\\d+\\.?\\d*)\\s*(MiB|GiB)", options: []),
                       let match = sizeMatch.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)),
                       match.numberOfRanges > 2 {
                        
                        if let sizeRange = Range(match.range(at: 1), in: line),
                           let unitRange = Range(match.range(at: 2), in: line),
                           let sizeValue = Double(line[sizeRange]),
                           let unit = String(line[unitRange]) as String? {
                            
                            let bytes: Int64
                            if unit == "MiB" {
                                bytes = Int64(sizeValue * 1024 * 1024)
                            } else if unit == "GiB" {
                                bytes = Int64(sizeValue * 1024 * 1024 * 1024)
                            } else {
                                continue
                            }
                            
                            // Prefer 4K/1080p formats, take largest
                            if bestSize == nil || bytes > bestSize! {
                                bestSize = bytes
                            }
                        }
                    }
                }
            }
            
            return bestSize
        } catch {
            print("Error fetching download size: \(error)")
        }
        
        // Fallback: use dump-json to get filesize
        return await fetchDownloadSizeFromJSON(youtubeURL: youtubeURL, ytdlpPath: ytdlpPath)
    }
    
    private func fetchDownloadSizeFromJSON(youtubeURL: String, ytdlpPath: String) async -> Int64? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        process.arguments = ["--dump-json", "--no-warnings", youtubeURL]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let formats = json["formats"] as? [[String: Any]] else {
                return nil
            }
            
            // Find best format (highest resolution)
            var bestSize: Int64? = nil
            
            for format in formats {
                if let filesize = format["filesize"] as? Int64 {
                    if bestSize == nil || filesize > bestSize! {
                        bestSize = filesize
                    }
                } else if let filesizeApprox = format["filesize_approx"] as? Int64 {
                    if bestSize == nil || filesizeApprox > bestSize! {
                        bestSize = filesizeApprox
                    }
                }
            }
            
            return bestSize
        } catch {
            print("Error fetching download size from JSON: \(error)")
            return nil
        }
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
