import SwiftUI

struct ContentView: View {
    @ObservedObject var wallpaperManager: VideoWallpaperManager
    @State private var showingURLInput = false
    @State private var showingSettings = false
    @State private var selectedTab: TabSelection = .myWallpaper
    
    enum TabSelection: CaseIterable {
        case myWallpaper
        case explore
        
        var title: String {
            switch self {
            case .myWallpaper: return "Library"
            case .explore: return "Discover"
            }
        }
        
        var icon: String {
            switch self {
            case .myWallpaper: return "square.grid.2x2"
            case .explore: return "sparkles"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with glass material
            HStack(spacing: 12) {
                SegmentedTabBar(selectedTab: $selectedTab)
                
                Spacer()
                
                HStack(spacing: 4) {
                    IconButton(icon: "gearshape.fill", size: 12) {
                        showingSettings.toggle()
                    }
                    .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
                        SettingsView(wallpaperManager: wallpaperManager)
                            .frame(width: 200)
                    }
                    
                    IconButton(icon: "xmark", size: 10, weight: .semibold) {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            
            // Content Area
            ZStack {
                if showingURLInput {
                    URLInputView(wallpaperManager: wallpaperManager, isPresented: $showingURLInput)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    if selectedTab == .myWallpaper {
                        LibraryView(wallpaperManager: wallpaperManager, showingURLInput: $showingURLInput)
                            .transition(.opacity)
                    } else {
                        ExploreView(wallpaperManager: wallpaperManager)
                            .transition(.opacity)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedTab)
            .animation(.easeInOut(duration: 0.2), value: showingURLInput)
        }
        .background(.thinMaterial)
        .frame(width: 460, height: 380)
    }
}

// MARK: - Segmented Tab Bar

struct SegmentedTabBar: View {
    @Binding var selectedTab: ContentView.TabSelection
    @Namespace private var tabAnimation
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(ContentView.TabSelection.allCases, id: \.self) { tab in
                TabItem(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    namespace: tabAnimation
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                }
            }
        }
        .padding(3)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct TabItem: View {
    let tab: ContentView.TabSelection
    let isSelected: Bool
    var namespace: Namespace.ID
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: .medium))
                Text(tab.title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.4, green: 0.5, blue: 0.95),
                                    Color(red: 0.35, green: 0.4, blue: 0.85)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color(red: 0.35, green: 0.4, blue: 0.85).opacity(0.4), radius: 4, y: 2)
                        .matchedGeometryEffect(id: "tab", in: namespace)
                }
            }
        }
        .buttonStyle(.plain)
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

// MARK: - URL Input View

struct URLInputView: View {
    @ObservedObject var wallpaperManager: VideoWallpaperManager
    @Binding var isPresented: Bool
    @State private var urlInput: String = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 20) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(.secondary)
                
                VStack(spacing: 4) {
                    Text("Add Wallpaper")
                        .font(.system(size: 15, weight: .medium))
                    Text("Paste a YouTube link")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        TextField("youtube.com/watch?v=...", text: $urlInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .focused($isInputFocused)
                            .onSubmit(startDownload)
                        
                        if !urlInput.isEmpty {
                            Button(action: { urlInput = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                    
                    HStack(spacing: 8) {
                        Button("Cancel") {
                            isPresented = false
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .frame(width: 70, height: 28)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        
                        Button(action: startDownload) {
                            Text("Add")
                                .fontWeight(.medium)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(urlInput.isEmpty)
                    }
                }
                .frame(width: 260)
            }
            .padding(24)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isInputFocused = true
        }
    }
    
    private func startDownload() {
        guard !urlInput.isEmpty else { return }
        Task {
            await wallpaperManager.addVideo(youtubeURL: urlInput)
            isPresented = false
        }
    }
}

// MARK: - Library View

struct LibraryView: View {
    @ObservedObject var wallpaperManager: VideoWallpaperManager
    @Binding var showingURLInput: Bool
    
    let columns = [
        GridItem(.adaptive(minimum: 140), spacing: 12)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                AddWallpaperCard(showingURLInput: $showingURLInput)
                
                ForEach(wallpaperManager.videoEntries) { entry in
                    VideoEntryCard(entry: entry, wallpaperManager: wallpaperManager)
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Add Wallpaper Card

struct AddWallpaperCard: View {
    @Binding var showingURLInput: Bool
    @State private var isHovering = false
    
    var body: some View {
        GeometryReader { geometry in
            Button(action: { showingURLInput = true }) {
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
}

// MARK: - Video Entry Card

struct VideoEntryCard: View {
    let entry: VideoEntry
    @ObservedObject var wallpaperManager: VideoWallpaperManager
    @State private var isHovering = false
    @State private var isHoveringTrash = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geometry in
                ZStack(alignment: .bottomLeading) {
                    // Thumbnail
                    if let thumbnail = entry.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.width * 9/16)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(nsColor: .controlBackgroundColor).opacity(0.6),
                                        Color(nsColor: .controlBackgroundColor).opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: geometry.size.width, height: geometry.size.width * 9/16)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.6)
                            )
                    }
                    
                    // Delete button - only on hover
                    if isHovering {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Button(action: { wallpaperManager.deleteEntry(entry) }) {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(isHoveringTrash ? Color(red: 1, green: 0.4, blue: 0.4) : .white.opacity(0.9))
                                        .frame(width: 24, height: 24)
                                        .background(
                                            Circle()
                                                .fill(isHoveringTrash ? Color.red.opacity(0.25) : Color.black.opacity(0.4))
                                        )
                                }
                                .buttonStyle(.plain)
                                .onHover { h in
                                    withAnimation(.easeOut(duration: 0.15)) { isHoveringTrash = h }
                                }
                            }
                            .padding(8)
                        }
                        .transition(.opacity)
                    }
                    
                    // Download progress bar
                    if entry.isDownloading {
                        VStack {
                            Spacer()
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(height: 3)
                                    
                                    Rectangle()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.45, green: 0.55, blue: 1.0),
                                                    Color(red: 0.4, green: 0.45, blue: 0.9)
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: geo.size.width * min(entry.downloadProgress, 1.0), height: 3)
                                        .animation(.easeInOut(duration: 0.3), value: entry.downloadProgress)
                                }
                            }
                            .frame(height: 3)
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.width * 9/16)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isHoveringTrash
                                ? Color.red.opacity(0.6)
                                : (isHovering ? Color.white.opacity(0.4) : Color.clear),
                            lineWidth: 2
                        )
                )
                .shadow(color: Color.black.opacity(0.15), radius: 4, y: 2)
                .scaleEffect(isHovering ? 1.02 : 1.0)
                .onTapGesture {
                    if !isHoveringTrash {
                        Task {
                            await wallpaperManager.downloadAndSetWallpaper(entry)
                        }
                    }
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var wallpaperManager: VideoWallpaperManager
    @State private var isHoveringFolder = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Audio Toggle
            HStack {
                Image(systemName: wallpaperManager.audioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 12))
                    .foregroundColor(wallpaperManager.audioEnabled ? .accentColor : .secondary)
                    .frame(width: 20)
                
                Text("Audio")
                    .font(.system(size: 12))
                
                Spacer()
                
                Toggle("", isOn: $wallpaperManager.audioEnabled)
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
            }
            
            Divider()
            
            // Open Folder Button
            Button(action: {
                let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                let videosDirectory = appSupport.appendingPathComponent("MacLiveWallpaper/Videos", isDirectory: true)
                NSWorkspace.shared.open(videosDirectory)
            }) {
                HStack {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    
                    Text("Open Videos Folder")
                        .font(.system(size: 12))
                    
                    Spacer()
                    
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Divider()
            
            // Version
            HStack {
                Text("MacLive")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text("v1.0.0")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .padding(12)
    }
}

// MARK: - Explore View

struct ExploreView: View {
    @ObservedObject var wallpaperManager: VideoWallpaperManager
    @State private var exploreVideos: [ExploreVideo] = []
    @State private var isLoading = true
    
    let columns = [
        GridItem(.adaptive(minimum: 140), spacing: 12)
    ]
    
    var body: some View {
        ScrollView {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading wallpapers...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else if exploreVideos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No wallpapers available")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(exploreVideos) { video in
                        ExploreVideoCard(video: video, wallpaperManager: wallpaperManager)
                    }
                }
                .padding(16)
            }
        }
        .task {
            await loadExploreVideos()
        }
    }
    
    private func loadExploreVideos() async {
        var jsonURL: URL?
        
        if let bundlePath = Bundle.main.path(forResource: "explore", ofType: "json") {
            jsonURL = URL(fileURLWithPath: bundlePath)
        } else {
            let currentDir = FileManager.default.currentDirectoryPath
            let filePath = currentDir + "/explore.json"
            if FileManager.default.fileExists(atPath: filePath) {
                jsonURL = URL(fileURLWithPath: filePath)
            } else {
                let workspacePath = "/Users/luka/Documents/mac-live/explore.json"
                if FileManager.default.fileExists(atPath: workspacePath) {
                    jsonURL = URL(fileURLWithPath: workspacePath)
                }
            }
        }
        
        guard let jsonURL = jsonURL, FileManager.default.fileExists(atPath: jsonURL.path) else {
            await MainActor.run { isLoading = false }
            return
        }
        
        do {
            let data = try Data(contentsOf: jsonURL)
            let result = try JSONDecoder().decode(ExploreJSON.self, from: data)
            
            await MainActor.run {
                exploreVideos = result.videos
                isLoading = false
            }
            
            for video in result.videos {
                await loadThumbnail(for: video)
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }
    
    private func loadThumbnail(for video: ExploreVideo) async {
        let thumbnail = await MetadataService.shared.fetchThumbnail(for: video.url)
        await MainActor.run {
            if let thumbnail = thumbnail, let index = exploreVideos.firstIndex(where: { $0.id == video.id }) {
                exploreVideos[index].thumbnail = thumbnail
            }
        }
    }
}

// MARK: - Explore Video Card

struct ExploreVideoCard: View {
    let video: ExploreVideo
    @ObservedObject var wallpaperManager: VideoWallpaperManager
    @State private var isHovering = false
    @State private var isHoveringAdd = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Thumbnail
                if let thumbnail = video.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.width * 9/16)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(nsColor: .controlBackgroundColor).opacity(0.6),
                                    Color(nsColor: .controlBackgroundColor).opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: geometry.size.width, height: geometry.size.width * 9/16)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.6)
                        )
                }
                
                // Add button overlay - shown on hover
                if isHovering {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                Task {
                                    await wallpaperManager.addVideo(youtubeURL: video.url)
                                }
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(
                                        isHoveringAdd
                                            ? LinearGradient(
                                                colors: [
                                                    Color(red: 0.5, green: 0.6, blue: 1.0),
                                                    Color(red: 0.45, green: 0.5, blue: 0.95)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                            : LinearGradient(
                                                colors: [.white, .white.opacity(0.9)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                    )
                                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                            }
                            .buttonStyle(.plain)
                            .onHover { h in
                                withAnimation(.easeOut(duration: 0.15)) { isHoveringAdd = h }
                            }
                        }
                        .padding(10)
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.width * 9/16)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isHovering ? Color.white.opacity(0.4) : Color.clear,
                        lineWidth: 2
                    )
            )
            .shadow(color: Color.black.opacity(0.15), radius: 4, y: 2)
            .scaleEffect(isHovering ? 1.02 : 1.0)
        }
        .aspectRatio(16/9, contentMode: .fit)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Explore Models

struct ExploreJSON: Codable {
    let videos: [ExploreVideo]
}

struct ExploreVideo: Identifiable {
    let id: String
    let title: String
    let url: String
    var thumbnail: NSImage?
}

extension ExploreVideo: Codable {
    enum CodingKeys: String, CodingKey {
        case id, title, url
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

