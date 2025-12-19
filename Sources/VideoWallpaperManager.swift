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
            updateCurrentPlayerAudio()
        }
    }
    
    private let thumbnailsDirectory: URL
    private let metadataDirectory: URL
    private let videosDirectory: URL
    
    private var desktopWindow: DesktopWindow?
    private var player: AVPlayer?
    private var loopObserver: NSObjectProtocol?
    private var timeObserver: Any?
    
    init() {
        // Load audio setting from UserDefaults (default to false/muted)
        audioEnabled = UserDefaults.standard.bool(forKey: "MacLiveWallpaper.audioEnabled")
        
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
        // Load saved entries from metadata
        do {
            let metadataFiles = try FileManager.default.contentsOfDirectory(at: metadataDirectory, includingPropertiesForKeys: nil)
            let titleFiles = metadataFiles.filter { $0.pathExtension == "txt" }
            
            var entries: [VideoEntry] = []
            
            for titleFile in titleFiles {
                let videoID = titleFile.deletingPathExtension().lastPathComponent
                let title = (try? String(contentsOf: titleFile, encoding: .utf8)) ?? videoID
                let thumbnail = await loadLocalThumbnail(for: videoID)
                
                // Check if video file exists
                let videoFiles = try? FileManager.default.contentsOfDirectory(at: videosDirectory, includingPropertiesForKeys: nil)
                let videoFile = videoFiles?.first { $0.lastPathComponent.hasPrefix(videoID) && ($0.pathExtension == "mp4" || $0.pathExtension == "f137") }
                
                entries.append(VideoEntry(
                    id: videoID,
                    name: title,
                    thumbnail: thumbnail,
                    videoURL: videoFile,
                    isDownloading: false,
                    downloadProgress: videoFile != nil ? 1.0 : 0.0
                ))
            }
            
            self.videoEntries = entries.sorted { $0.name < $1.name }
        } catch {
            print("Failed to load library: \(error)")
        }
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
        }
    }
    
    private func saveTitle(_ title: String, for videoID: String) {
        let path = metadataDirectory.appendingPathComponent("\(videoID).txt")
        try? title.write(to: path, atomically: true, encoding: .utf8)
    }
    
    func addVideo(youtubeURL: String) async {
        guard let videoID = await MetadataService.shared.extractVideoID(from: youtubeURL) else {
            return
        }
        
        if videoEntries.contains(where: { $0.id == videoID }) {
            return
        }
        
        // Create entry with video ID as placeholder
        let entry = VideoEntry(
            id: videoID,
            name: videoID,
            thumbnail: nil
        )
        videoEntries.insert(entry, at: 0)
        
        // Fetch title and thumbnail
        async let titleTask = MetadataService.shared.fetchTitle(for: youtubeURL)
        async let thumbnailTask = MetadataService.shared.fetchThumbnail(for: youtubeURL)
        
        let (title, thumbnail) = await (titleTask, thumbnailTask)
        
        // Update entry
        if let index = videoEntries.firstIndex(where: { $0.id == videoID }) {
            var updatedEntry = videoEntries[index]
            if let t = title {
                updatedEntry.name = t
                saveTitle(t, for: videoID)
            }
            if let thumb = thumbnail {
                updatedEntry.thumbnail = thumb
                saveThumbnail(thumb, for: videoID)
            }
            videoEntries[index] = updatedEntry
        }
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
        
        let thumbPath = thumbnailsDirectory.appendingPathComponent("\(entry.id).jpg")
        let titlePath = metadataDirectory.appendingPathComponent("\(entry.id).txt")
        if let videoURL = entry.videoURL {
            try? FileManager.default.removeItem(at: videoURL)
        }
        try? FileManager.default.removeItem(at: thumbPath)
        try? FileManager.default.removeItem(at: titlePath)
        
        withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
            videoEntries.removeAll { $0.id == entry.id }
        }
    }
    
    // MARK: - Download & Playback
    
    func downloadAndSetWallpaper(_ entry: VideoEntry) async {
        // If already downloaded, just play it
        if let videoURL = entry.videoURL, FileManager.default.fileExists(atPath: videoURL.path) {
            await playVideo(at: videoURL, entryID: entry.id)
            return
        }
        
        // Otherwise, download first
        let youtubeURL = "https://www.youtube.com/watch?v=\(entry.id)"
        
        // Update entry to show downloading state
        if let index = videoEntries.firstIndex(where: { $0.id == entry.id }) {
            videoEntries[index].isDownloading = true
            videoEntries[index].downloadProgress = 0.0
        }
        
        do {
            let (formatID, height, _) = try await DownloadService.shared.fetchBestFormat(url: youtubeURL)
            let outputPath = videosDirectory.appendingPathComponent("\(entry.id)_\(height)p.mp4")
            
            try await DownloadService.shared.downloadVideo(
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
            
            // Update entry with video URL
            if let index = videoEntries.firstIndex(where: { $0.id == entry.id }) {
                videoEntries[index].videoURL = outputPath
                videoEntries[index].isDownloading = false
                videoEntries[index].downloadProgress = 1.0
            }
            
            // Auto-play after download
            await playVideo(at: outputPath, entryID: entry.id)
            
        } catch {
            print("Download error: \(error)")
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
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
