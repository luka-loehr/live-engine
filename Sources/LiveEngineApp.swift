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

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var wallpaperManager: VideoWallpaperManager!
    var menu: NSMenu!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        wallpaperManager = VideoWallpaperManager()
        
        // Observe wallpaper manager changes to update menu
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateMenuItems),
            name: NSNotification.Name("WallpaperStateChanged"),
            object: nil
        )
        
        // Initialize main window
        if MainWindow.shared == nil {
            MainWindow.shared = MainWindow(wallpaperManager: wallpaperManager)
        }

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
            button.action = #selector(showMenu)
        }
        
        // Create menu
        Task { @MainActor in
            createMenu()
        }

        // Show dock icon since we're now a windowed app
        NSApp.setActivationPolicy(.regular)

        // Test LiveWallpaperPlayer if test video exists and --test flag is passed
        if CommandLine.arguments.contains("--test") {
            testLiveWallpaperPlayer()
        }

        // Show main window on launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            MainWindow.shared?.show()
        }
    }
    
    @objc func updateMenuItems() {
        // Menu items will be updated when menu is shown
    }
    
    @MainActor
    func createMenu() {
        menu = NSMenu()
        
        // Library item
        let libraryItem = NSMenuItem(
            title: "Library",
            action: #selector(showMainWindow),
            keyEquivalent: "w"
        )
        libraryItem.target = self
        menu.addItem(libraryItem)
        
        // Settings item
        let settingsItem = NSMenuItem(
            title: "Settings",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        // Audio toggle item
        let audioItem = NSMenuItem(
            title: wallpaperManager.audioEnabled ? "Audio" : "Audio",
            action: #selector(toggleAudio),
            keyEquivalent: ""
        )
        audioItem.target = self
        audioItem.state = wallpaperManager.audioEnabled ? .on : .off
        menu.addItem(audioItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit item with red highlight on hover
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.attributedTitle = NSAttributedString(
            string: "Quit",
            attributes: [.foregroundColor: NSColor.labelColor]
        )
        menu.addItem(quitItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Version item at bottom
        let versionItem = NSMenuItem(
            title: "v1.0.0",
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        versionItem.attributedTitle = NSAttributedString(
            string: "v1.0.0",
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 11)
            ]
        )
        menu.addItem(versionItem)
        
        // Set up menu delegate for hover effects
        menu.delegate = self
    }
    
    @objc func showMainWindow() {
        MainWindow.shared?.show()
    }
    
    @objc func showMenu() {
        guard let button = statusItem.button else { return }
        
        // Update menu items based on current state
        // Index 0: Library
        // Index 1: Settings
        // Index 2: Audio
        // Index 3: Separator
        // Index 4: Quit
        // Index 5: Separator
        // Index 6: Version
        
        Task { @MainActor in
            if let audioItem = menu.item(at: 2) {
                audioItem.state = wallpaperManager.audioEnabled ? .on : .off
            }
            
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
        }
    }
    
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        // Highlight Quit item in red on hover
        if let item = item, item.title == "Quit" {
            item.attributedTitle = NSAttributedString(
                string: "Quit",
                attributes: [.foregroundColor: NSColor.systemRed]
            )
        } else if let quitItem = menu.items.first(where: { $0.title == "Quit" }) {
            // Reset Quit item color when not hovering
            quitItem.attributedTitle = NSAttributedString(
                string: "Quit",
                attributes: [.foregroundColor: NSColor.labelColor]
            )
        }
    }
    
    @objc func togglePlayPause() {
        Task { @MainActor in
            if wallpaperManager.currentPlayingID != nil {
                // Currently playing - pause/stop
                wallpaperManager.stopWallpaper()
            } else {
                // Not playing - restore last wallpaper if available
                await wallpaperManager.restoreLastWallpaperIfNeeded()
            }
        }
    }
    
    @objc func toggleAudio() {
        Task { @MainActor in
            wallpaperManager.audioEnabled.toggle()
        }
    }
    
    @objc func showSettings() {
        // Show main window and trigger settings view
        MainWindow.shared?.show()
        // Post notification to show settings in main window
        NotificationCenter.default.post(name: NSNotification.Name("ShowSettings"), object: nil)
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
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
    
}
