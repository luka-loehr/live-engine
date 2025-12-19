import AppKit
import AVKit

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    private var playerView: AVPlayerView?
    private var fadeOverlay: NSView?
    
    init() {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        
        super.init(
            contentRect: screenFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        
        configure()
    }
    
    private func configure() {
        // Set window level to desktop window level (behind desktop icons)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        
        styleMask = .borderless
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        setFrame(NSScreen.main?.frame ?? frame, display: true)
        
        // Create player view
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        view.frame = contentView?.bounds ?? .zero
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.drawsAsynchronously = true
        contentView?.addSubview(view)
        playerView = view
        
        // Create fade overlay for smooth transitions
        let overlay = NSView(frame: contentView?.bounds ?? .zero)
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.cgColor
        overlay.alphaValue = 0.0
        overlay.autoresizingMask = [.width, .height]
        contentView?.addSubview(overlay)
        fadeOverlay = overlay
        
        // Make window visible and order it back
        orderBack(nil)
        isReleasedWhenClosed = false
        
        // Handle screen changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    @objc private func screenDidChange(_ notification: Notification) {
        if let screen = NSScreen.main {
            setFrame(screen.frame, display: true)
        }
    }
    
    func setPlayer(_ player: AVPlayer?, animated: Bool = true) {
        if animated && playerView?.player != nil && player != nil {
            // Fade transition: fade out old, switch player, fade in new
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                fadeOverlay?.animator().alphaValue = 1.0
            }) { [weak self] in
                self?.playerView?.player = player
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.3
                    self?.fadeOverlay?.animator().alphaValue = 0.0
                })
            }
        } else {
            // Instant switch
            playerView?.player = player
            fadeOverlay?.alphaValue = 0.0
        }
        
        if player != nil {
            // Ensure window stays visible
            orderBack(nil)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
