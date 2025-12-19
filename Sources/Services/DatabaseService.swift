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
}

struct DatabaseSchema: Codable {
    var version: Int = 1
    var library: [LibraryEntry] = []
    var explore: [ExploreEntry] = []
    var settings: AppSettings = AppSettings()
}

struct AppSettings: Codable {
    var audioEnabled: Bool = false
    var preferredQuality: String = "1080p"
    var autoPlay: Bool = false
}

// MARK: - Database Service

@MainActor
class DatabaseService: ObservableObject {
    static let shared = DatabaseService()
    
    @Published private(set) var library: [LibraryEntry] = []
    @Published private(set) var explore: [ExploreEntry] = []
    @Published var settings: AppSettings = AppSettings()
    
    private let databaseURL: URL
    private var schema: DatabaseSchema
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("MacLiveWallpaper", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        
        databaseURL = appDirectory.appendingPathComponent("database.json")
        schema = DatabaseSchema()
        
        load()
    }
    
    // MARK: - Persistence
    
    private func load() {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            // Load explore from bundled JSON on first run
            loadBundledExplore()
            return
        }
        
        do {
            let data = try Data(contentsOf: databaseURL)
            schema = try JSONDecoder().decode(DatabaseSchema.self, from: data)
            library = schema.library
            explore = schema.explore
            settings = schema.settings
        } catch {
            print("Failed to load database: \(error)")
            loadBundledExplore()
        }
    }
    
    private func save() {
        schema.library = library
        schema.explore = explore
        schema.settings = settings
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(schema)
            try data.write(to: databaseURL)
        } catch {
            print("Failed to save database: \(error)")
        }
    }
    
    private func loadBundledExplore() {
        // Try to load from bundled explore.json
        var jsonURL: URL?
        
        if let bundlePath = Bundle.main.path(forResource: "explore", ofType: "json") {
            jsonURL = URL(fileURLWithPath: bundlePath)
        } else {
            let paths = [
                FileManager.default.currentDirectoryPath + "/explore.json",
                "/Users/luka/Documents/mac-live/explore.json"
            ]
            for path in paths {
                if FileManager.default.fileExists(atPath: path) {
                    jsonURL = URL(fileURLWithPath: path)
                    break
                }
            }
        }
        
        guard let url = jsonURL else { return }
        
        do {
            let data = try Data(contentsOf: url)
            let json = try JSONDecoder().decode(BundledExploreJSON.self, from: data)
            explore = json.videos.map { video in
                ExploreEntry(id: video.id, title: video.title, url: video.url)
            }
            save()
        } catch {
            print("Failed to load bundled explore: \(error)")
        }
    }
    
    // MARK: - Library Operations
    
    func addToLibrary(id: String, title: String) {
        guard !isInLibrary(id: id) else { return }
        
        let entry = LibraryEntry(
            id: id,
            title: title,
            addedAt: Date(),
            lastPlayedAt: nil,
            isDownloaded: false
        )
        library.append(entry)
        save()
    }
    
    func removeFromLibrary(id: String) {
        library.removeAll { $0.id == id }
        save()
    }
    
    func updateLibraryEntry(id: String, title: String? = nil, isDownloaded: Bool? = nil, lastPlayedAt: Date? = nil) {
        guard let index = library.firstIndex(where: { $0.id == id }) else { return }
        
        if let title = title {
            library[index].title = title
        }
        if let isDownloaded = isDownloaded {
            library[index].isDownloaded = isDownloaded
        }
        if let lastPlayedAt = lastPlayedAt {
            library[index].lastPlayedAt = lastPlayedAt
        }
        save()
    }
    
    func isInLibrary(id: String) -> Bool {
        library.contains { $0.id == id }
    }
    
    func getLibraryEntry(id: String) -> LibraryEntry? {
        library.first { $0.id == id }
    }
    
    // MARK: - Explore Operations
    
    func refreshExplore() {
        loadBundledExplore()
    }
    
    // MARK: - Settings
    
    func updateSettings(_ update: (inout AppSettings) -> Void) {
        update(&settings)
        save()
    }
}

// Helper for decoding bundled explore.json
private struct BundledExploreJSON: Codable {
    let videos: [BundledExploreVideoJSON]
}

private struct BundledExploreVideoJSON: Codable {
    let id: String
    let title: String
    let url: String
}

