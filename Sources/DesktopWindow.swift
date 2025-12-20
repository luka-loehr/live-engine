import AppKit
import AVFoundation
import MediaPlayer

/// Custom view that uses AVPlayerLayer directly (not AVPlayerView) to avoid macOS Media Center registration
final class VideoLayerView: NSView {
    var playerLayer: AVPlayerLayer? {
        return layer as? AVPlayerLayer
    }
    
    override func makeBackingLayer() -> CALayer {
        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspectFill
        return layer
    }
    
    override var wantsUpdateLayer: Bool {
        return true
    }
    
    func setPlayer(_ player: AVPlayer?) {
        playerLayer?.player = player
    }
}

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    private var videoLayerView: VideoLayerView?
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
        
        // Create custom video layer view (using AVPlayerLayer directly, not AVPlayerView)
        // This prevents macOS from registering the video as a media source
        let view = VideoLayerView()
        view.frame = contentView?.bounds ?? .zero
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.drawsAsynchronously = true
        
        contentView?.addSubview(view)
        videoLayerView = view
        
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
                    self.videoLayerView?.setPlayer(nil)
                    self.orderOut(nil) // Hide window
                    self.fadeOverlay?.alphaValue = 0.0
                }
            } else {
                videoLayerView?.setPlayer(nil)
                orderOut(nil) // Hide window
            }
        } else if animated && videoLayerView?.playerLayer?.player != nil {
            // Fade transition: fade out old, switch player, fade in new
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                fadeOverlay?.animator().alphaValue = 1.0
            }) { [weak self] in
                guard let self = self, self.animationGeneration == currentGeneration else { return }
                self.videoLayerView?.setPlayer(player)
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
            videoLayerView?.setPlayer(player)
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
            videoLayerView?.setPlayer(player)
            fadeOverlay?.alphaValue = 0.0
            orderBack(nil)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
