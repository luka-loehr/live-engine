import Foundation
import SQLite3

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

struct VideoFile: Identifiable {
    let id: Int64
    let videoId: String
    let filePath: String
    let fileType: String  // "video", "video_temp", "audio_temp", "thumbnail", "metadata"
    let fileSize: Int64
    let createdAt: Date
    let isTemporary: Bool
}

struct ExploreEntry: Codable, Identifiable {
    let id: String
    let title: String
    let url: String
    var category: String?
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
    private var db: OpaquePointer?
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("MacLiveWallpaper", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        
        databaseURL = appDirectory.appendingPathComponent("database.sqlite")
        
        initializeDatabase()
        loadLibrary()
        loadExplore()
        loadSettings()
        cleanupOrphanedTempFiles()
    }
    
    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
    
    // MARK: - Database Initialization
    
    private func initializeDatabase() {
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
            print("Unable to open database: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        
        createTables()
    }
    
    private func createTables() {
        // Library entries table
        let createLibraryTable = """
        CREATE TABLE IF NOT EXISTS library_entries (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            added_at TEXT NOT NULL,
            last_played_at TEXT,
            is_downloaded INTEGER NOT NULL DEFAULT 0
        );
        """
        
        // Video files table
        let createVideoFilesTable = """
        CREATE TABLE IF NOT EXISTS video_files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            video_id TEXT NOT NULL,
            file_path TEXT NOT NULL,
            file_type TEXT NOT NULL,
            file_size INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            is_temporary INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (video_id) REFERENCES library_entries(id) ON DELETE CASCADE,
            UNIQUE(video_id, file_path)
        );
        """
        
        // Explore entries table
        let createExploreTable = """
        CREATE TABLE IF NOT EXISTS explore_entries (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            url TEXT NOT NULL,
            category TEXT
        );
        """
        
        // Settings table
        let createSettingsTable = """
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """
        
        // Create indexes
        let createIndexes = """
        CREATE INDEX IF NOT EXISTS idx_video_files_video_id ON video_files(video_id);
        CREATE INDEX IF NOT EXISTS idx_video_files_is_temporary ON video_files(is_temporary);
        """
        
        let statements = [
            createLibraryTable,
            createVideoFilesTable,
            createExploreTable,
            createSettingsTable,
            createIndexes
        ]
        
        for statement in statements {
            var statementPtr: OpaquePointer?
            if sqlite3_prepare_v2(db, statement, -1, &statementPtr, nil) == SQLITE_OK {
                if sqlite3_step(statementPtr) != SQLITE_DONE {
                    print("Error creating table: \(String(cString: sqlite3_errmsg(db)))")
                }
            } else {
                print("Error preparing statement: \(String(cString: sqlite3_errmsg(db)))")
            }
            sqlite3_finalize(statementPtr)
        }
    }
    
    // MARK: - Persistence
    
    private func loadLibrary() {
        let query = "SELECT id, title, added_at, last_played_at, is_downloaded FROM library_entries ORDER BY added_at DESC;"
        var statement: OpaquePointer?
        
        var entries: [LibraryEntry] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let title = String(cString: sqlite3_column_text(statement, 1))
                let addedAtString = String(cString: sqlite3_column_text(statement, 2))
                let lastPlayedAtString = sqlite3_column_text(statement, 3) != nil ? String(cString: sqlite3_column_text(statement, 3)) : nil
                let isDownloaded = sqlite3_column_int(statement, 4) != 0
                
                let formatter = ISO8601DateFormatter()
                let addedAt = formatter.date(from: addedAtString) ?? Date()
                let lastPlayedAt = lastPlayedAtString.flatMap { formatter.date(from: $0) }
                
                entries.append(LibraryEntry(
                    id: id,
                    title: title,
                    addedAt: addedAt,
                    lastPlayedAt: lastPlayedAt,
                    isDownloaded: isDownloaded
                ))
            }
        } else {
            print("Error loading library: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        sqlite3_finalize(statement)
        library = entries
    }
    
    private func loadExplore() {
        let query = "SELECT id, title, url, category FROM explore_entries;"
        var statement: OpaquePointer?
        
        var entries: [ExploreEntry] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let title = String(cString: sqlite3_column_text(statement, 1))
                let url = String(cString: sqlite3_column_text(statement, 2))
                let category = sqlite3_column_text(statement, 3) != nil ? String(cString: sqlite3_column_text(statement, 3)) : nil
                
                entries.append(ExploreEntry(id: id, title: title, url: url, category: category))
            }
        }
        
        sqlite3_finalize(statement)
        
        // If no explore entries, load from bundled JSON
        if entries.isEmpty {
            loadBundledExplore()
        } else {
            explore = entries
        }
    }
    
    private func loadSettings() {
        let query = "SELECT key, value FROM settings;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let key = String(cString: sqlite3_column_text(statement, 0))
                let value = String(cString: sqlite3_column_text(statement, 1))
                
                switch key {
                case "audioEnabled":
                    settings.audioEnabled = value == "true"
                case "preferredQuality":
                    settings.preferredQuality = value
                case "autoPlay":
                    settings.autoPlay = value == "true"
                default:
                    break
                }
            }
        }
        
        sqlite3_finalize(statement)
    }
    
    private func saveSettings() {
        let deleteQuery = "DELETE FROM settings;"
        var statement: OpaquePointer?
        
        sqlite3_prepare_v2(db, deleteQuery, -1, &statement, nil)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
        
        let insertQuery = "INSERT INTO settings (key, value) VALUES (?, ?);"
        
        let settingsToSave = [
            ("audioEnabled", settings.audioEnabled ? "true" : "false"),
            ("preferredQuality", settings.preferredQuality),
            ("autoPlay", settings.autoPlay ? "true" : "false")
        ]
        
        for (key, value) in settingsToSave {
            sqlite3_prepare_v2(db, insertQuery, -1, &statement, nil)
            sqlite3_bind_text(statement, 1, key, -1, nil)
            sqlite3_bind_text(statement, 2, value, -1, nil)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }
    
    private func loadBundledExplore() {
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
            for video in json.videos {
                let entry = ExploreEntry(id: video.id, title: video.title, url: video.url)
                addExploreEntry(entry)
            }
        } catch {
            print("Failed to load bundled explore: \(error)")
        }
    }
    
    // MARK: - Library Operations
    
    func addToLibrary(id: String, title: String) {
        guard !isInLibrary(id: id) else { return }
        
        let formatter = ISO8601DateFormatter()
        let addedAtString = formatter.string(from: Date())
        
        let query = "INSERT INTO library_entries (id, title, added_at, is_downloaded) VALUES (?, ?, ?, 0);"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, id, -1, nil)
            sqlite3_bind_text(statement, 2, title, -1, nil)
            sqlite3_bind_text(statement, 3, addedAtString, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_DONE {
                loadLibrary()
            } else {
                print("Error adding to library: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
        
        sqlite3_finalize(statement)
    }
    
    func removeFromLibrary(id: String) {
        // Delete video files first (CASCADE should handle this, but being explicit)
        deleteVideoFiles(videoId: id)
        
        let query = "DELETE FROM library_entries WHERE id = ?;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, id, -1, nil)
            sqlite3_step(statement)
        }
        
        sqlite3_finalize(statement)
        loadLibrary()
    }
    
    func updateLibraryEntry(id: String, title: String? = nil, isDownloaded: Bool? = nil, lastPlayedAt: Date? = nil) {
        var updates: [String] = []
        var values: [Any] = []
        var paramIndex = 1
        
        if let title = title {
            updates.append("title = ?")
            values.append(title)
            paramIndex += 1
        }
        
        if let isDownloaded = isDownloaded {
            updates.append("is_downloaded = ?")
            values.append(isDownloaded ? 1 : 0)
            paramIndex += 1
        }
        
        if let lastPlayedAt = lastPlayedAt {
            updates.append("last_played_at = ?")
            let formatter = ISO8601DateFormatter()
            values.append(formatter.string(from: lastPlayedAt))
            paramIndex += 1
        }
        
        guard !updates.isEmpty else { return }
        
        let query = "UPDATE library_entries SET \(updates.joined(separator: ", ")) WHERE id = ?;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            var bindIndex: Int32 = 1
            for value in values {
                if let stringValue = value as? String {
                    sqlite3_bind_text(statement, bindIndex, stringValue, -1, nil)
                } else if let intValue = value as? Int {
                    sqlite3_bind_int(statement, bindIndex, Int32(intValue))
                }
                bindIndex += 1
            }
            sqlite3_bind_text(statement, bindIndex, id, -1, nil)
            
            sqlite3_step(statement)
        }
        
        sqlite3_finalize(statement)
        loadLibrary()
    }
    
    func isInLibrary(id: String) -> Bool {
        return library.contains { $0.id == id }
    }
    
    func getLibraryEntry(id: String) -> LibraryEntry? {
        return library.first { $0.id == id }
    }
    
    // MARK: - Video File Operations
    
    func addVideoFile(videoId: String, filePath: String, fileType: String, fileSize: Int64 = 0, isTemporary: Bool = false) {
        let formatter = ISO8601DateFormatter()
        let createdAtString = formatter.string(from: Date())
        
        let query = "INSERT OR REPLACE INTO video_files (video_id, file_path, file_type, file_size, created_at, is_temporary) VALUES (?, ?, ?, ?, ?, ?);"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, videoId, -1, nil)
            sqlite3_bind_text(statement, 2, filePath, -1, nil)
            sqlite3_bind_text(statement, 3, fileType, -1, nil)
            sqlite3_bind_int64(statement, 4, fileSize)
            sqlite3_bind_text(statement, 5, createdAtString, -1, nil)
            sqlite3_bind_int(statement, 6, isTemporary ? 1 : 0)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                print("Error adding video file: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
        
        sqlite3_finalize(statement)
    }
    
    func getVideoFiles(videoId: String, includeTemporary: Bool = false) -> [VideoFile] {
        let query = includeTemporary
            ? "SELECT id, video_id, file_path, file_type, file_size, created_at, is_temporary FROM video_files WHERE video_id = ?;"
            : "SELECT id, video_id, file_path, file_type, file_size, created_at, is_temporary FROM video_files WHERE video_id = ? AND is_temporary = 0;"
        
        var statement: OpaquePointer?
        var files: [VideoFile] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, videoId, -1, nil)
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let videoId = String(cString: sqlite3_column_text(statement, 1))
                let filePath = String(cString: sqlite3_column_text(statement, 2))
                let fileType = String(cString: sqlite3_column_text(statement, 3))
                let fileSize = sqlite3_column_int64(statement, 4)
                let createdAtString = String(cString: sqlite3_column_text(statement, 5))
                let isTemporary = sqlite3_column_int(statement, 6) != 0
                
                let formatter = ISO8601DateFormatter()
                let createdAt = formatter.date(from: createdAtString) ?? Date()
                
                files.append(VideoFile(
                    id: id,
                    videoId: videoId,
                    filePath: filePath,
                    fileType: fileType,
                    fileSize: fileSize,
                    createdAt: createdAt,
                    isTemporary: isTemporary
                ))
            }
        }
        
        sqlite3_finalize(statement)
        return files
    }
    
    func deleteVideoFiles(videoId: String) {
        // Get all files first to delete from disk
        let files = getVideoFiles(videoId: videoId, includeTemporary: true)
        
        // Delete from disk
        for file in files {
            try? FileManager.default.removeItem(atPath: file.filePath)
        }
        
        // Delete from database
        let query = "DELETE FROM video_files WHERE video_id = ?;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, videoId, -1, nil)
            sqlite3_step(statement)
        }
        
        sqlite3_finalize(statement)
    }
    
    func markFileAsPermanent(videoId: String, filePath: String) {
        let query = "UPDATE video_files SET is_temporary = 0 WHERE video_id = ? AND file_path = ?;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, videoId, -1, nil)
            sqlite3_bind_text(statement, 2, filePath, -1, nil)
            sqlite3_step(statement)
        }
        
        sqlite3_finalize(statement)
    }
    
    func deleteTemporaryFiles(videoId: String) {
        // Get temporary files first to delete from disk
        let tempFiles = getVideoFiles(videoId: videoId, includeTemporary: true).filter { $0.isTemporary }
        
        // Delete from disk
        for file in tempFiles {
            try? FileManager.default.removeItem(atPath: file.filePath)
        }
        
        // Delete from database
        let query = "DELETE FROM video_files WHERE video_id = ? AND is_temporary = 1;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, videoId, -1, nil)
            sqlite3_step(statement)
        }
        
        sqlite3_finalize(statement)
    }
    
    func cleanupOrphanedTempFiles() {
        // Delete temporary files older than 24 hours
        let query = """
        SELECT id, file_path FROM video_files 
        WHERE is_temporary = 1 
        AND datetime(created_at) < datetime('now', '-24 hours');
        """
        
        var statement: OpaquePointer?
        var filesToDelete: [(Int64, String)] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let filePath = String(cString: sqlite3_column_text(statement, 1))
                filesToDelete.append((id, filePath))
            }
        }
        
        sqlite3_finalize(statement)
        
        // Delete files from disk and database
        for (id, filePath) in filesToDelete {
            try? FileManager.default.removeItem(atPath: filePath)
            
            let deleteQuery = "DELETE FROM video_files WHERE id = ?;"
            sqlite3_prepare_v2(db, deleteQuery, -1, &statement, nil)
            sqlite3_bind_int64(statement, 1, id)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
        
        // Also remove database entries for files that no longer exist
        let verifyQuery = "SELECT id, file_path FROM video_files;"
        sqlite3_prepare_v2(db, verifyQuery, -1, &statement, nil)
        
        var missingFiles: [Int64] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let filePath = String(cString: sqlite3_column_text(statement, 1))
            
            if !FileManager.default.fileExists(atPath: filePath) {
                missingFiles.append(id)
            }
        }
        sqlite3_finalize(statement)
        
        for id in missingFiles {
            let deleteQuery = "DELETE FROM video_files WHERE id = ?;"
            sqlite3_prepare_v2(db, deleteQuery, -1, &statement, nil)
            sqlite3_bind_int64(statement, 1, id)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }
    
    // MARK: - Explore Operations
    
    private func addExploreEntry(_ entry: ExploreEntry) {
        let query = "INSERT OR REPLACE INTO explore_entries (id, title, url, category) VALUES (?, ?, ?, ?);"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, entry.id, -1, nil)
            sqlite3_bind_text(statement, 2, entry.title, -1, nil)
            sqlite3_bind_text(statement, 3, entry.url, -1, nil)
            if let category = entry.category {
                sqlite3_bind_text(statement, 4, category, -1, nil)
            } else {
                sqlite3_bind_null(statement, 4)
            }
            
            sqlite3_step(statement)
        }
        
        sqlite3_finalize(statement)
        loadExplore()
    }
    
    func refreshExplore() {
        loadBundledExplore()
    }
    
    // MARK: - Settings
    
    func updateSettings(_ update: (inout AppSettings) -> Void) {
        update(&settings)
        saveSettings()
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
