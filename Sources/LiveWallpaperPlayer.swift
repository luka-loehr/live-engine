import Foundation
import AppKit
import AVFoundation

/// A simple component that displays an MP4 video as a live wallpaper with infinite looping
@MainActor
class LiveWallpaperPlayer: ObservableObject {
    private var desktopWindows: [ObjectIdentifier: DesktopWindow] = [:]
    private var screenToID: [NSScreen: ObjectIdentifier] = [:]
    private var player: AVPlayer?
    private var loopObserver: NSObjectProtocol?
    private var screenChangeObserver: NSObjectProtocol?
    private var audioEnabled: Bool = false
    
    init() {
        // Listen for screen configuration changes
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenConfigurationChange()
            }
        }
    }
    
    /// Starts playing a video file as wallpaper with infinite loop
    /// - Parameter videoURL: The file URL to the MP4 video file
    func playVideo(at videoURL: URL) async throws {
        // Verify file exists
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw LiveWallpaperError.fileNotFound(videoURL.path)
        }
        
        // Check if we're switching from an existing video or starting fresh
        let hasExistingPlayer = player != nil
        
        // Clean up existing playback without animated hide (avoid race condition)
        // Just pause and clear observer - let setPlayer handle the transition
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
        player?.pause()
        player = nil
        
        // Ensure we have windows for all screens
        ensureWindowsForAllScreens()
        
        // If we had an existing player, clear it from all views first to ensure smooth transition
        if hasExistingPlayer {
            for (_, window) in desktopWindows {
                window.setPlayer(nil, animated: false)
            }
        }
        
        // Create player
        let newPlayer = AVPlayer(url: videoURL)
        newPlayer.actionAtItemEnd = .none
        
        // Store player reference early so audio settings can be applied
        self.player = newPlayer
        
        // Apply current audio settings immediately
        newPlayer.isMuted = !audioEnabled
        newPlayer.volume = audioEnabled ? 1.0 : 0.0
        
        // Wait for player to be ready
        await waitForPlayerReady(player: newPlayer)
        
        // Preload first frame but keep paused for smooth fade-in
        newPlayer.pause()
        
        // Set up infinite looping
        setupLoopObserver(for: newPlayer)
        
        // Set player in all desktop windows (this will handle transition from old to new)
        // Always use animated: true to ensure smooth fade-in
        for (_, window) in desktopWindows {
            window.setPlayer(newPlayer, animated: true)
        }
        
        // Start playback after a short delay to allow fade-in to begin
        // This ensures the first frame is hidden behind the fade overlay
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        newPlayer.play()
    }
    
    /// Stops the wallpaper playback
    func stop() {
        print("[PLAYER] Stopping wallpaper playback")
        
        // Remove loop observer
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
        
        // Stop player
        player?.pause()
        player = nil
        
        // Hide all desktop windows with fade animation
        for (_, window) in desktopWindows {
            window.setPlayer(nil, animated: true)
        }
        // Keep the window references for reuse
        
        print("[PLAYER] Wallpaper stopped")
    }
    
    /// Sets whether audio should be enabled with smooth fade in/out
    /// - Parameter enabled: Whether audio should play
    func setAudioEnabled(_ enabled: Bool) {
        audioEnabled = enabled
        guard let player = player else {
            print("[PLAYER] Audio setting saved (\(enabled ? "enabled" : "disabled")) but no player active yet")
            return
        }
        
        if enabled {
            // Fade in: unmute and gradually increase volume
            player.isMuted = false
            fadeVolume(from: 0.0, to: 1.0, duration: 1.0, player: player)
            print("[PLAYER] Audio fading in - muted: false")
        } else {
            // Fade out: gradually decrease volume, then mute
            let currentVolume = player.volume
            fadeVolume(from: currentVolume, to: 0.0, duration: 1.0, player: player) {
                player.isMuted = true
            }
            print("[PLAYER] Audio fading out - will mute after fade")
        }
    }
    
    /// Fades the volume smoothly over the specified duration
    private func fadeVolume(from startVolume: Float, to endVolume: Float, duration: TimeInterval, player: AVPlayer, completion: (() -> Void)? = nil) {
        let startTime = CACurrentMediaTime()
        let endTime = startTime + duration
        
        // Use a timer to update volume smoothly
        let timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak player] timer in
            guard let player = player else {
                timer.invalidate()
                return
            }
            
            let currentTime = CACurrentMediaTime()
            if currentTime >= endTime {
                player.volume = endVolume
                timer.invalidate()
                completion?()
            } else {
                let progress = Float((currentTime - startTime) / duration)
                let easedProgress = Self.easeInOut(progress) // Smooth easing
                player.volume = startVolume + (endVolume - startVolume) * easedProgress
            }
        }
        
        // Ensure timer runs on main thread
        RunLoop.main.add(timer, forMode: .common)
    }
    
    /// Easing function for smooth transitions
    nonisolated private static func easeInOut(_ t: Float) -> Float {
        return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }
    
    // MARK: - Private Helpers
    
    private func waitForPlayerReady(player: AVPlayer) async {
        // Wait for currentItem to exist
        var attempts = 0
        while player.currentItem == nil && attempts < 30 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            attempts += 1
        }
        
        guard let item = player.currentItem else {
            print("Player item never appeared")
            return
        }
        
        // Wait for ready status
        if item.status == .readyToPlay {
            return
        }
        
        // Poll for ready status
        attempts = 0
        while item.status != .readyToPlay && attempts < 30 {
            if item.status == .failed {
                print("Player item failed: \(item.error?.localizedDescription ?? "unknown")")
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            attempts += 1
        }
    }
    
    private func setupLoopObserver(for player: AVPlayer) {
        // Remove existing observer
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
        
        guard let item = player.currentItem else {
            print("Cannot set up loop observer: no player item")
            return
        }
        
        // Set up observer for infinite looping
        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            guard let player = player else { return }
            // Seek back to beginning and play again
            player.seek(to: .zero) { _ in
                player.play()
            }
        }
        
        loopObserver = observer
    }
    
    // MARK: - Screen Management
    
    private func ensureWindowsForAllScreens() {
        let currentScreens = NSScreen.screens
        let currentScreenIDs = Set(currentScreens.map { ObjectIdentifier($0) })
        let existingScreenIDs = Set(desktopWindows.keys)
        
        // Create windows for new screens
        for screen in currentScreens {
            let screenID = ObjectIdentifier(screen)
            if desktopWindows[screenID] == nil {
                print("[PLAYER] Creating desktop window for screen: \(screen.localizedName)")
                let window = DesktopWindow(screen: screen)
                desktopWindows[screenID] = window
                screenToID[screen] = screenID
                
                // If we have a player, set it immediately on the new window
                if let player = player {
                    window.setPlayer(player, animated: false)
                }
            }
        }
        
        // Remove windows for screens that no longer exist
        for screenID in existingScreenIDs {
            if !currentScreenIDs.contains(screenID) {
                print("[PLAYER] Removing desktop window for disconnected screen")
                desktopWindows[screenID]?.close()
                desktopWindows.removeValue(forKey: screenID)
            }
        }
        
        // Clean up screenToID mapping for disconnected screens
        screenToID = screenToID.filter { currentScreens.contains($0.key) }
    }
    
    private func handleScreenConfigurationChange() {
        print("[PLAYER] Screen configuration changed, updating windows...")
        ensureWindowsForAllScreens()
    }
    
    deinit {
        // Clean up observers synchronously (deinit can't be async)
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        // Close all windows
        for (_, window) in desktopWindows {
            window.close()
        }
        desktopWindows.removeAll()
        screenToID.removeAll()
        // Player will be cleaned up automatically
    }
}

// MARK: - Errors

enum LiveWallpaperError: LocalizedError {
    case fileNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Video file not found at path: \(path)"
        }
    }
}

