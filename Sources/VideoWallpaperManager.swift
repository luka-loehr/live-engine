import Foundation
import AppKit
import SwiftUI
import AVFoundation

@MainActor
class VideoWallpaperManager: ObservableObject {
    @Published var videoEntries: [VideoEntry] = []
    @Published var currentPlayingID: String? = nil
    @Published var audioEnabled: Bool {
        didSet {
            LocalStorageService.shared.updateSettings { $0.audioEnabled = audioEnabled }
            updateCurrentPlayerAudio()
            // Notify menu to update
            NotificationCenter.default.post(name: NSNotification.Name("WallpaperStateChanged"), object: nil)
        }
    }
    @Published var autoStartOnLaunch: Bool {
        didSet {
            LocalStorageService.shared.updateSettings { $0.autoStartOnLaunch = autoStartOnLaunch }
            // Only update login items if this is a user-initiated change (not during init)
            if !isInitializing {
                updateLoginItem()
            }
        }
    }
    
    private var isInitializing = true

    private let thumbnailsDirectory: URL
    private let videosDirectory: URL
    private let storage = LocalStorageService.shared

    // Use LiveWallpaperPlayer for video playback
    private let wallpaperPlayer = LiveWallpaperPlayer()
    
    init() {
        print("[VIDEO] Initializing VideoWallpaperManager...")
        // Load settings from local storage
        audioEnabled = LocalStorageService.shared.settings.audioEnabled
        autoStartOnLaunch = LocalStorageService.shared.settings.autoStartOnLaunch

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        thumbnailsDirectory = appSupport.appendingPathComponent("LiveEngine/Thumbnails", isDirectory: true)
        videosDirectory = appSupport.appendingPathComponent("LiveEngine/Videos", isDirectory: true)

        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
        print("[VIDEO] Directories initialized: thumbnails=\(thumbnailsDirectory.path), videos=\(videosDirectory.path)")

        Task { @MainActor in
            await loadLibrary()
            // Restore last wallpaper if auto start is enabled
            await restoreLastWallpaperIfNeeded()
            
            // Mark initialization as complete
            isInitializing = false
            
            // Don't update login items during init - only when user changes setting
            // Login items will be synced when user toggles the setting
        }
    }
    
    private func updateCurrentPlayerAudio() {
        // Update audio setting on the wallpaper player
        wallpaperPlayer.setAudioEnabled(audioEnabled)
    }
    
    private func updateLoginItem() {
        // Add or remove LaunchAgent plist file based on autoStartOnLaunch setting
        // Ensure we're on the main thread
        guard Thread.isMainThread else {
            Task { @MainActor in
                updateLoginItem()
            }
            return
        }
        
        let appURL = Bundle.main.bundleURL
        let appBundleIdentifier = Bundle.main.bundleIdentifier ?? "com.liveengine.app"
        let launchAgentName = "\(appBundleIdentifier).plist"
        
        // Get LaunchAgents directory
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let launchAgentsURL = homeDirectory.appendingPathComponent("Library/LaunchAgents")
        let launchAgentURL = launchAgentsURL.appendingPathComponent(launchAgentName)
        
        let fileManager = FileManager.default
        
        if autoStartOnLaunch {
            // Create LaunchAgents directory if it doesn't exist
            try? fileManager.createDirectory(at: launchAgentsURL, withIntermediateDirectories: true)
            
            // Create LaunchAgent plist
            let plist: [String: Any] = [
                "Label": appBundleIdentifier,
                "ProgramArguments": [appURL.path],
                "RunAtLoad": true
            ]
            
            if let plistData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                do {
                    try plistData.write(to: launchAgentURL)
                    print("[SETTINGS] Created LaunchAgent: \(launchAgentURL.path)")
                } catch {
                    print("[SETTINGS] Failed to write LaunchAgent file: \(error)")
                }
            } else {
                print("[SETTINGS] Failed to serialize LaunchAgent plist")
            }
        } else {
            // Remove LaunchAgent plist
            if fileManager.fileExists(atPath: launchAgentURL.path) {
                do {
                    try fileManager.removeItem(at: launchAgentURL)
                    print("[SETTINGS] Removed LaunchAgent: \(launchAgentURL.path)")
                } catch {
                    print("[SETTINGS] Failed to remove LaunchAgent: \(error)")
                }
            } else {
                print("[SETTINGS] LaunchAgent not found (already removed)")
            }
        }
    }
    
    
    // MARK: - Library Management

    func loadLibrary() async {
        print("[LIBRARY] Loading library videos...")
        // Load from local storage
        let libraryVideos = storage.getLibraryVideos()
        var entries: [VideoEntry] = []

        for video in libraryVideos {
            // Load thumbnail from local storage
            var thumbnail: NSImage? = nil
            if let thumbnailPath = video.thumbnailPath, !thumbnailPath.isEmpty {
                thumbnail = storage.loadThumbnail(videoId: video.id)
            }

            // Load video URL from download_path if downloaded
            var videoURL: URL? = nil
            if video.downloaded, let downloadPath = video.downloadPath,
               FileManager.default.fileExists(atPath: downloadPath) {
                videoURL = URL(fileURLWithPath: downloadPath)
            }

            entries.append(VideoEntry(
                id: video.id,
                name: video.title ?? video.id,
                thumbnail: thumbnail,
                videoURL: videoURL,
                isDownloaded: video.downloaded,
                isDownloading: false,
                downloadProgress: 1.0,
                downloadSize: video.downloadSize
            ))
        }

        // Load videos in saved order, or sort alphabetically if no order saved
        let orderedVideos = storage.getLibraryVideosInOrder()
        let videoMap = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        
        var orderedEntries: [VideoEntry] = []
        for video in orderedVideos {
            if let entry = videoMap[video.id] {
                orderedEntries.append(entry)
            }
        }
        
        // Add any entries that weren't in the ordered list (new videos)
        let orderedIDs = Set(orderedEntries.map { $0.id })
        for entry in entries where !orderedIDs.contains(entry.id) {
            orderedEntries.append(entry)
        }
        
        self.videoEntries = orderedEntries
        print("[LIBRARY] Loaded \(entries.count) videos into library")
    }
    
    func addVideo(from sourceURL: URL) async {
        print("[LIBRARY] Adding video from local file: \(sourceURL.path)")
        
        // Generate unique ID from file name and timestamp
        let videoID = UUID().uuidString
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            print("[LIBRARY] ERROR: Source file does not exist: \(sourceURL.path)")
            return
        }
        
        // Get file size
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64) ?? 0
        
        // Get file name without extension as title
        let fileName = sourceURL.deletingPathExtension().lastPathComponent
        
        // Copy file to videos directory, preserving original extension
        let fileExtension = sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension
        let destinationURL = videosDirectory.appendingPathComponent("\(videoID).\(fileExtension)")
        
        do {
            // Ensure destination directory exists
            try FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
            
            // Copy file
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            print("[LIBRARY] Copied video to: \(destinationURL.path)")
        } catch {
            print("[LIBRARY] ERROR: Failed to copy file: \(error)")
            return
        }
        
        // STEP 1: Immediately add video to library with placeholder
        let entry = VideoEntry(
            id: videoID,
            name: fileName,
            thumbnail: nil,
            videoURL: destinationURL,
            isDownloaded: true,
            isDownloading: false,
            downloadProgress: 1.0,
            downloadSize: fileSize
        )
        // Add to entries - append to end to maintain user's order
        // Wrap in MainActor.run to ensure UI updates happen on main thread
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.5)) {
                videoEntries.append(entry)
            }
            
            // Save the new order (with new video at the end)
            let order = videoEntries.map { $0.id }
            storage.saveLibraryOrder(order)
        }
        
        // Save to local storage immediately
        storage.saveVideo(
            videoId: videoID,
            title: fileName,
            thumbnailPath: nil,
            downloadSize: fileSize,
            addedToLibrary: true
        )
        storage.setDownloaded(videoId: videoID, path: destinationURL.path)
        
        print("[LIBRARY] Video added to library: \(videoID)")
        
        // STEP 2: Generate thumbnail in background
        Task {
            if let thumbnail = await generateThumbnail(from: destinationURL) {
                // Save thumbnail to disk
                if let thumbnailPath = self.storage.saveThumbnail(videoId: videoID, image: thumbnail) {
                    self.storage.saveVideo(
                        videoId: videoID,
                        title: nil,
                        thumbnailPath: thumbnailPath,
                        downloadSize: nil,
                        addedToLibrary: nil
                    )
                }
                
                // Update UI immediately
                if let index = self.videoEntries.firstIndex(where: { $0.id == videoID }) {
                    self.videoEntries[index].thumbnail = thumbnail
                }
                print("[LIBRARY] Thumbnail generated for: \(videoID)")
            }
        }
    }
    
    // Generate thumbnail from video file using AVFoundation
    private func generateThumbnail(from videoURL: URL) async -> NSImage? {
        let asset = AVAsset(url: videoURL)
        
        // Create image generator
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        // Get thumbnail at 1 second (or start if video is shorter)
        let duration = try? await asset.load(.duration)
        let time = min(CMTime(seconds: 1.0, preferredTimescale: 600), duration ?? CMTime.zero)
        
        do {
            let result = try await imageGenerator.image(at: time)
            let cgImage = result.image
            let size = NSSize(width: cgImage.width, height: cgImage.height)
            return NSImage(cgImage: cgImage, size: size)
        } catch {
            print("[THUMBNAIL] ERROR: Failed to generate thumbnail: \(error)")
            return nil
        }
    }
    
    func isInLibrary(videoID: String) -> Bool {
        storage.isInLibrary(videoId: videoID)
    }

    func renameEntry(_ entry: VideoEntry, newName: String) {
        guard let index = videoEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        videoEntries[index].name = newName

        // Update title in local storage
        if let video = storage.getVideo(videoId: entry.id) {
            storage.saveVideo(
                videoId: entry.id,
                title: newName,
                thumbnailPath: video.thumbnailPath,
                downloadSize: video.downloadSize,
                addedToLibrary: video.addedToLibrary
            )
        }
    }

    func deleteEntry(_ entry: VideoEntry) {
        print("[LIBRARY] Deleting video entry: \(entry.id) - \(entry.name)")

        // Stop if playing
        if currentPlayingID == entry.id {
            stopWallpaper()
        }

        // Remove from UI with animation
        Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.25)) {
                videoEntries.removeAll { $0.id == entry.id }
            }
            
            // Update saved order after deletion
            let order = videoEntries.map { $0.id }
            storage.saveLibraryOrder(order)
        }

        // Clean up files and storage in background
        Task {
            if let video = storage.getVideo(videoId: entry.id) {
                // Delete video file
                if let downloadPath = video.downloadPath {
                    try? FileManager.default.removeItem(atPath: downloadPath)
                }
            }
            storage.deleteVideo(videoId: entry.id)
            print("[LIBRARY] Deleted: \(entry.id)")
        }
    }
    
    func moveEntry(from sourceEntry: VideoEntry, to targetEntry: VideoEntry) {
        guard let sourceIndex = videoEntries.firstIndex(where: { $0.id == sourceEntry.id }),
              let targetIndex = videoEntries.firstIndex(where: { $0.id == targetEntry.id }),
              sourceIndex != targetIndex else {
            return
        }
        
        withAnimation(.easeInOut(duration: 0.25)) {
            let item = videoEntries.remove(at: sourceIndex)
            videoEntries.insert(item, at: targetIndex)
        }
        
        // Save the new order
        let order = videoEntries.map { $0.id }
        storage.saveLibraryOrder(order)
    }
    
    // MARK: - Playback
    
    // Simple function to set already-downloaded video as wallpaper
    func setWallpaper(_ entry: VideoEntry) async {
        print("[WALLPAPER] Setting wallpaper: \(entry.id)")

        // Find the video file path
        var videoPath: URL?

        if let url = entry.videoURL, FileManager.default.fileExists(atPath: url.path) {
            videoPath = url
        } else if let video = storage.getVideo(videoId: entry.id),
                  let downloadPath = video.downloadPath,
                  FileManager.default.fileExists(atPath: downloadPath) {
            videoPath = URL(fileURLWithPath: downloadPath)
        }

        guard let path = videoPath else {
            print("[WALLPAPER] ERROR: Video file not found")
            return
        }

        await playVideo(at: path, entryID: entry.id)
    }

    private func playVideo(at url: URL, entryID: String) async {
        print("[WALLPAPER] Attempting to play video: \(url.path)")
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[WALLPAPER] ERROR: Video file not found: \(url.path)")
            return
        }
        
        // Configure audio before playing - this sets the internal state
        wallpaperPlayer.setAudioEnabled(audioEnabled)
        print("[WALLPAPER] Audio enabled: \(audioEnabled)")
        
        // Use LiveWallpaperPlayer to play the video
        do {
            try await wallpaperPlayer.playVideo(at: url)
            // Ensure audio setting is applied after player is created
            wallpaperPlayer.setAudioEnabled(audioEnabled)
            currentPlayingID = entryID
            // Save last wallpaper ID
            storage.setLastWallpaperID(entryID)
            // Notify menu to update
            NotificationCenter.default.post(name: NSNotification.Name("WallpaperStateChanged"), object: nil)
            print("[WALLPAPER] Video wallpaper started successfully: \(url.lastPathComponent)")
        } catch {
            print("[WALLPAPER] ERROR: Failed to play video wallpaper: \(error.localizedDescription)")
        }
    }
    
    func stopWallpaper() {
        print("[WALLPAPER] Stopping wallpaper (current ID: \(currentPlayingID ?? "none"))")
        wallpaperPlayer.stop()
        currentPlayingID = nil
        // Clear last wallpaper ID when stopped
        storage.setLastWallpaperID(nil)
        // Notify menu to update
        NotificationCenter.default.post(name: NSNotification.Name("WallpaperStateChanged"), object: nil)
        print("[WALLPAPER] Wallpaper stopped")
    }
    
    // Restore last wallpaper if auto start is enabled
    func restoreLastWallpaperIfNeeded() async {
        guard autoStartOnLaunch else {
            print("[WALLPAPER] Auto start disabled, skipping wallpaper restoration")
            return
        }
        
        guard let lastWallpaperID = storage.getLastWallpaperID() else {
            print("[WALLPAPER] No last wallpaper found")
            return
        }
        
        // Find the entry with the last wallpaper ID
        guard let entry = videoEntries.first(where: { $0.id == lastWallpaperID }) else {
            print("[WALLPAPER] Last wallpaper entry not found: \(lastWallpaperID)")
            return
        }
        
        // Verify the video file still exists
        var videoPath: URL?
        if let url = entry.videoURL, FileManager.default.fileExists(atPath: url.path) {
            videoPath = url
        } else if let video = storage.getVideo(videoId: entry.id),
                  let downloadPath = video.downloadPath,
                  FileManager.default.fileExists(atPath: downloadPath) {
            videoPath = URL(fileURLWithPath: downloadPath)
        }
        
        guard let path = videoPath else {
            print("[WALLPAPER] Last wallpaper file not found, clearing saved ID")
            storage.setLastWallpaperID(nil)
            return
        }
        
        print("[WALLPAPER] Restoring last wallpaper: \(entry.name)")
        await playVideo(at: path, entryID: entry.id)
    }
}
