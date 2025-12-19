import Foundation
import AppKit

// MARK: - Models

struct VideoQuality: Identifiable, Equatable {
    let id = UUID()
    let resolution: Int
    let url: URL
    
    var label: String {
        switch resolution {
        case 2160: return "4K"
        case 1440: return "2K"
        case 1080: return "1080p"
        default: return "\(resolution)p"
        }
    }
}

struct VideoEntry: Identifiable, Equatable {
    let id: String
    var name: String
    var thumbnail: NSImage?
    var videoURL: URL?
    var isDownloaded: Bool = false
    var isDownloading: Bool = false
    var downloadProgress: Double = 0.0
    
    static func == (lhs: VideoEntry, rhs: VideoEntry) -> Bool {
        lhs.id == rhs.id
    }
}

