import AppKit
import AVKit
import MediaPlayer

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    private var playerView: AVPlayerView?
    private var fadeOverlay: NSView?
    private var animationGeneration: Int = 0  // Track animation generation to ignore stale callbacks
    private let targetScreen: NSScreen
    
    init(screen: NSScreen) {
        self.targetScreen = screen
        let screenFrame = screen.frame
        
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
        setFrame(targetScreen.frame, display: true)
        
        // Create player view
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        view.frame = contentView?.bounds ?? .zero
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.drawsAsynchronously = true
        
        // Prevent this player from appearing in macOS media controls
        // AVPlayerView doesn't have direct properties for this, but we'll handle it
        // by clearing Now Playing info whenever the player is set
        
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
        // Update frame if this window's screen still exists
        let screens = NSScreen.screens
        if screens.contains(targetScreen) {
            setFrame(targetScreen.frame, display: true)
        }
    }
    
    func setPlayer(_ player: AVPlayer?, animated: Bool = true) {
        // Clear Now Playing info to prevent macOS from detecting this as media
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        
        // Increment generation to invalidate any pending animation callbacks
        animationGeneration += 1
        let currentGeneration = animationGeneration
        
        if player == nil {
            // Stopping - hide the window
            if animated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.3
                    fadeOverlay?.animator().alphaValue = 1.0
                }) { [weak self] in
                    // Only proceed if this is still the current animation
                    guard let self = self, self.animationGeneration == currentGeneration else { return }
                    self.playerView?.player = nil
                    self.orderOut(nil) // Hide window
                    self.fadeOverlay?.alphaValue = 0.0
                }
            } else {
                playerView?.player = nil
                orderOut(nil) // Hide window
            }
        } else if animated && playerView?.player != nil {
            // Fade transition: fade out old, switch player, fade in new
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                fadeOverlay?.animator().alphaValue = 1.0
            }) { [weak self] in
                guard let self = self, self.animationGeneration == currentGeneration else { return }
                self.playerView?.player = player
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.3
                    self.fadeOverlay?.animator().alphaValue = 0.0
                })
            }
            orderBack(nil)
        } else if animated {
            // First play with animation - fade in from black
            // Set overlay to fully opaque BEFORE setting player and showing window
            fadeOverlay?.alphaValue = 1.0
            // Set the player while overlay is covering it
            playerView?.player = player
            // Now show the window (player is hidden behind black overlay)
            orderBack(nil)
            // Start fade-in animation immediately
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.6
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                fadeOverlay?.animator().alphaValue = 0.0
            })
        } else {
            // Instant switch (no animation)
            playerView?.player = player
            fadeOverlay?.alphaValue = 0.0
            orderBack(nil)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
