import Foundation
import AppKit
import AVFoundation

/// A simple component that displays an MP4 video as a live wallpaper with infinite looping
@MainActor
class LiveWallpaperPlayer: ObservableObject {
    private var desktopWindow: DesktopWindow?
    private var player: AVPlayer?
    private var loopObserver: NSObjectProtocol?
    
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
        
        // Create or reuse desktop window
        if desktopWindow == nil {
            desktopWindow = DesktopWindow()
        }
        
        // If we had an existing player, clear it from the view first to ensure smooth transition
        if hasExistingPlayer {
            desktopWindow?.setPlayer(nil, animated: false)
        }
        
        // Create player
        let newPlayer = AVPlayer(url: videoURL)
        newPlayer.actionAtItemEnd = .none
        
        // Mute audio by default (wallpaper typically shouldn't have sound)
        newPlayer.isMuted = true
        newPlayer.volume = 0.0
        
        // Wait for player to be ready
        await waitForPlayerReady(player: newPlayer)
        
        // Preload first frame but keep paused for smooth fade-in
        newPlayer.pause()
        
        // Set up infinite looping
        setupLoopObserver(for: newPlayer)
        
        // Set player in desktop window (this will handle transition from old to new)
        // Always use animated: true to ensure smooth fade-in
        desktopWindow?.setPlayer(newPlayer, animated: true)
        
        // Store player reference
        self.player = newPlayer
        
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
        
        // Hide desktop window with fade animation
        desktopWindow?.setPlayer(nil, animated: true)
        // Keep the window reference for reuse
        
        print("[PLAYER] Wallpaper stopped")
    }
    
    /// Sets whether audio should be enabled
    /// - Parameter enabled: Whether audio should play
    func setAudioEnabled(_ enabled: Bool) {
        player?.isMuted = !enabled
        player?.volume = enabled ? 1.0 : 0.0
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
    
    deinit {
        // Clean up observer synchronously (deinit can't be async)
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        // Player and window will be cleaned up automatically
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

