import Foundation
import AppKit
import SwiftUI

@MainActor
class VideoWallpaperManager: ObservableObject {
    @Published var videoEntries: [VideoEntry] = []
    @Published var currentPlayingID: String? = nil
    @Published var audioEnabled: Bool {
        didSet {
            UserDefaults.standard.set(audioEnabled, forKey: "MacLiveWallpaper.audioEnabled")
            DatabaseService.shared.updateSettings { $0.audioEnabled = audioEnabled }
        }
    }
    
    private let thumbnailsDirectory: URL
    private let metadataDirectory: URL
    private let videosDirectory: URL
    private let db = DatabaseService.shared
    
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
        
        let finalTitle = title ?? videoID
        
        // Update entry
        if let index = videoEntries.firstIndex(where: { $0.id == videoID }) {
            var updatedEntry = videoEntries[index]
            updatedEntry.name = finalTitle
            saveTitle(finalTitle, for: videoID)
            
            if let thumb = thumbnail {
                updatedEntry.thumbnail = thumb
                saveThumbnail(thumb, for: videoID)
            }
            videoEntries[index] = updatedEntry
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
        // Clear playing state if this entry was playing
        if currentPlayingID == entry.id {
            currentPlayingID = nil
        }
        
        let thumbPath = thumbnailsDirectory.appendingPathComponent("\(entry.id).jpg")
        let titlePath = metadataDirectory.appendingPathComponent("\(entry.id).txt")
        if let videoURL = entry.videoURL {
            try? FileManager.default.removeItem(at: videoURL)
        }
        try? FileManager.default.removeItem(at: thumbPath)
        try? FileManager.default.removeItem(at: titlePath)
        
        // Remove from database
        db.removeFromLibrary(id: entry.id)
        
        withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
            videoEntries.removeAll { $0.id == entry.id }
        }
    }
    
    // MARK: - Download
    
    func downloadAndSetWallpaper(_ entry: VideoEntry) async {
        // If already downloaded, just mark as ready
        if let videoURL = entry.videoURL, FileManager.default.fileExists(atPath: videoURL.path) {
            currentPlayingID = entry.id
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
            
            // Mark as current (but don't actually play)
            currentPlayingID = entry.id
            
        } catch {
            print("Download error: \(error)")
            if let index = videoEntries.firstIndex(where: { $0.id == entry.id }) {
                videoEntries[index].isDownloading = false
                videoEntries[index].downloadProgress = 0.0
            }
        }
    }
    
    func stopWallpaper() {
        // Clear playing state
        currentPlayingID = nil
    }
}
