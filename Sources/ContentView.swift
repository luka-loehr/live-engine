import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var wallpaperManager: VideoWallpaperManager
    @State private var showingSettings = false
    @State private var selectedTab: TabSelection = .library
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var showingURLInput = false  // Keep for compatibility but not used
    
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
                // Header with glass material
                HStack(spacing: 12) {
                    Text("Library")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    IconButton(icon: "gearshape.fill", size: 12) {
                        showingSettings.toggle()
                    }
                    .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
                        SettingsView(wallpaperManager: wallpaperManager)
                            .frame(width: 200)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                
                // Content Area
                LibraryView(
                    wallpaperManager: wallpaperManager,
                    showingURLInput: $showingURLInput,
                    onAdded: { showToastMessage("Added to Library") },
                    onToast: showToastMessage
                )
                .transition(.opacity)
            }
            
            // Toast overlay
            if showToast {
                VStack {
                    Spacer()
                    ToastView(message: toastMessage)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 16)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showToast)
            }
            
        }
        .background(.thinMaterial)
        .frame(width: 460, height: 380)
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

    let columns = [
        GridItem(.adaptive(minimum: 140), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                AddWallpaperCard(wallpaperManager: wallpaperManager, onAdded: onAdded)

                ForEach(wallpaperManager.videoEntries) { entry in
                    VideoEntryCard(
                        entry: entry,
                        wallpaperManager: wallpaperManager,
                        onToast: onToast
                    )
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale(scale: 0.8).combined(with: .opacity)
                    ))
                }
            }
            .padding(16)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: wallpaperManager.videoEntries.map { $0.id })
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
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType.mpeg4Movie, UTType.movie, UTType.quickTimeMovie]
        panel.allowsOtherFileTypes = true
        panel.message = "Select a video file to add to your library"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                // Verify it's a video file
                let pathExtension = url.pathExtension.lowercased()
                let videoExtensions = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]
                
                guard videoExtensions.contains(pathExtension) else {
                    print("[FILE PICKER] Invalid file type: \(pathExtension)")
                    return
                }
                
                Task {
                    await wallpaperManager.addVideo(from: url)
                    onAdded()
                }
            }
        }
    }
}

// MARK: - Video Entry Card

struct VideoEntryCard: View {
    let entry: VideoEntry
    @ObservedObject var wallpaperManager: VideoWallpaperManager
    var onToast: (String) -> Void = { _ in }
    @State private var isHovering = false
    @State private var isHoveringDelete = false
    @State private var pulseAnimation = false

    private var isPlaying: Bool {
        wallpaperManager.currentPlayingID == entry.id
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Thumbnail or placeholder
                if let thumbnail = entry.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.width * 9/16)
                        .clipped()
                        .opacity(entry.isDownloaded ? 1.0 : 0.5)
                } else {
                    // Loading placeholder
                    Rectangle()
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .frame(width: geometry.size.width, height: geometry.size.width * 9/16)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.6)
                        )
                }

                // Delete button - bottom right, on hover
                if isHovering {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                let videoName = entry.name
                                wallpaperManager.deleteEntry(entry)
                                onToast("Removed \"\(videoName)\"")
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(isHoveringDelete ? .red : .white.opacity(0.8))
                                    .shadow(color: .black.opacity(0.5), radius: 2)
                            }
                            .buttonStyle(.plain)
                            .onHover { h in isHoveringDelete = h }
                        }
                        .padding(6)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.width * 9/16)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isPlaying ? Color.green :
                            (isHovering ? Color.white.opacity(0.4) : Color.clear),
                        lineWidth: isPlaying ? 3 : 2
                    )
                    .opacity(isPlaying ? (pulseAnimation ? 1.0 : 0.5) : 1.0)
            )
            .shadow(
                color: isPlaying ? Color.green.opacity(pulseAnimation ? 0.4 : 0.2) : Color.black.opacity(0.15),
                radius: isPlaying ? (pulseAnimation ? 8 : 4) : 4,
                y: isPlaying ? 0 : 2
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
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
                        onToast("Playing \"\(entry.name)\"")
                    }
                }
            }
            .onChange(of: isPlaying) { playing in
                if playing {
                    // Start pulsating animation
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        pulseAnimation = true
                    }
                } else {
                    // Stop animation
                    withAnimation(.easeOut(duration: 0.3)) {
                        pulseAnimation = false
                    }
                }
            }
            .onAppear {
                // Initialize animation state if already playing
                if isPlaying {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        pulseAnimation = true
                    }
                }
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
                if !hovering { isHoveringDelete = false }
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var wallpaperManager: VideoWallpaperManager
    @State private var isHoveringFolder = false
    @State private var isHoveringClear = false
    @State private var isHoveringSupport = false
    @State private var isHoveringQuit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                Text("Configure your wallpaper")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
            
            // Audio Toggle Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Playback")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(wallpaperManager.audioEnabled ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: wallpaperManager.audioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.system(size: 14))
                            .foregroundColor(wallpaperManager.audioEnabled ? .accentColor : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Audio")
                            .font(.system(size: 12, weight: .medium))
                        Text(wallpaperManager.audioEnabled ? "Enabled" : "Muted")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $wallpaperManager.audioEnabled)
                        .toggleStyle(.switch)
                        .scaleEffect(0.75)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .padding(.vertical, 8)

            Divider()

            // Actions Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Actions")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                
                VStack(spacing: 4) {
                    // Open Folder Button
                    SettingsButton(
                        icon: "folder.fill",
                        title: "Open Videos Folder",
                        iconColor: .blue,
                        isHovering: $isHoveringFolder,
                        action: {
                            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                            let videosDirectory = appSupport.appendingPathComponent("MacLiveWallpaper/Videos", isDirectory: true)
                            NSWorkspace.shared.open(videosDirectory)
                        }
                    )

                    // Clear Library Button
                    SettingsButton(
                        icon: "trash.fill",
                        title: "Clear Library",
                        iconColor: .red,
                        isHovering: $isHoveringClear,
                        action: {
                            wallpaperManager.clearLibrary()
                        }
                    )
                    
                    // Support Me Button
                    SettingsButton(
                        icon: "heart.fill",
                        title: "Support Me",
                        iconColor: .pink,
                        isHovering: $isHoveringSupport,
                        showArrow: true,
                        action: {
                            if let url = URL(string: "https://buymeacoffee.com/lukaloehr") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    )
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 8)
            
            Divider()
            
            // Quit Button Section
            VStack(spacing: 8) {
                SettingsButton(
                    icon: "power",
                    title: "Quit MacLive",
                    iconColor: .gray,
                    isHovering: $isHoveringQuit,
                    action: {
                        NSApplication.shared.terminate(nil)
                    }
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Spacer()
            
            // Version Section (at bottom)
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.green.opacity(0.7))
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("MacLive Wallpaper")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.primary.opacity(0.8))
                    Text("Version 1.0.0")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.secondary.opacity(0.05))
        }
        .frame(width: 240)
    }
}

// MARK: - Settings Button Component

struct SettingsButton: View {
    let icon: String
    let title: String
    let iconColor: Color
    @Binding var isHovering: Bool
    var showArrow: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isHovering ? iconColor.opacity(0.15) : Color.secondary.opacity(0.1))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(isHovering ? iconColor : .secondary)
                }
                
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                
                Spacer()
                
                if showArrow {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isHovering ? iconColor.opacity(0.08) : Color.clear)
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = h }
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

