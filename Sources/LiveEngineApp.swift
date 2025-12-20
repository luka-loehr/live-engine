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
        
        // Observe when main window is hidden to switch back to accessory mode
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mainWindowHidden),
            name: NSNotification.Name("MainWindowHidden"),
            object: nil
        )
        
        // Detect if app was launched via LaunchAgent or manually
        let isLaunchAgentLaunch = detectLaunchAgentLaunch()
        
        // Initialize main window
        if MainWindow.shared == nil {
            MainWindow.shared = MainWindow(wallpaperManager: wallpaperManager)
        }

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            // Try to load dedicated menu bar icon (template PNG or PDF)
            // Menu bar icons should be monochrome template images for proper tinting
            var menuBarIcon: NSImage? = nil
            
            // Try menu bar specific icon files (in order of preference)
            // First try bundle resources (for built app)
            if let iconPath = Bundle.main.path(forResource: "MenuBarIcon", ofType: "pdf"),
               let icon = NSImage(contentsOfFile: iconPath) {
                menuBarIcon = icon
                print("[MENU] Loaded MenuBarIcon.pdf from bundle")
            } else if let iconPath = Bundle.main.path(forResource: "MenuBarIcon", ofType: "png"),
                      let icon = NSImage(contentsOfFile: iconPath) {
                menuBarIcon = icon
                print("[MENU] Loaded MenuBarIcon.png from bundle")
            } else if let iconPath = Bundle.main.path(forResource: "menu-bar-icon", ofType: "png"),
                      let icon = NSImage(contentsOfFile: iconPath) {
                menuBarIcon = icon
                print("[MENU] Loaded menu-bar-icon.png from bundle")
            }
            
            // Fallback: Try source directory (for swift run / debug mode)
            if menuBarIcon == nil {
                // Try to find project root by looking for Package.swift
                let fileManager = FileManager.default
                var projectRoot: String? = nil
                
                // Start from executable path and walk up to find Package.swift
                if let executablePath = Bundle.main.executablePath {
                    var currentPath = (executablePath as NSString).deletingLastPathComponent
                    for _ in 0..<10 { // Limit search depth
                        let packagePath = (currentPath as NSString).appendingPathComponent("Package.swift")
                        if fileManager.fileExists(atPath: packagePath) {
                            projectRoot = currentPath
                            break
                        }
                        let parent = (currentPath as NSString).deletingLastPathComponent
                        if parent == currentPath { break } // Reached root
                        currentPath = parent
                    }
                }
                
                // Also try current directory
                if projectRoot == nil {
                    projectRoot = fileManager.currentDirectoryPath
                }
                
                if let root = projectRoot {
                    let possiblePaths = [
                        "Assets/Icons/MenuBarIcon.pdf",
                        "Assets/Icons/MenuBarIcon.png",
                        "Assets/Icons/menu-bar-icon.png"
                    ]
                    
                    for relativePath in possiblePaths {
                        let fullPath = (root as NSString).appendingPathComponent(relativePath)
                        if fileManager.fileExists(atPath: fullPath),
                           let icon = NSImage(contentsOfFile: fullPath) {
                            menuBarIcon = icon
                            print("[MENU] Loaded \(relativePath) from project root: \(root)")
                            break
                        }
                    }
                }
            }
            
            if let icon = menuBarIcon {
                // Set as template so macOS can tint it for light/dark mode
                icon.isTemplate = true
                
                // Ensure the icon has the correct size for menu bar (18x18 points)
                // The actual pixel size should be 36x36 for @2x Retina
                if icon.size.width != 18 || icon.size.height != 18 {
                    icon.size = NSSize(width: 18, height: 18)
                }
                
                // Set the image directly - NSStatusItem will handle the sizing
                button.image = icon
                print("[MENU] Menu bar icon set successfully (icon size: \(icon.size), representations: \(icon.representations.count))")
            } else {
                print("[MENU] No custom menu bar icon found, using fallback")
                if let image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "Live Wallpaper") {
                    // Fallback to SF Symbol
                    image.isTemplate = true
                    button.image = image
                } else {
                    // Final fallback to text
                    button.title = "▶"
                }
            }
            button.target = self
            button.action = #selector(showMenu)
        }
        
        // Create menu
        Task { @MainActor in
            createMenu()
        }

        // Test LiveWallpaperPlayer if test video exists and --test flag is passed
        if CommandLine.arguments.contains("--test") {
            testLiveWallpaperPlayer()
        }

        if isLaunchAgentLaunch {
            // Launched via LaunchAgent: menu bar only, no UI
            NSApp.setActivationPolicy(.accessory)
            print("[LAUNCH] Detected LaunchAgent launch - showing menu bar icon only")
        } else {
            // Manual launch: show UI library + menu bar icon
            NSApp.setActivationPolicy(.regular)
            // Show main window after a short delay to ensure everything is initialized
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                MainWindow.shared?.show()
                NotificationCenter.default.post(name: NSNotification.Name("ShowLibrary"), object: nil)
            }
            print("[LAUNCH] Detected manual launch - showing UI library")
        }
    }
    
    /// Detect if the app was launched via LaunchAgent by checking command-line arguments
    private func detectLaunchAgentLaunch() -> Bool {
        // LaunchAgent passes --launchagent flag, manual launches don't
        return CommandLine.arguments.contains("--launchagent")
    }
    
    @objc func updateMenuItems() {
        // Menu items will be updated when menu is shown
    }
    
    @objc func mainWindowHidden() {
        // Switch back to accessory mode (menu bar only) when window is hidden
        NSApp.setActivationPolicy(.accessory)
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
        // Temporarily switch to regular activation policy to allow window activation
        NSApp.setActivationPolicy(.regular)
        MainWindow.shared?.show()
        // Post notification to show library (close settings if open)
        NotificationCenter.default.post(name: NSNotification.Name("ShowLibrary"), object: nil)
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
        // Temporarily switch to regular activation policy to allow window activation
        NSApp.setActivationPolicy(.regular)
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
