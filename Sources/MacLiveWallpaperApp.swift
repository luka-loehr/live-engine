import SwiftUI
import AppKit

@main
struct LiveEngineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var wallpaperManager: VideoWallpaperManager!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        wallpaperManager = VideoWallpaperManager()
        
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "Live Wallpaper") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "▶"
            }
            button.target = self
            button.action = #selector(togglePopover)
        }
        
        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 450, height: 350)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: ContentView(wallpaperManager: wallpaperManager)
        )
        
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
        
        // Test LiveWallpaperPlayer if test video exists and --test flag is passed
        if CommandLine.arguments.contains("--test") {
            testLiveWallpaperPlayer()
        }
    }
    
    @MainActor
    private func testLiveWallpaperPlayer() {
        let testVideoPath = "/Users/luka/Documents/live-engine/test-videos/2020 LG OLED l  The Black 4K HDR 60fps.mp4"
        
        guard FileManager.default.fileExists(atPath: testVideoPath) else {
            print("Test video not found at: \(testVideoPath)")
            return
        }
        
        print("🧪 Testing LiveWallpaperPlayer...")
        let player = LiveWallpaperPlayer()
        let videoURL = URL(fileURLWithPath: testVideoPath)
        
        Task { @MainActor in
            do {
                print("▶️  Starting wallpaper playback...")
                try await player.playVideo(at: videoURL)
                print("✅ Video wallpaper started successfully!")
                print("🔄 Video is looping infinitely")
            } catch {
                print("❌ Error: \(error.localizedDescription)")
            }
        }
    }
    
    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
