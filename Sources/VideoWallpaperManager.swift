import Foundation
import AppKit
import AVFoundation
import SwiftUI

@MainActor
class VideoWallpaperManager: ObservableObject {
    @Published var videoEntries: [VideoEntry] = []
    @Published var currentPlayingID: String? = nil
    @Published var audioEnabled: Bool {
        didSet {
            UserDefaults.standard.set(audioEnabled, forKey: "MacLiveWallpaper.audioEnabled")
            DatabaseService.shared.updateSettings { $0.audioEnabled = audioEnabled }
            updateCurrentPlayerAudio()
        }
    }
    
    private let thumbnailsDirectory: URL
    private let metadataDirectory: URL
    private let videosDirectory: URL
    private let db = DatabaseService.shared
    
    private var desktopWindow: DesktopWindow?
    private var player: AVPlayer?
    private var loopObserver: NSObjectProtocol?
    private var timeObserver: Any?
    
    init() {
        // Load audio setting from database/UserDefaults (default to false/muted)
        audioEnabled = DatabaseService.shared.settings.audioEnabled
        
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        thumbnailsDirectory = appSupport.appendingPathComponent("MacLiveWallpaper/Thumbnails", isDirectory: true)
        metadataDirectory = appSupport.appendingPathComponent("MacLiveWallpaper/Metadata", isDirectory: true)
        videosDirectory = appSupport.appendingPathComponent("MacLiveWallpaper/Videos", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
        
        Task {
            await loadLibrary()
        }
    }
    
    private func updateCurrentPlayerAudio() {
        guard let player = player else { return }
        
        if audioEnabled {
            player.isMuted = false
            player.volume = 1.0
            // Remove audio mix to restore normal audio
            player.currentItem?.audioMix = nil
        } else {
            player.isMuted = true
            player.volume = 0.0
            // Apply silent audio mix
            applySilentAudioMix(to: player)
        }
    }
    
    private func applySilentAudioMix(to player: AVPlayer) {
        guard let playerItem = player.currentItem else { return }
        
        let audioTracks = playerItem.tracks.compactMap { track -> AVAssetTrack? in
            guard let assetTrack = track.assetTrack, assetTrack.mediaType == .audio else { return nil }
            return assetTrack
        }
        
        if !audioTracks.isEmpty {
            let audioMix = AVMutableAudioMix()
            var inputParameters: [AVMutableAudioMixInputParameters] = []
            for track in audioTracks {
                let params = AVMutableAudioMixInputParameters(track: track)
                params.setVolume(0.0, at: CMTime.zero)
                inputParameters.append(params)
            }
            audioMix.inputParameters = inputParameters
            playerItem.audioMix = audioMix
        }
    }
    
    // MARK: - Library Management
    
    func loadLibrary() async {
        // Load from database instead of scanning filesystem
        var entries: [VideoEntry] = []
        
        for libraryEntry in db.library {
            let videoID = libraryEntry.id
            
            // Load thumbnail from database metadata or disk
            var thumbnail = await loadLocalThumbnail(for: videoID)
            
            // Load download size from database metadata
            var downloadSize: Int64? = nil
            if let metadata = db.getVideoMetadata(videoId: videoID) {
                downloadSize = metadata.downloadSize
                // Also try to load thumbnail from metadata path if not already loaded
                if thumbnail == nil, let thumbnailPath = metadata.thumbnailPath,
                   FileManager.default.fileExists(atPath: thumbnailPath) {
                    thumbnail = NSImage(contentsOfFile: thumbnailPath)
                }
            }
            
            // Get video file from database (only permanent files)
            let videoFiles = db.getVideoFiles(videoId: videoID, includeTemporary: false)
            let videoFile = videoFiles.first { $0.fileType == "video" }
            let videoURL = videoFile.map { URL(fileURLWithPath: $0.filePath) }
            
            // Verify file actually exists - sync database status if needed
            var isDownloaded = libraryEntry.isDownloaded
            if isDownloaded {
                // If database says downloaded but file doesn't exist, update database
                if let url = videoURL, !FileManager.default.fileExists(atPath: url.path) {
                    isDownloaded = false
                    db.updateLibraryEntry(id: videoID, isDownloaded: false)
                }
            } else {
                // If database says not downloaded but file exists, update database
                if let url = videoURL, FileManager.default.fileExists(atPath: url.path) {
                    isDownloaded = true
                    db.updateLibraryEntry(id: videoID, isDownloaded: true)
                }
            }
            
            entries.append(VideoEntry(
                id: videoID,
                name: libraryEntry.title,
                thumbnail: thumbnail,
                videoURL: videoURL,
                isDownloaded: isDownloaded,
                isDownloading: false,
                downloadProgress: isDownloaded ? 1.0 : 0.0,
                downloadSize: downloadSize
            ))
        }
        
        self.videoEntries = entries.sorted { $0.name < $1.name }
    }
    
    private func loadLocalThumbnail(for videoID: String) async -> NSImage? {
        let path = thumbnailsDirectory.appendingPathComponent("\(videoID).jpg")
        if FileManager.default.fileExists(atPath: path.path) {
            return NSImage(contentsOf: path)
        }
        return nil
    }
    
    private func saveThumbnail(_ image: NSImage, for videoID: String) {
        let path = thumbnailsDirectory.appendingPathComponent("\(videoID).jpg")
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
            try? jpegData.write(to: path)
            
            // Track thumbnail file in database
            let fileSize = Int64(jpegData.count)
            db.addVideoFile(
                videoId: videoID,
                filePath: path.path,
                fileType: "thumbnail",
                fileSize: fileSize,
                isTemporary: false
            )
            
            // Also save to video_metadata table
            db.updateVideoMetadata(videoId: videoID, thumbnailPath: path.path)
        }
    }
    
    private func saveTitle(_ title: String, for videoID: String) {
        let path = metadataDirectory.appendingPathComponent("\(videoID).txt")
        if let data = title.data(using: .utf8) {
            try? data.write(to: path)
            
            // Track metadata file in database
            let fileSize = Int64(data.count)
            db.addVideoFile(
                videoId: videoID,
                filePath: path.path,
                fileType: "metadata",
                fileSize: fileSize,
                isTemporary: false
            )
            
            // Also save to video_metadata table
            db.updateVideoMetadata(videoId: videoID, title: title)
        }
    }
    
    func addVideo(youtubeURL: String) async {
        guard let videoID = await MetadataService.shared.extractVideoID(from: youtubeURL) else {
            return
        }
        
        if videoEntries.contains(where: { $0.id == videoID }) {
            return
        }
        
        // Check database first for metadata
        var title: String?
        var thumbnail: NSImage?
        var downloadSize: Int64?
        
        if let metadata = db.getVideoMetadata(videoId: videoID) {
            // Load from database
            title = metadata.title
            downloadSize = metadata.downloadSize
            
            // Load thumbnail from disk if path exists
            if let thumbnailPath = metadata.thumbnailPath,
               FileManager.default.fileExists(atPath: thumbnailPath) {
                thumbnail = NSImage(contentsOfFile: thumbnailPath)
            }
        }
        
        // Fetch missing metadata from server
        if title == nil || thumbnail == nil || downloadSize == nil {
            async let titleTask = title == nil ? MetadataService.shared.fetchTitle(for: youtubeURL) : Task { title }
            async let thumbnailTask = thumbnail == nil ? MetadataService.shared.fetchThumbnail(for: youtubeURL) : Task { thumbnail }
            async let sizeTask = downloadSize == nil ? MetadataService.shared.fetchDownloadSize(for: youtubeURL) : Task { downloadSize }
            
            let (fetchedTitle, fetchedThumbnail, fetchedSize) = await (titleTask, thumbnailTask, sizeTask)
            
            if title == nil {
                title = fetchedTitle
            }
            if thumbnail == nil {
                thumbnail = fetchedThumbnail
            }
            if downloadSize == nil {
                downloadSize = fetchedSize
            }
        }
        
        let finalTitle = title ?? videoID
        
        // Create entry with metadata
        let entry = VideoEntry(
            id: videoID,
            name: finalTitle,
            thumbnail: thumbnail,
            isDownloaded: false,
            downloadSize: downloadSize
        )
        videoEntries.insert(entry, at: 0)
        
        // Save metadata to database and disk
        saveTitle(finalTitle, for: videoID)
        if let thumb = thumbnail {
            saveThumbnail(thumb, for: videoID)
        }
        
        // Save download size to metadata table (thumbnail and title are already saved by saveThumbnail/saveTitle)
        if let size = downloadSize {
            db.updateVideoMetadata(videoId: videoID, downloadSize: size)
        }
        
        // Add to database
        db.addToLibrary(id: videoID, title: finalTitle)
    }
    
    func isInLibrary(videoID: String) -> Bool {
        db.isInLibrary(id: videoID) || videoEntries.contains { $0.id == videoID }
    }
    
    func renameEntry(_ entry: VideoEntry, newName: String) {
        guard let index = videoEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        videoEntries[index].name = newName
        saveTitle(newName, for: entry.id)
    }
    
    func deleteEntry(_ entry: VideoEntry) {
        // Stop if playing
        if currentPlayingID == entry.id {
            stopWallpaper()
        }
        
        // Get all files from database and delete them
        // This includes video files, thumbnails, metadata, and any temporary files
        let allFiles = db.getVideoFiles(videoId: entry.id, includeTemporary: true)
        
        // Delete all tracked files from disk
        for file in allFiles {
            try? FileManager.default.removeItem(atPath: file.filePath)
        }
        
        // Also delete thumbnail and metadata files directly (for backward compatibility)
        let thumbPath = thumbnailsDirectory.appendingPathComponent("\(entry.id).jpg")
        let titlePath = metadataDirectory.appendingPathComponent("\(entry.id).txt")
        try? FileManager.default.removeItem(at: thumbPath)
        try? FileManager.default.removeItem(at: titlePath)
        
        // Remove from database (this will also delete file records via CASCADE)
        db.removeFromLibrary(id: entry.id)
        
        withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
            videoEntries.removeAll { $0.id == entry.id }
        }
    }
    
    // MARK: - Download & Playback
    
    func downloadVideo(entry: VideoEntry) async -> Bool {
        // Check database for existing video file first
        let existingFiles = db.getVideoFiles(videoId: entry.id, includeTemporary: false)
        if let videoFile = existingFiles.first(where: { $0.fileType == "video" }),
           FileManager.default.fileExists(atPath: videoFile.filePath) {
            // Already downloaded, update status
            if let index = videoEntries.firstIndex(where: { $0.id == entry.id }) {
                var updatedEntry = videoEntries[index]
                updatedEntry.isDownloaded = true
                updatedEntry.videoURL = URL(fileURLWithPath: videoFile.filePath)
                videoEntries[index] = updatedEntry
            }
            db.updateLibraryEntry(id: entry.id, isDownloaded: true)
            return true
        }
        
        // Otherwise, download first
        let youtubeURL = "https://www.youtube.com/watch?v=\(entry.id)"
        
        // Update entry to show downloading state
        if let index = videoEntries.firstIndex(where: { $0.id == entry.id }) {
            var updatedEntry = videoEntries[index]
            updatedEntry.isDownloading = true
            updatedEntry.downloadProgress = 0.0
            videoEntries[index] = updatedEntry
        }
        
        // Track expected output file as temporary before download starts
        let (formatID, height, _, _): (String, Int, Int, Int64?)
        do {
            (formatID, height, _, _) = try await DownloadService.shared.fetchBestFormat(url: youtubeURL)
        } catch {
            print("Failed to fetch format: \(error)")
            if let index = videoEntries.firstIndex(where: { $0.id == entry.id }) {
                var updatedEntry = videoEntries[index]
                updatedEntry.isDownloading = false
                updatedEntry.downloadProgress = 0.0
                videoEntries[index] = updatedEntry
            }
            return false
        }
        let outputPath = videosDirectory.appendingPathComponent("\(entry.id)_\(height)p.mp4")
        
        // Track the expected output file as temporary
        db.addVideoFile(
            videoId: entry.id,
            filePath: outputPath.path,
            fileType: "video",
            fileSize: 0,
            isTemporary: true
        )
        
        do {
            // Get initial files in directory to track temporary files created during download
            let initialFiles = (try? FileManager.default.contentsOfDirectory(at: videosDirectory, includingPropertiesForKeys: nil)) ?? []
            
            let finalPath = try await DownloadService.shared.downloadVideo(
                url: youtubeURL,
                formatID: formatID,
                outputURL: outputPath
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    if let index = self?.videoEntries.firstIndex(where: { $0.id == entry.id }) {
                        self?.videoEntries[index].downloadProgress = progress
                    }
                }
            }
            
            // Get files after download to find temporary files
            let finalFiles = (try? FileManager.default.contentsOfDirectory(at: videosDirectory, includingPropertiesForKeys: nil)) ?? []
            let newFiles = finalFiles.filter { file in
                !initialFiles.contains(file) && 
                (file.lastPathComponent.contains(entry.id) || file.pathExtension == "webm" || file.pathExtension == "part")
            }
            
            // Track any temporary files that were created
            for tempFile in newFiles {
                if tempFile.path != finalPath.path {
                    let fileSize = (try? tempFile.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    let fileType = tempFile.pathExtension == "webm" ? "video_temp" : "audio_temp"
                    db.addVideoFile(
                        videoId: entry.id,
                        filePath: tempFile.path,
                        fileType: fileType,
                        fileSize: Int64(fileSize),
                        isTemporary: true
                    )
                }
            }
            
            // Verify final file exists and get its size
            guard FileManager.default.fileExists(atPath: finalPath.path) else {
                throw NSError(domain: "DownloadError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Final video file not found"])
            }
            
            let fileSize = (try? finalPath.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            
            // Mark final file as permanent (this will replace the temporary entry)
            db.addVideoFile(
                videoId: entry.id,
                filePath: finalPath.path,
                fileType: "video",
                fileSize: Int64(fileSize),
                isTemporary: false
            )
            
            // Clean up temporary files from disk and database
            db.deleteTemporaryFiles(videoId: entry.id)
            
            // Update entry with video URL and download status (replace entire entry to trigger SwiftUI update)
            if let index = videoEntries.firstIndex(where: { $0.id == entry.id }) {
                var updatedEntry = videoEntries[index]
                updatedEntry.videoURL = finalPath
                updatedEntry.isDownloaded = true
                updatedEntry.isDownloading = false
                updatedEntry.downloadProgress = 1.0
                videoEntries[index] = updatedEntry
            }
            
            // Update database
            db.updateLibraryEntry(id: entry.id, isDownloaded: true, lastPlayedAt: Date())
            
            // Return success without auto-playing - let user decide
            return true
            
        } catch {
            print("Download error: \(error)")
            
            // Clean up any temporary files on error
            db.deleteTemporaryFiles(videoId: entry.id)
            
            if let index = videoEntries.firstIndex(where: { $0.id == entry.id }) {
                var updatedEntry = videoEntries[index]
                updatedEntry.isDownloading = false
                updatedEntry.downloadProgress = 0.0
                videoEntries[index] = updatedEntry
            }
            return false
        }
    }
    
    func downloadAndSetWallpaper(_ entry: VideoEntry) async {
        // Check database for existing video file first
        let existingFiles = db.getVideoFiles(videoId: entry.id, includeTemporary: false)
        if let videoFile = existingFiles.first(where: { $0.fileType == "video" }),
           FileManager.default.fileExists(atPath: videoFile.filePath) {
            let videoURL = URL(fileURLWithPath: videoFile.filePath)
            await playVideo(at: videoURL, entryID: entry.id)
            
            // Update database
            db.updateLibraryEntry(id: entry.id, isDownloaded: true, lastPlayedAt: Date())
            return
        }
        
        // Otherwise, download first
        let youtubeURL = "https://www.youtube.com/watch?v=\(entry.id)"
        
        // Update entry to show downloading state
        if let index = videoEntries.firstIndex(where: { $0.id == entry.id }) {
            videoEntries[index].isDownloading = true
            videoEntries[index].downloadProgress = 0.0
        }
        
        // Track expected output file as temporary before download starts
        let (formatID, height, _, _): (String, Int, Int, Int64?)
        do {
            (formatID, height, _, _) = try await DownloadService.shared.fetchBestFormat(url: youtubeURL)
        } catch {
            print("Failed to fetch format: \(error)")
            if let index = videoEntries.firstIndex(where: { $0.id == entry.id }) {
                videoEntries[index].isDownloading = false
                videoEntries[index].downloadProgress = 0.0
            }
            return
        }
        let outputPath = videosDirectory.appendingPathComponent("\(entry.id)_\(height)p.mp4")
        
        // Track the expected output file as temporary
        db.addVideoFile(
            videoId: entry.id,
            filePath: outputPath.path,
            fileType: "video",
            fileSize: 0,
            isTemporary: true
        )
        
        do {
            // Get initial files in directory to track temporary files created during download
            let initialFiles = (try? FileManager.default.contentsOfDirectory(at: videosDirectory, includingPropertiesForKeys: nil)) ?? []
            
            let finalPath = try await DownloadService.shared.downloadVideo(
                url: youtubeURL,
                formatID: formatID,
                outputURL: outputPath
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    if let index = self?.videoEntries.firstIndex(where: { $0.id == entry.id }) {
                        self?.videoEntries[index].downloadProgress = progress
                    }
                }
            }
            
            // Get files after download to find temporary files
            let finalFiles = (try? FileManager.default.contentsOfDirectory(at: videosDirectory, includingPropertiesForKeys: nil)) ?? []
            let newFiles = finalFiles.filter { file in
                !initialFiles.contains(file) && 
                (file.lastPathComponent.contains(entry.id) || file.pathExtension == "webm" || file.pathExtension == "part")
            }
            
            // Track any temporary files that were created
            for tempFile in newFiles {
                if tempFile.path != finalPath.path {
                    let fileSize = (try? tempFile.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    let fileType = tempFile.pathExtension == "webm" ? "video_temp" : "audio_temp"
                    db.addVideoFile(
                        videoId: entry.id,
                        filePath: tempFile.path,
                        fileType: fileType,
                        fileSize: Int64(fileSize),
                        isTemporary: true
                    )
                }
            }
            
            // Verify final file exists and get its size
            guard FileManager.default.fileExists(atPath: finalPath.path) else {
                throw NSError(domain: "DownloadError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Final video file not found"])
            }
            
            let fileSize = (try? finalPath.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            
            // Mark final file as permanent (this will replace the temporary entry)
            db.addVideoFile(
                videoId: entry.id,
                filePath: finalPath.path,
                fileType: "video",
                fileSize: Int64(fileSize),
                isTemporary: false
            )
            
            // Clean up temporary files from disk and database
            db.deleteTemporaryFiles(videoId: entry.id)
            
            // Update entry with video URL and download status (replace entire entry to trigger SwiftUI update)
            if let index = videoEntries.firstIndex(where: { $0.id == entry.id }) {
                var updatedEntry = videoEntries[index]
                updatedEntry.videoURL = finalPath
                updatedEntry.isDownloaded = true
                updatedEntry.isDownloading = false
                updatedEntry.downloadProgress = 1.0
                videoEntries[index] = updatedEntry
            }
            
            // Update database
            db.updateLibraryEntry(id: entry.id, isDownloaded: true, lastPlayedAt: Date())
            
            // Return without auto-playing - let user decide
            return
            
        } catch {
            print("Download error: \(error)")
            
            // Clean up any temporary files on error
            db.deleteTemporaryFiles(videoId: entry.id)
            
            if let index = videoEntries.firstIndex(where: { $0.id == entry.id }) {
                videoEntries[index].isDownloading = false
                videoEntries[index].downloadProgress = 0.0
            }
        }
    }
    
    private func playVideo(at url: URL, entryID: String) async {
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("Video file not found: \(url.path)")
            return
        }
        
        // Create or reuse desktop window (don't destroy it)
        if desktopWindow == nil {
            desktopWindow = DesktopWindow()
        }
        
        // Stop old player observers but keep window alive
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
        
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        
        // Pause old player but don't clear it yet
        let oldPlayer = player
        oldPlayer?.pause()
        
        // Create new player
        let newPlayer = AVPlayer(url: url)
        newPlayer.actionAtItemEnd = .none
        
        // Configure audio based on setting
        if audioEnabled {
            newPlayer.isMuted = false
            newPlayer.volume = 1.0
        } else {
            newPlayer.isMuted = true
            newPlayer.volume = 0.0
        }
        
        // Wait for new player to be ready before switching
        await waitForPlayerReady(player: newPlayer)
        
        // Apply audio mix if audio is disabled
        if !audioEnabled {
            applySilentAudioMix(to: newPlayer)
        }
        
        // Set up looping for new player
        setupLoopObserver(for: newPlayer)
        
        // Switch to new player with fade transition
        desktopWindow?.setPlayer(newPlayer, animated: true)
        
        // Store new player reference
        self.player = newPlayer
        
        // Start playback
        newPlayer.play()
        currentPlayingID = entryID
        
        // Clear old player after transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            // Old player can be cleared now
        }
        
        print("Video wallpaper started: \(url.lastPathComponent)")
    }
    
    private func waitForPlayerReady(player: AVPlayer) async {
        // Wait for currentItem to exist
        var attempts = 0
        while player.currentItem == nil && attempts < 30 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }
        
        guard let item = player.currentItem else {
            print("Player item never appeared")
            return
        }
        
        // Wait for ready status
        if item.status == .readyToPlay {
            return
        }
        
        // Poll for ready status
        attempts = 0
        while item.status != .readyToPlay && attempts < 30 {
            if item.status == .failed {
                print("Player item failed: \(item.error?.localizedDescription ?? "unknown")")
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }
    }
    
    private func setupLoopObserver(for player: AVPlayer) {
        // Remove existing observer
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
        
        guard let item = player.currentItem else {
            print("Cannot set up loop observer: no player item")
            return
        }
        
        // Set up new observer
        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            guard let player = player else { return }
            player.seek(to: .zero) { _ in
                player.play()
            }
        }
        
        loopObserver = observer
    }
    
    func stopWallpaper() {
        // Remove observers
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
        
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        
        // Stop player with fade out
        desktopWindow?.setPlayer(nil, animated: true)
        
        // Clear after fade
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.player?.pause()
            self?.player = nil
            self?.desktopWindow = nil
            self?.currentPlayingID = nil
        }
    }
}
