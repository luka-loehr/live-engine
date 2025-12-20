import SwiftUI
import AppKit

class MainWindow: NSWindow, NSWindowDelegate {
    static var shared: MainWindow?
    
    init(wallpaperManager: VideoWallpaperManager) {
        let contentView = ContentView(wallpaperManager: wallpaperManager)
        let hostingController = NSHostingController(rootView: contentView)
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        self.title = "live-engine"
        self.contentViewController = hostingController
        self.isReleasedWhenClosed = false
        self.delegate = self
        self.center()
        self.setFrameAutosaveName("MainWindow")
        self.minSize = NSSize(width: 600, height: 400)
    }
    
    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Post notification to refresh tip when window is shown
        NotificationCenter.default.post(name: NSNotification.Name("MainWindowShown"), object: nil)
    }
    
    func windowWillClose(_ notification: Notification) {
        // Don't quit the app when main window closes, just hide it
        // The app will continue running in the menu bar
        orderOut(nil)
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide window instead of closing it
        orderOut(nil)
        // Notify that window was hidden so we can switch back to accessory mode
        NotificationCenter.default.post(name: NSNotification.Name("MainWindowHidden"), object: nil)
        return false
    }
    
    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        // Notify that window was hidden so we can switch back to accessory mode
        NotificationCenter.default.post(name: NSNotification.Name("MainWindowHidden"), object: nil)
    }
}
