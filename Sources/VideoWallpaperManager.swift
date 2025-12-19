import Foundation
import AppKit

@MainActor
class VideoWallpaperManager: ObservableObject {
    @Published var videoEntries: [VideoEntry] = []
    
    private let thumbnailsDirectory: URL
    private let metadataDirectory: URL
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        thumbnailsDirectory = appSupport.appendingPathComponent("MacLiveWallpaper/Thumbnails", isDirectory: true)
        metadataDirectory = appSupport.appendingPathComponent("MacLiveWallpaper/Metadata", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        
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
                
                entries.append(VideoEntry(
                    id: videoID,
                    name: title,
                    thumbnail: thumbnail
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
        let thumbPath = thumbnailsDirectory.appendingPathComponent("\(entry.id).jpg")
        let titlePath = metadataDirectory.appendingPathComponent("\(entry.id).txt")
        try? FileManager.default.removeItem(at: thumbPath)
        try? FileManager.default.removeItem(at: titlePath)
        
        videoEntries.removeAll { $0.id == entry.id }
    }
}
