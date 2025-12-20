import AppKit
import AVFoundation

/// Custom view that uses AVPlayerLayer directly (not AVPlayerView) to avoid macOS Media Center registration
final class VideoLayerView: NSView {
    var playerLayer: AVPlayerLayer? {
        return layer as? AVPlayerLayer
    }
    
    override func makeBackingLayer() -> CALayer {
        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspectFill
        layer.opacity = 0.0  // Start transparent for fade-in
        return layer
    }
    
    override var wantsUpdateLayer: Bool {
        return true
    }
    
    func setPlayer(_ player: AVPlayer?) {
        playerLayer?.player = player
    }
    
    func fadeIn(duration: TimeInterval, completion: (() -> Void)? = nil) {
        guard let layer = playerLayer else {
            completion?()
            return
        }
        
        // Create fade-in animation
        let fadeAnimation = CABasicAnimation(keyPath: "opacity")
        fadeAnimation.fromValue = 0.0
        fadeAnimation.toValue = 1.0
        fadeAnimation.duration = duration
        fadeAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        fadeAnimation.fillMode = .forwards
        fadeAnimation.isRemovedOnCompletion = false
        
        // Set final opacity value
        layer.opacity = 1.0
        
        // Add animation
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        layer.add(fadeAnimation, forKey: "fadeIn")
        CATransaction.commit()
    }
    
    func fadeOut(duration: TimeInterval, completion: (() -> Void)? = nil) {
        guard let layer = playerLayer else {
            completion?()
            return
        }
        
        // Create fade-out animation
        let fadeAnimation = CABasicAnimation(keyPath: "opacity")
        fadeAnimation.fromValue = layer.opacity
        fadeAnimation.toValue = 0.0
        fadeAnimation.duration = duration
        fadeAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        fadeAnimation.fillMode = .forwards
        fadeAnimation.isRemovedOnCompletion = false
        
        // Set final opacity value
        layer.opacity = 0.0
        
        // Add animation
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        layer.add(fadeAnimation, forKey: "fadeOut")
        CATransaction.commit()
    }
}

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    private var videoLayerView: VideoLayerView?
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
        
        guard let videoView = videoLayerView else { return }
        
        if player == nil {
            // Stopping - fade out and hide the window
            if animated {
                videoView.fadeOut(duration: 0.3) { [weak self] in
                    // Only proceed if this is still the current animation
                    guard let self = self, self.animationGeneration == currentGeneration else { return }
                    self.videoLayerView?.setPlayer(nil)
                    self.orderOut(nil) // Hide window
                }
            } else {
                videoView.playerLayer?.opacity = 0.0
                videoView.setPlayer(nil)
                orderOut(nil) // Hide window
            }
        } else if animated && videoView.playerLayer?.player != nil {
            // Fade transition: fade out old, switch player, fade in new (1 second fade-in)
            videoView.fadeOut(duration: 0.3) { [weak self] in
                guard let self = self, self.animationGeneration == currentGeneration else { return }
                // Reset opacity to 0 before setting new player
                self.videoLayerView?.playerLayer?.opacity = 0.0
                self.videoLayerView?.setPlayer(player)
                self.orderBack(nil)
                // Fade in new video - 1 second
                self.videoLayerView?.fadeIn(duration: 1.0)
            }
        } else if animated {
            // First play with animation - fade in video from transparent
            // Start with opacity 0
            videoView.playerLayer?.opacity = 0.0
            videoView.setPlayer(player)
            orderBack(nil)
            // Fade in video - exactly 1 second
            videoView.fadeIn(duration: 1.0)
        } else {
            // Instant switch (no animation)
            videoView.playerLayer?.opacity = 1.0
            videoView.setPlayer(player)
            orderBack(nil)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
