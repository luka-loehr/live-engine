import Foundation
import AppKit

actor MetadataService {
    static let shared = MetadataService()
    
    private init() {}
    
    func extractVideoID(from url: String) -> String? {
        let patterns = [
            #"(?:youtube\.com/watch\?v=|youtu\.be/)([a-zA-Z0-9_-]{11})"#,
            #"youtube\.com/embed/([a-zA-Z0-9_-]{11})"#,
            #"youtube\.com/v/([a-zA-Z0-9_-]{11})"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
               let range = Range(match.range(at: 1), in: url) {
                return String(url[range])
            }
        }
        return nil
    }
    
    func fetchTitle(for youtubeURL: String) async -> String? {
        guard var components = URLComponents(string: "https://www.youtube.com/oembed") else {
            return nil
        }
        
        components.queryItems = [
            URLQueryItem(name: "url", value: youtubeURL),
            URLQueryItem(name: "format", value: "json")
        ]
        
        guard let oembedURL = components.url else {
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: oembedURL)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let title = json["title"] as? String {
                return title
            }
        } catch {
            print("Failed to fetch title: \(error)")
        }
        
        return nil
    }
    
    func fetchThumbnail(for youtubeURL: String) async -> NSImage? {
        guard let videoID = extractVideoID(from: youtubeURL) else {
            return nil
        }
        
        let thumbnailURLs = [
            "https://img.youtube.com/vi/\(videoID)/maxresdefault.jpg",
            "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg",
            "https://img.youtube.com/vi/\(videoID)/mqdefault.jpg"
        ]
        
        for urlString in thumbnailURLs {
            if let url = URL(string: urlString) {
                do {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    if let httpResponse = response as? HTTPURLResponse,
                       httpResponse.statusCode == 200,
                       let image = NSImage(data: data) {
                        return image
                    }
                } catch {
                    continue
                }
            }
        }
        
        return nil
    }
    
    func fetchDownloadSize(for youtubeURL: String) async -> Int64? {
        do {
            let (_, _, _, size) = try await DownloadService.shared.fetchBestFormat(url: youtubeURL)
            return size
        } catch {
            print("Failed to fetch download size: \(error)")
            return nil
        }
    }
}

