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
            // Try to load custom app icon from bundle
            if let appIconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
               let appIcon = NSImage(contentsOfFile: appIconPath) {
                // Resize icon for menu bar (typically 18x18 or 22x22 points)
                let resizedIcon = NSImage(size: NSSize(width: 18, height: 18))
                resizedIcon.lockFocus()
                appIcon.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
                resizedIcon.unlockFocus()
                resizedIcon.isTemplate = true
                button.image = resizedIcon
            } else if let image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "Live Wallpaper") {
                // Fallback to SF Symbol
                image.isTemplate = true
                button.image = image
            } else {
                // Final fallback to text
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

        // Automatically show the popover when app launches
        // Use robust polling mechanism to wait for status bar button to be ready
        showPopoverWhenReady()
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
    
    /// Polls until the status bar button is ready, then shows the popover
    /// Uses exponential backoff with a maximum timeout for robustness
    private func showPopoverWhenReady(attempt: Int = 0, maxAttempts: Int = 50) {
        guard attempt < maxAttempts else {
            // Fallback: try to show anyway after max attempts
            print("⚠️ Status bar button not ready after \(maxAttempts) attempts, showing popover anyway")
            showPopover()
            return
        }
        
        guard let button = statusItem.button else {
            // Retry if button doesn't exist yet
            let delay = min(0.05 * Double(attempt + 1), 0.2) // Exponential backoff, max 0.2s
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.showPopoverWhenReady(attempt: attempt + 1, maxAttempts: maxAttempts)
            }
            return
        }
        
        // Check if button is ready: window exists, window is visible, and button has valid bounds
        let isReady = button.window != nil &&
                     button.window?.isVisible == true &&
                     !button.bounds.isEmpty &&
                     button.bounds.width > 0 &&
                     button.bounds.height > 0
        
        if isReady {
            // Button is ready, wait an additional 500ms to ensure everything is fully settled
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showPopover()
            }
        } else {
            // Not ready yet, retry with exponential backoff
            let delay = min(0.05 * Double(attempt + 1), 0.2) // Exponential backoff, max 0.2s
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.showPopoverWhenReady(attempt: attempt + 1, maxAttempts: maxAttempts)
            }
        }
    }
    
    func showPopover() {
        guard let button = statusItem.button else { return }
        
        // Ensure the button's window is ready and visible
        guard let window = button.window, window.isVisible else {
            // If window isn't ready, use the polling mechanism
            showPopoverWhenReady()
            return
        }
        
        // Activate the app first to ensure proper positioning
        NSApp.activate(ignoringOtherApps: true)
        
        // Ensure button is properly laid out
        window.update()
        
        // Verify button has valid bounds before showing
        guard !button.bounds.isEmpty else {
            // Button bounds not ready, retry
            showPopoverWhenReady()
            return
        }
        
        // Show popover relative to button, positioned below it (.maxY = bottom edge)
        // This will attach it to the menu bar icon at the top
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
    }

    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }
}
