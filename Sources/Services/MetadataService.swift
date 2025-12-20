import Foundation
import AppKit

// MARK: - Metadata Service (UI-only prototype)

actor MetadataService {
    static let shared = MetadataService()
    
    private init() {}
    
    func extractVideoID(from url: String) -> String? {
        // No-op: UI prototype doesn't extract video IDs
        return nil
    }
    
    func fetchTitle(for youtubeURL: String) async -> String? {
        // No-op: UI prototype doesn't fetch titles
        return nil
    }
    
    func fetchThumbnail(for youtubeURL: String) async -> NSImage? {
        // No-op: UI prototype doesn't fetch thumbnails
        return nil
    }
    
    func fetchDownloadSize(for youtubeURL: String) async -> Int64? {
        // No-op: UI prototype doesn't fetch download sizes
        return nil
    }
}
