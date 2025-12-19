import SwiftUI
import AppKit

@main
struct MacLiveWallpaperApp: App {
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
