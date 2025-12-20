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
        }
    }

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

        Task {
            await loadLibrary()
            // Restore last wallpaper if auto start is enabled
            await restoreLastWallpaperIfNeeded()
        }
    }
    
    private func updateCurrentPlayerAudio() {
        // Update audio setting on the wallpaper player
        wallpaperPlayer.setAudioEnabled(audioEnabled)
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

        self.videoEntries = entries.sorted { $0.name < $1.name }
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
        // Add to entries and sort to maintain alphabetical order
        // Wrap in MainActor.run to ensure UI updates happen on main thread
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.5)) {
                videoEntries.append(entry)
                videoEntries.sort { $0.name < $1.name }
            }
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
        
        // Configure audio before playing
        wallpaperPlayer.setAudioEnabled(audioEnabled)
        print("[WALLPAPER] Audio enabled: \(audioEnabled)")
        
        // Use LiveWallpaperPlayer to play the video
        do {
            try await wallpaperPlayer.playVideo(at: url)
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
