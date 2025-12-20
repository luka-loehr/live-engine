import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation
import CoreImage

struct ContentView: View {
    @ObservedObject var wallpaperManager: VideoWallpaperManager
    @State private var selectedTab: TabSelection = .library
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var showingURLInput = false  // Keep for compatibility but not used
    @State private var showingSettings = false
    @State private var currentTip: String = ""
    
    private let tips = [
        "In the settings you can enable auto launch",
        "Enable and disable audio in settings",
        "Thank you for using live-engine",
        "Click on any wallpaper to set it as your desktop background",
        "Hover over a wallpaper and click the X to remove it",
        "Your wallpapers are stored locally for quick access",
        "Press Cmd+W to show the main window from menu bar",
        "Use the menu bar icon for quick controls",
        "You can support my work here: buymeacoffee.com/lukaloehr"
    ]
    
    enum TabSelection {
        case library

        var title: String {
            switch self {
            case .library: return "Library"
            }
        }

        var icon: String {
            switch self {
            case .library: return "square.grid.2x2"
            }
        }
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header - consistent layout for both views
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(showingSettings ? "Settings" : "Library")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.primary)
                        
                        if showingSettings {
                            Text("Configure live-engine preferences")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        } else {
                            if wallpaperManager.videoEntries.isEmpty {
                                Text("To get started, add a new wallpaper by uploading from your local file system")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text(currentTip.isEmpty ? tips.randomElement() ?? tips[0] : currentTip)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    
                    Spacer()

                    IconButton(icon: showingSettings ? "xmark" : "gearshape.fill", size: 14) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showingSettings.toggle()
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)
                .background(.regularMaterial)
                .onAppear {
                    if !wallpaperManager.videoEntries.isEmpty {
                        // Pick a random tip when window appears
                        currentTip = tips.randomElement() ?? tips[0]
                    }
                }
                .onChange(of: showingSettings) { _ in
                    if !showingSettings && !wallpaperManager.videoEntries.isEmpty {
                        // Pick a new random tip when returning to library
                        currentTip = tips.randomElement() ?? tips[0]
                    }
                }
                .onChange(of: wallpaperManager.videoEntries.count) { count in
                    if count > 0 && currentTip.isEmpty {
                        // Pick a tip when wallpapers are added
                        currentTip = tips.randomElement() ?? tips[0]
                    }
                }
                
                // Content Area
                if showingSettings {
                    SettingsView(wallpaperManager: wallpaperManager)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    LibraryView(
                        wallpaperManager: wallpaperManager,
                        showingURLInput: $showingURLInput,
                        onAdded: { showToastMessage("Added to Library") },
                        onToast: showToastMessage
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            
            // Toast overlay
            if showToast {
                VStack {
                    Spacer()
                    ToastView(message: toastMessage)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 24)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showToast)
            }
            
        }
        .background(.thinMaterial)
        .frame(minWidth: 600, minHeight: 400)
        .onDrop(of: [.fileURL], delegate: VideoDropDelegate(wallpaperManager: wallpaperManager, onToast: showToastMessage))
        .onChange(of: showingSettings) { newValue in
            // When switching back to library, videos will fade in smoothly
            if !newValue {
                // Library view is being shown - videos will fade in via their onAppear handlers
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowSettings"))) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showingSettings = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowLibrary"))) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showingSettings = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MainWindowShown"))) { _ in
            // Pick a new random tip when window is shown
            if !wallpaperManager.videoEntries.isEmpty {
                currentTip = tips.randomElement() ?? tips[0]
            }
        }
    }
    
    func showToastMessage(_ message: String) {
        toastMessage = message
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showToast = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeOut(duration: 0.2)) {
                showToast = false
            }
        }
    }
    
    
}

// MARK: - Toast View

struct ToastView: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.green)
            
            Text(message)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}




// MARK: - Icon Button

struct IconButton: View {
    let icon: String
    var size: CGFloat = 12
    var weight: Font.Weight = .regular
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: weight))
                .foregroundColor(isHovering ? .primary : .secondary)
                .frame(width: 26, height: 26)
                .background(isHovering ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.clear))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}


// MARK: - Library View

struct LibraryView: View {
    @ObservedObject var wallpaperManager: VideoWallpaperManager
    @Binding var showingURLInput: Bool
    var onAdded: () -> Void = {}
    var onToast: (String) -> Void = { _ in }
    @State private var draggedEntryID: String?

    let columns = [
        GridItem(.adaptive(minimum: 140), spacing: 12)
    ]

    var body: some View {
        ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    AddWallpaperCard(wallpaperManager: wallpaperManager, onAdded: onAdded)

                    ForEach(wallpaperManager.videoEntries) { entry in
                        VideoEntryCard(
                            entry: entry,
                            wallpaperManager: wallpaperManager,
                            onToast: onToast,
                            isDragging: draggedEntryID == entry.id
                        )
                        .id(entry.id)
                        .onDrag {
                            draggedEntryID = entry.id
                            return NSItemProvider(object: entry.id as NSString)
                        } preview: {
                            VideoEntryCard(
                                entry: entry,
                                wallpaperManager: wallpaperManager,
                                onToast: { _ in },
                                isDragging: false
                            )
                            .frame(width: 200, height: 112)
                        }
                        .onDrop(of: [.text], delegate: VideoDropReorderDelegate(
                            entry: entry,
                            wallpaperManager: wallpaperManager,
                            draggedEntryID: $draggedEntryID
                        ))
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.9)),
                            removal: .opacity.combined(with: .scale(scale: 0.9))
                        ))
                    }
                    .animation(.easeInOut(duration: 0.25), value: wallpaperManager.videoEntries.map { $0.id })
                }
                .padding(24)
        }
    }
}

// MARK: - Add Wallpaper Card

struct AddWallpaperCard: View {
    @ObservedObject var wallpaperManager: VideoWallpaperManager
    var onAdded: () -> Void = {}
    @State private var isHovering = false
    
    var body: some View {
        GeometryReader { geometry in
            Button(action: {
                openFilePicker()
            }) {
                ZStack {
                    // Glass background
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isHovering ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.ultraThinMaterial))
                    
                    // Subtle border
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isHovering
                                ? Color.primary.opacity(0.2)
                                : Color.primary.opacity(0.08),
                            lineWidth: 1
                        )
                    
                    // Content
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .light))
                            .foregroundColor(isHovering ? .primary : .secondary)
                        
                        Text("Add New")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(isHovering ? .primary : .secondary)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.width * 9/16)
            }
            .buttonStyle(.plain)
        }
        .aspectRatio(16/9, contentMode: .fit)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
    
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType.mpeg4Movie, UTType.movie, UTType.quickTimeMovie]
        panel.allowsOtherFileTypes = true
        panel.message = "Select video files to add to your library"
        
        panel.begin { response in
            if response == .OK {
                let videoExtensions = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]
                var validURLs: [URL] = []
                
                // Process all selected files
                for url in panel.urls {
                    let pathExtension = url.pathExtension.lowercased()
                    
                    if videoExtensions.contains(pathExtension) {
                        validURLs.append(url)
                    } else {
                        print("[FILE PICKER] Invalid file type: \(pathExtension)")
                    }
                }
                
                // Add all valid videos to library
                if !validURLs.isEmpty {
                    Task {
                        for url in validURLs {
                            await wallpaperManager.addVideo(from: url)
                        }
                        onAdded()
                    }
                }
            }
        }
    }
}

// MARK: - Video Preview View

struct VideoPreviewView: NSViewRepresentable {
    let videoURL: URL
    @Binding var isPlaying: Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = VideoPreviewContainerView()
        view.coordinator = context.coordinator
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let containerView = nsView as? VideoPreviewContainerView else { return }
        
        // Always play if isPlaying is true (which it will be for always-on previews)
        if isPlaying {
            // Only create player if we don't have one or URL changed
            if context.coordinator.player == nil || context.coordinator.videoURL != videoURL {
                context.coordinator.cleanup()
                context.coordinator.setupPlayer(url: videoURL, containerView: containerView)
            }
        } else {
            // Clean up player when not playing
            context.coordinator.cleanup()
        }
        
        // Update layer frame
        context.coordinator.updateFrame(containerView.bounds)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var player: AVPlayer?
        var playerLayer: AVPlayerLayer?
        var loopObserver: NSObjectProtocol?
        var videoURL: URL?
        
        func setupPlayer(url: URL, containerView: VideoPreviewContainerView) {
            videoURL = url
            
            // Create and configure player
            let player = AVPlayer(url: url)
            player.isMuted = true
            player.actionAtItemEnd = .none
            
            // Create player layer
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.frame = containerView.bounds
            
            // Add to view
            containerView.layer?.addSublayer(playerLayer)
            
            // Store references
            self.player = player
            self.playerLayer = playerLayer
            
            // Set up looping
            if let item = player.currentItem {
                loopObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { [weak player] _ in
                    player?.seek(to: .zero) { _ in
                        player?.play()
                    }
                }
            }
            
            // Start playing
            player.play()
        }
        
        func updateFrame(_ frame: CGRect) {
            playerLayer?.frame = frame
        }
        
        func cleanup() {
            if let observer = loopObserver {
                NotificationCenter.default.removeObserver(observer)
                loopObserver = nil
            }
            player?.pause()
            playerLayer?.removeFromSuperlayer()
            player = nil
            playerLayer = nil
            videoURL = nil
        }
        
        deinit {
            cleanup()
        }
    }
}

// Custom NSView to hold the player layer
class VideoPreviewContainerView: NSView {
    weak var coordinator: VideoPreviewView.Coordinator?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    
    override func layout() {
        super.layout()
        coordinator?.updateFrame(bounds)
    }
}

// MARK: - Video Entry Card

struct VideoEntryCard: View {
    let entry: VideoEntry
    @ObservedObject var wallpaperManager: VideoWallpaperManager
    var onToast: (String) -> Void = { _ in }
    var isDragging: Bool = false
    @State private var isHovering = false
    @State private var isHoveringDelete = false
    @State private var pulseAnimation = false
    @State private var dominantColors: [Color] = [.blue, .blue] // Default to blue gradient
    @State private var videoPreviewReady = false

    private var isPlaying: Bool {
        wallpaperManager.currentPlayingID == entry.id
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Loading placeholder - always shown until video is ready
                Rectangle()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .frame(width: geometry.size.width, height: geometry.size.width * 9/16)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.6)
                            .opacity(videoPreviewReady ? 0.0 : 1.0)
                    )
                    .opacity(videoPreviewReady ? 0.0 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: videoPreviewReady)
                
                // Video preview - fades in when ready
                if let videoURL = entry.videoURL, entry.isDownloaded {
                    VideoPreviewView(videoURL: videoURL, isPlaying: .constant(true))
                        .frame(width: geometry.size.width, height: geometry.size.width * 9/16)
                        .clipped()
                        .opacity(videoPreviewReady && !isDragging ? 1.0 : (isDragging ? 0.3 : 0.0))
                        .animation(.easeInOut(duration: 0.4), value: videoPreviewReady)
                        .animation(.easeInOut(duration: 0.2), value: isDragging)
                }

                // Delete button - bottom right, on hover
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            let videoName = entry.name
                            let truncatedName = videoName.count > 15 ? String(videoName.prefix(15)) + "..." : videoName
                            wallpaperManager.deleteEntry(entry)
                            onToast("Removed \"\(truncatedName)\"")
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(isHoveringDelete ? .red : .white.opacity(0.8))
                                .shadow(color: .black.opacity(0.5), radius: 2)
                                .animation(.easeInOut(duration: 0.2), value: isHoveringDelete)
                        }
                        .buttonStyle(.plain)
                        .onHover { h in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isHoveringDelete = h
                            }
                        }
                        .opacity(isHovering ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.2), value: isHovering)
                    }
                    .padding(6)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.width * 9/16)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                ZStack {
                    // Border with single gradient color when playing - fades in/out
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            dominantColors[0],
                            lineWidth: isHovering ? 4 : 2
                        )
                        .opacity(isPlaying ? (pulseAnimation ? 0.8 : 0.4) : 0.0)
                        // Multiple shadow layers with the same color to create glow
                        .shadow(
                            color: dominantColors[0].opacity(isPlaying ? (pulseAnimation ? 1.0 : 0.7) : 0.0),
                            radius: isHovering ? (pulseAnimation ? 18 : 12) : (pulseAnimation ? 16 : 10)
                        )
                        .shadow(
                            color: dominantColors[0].opacity(isPlaying ? (pulseAnimation ? 0.9 : 0.65) : 0.0),
                            radius: isHovering ? (pulseAnimation ? 14 : 9) : (pulseAnimation ? 12 : 8)
                        )
                        .shadow(
                            color: dominantColors[0].opacity(isPlaying ? (pulseAnimation ? 0.7 : 0.5) : 0.0),
                            radius: isHovering ? (pulseAnimation ? 10 : 7) : (pulseAnimation ? 8 : 6)
                        )
                        .shadow(
                            color: dominantColors[0].opacity(isPlaying ? (pulseAnimation ? 0.5 : 0.3) : 0.0),
                            radius: isHovering ? (pulseAnimation ? 8 : 5) : (pulseAnimation ? 6 : 4)
                        )
                        .animation(.easeInOut(duration: 0.3), value: isPlaying)
                    
                    // Subtle single color outline when hovering but not playing
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            dominantColors[0],
                            lineWidth: 2.5
                        )
                        .opacity(isHovering && !isPlaying ? 0.3 : 0.0)
                        .shadow(
                            color: dominantColors[0].opacity(isHovering && !isPlaying ? 0.4 : 0.0),
                            radius: 8
                        )
                        .shadow(
                            color: dominantColors[0].opacity(isHovering && !isPlaying ? 0.3 : 0.0),
                            radius: 6
                        )
                        .animation(.easeInOut(duration: 0.2), value: isHovering)
                }
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isHoveringDelete else { return }

                if isPlaying {
                    // Currently playing this video - stop it
                    wallpaperManager.stopWallpaper()
                    onToast("Wallpaper stopped")
                } else {
                    // Not playing - start playing this video
                    Task {
                        await wallpaperManager.setWallpaper(entry)
                        let truncatedName = entry.name.count > 15 ? String(entry.name.prefix(15)) + "..." : entry.name
                        onToast("Playing \"\(truncatedName)\"")
                    }
                }
            }
            .onChange(of: isPlaying) { playing in
                if playing {
                    // Fade in glow and start pulsating animation
                    withAnimation(.easeInOut(duration: 0.3)) {
                        // Glow will fade in via opacity
                    }
                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                        pulseAnimation = true
                    }
                } else {
                    // Fade out glow and stop animation
                    withAnimation(.easeOut(duration: 0.3)) {
                        pulseAnimation = false
                    }
                }
            }
            .onAppear {
                // Initialize animation state if already playing
                if isPlaying {
                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                        pulseAnimation = true
                    }
                }
                // Extract colors from video
                extractColorsFromVideo()
                
                // Reset preview ready state when card appears
                videoPreviewReady = false
                
                // Mark preview as ready after a short delay to allow video to start loading
                if entry.videoURL != nil, entry.isDownloaded {
                    Task {
                        // Wait a bit for the video to start loading and render first frame
                        try? await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                videoPreviewReady = true
                            }
                        }
                    }
                } else {
                    videoPreviewReady = false
                }
            }
            .onChange(of: entry.videoURL) { _ in
                extractColorsFromVideo()
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovering = hovering
            }
            if !hovering { 
                isHoveringDelete = false
            }
        }
    }
    
    private func extractColorsFromVideo() {
        guard let videoURL = entry.videoURL, entry.isDownloaded else {
            dominantColors = [.blue, .blue]
            return
        }
        
        Task {
            let colors = await extractDominantColors(from: videoURL)
            await MainActor.run {
                dominantColors = colors
            }
        }
    }
    
    private func extractDominantColors(from url: URL) async -> [Color] {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        // Get frame at 1 second (or start)
        let duration = try? await asset.load(.duration)
        let time = min(CMTime(seconds: 1.0, preferredTimescale: 600), duration ?? CMTime.zero)
        
        guard let cgImage = try? await imageGenerator.image(at: time).image else {
            return [.blue, .blue]
        }
        
        // Extract colors from different areas using Core Image
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()
        let size = ciImage.extent.size
        
        var colors: [Color] = []
        
        // Sample colors from different areas (corners and center)
        let positions: [(CGFloat, CGFloat)] = [
            (0.15, 0.15),    // top-left
            (0.85, 0.15),    // top-right
            (0.15, 0.85),    // bottom-left
            (0.85, 0.85),    // bottom-right
            (0.5, 0.5)       // center
        ]
        
        let sampleSize = CGSize(width: size.width * 0.15, height: size.height * 0.15)
        
        for (x, y) in positions {
            let rect = CGRect(
                x: size.width * x - sampleSize.width / 2,
                y: size.height * y - sampleSize.height / 2,
                width: sampleSize.width,
                height: sampleSize.height
            )
            
            let filter = CIFilter(name: "CIAreaAverage")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            filter?.setValue(CIVector(cgRect: rect), forKey: kCIInputExtentKey)
            
            if let outputImage = filter?.outputImage,
               let outputCGImage = context.createCGImage(outputImage, from: outputImage.extent) {
                // Get pixel data
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let bytesPerPixel = 4
                let bytesPerRow = bytesPerPixel
                let bitsPerComponent = 8
                var pixelData = [UInt8](repeating: 0, count: bytesPerPixel)
                
                if let context = CGContext(
                    data: &pixelData,
                    width: 1,
                    height: 1,
                    bitsPerComponent: bitsPerComponent,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) {
                    context.draw(outputCGImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                    let r = CGFloat(pixelData[0]) / 255.0
                    let g = CGFloat(pixelData[1]) / 255.0
                    let b = CGFloat(pixelData[2]) / 255.0
                    colors.append(Color(red: r, green: g, blue: b))
                }
            }
        }
        
        // If we got colors, use them; otherwise default to blue
        if colors.isEmpty {
            return [.blue, .blue]
        }
        
        // Return up to 3 most distinct colors
        return Array(colors.prefix(3))
    }
}


// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var wallpaperManager: VideoWallpaperManager
    @Environment(\.dismiss) private var dismiss
    @State private var isHoveringFolder = false
    @State private var isHoveringSupport = false
    @State private var isHoveringQuit = false
    @State private var isHoveringFooter = false
    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var scrollViewHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .trailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                // Preferences Section
                VStack(alignment: .leading, spacing: 0) {
                    Text("Preferences")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .padding(.bottom, 12)
                    
                    VStack(spacing: 0) {
                        // Audio Toggle
                        SettingsRow(
                            icon: wallpaperManager.audioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                            title: "Audio",
                            subtitle: "Enable audio playback for wallpapers",
                            isEnabled: wallpaperManager.audioEnabled
                        ) {
                            Toggle("", isOn: $wallpaperManager.audioEnabled)
                                .toggleStyle(.switch)
                        }
                        
                        Divider()
                            .padding(.leading, 24)
                        
                        // Auto Start Toggle
                        SettingsRow(
                            icon: wallpaperManager.autoStartOnLaunch ? "play.circle.fill" : "play.circle",
                            title: "Auto Start on Launch",
                            subtitle: "Automatically restore last wallpaper on app launch",
                            isEnabled: wallpaperManager.autoStartOnLaunch
                        ) {
                            Toggle("", isOn: $wallpaperManager.autoStartOnLaunch)
                                .toggleStyle(.switch)
                        }
                    }
                    .background(.regularMaterial)
                    .cornerRadius(10)
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 32)
                
                // Actions Section
                VStack(alignment: .leading, spacing: 0) {
                    Text("Actions")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                    
                    VStack(spacing: 0) {
                        // Open Folder Button
                        SettingsActionRow(
                            icon: "folder",
                            title: "Open Library",
                            subtitle: "Open the folder containing your wallpapers",
                            isHovering: isHoveringFolder
                        ) {
                            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                            let videosDirectory = appSupport.appendingPathComponent("LiveEngine/Videos", isDirectory: true)
                            NSWorkspace.shared.open(videosDirectory)
                        } onHover: { hovering in
                            withAnimation(.easeOut(duration: 0.15)) {
                                isHoveringFolder = hovering
                            }
                        }
                        
                        Divider()
                            .padding(.leading, 24)
                        
                        // Support Me Button
                        SettingsActionRow(
                            icon: "heart.fill",
                            title: "Support Me",
                            subtitle: "Buy me a coffee",
                            iconColor: .pink,
                            isHovering: isHoveringSupport
                        ) {
                            if let url = URL(string: "https://buymeacoffee.com/lukaloehr") {
                                NSWorkspace.shared.open(url)
                            }
                        } onHover: { hovering in
                            withAnimation(.easeOut(duration: 0.15)) {
                                isHoveringSupport = hovering
                            }
                        }
                    }
                    .background(.regularMaterial)
                    .cornerRadius(10)
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 32)
                
                // Quit Section
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        SettingsActionRow(
                            icon: "power",
                            title: "Quit live-engine",
                            subtitle: "Exit the application",
                            iconColor: .red,
                            isHovering: isHoveringQuit
                        ) {
                            NSApplication.shared.terminate(nil)
                        } onHover: { hovering in
                            withAnimation(.easeOut(duration: 0.15)) {
                                isHoveringQuit = hovering
                            }
                        }
                    }
                    .background(.regularMaterial)
                    .cornerRadius(10)
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 24)
                
                // Footer
                HStack {
                    Spacer()
                    Button(action: {
                        if let url = URL(string: "https://github.com/luka-loehr/live-engine") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Text("live-engine")
                                .font(.system(size: 11, weight: .medium))
                            Text("v1.0.0")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .foregroundColor(isHoveringFooter ? .accentColor : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isHoveringFooter ? Color.accentColor.opacity(0.1) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .onHover { h in
                        withAnimation(.easeOut(duration: 0.15)) { isHoveringFooter = h }
                    }
                    Spacer()
                }
                .padding(.bottom, 24)
                    }
                    .background(
                        GeometryReader { contentGeometry in
                            Color.clear
                                .preference(key: ScrollOffsetPreferenceKey.self, value: contentGeometry.frame(in: .named("scroll")).minY)
                                .preference(key: ContentHeightPreferenceKey.self, value: contentGeometry.size.height)
                        }
                    )
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = -value
                }
                .onPreferenceChange(ContentHeightPreferenceKey.self) { value in
                    contentHeight = value
                }
                .onAppear {
                    scrollViewHeight = geometry.size.height
                }
                .onChange(of: geometry.size.height) { newHeight in
                    scrollViewHeight = newHeight
                }
                .scrollIndicators(.hidden)
                
                // Custom Scrollbar
                if contentHeight > scrollViewHeight {
                    CustomScrollbar(
                        scrollOffset: scrollOffset,
                        contentHeight: contentHeight,
                        scrollViewHeight: scrollViewHeight
                    )
                    .padding(.trailing, 4)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(.thinMaterial)
    }

// MARK: - Custom Scrollbar

struct CustomScrollbar: View {
    let scrollOffset: CGFloat
    let contentHeight: CGFloat
    let scrollViewHeight: CGFloat
    @State private var isHovering = false
    
    private var scrollbarHeight: CGFloat {
        let ratio = scrollViewHeight / contentHeight
        return max(30, scrollViewHeight * ratio)
    }
    
    private var scrollbarPosition: CGFloat {
        let maxOffset = contentHeight - scrollViewHeight
        guard maxOffset > 0 else { return 0 }
        let progress = min(max(0, scrollOffset / maxOffset), 1)
        return progress * (scrollViewHeight - scrollbarHeight)
    }
    
    var body: some View {
        VStack {
            Spacer()
                .frame(height: scrollbarPosition)
            
            RoundedRectangle(cornerRadius: 3)
                .fill(isHovering ? Color.primary.opacity(0.4) : Color.primary.opacity(0.2))
                .frame(width: 4)
                .frame(height: scrollbarHeight)
                .animation(.easeOut(duration: 0.15), value: isHovering)
            
            Spacer()
        }
        .frame(width: 8)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Scroll Preference Keys

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
}

// MARK: - Settings Row Components

struct SettingsRow<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let isEnabled: Bool
    let content: Content
    
    init(
        icon: String,
        title: String,
        subtitle: String,
        isEnabled: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.isEnabled = isEnabled
        self.content = content()
    }
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(isEnabled ? .accentColor : .secondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            content
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

struct SettingsActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var iconColor: Color = .accentColor
    let isHovering: Bool
    let action: () -> Void
    let onHover: (Bool) -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(isHovering ? iconColor : .secondary)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isHovering ? iconColor : .primary)
                    
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(isHovering ? iconColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            onHover(hovering)
        }
    }
}




// MARK: - Visual Effect View

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }
    
    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}

// MARK: - Drag and Drop Reorder Delegate

struct VideoDropReorderDelegate: DropDelegate {
    let entry: VideoEntry
    let wallpaperManager: VideoWallpaperManager
    @Binding var draggedEntryID: String?
    
    func performDrop(info: DropInfo) -> Bool {
        guard let draggedID = draggedEntryID,
              let draggedEntry = wallpaperManager.videoEntries.first(where: { $0.id == draggedID }),
              draggedID != entry.id else {
            // Reset dragged state even if drop failed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                draggedEntryID = nil
            }
            return false
        }
        
        wallpaperManager.moveEntry(from: draggedEntry, to: entry)
        
        // Reset dragged state after a short delay to allow animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            draggedEntryID = nil
        }
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggedID = draggedEntryID,
              let draggedEntry = wallpaperManager.videoEntries.first(where: { $0.id == draggedID }),
              draggedID != entry.id else {
            return
        }
        
        wallpaperManager.moveEntry(from: draggedEntry, to: entry)
    }
    
    func dropExited(info: DropInfo) {
        // Optional: handle when drag exits
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

// MARK: - Drag and Drop Delegate

struct VideoDropDelegate: DropDelegate {
    let wallpaperManager: VideoWallpaperManager
    let onToast: (String) -> Void
    
    func validateDrop(info: DropInfo) -> Bool {
        // Check if we have file URLs
        return info.hasItemsConforming(to: [.fileURL])
    }
    
    func performDrop(info: DropInfo) -> Bool {
        let itemProviders = info.itemProviders(for: [.fileURL])
        
        guard !itemProviders.isEmpty else {
            return false
        }
        
        var validVideoURLs: [URL] = []
        let videoExtensions = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]
        let group = DispatchGroup()
        
        // Process all dropped files
        for itemProvider in itemProviders {
            group.enter()
            itemProvider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                defer { group.leave() }
                
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }
                
                // Check if it's a video file
                let pathExtension = url.pathExtension.lowercased()
                
                if videoExtensions.contains(pathExtension) {
                    validVideoURLs.append(url)
                }
            }
        }
        
        // Wait for all files to be processed, then add them to library
        group.notify(queue: .main) {
            Task { @MainActor in
                // Add all valid videos to library
                for url in validVideoURLs {
                    await wallpaperManager.addVideo(from: url)
                }
                
                // Show toast notification
                if validVideoURLs.count > 0 {
                    if validVideoURLs.count == 1 {
                        onToast("Added to Library")
                    } else {
                        onToast("Added \(validVideoURLs.count) videos to Library")
                    }
                }
            }
        }
        
        return true
    }
}

