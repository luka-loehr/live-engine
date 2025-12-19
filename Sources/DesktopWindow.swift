import AppKit
import AVKit

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    private var playerView: AVPlayerView?
    private var overlayView: NSView?
    
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
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        styleMask = .borderless
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        setFrame(NSScreen.main?.frame ?? frame, display: true)
        
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        view.frame = contentView?.bounds ?? .zero
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.drawsAsynchronously = true
        contentView?.addSubview(view)
        playerView = view
        
        let overlay = NSView(frame: contentView?.bounds ?? .zero)
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.cgColor
        overlay.alphaValue = 0
        overlay.autoresizingMask = [.width, .height]
        contentView?.addSubview(overlay)
        overlayView = overlay
        
        orderBack(nil)
        
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
    
    func setPlayer(_ player: AVPlayer?, animated: Bool = false) {
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.5
                overlayView?.animator().alphaValue = 1.0
            } completionHandler: { [weak self] in
                self?.playerView?.player = player
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.5
                    self?.overlayView?.animator().alphaValue = 0.0
                }
            }
        } else {
            playerView?.player = player
            overlayView?.alphaValue = 0.0
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

