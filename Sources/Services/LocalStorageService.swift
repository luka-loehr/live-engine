import Foundation
import AppKit

// MARK: - Local Video Models

struct LocalVideo: Identifiable, Equatable, Codable {
    let id: String  // video_id
    var title: String?
    var thumbnailPath: String?  // Local file path to thumbnail
    var downloadSize: Int64?
    var youtubeURL: String?  // Optional, not used for local files
    var addedToLibrary: Bool
    var downloaded: Bool
    var downloadPath: String?
    var downloadStatus: Double
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id = "video_id"
        case title
        case thumbnailPath = "thumbnail_path"
        case downloadSize = "download_size"
        case youtubeURL = "youtube_url"
        case addedToLibrary = "added_to_library"
        case downloaded
        case downloadPath = "download_path"
        case downloadStatus = "download_status"
        case createdAt = "created_at"
    }

    static func == (lhs: LocalVideo, rhs: LocalVideo) -> Bool {
        lhs.id == rhs.id
    }
}

struct AppSettings: Codable {
    var audioEnabled: Bool = false
    var preferredQuality: String = "1080p"
    var autoPlay: Bool = false
}

// MARK: - Local Storage Service

@MainActor
class LocalStorageService: ObservableObject {
    static let shared = LocalStorageService()

    @Published var settings: AppSettings = AppSettings()

    // In-memory cache
    private var videoCache: [String: LocalVideo] = [:]
    private var libraryVideosCache: [LocalVideo] = []

    private let videosKey = "MacLiveWallpaper.videos"
    private let settingsKey = "MacLiveWallpaper.settings"
    private let thumbnailsDirectory: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        thumbnailsDirectory = appSupport.appendingPathComponent("MacLiveWallpaper/Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)

        loadSettings()
        loadVideos()
    }

    // MARK: - Settings

    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decodedSettings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decodedSettings
        }
    }

    func updateSettings(_ update: (inout AppSettings) -> Void) {
        update(&settings)
        saveSettings()
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    // MARK: - Video Operations

    func saveVideo(
        videoId: String,
        title: String? = nil,
        thumbnailPath: String? = nil,
        downloadSize: Int64? = nil,
        youtubeURL: String? = nil,
        addedToLibrary: Bool? = nil
    ) {
        let existingVideo = videoCache[videoId]

        // Build updated video
        let updatedVideo = LocalVideo(
            id: videoId,
            title: title ?? existingVideo?.title,
            thumbnailPath: thumbnailPath ?? existingVideo?.thumbnailPath,
            downloadSize: downloadSize ?? existingVideo?.downloadSize,
            youtubeURL: youtubeURL ?? existingVideo?.youtubeURL,
            addedToLibrary: addedToLibrary ?? existingVideo?.addedToLibrary ?? false,
            downloaded: existingVideo?.downloaded ?? false,
            downloadPath: existingVideo?.downloadPath,
            downloadStatus: existingVideo?.downloadStatus ?? 0.0,
            createdAt: existingVideo?.createdAt ?? Date()
        )

        videoCache[videoId] = updatedVideo

        if updatedVideo.addedToLibrary {
            if !libraryVideosCache.contains(where: { $0.id == videoId }) {
                libraryVideosCache.append(updatedVideo)
            }
        } else {
            libraryVideosCache.removeAll { $0.id == videoId }
        }

        saveVideos()
    }

    func getVideo(videoId: String) -> LocalVideo? {
        return videoCache[videoId]
    }

    func getAllVideos() -> [LocalVideo] {
        return Array(videoCache.values)
    }

    func getLibraryVideos() -> [LocalVideo] {
        return libraryVideosCache
    }

    func addToLibrary(videoId: String) {
        if var video = videoCache[videoId] {
            video.addedToLibrary = true
            videoCache[videoId] = video
            if !libraryVideosCache.contains(where: { $0.id == videoId }) {
                libraryVideosCache.append(video)
            }
            saveVideos()
        }
    }

    func removeFromLibrary(videoId: String) {
        if var video = videoCache[videoId] {
            video.addedToLibrary = false
            videoCache[videoId] = video
            libraryVideosCache.removeAll { $0.id == videoId }
            saveVideos()
        }
    }

    func isInLibrary(videoId: String) -> Bool {
        return videoCache[videoId]?.addedToLibrary ?? false
    }

    func updateDownloadStatus(videoId: String, progress: Double) {
        if var video = videoCache[videoId] {
            video.downloadStatus = progress
            videoCache[videoId] = video
            saveVideos()
        }
    }

    func setDownloaded(videoId: String, path: String) {
        if var video = videoCache[videoId] {
            video.downloaded = true
            video.downloadPath = path
            video.downloadStatus = 1.0
            videoCache[videoId] = video
            saveVideos()
        }
    }

    func setNotDownloaded(videoId: String) {
        if var video = videoCache[videoId] {
            video.downloaded = false
            video.downloadPath = nil
            video.downloadStatus = 0.0
            videoCache[videoId] = video
            saveVideos()
        }
    }

    func deleteVideo(videoId: String) {
        // Delete thumbnail file if exists
        if let video = videoCache[videoId],
           let thumbnailPath = video.thumbnailPath,
           FileManager.default.fileExists(atPath: thumbnailPath) {
            try? FileManager.default.removeItem(atPath: thumbnailPath)
        }

        videoCache.removeValue(forKey: videoId)
        libraryVideosCache.removeAll { $0.id == videoId }
        saveVideos()
    }

    // MARK: - Thumbnail Storage

    func saveThumbnail(videoId: String, image: NSImage) -> String? {
        let thumbnailPath = thumbnailsDirectory.appendingPathComponent("\(videoId).jpg").path

        // Convert NSImage to JPEG data
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return nil
        }

        do {
            try jpegData.write(to: URL(fileURLWithPath: thumbnailPath))
            return thumbnailPath
        } catch {
            print("Error saving thumbnail: \(error)")
            return nil
        }
    }

    func loadThumbnail(videoId: String) -> NSImage? {
        let thumbnailPath = thumbnailsDirectory.appendingPathComponent("\(videoId).jpg").path
        return NSImage(contentsOfFile: thumbnailPath)
    }

    // MARK: - Persistence

    private func loadVideos() {
        if let data = UserDefaults.standard.data(forKey: videosKey),
           let decodedVideos = try? JSONDecoder().decode([String: LocalVideo].self, from: data) {
            videoCache = decodedVideos
            libraryVideosCache = videoCache.values.filter { $0.addedToLibrary }
        }
    }

    private func saveVideos() {
        if let data = try? JSONEncoder().encode(videoCache) {
            UserDefaults.standard.set(data, forKey: videosKey)
        }
    }
}
