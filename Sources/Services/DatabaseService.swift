import Foundation

// MARK: - Database Models

struct LibraryEntry: Codable, Identifiable, Equatable {
    let id: String  // YouTube video ID
    var title: String
    var addedAt: Date
    var lastPlayedAt: Date?
    var isDownloaded: Bool
    
    static func == (lhs: LibraryEntry, rhs: LibraryEntry) -> Bool {
        lhs.id == rhs.id
    }
}

struct ExploreEntry: Codable, Identifiable {
    let id: String
    let title: String
    let url: String
    var category: String?
    var lastUpdated: Date?
}

struct AppSettings: Codable {
    var audioEnabled: Bool = false
    var preferredQuality: String = "1080p"
    var autoPlay: Bool = false
}

// MARK: - Database Service (UI-only prototype)

@MainActor
class DatabaseService: ObservableObject {
    static let shared = DatabaseService()
    
    @Published var library: [LibraryEntry] = []
    @Published var explore: [ExploreEntry] = []
    @Published var settings: AppSettings = AppSettings()
    
    private init() {
        // UI-only prototype - no database operations
        // Library and explore remain empty for empty state display
    }
    
    // MARK: - Stub Methods (no-op for UI prototype)
    
    func addLibraryEntry(id: String, title: String) {
        // No-op: UI prototype doesn't persist data
    }
    
    func removeLibraryEntry(id: String) {
        // No-op: UI prototype doesn't persist data
    }
    
    func updateSettings(_ update: (inout AppSettings) -> Void) {
        update(&settings)
        // No-op: UI prototype doesn't persist settings
    }
    
    func getVideoMetadata(videoId: String) -> VideoMetadata? {
        // No-op: UI prototype doesn't fetch metadata
        return nil
    }
    
    func saveVideoMetadata(videoId: String, thumbnailPath: String? = nil, downloadSize: Int64? = nil, title: String? = nil) {
        // No-op: UI prototype doesn't save metadata
    }
    
    func isExploreCacheStale() -> Bool {
        // Always return true to show empty state
        return true
    }
    
    func updateExploreTimestamp() {
        // No-op: UI prototype doesn't update timestamps
    }
    
    func refreshExplore() {
        // No-op: UI prototype doesn't refresh data
    }
    
    func addToLibrary(id: String, title: String) {
        // No-op: UI prototype doesn't persist data
    }

    func isInLibrary(id: String) -> Bool {
        // No-op: UI prototype doesn't check library
        return false
    }

    func updateLibraryEntry(id: String, isDownloaded: Bool? = nil, lastPlayedAt: Date? = nil) {
        // No-op: UI prototype doesn't update entries
    }

    func removeFromLibrary(id: String) {
        // No-op: UI prototype doesn't remove entries
    }

    func getVideoFiles(videoId: String, includeTemporary: Bool) -> [VideoFile] {
        // No-op: UI prototype doesn't track files
        return []
    }

    func addVideoFile(videoId: String, filePath: String, fileType: String, fileSize: Int64, isTemporary: Bool) {
        // No-op: UI prototype doesn't track files
    }

    func deleteTemporaryFiles(videoId: String) {
        // No-op: UI prototype doesn't delete files
    }

    func updateVideoMetadata(videoId: String, thumbnailPath: String? = nil, downloadSize: Int64? = nil, title: String? = nil) {
        // No-op: UI prototype doesn't update metadata
    }

    // MARK: - Helper Structs

    struct VideoMetadata {
        let videoId: String
        let thumbnailPath: String?
        let downloadSize: Int64?
        let title: String?
    }

    struct VideoFile {
        let id: Int64
        let videoId: String
        let filePath: String
        let fileType: String
        let fileSize: Int64
        let createdAt: Date
        let isTemporary: Bool
    }
}
