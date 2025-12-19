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
        ZStack {
            // Subtle gradient background
            LinearGradient(
                colors: [
                    Color(nsColor: NSColor.windowBackgroundColor),
                    Color(nsColor: NSColor.windowBackgroundColor).opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Compact Header
                HStack(spacing: 12) {
                    // Tab Switcher
                    SegmentedTabBar(selectedTab: $selectedTab)
                    
                    Spacer()
                    
                    // Action Buttons
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
                .padding(.vertical, 14)
                
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
        }
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
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
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
                .background(
                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 0.8 : 0.4))
                )
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
    @State private var isHoveringCancel = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.4, green: 0.5, blue: 0.95).opacity(0.2),
                                    Color(red: 0.35, green: 0.4, blue: 0.85).opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.45, green: 0.55, blue: 1.0),
                                    Color(red: 0.4, green: 0.45, blue: 0.9)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                VStack(spacing: 6) {
                    Text("Add Wallpaper")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Paste a YouTube link to add it to your library")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 14) {
                    HStack(spacing: 0) {
                        Image(systemName: "link")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: 36)
                        
                        TextField("youtube.com/watch?v=...", text: $urlInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .focused($isInputFocused)
                            .onSubmit(startDownload)
                        
                        if !urlInput.isEmpty {
                            Button(action: { urlInput = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 10)
                        }
                    }
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    )
                    
                    HStack(spacing: 10) {
                        Button(action: { isPresented = false }) {
                            Text("Cancel")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(isHoveringCancel ? .primary : .secondary)
                                .frame(width: 80, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(nsColor: .controlBackgroundColor).opacity(isHoveringCancel ? 0.8 : 0.5))
                                )
                        }
                        .buttonStyle(.plain)
                        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { isHoveringCancel = h } }
                        
                        Button(action: startDownload) {
                            Text("Add to Library")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(
                                                    LinearGradient(
                                                        colors: urlInput.isEmpty
                                                            ? [Color.gray.opacity(0.3), Color.gray.opacity(0.25)]
                                                            : [Color(red: 0.4, green: 0.5, blue: 0.95), Color(red: 0.35, green: 0.4, blue: 0.85)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .shadow(color: urlInput.isEmpty ? .clear : Color(red: 0.35, green: 0.4, blue: 0.85).opacity(0.3), radius: 4, y: 2)
                                        )
                        }
                        .buttonStyle(.plain)
                        .disabled(urlInput.isEmpty)
                    }
                }
                .frame(width: 280)
            }
            .padding(.horizontal, 32)
            
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
                    // Background with gradient
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 0.9 : 0.5),
                                    Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 0.7 : 0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Border glow on hover
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: isHovering ? [
                                    Color(red: 0.45, green: 0.55, blue: 1.0).opacity(0.6),
                                    Color(red: 0.4, green: 0.45, blue: 0.9).opacity(0.3)
                                ] : [
                                    Color.primary.opacity(0.1),
                                    Color.primary.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                    
                    // Content
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: isHovering ? [
                                            Color(red: 0.4, green: 0.5, blue: 0.95).opacity(0.3),
                                            Color(red: 0.35, green: 0.4, blue: 0.85).opacity(0.15)
                                        ] : [
                                            Color.primary.opacity(0.08),
                                            Color.primary.opacity(0.04)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 36, height: 36)
                            
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(
                                    isHovering
                                        ? LinearGradient(
                                            colors: [
                                                Color(red: 0.5, green: 0.6, blue: 1.0),
                                                Color(red: 0.45, green: 0.5, blue: 0.95)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                        : LinearGradient(
                                            colors: [Color.secondary, Color.secondary],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                )
                        }
                        
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    
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
                    
                    // Gradient overlay at bottom
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0),
                            Color.black.opacity(isHovering ? 0.8 : 0.5)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geometry.size.width * 9/16 * 0.5)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    
                    // Title and controls bar
                    VStack {
                        Spacer()
                        HStack(alignment: .center, spacing: 8) {
                            if isEditingTitle {
                                TextField("Title", text: $editedTitle)
                                    .font(.system(size: 11, weight: .medium))
                                    .textFieldStyle(.plain)
                                    .foregroundColor(.white)
                                    .onSubmit {
                                        if !editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            wallpaperManager.renameEntry(entry, newName: editedTitle.trimmingCharacters(in: .whitespacesAndNewlines))
                                        }
                                        isEditingTitle = false
                                    }
                                    .onAppear { editedTitle = entry.name }
                            } else {
                                Text(entry.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                    .foregroundColor(.white)
                                    .onTapGesture {
                                        isEditingTitle = true
                                        editedTitle = entry.name
                                    }
                            }
                            
                            Spacer()
                            
                            // Delete button - only on hover
                            if isHovering {
                                Button(action: { wallpaperManager.deleteEntry(entry) }) {
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(isHoveringTrash ? Color(red: 1, green: 0.4, blue: 0.4) : .white.opacity(0.8))
                                        .frame(width: 22, height: 22)
                                        .background(
                                            Circle()
                                                .fill(isHoveringTrash ? Color.red.opacity(0.2) : Color.white.opacity(0.1))
                                        )
                                }
                                .buttonStyle(.plain)
                                .onHover { h in
                                    withAnimation(.easeOut(duration: 0.15)) { isHoveringTrash = h }
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
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
                .shadow(
                    color: Color.black.opacity(isHovering ? 0.3 : 0.15),
                    radius: isHovering ? 8 : 4,
                    y: isHovering ? 4 : 2
                )
                .scaleEffect(isHovering ? 1.02 : 1.0)
                .onTapGesture {
                    if !isHoveringTrash && !isEditingTitle {
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
        VStack(alignment: .leading, spacing: 12) {
            // Audio Toggle
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: wallpaperManager.audioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 12))
                        .foregroundColor(wallpaperManager.audioEnabled ? Color(red: 0.45, green: 0.55, blue: 1.0) : .secondary)
                }
                
                VStack(alignment: .leading, spacing: 1) {
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
            
            Divider()
                .opacity(0.5)
            
            // Open Folder Button
            Button(action: {
                let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                let videosDirectory = appSupport.appendingPathComponent("MacLiveWallpaper/Videos", isDirectory: true)
                NSWorkspace.shared.open(videosDirectory)
            }) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(isHoveringFolder ? 0.8 : 0.5))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "folder.fill")
                            .font(.system(size: 12))
                            .foregroundColor(isHoveringFolder ? Color(red: 0.45, green: 0.55, blue: 1.0) : .secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Videos Folder")
                            .font(.system(size: 12, weight: .medium))
                        Text("Open in Finder")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
            .buttonStyle(.plain)
            .onHover { h in
                withAnimation(.easeOut(duration: 0.15)) { isHoveringFolder = h }
            }
            
            Divider()
                .opacity(0.5)
            
            // Version
            HStack {
                Text("MacLive")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text("v1.0.0")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .padding(14)
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
                
                // Gradient overlay
                LinearGradient(
                    colors: [
                        Color.black.opacity(0),
                        Color.black.opacity(isHovering ? 0.85 : 0.5)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: geometry.size.width * 9/16 * 0.6)
                .frame(maxHeight: .infinity, alignment: .bottom)
                
                // Content overlay
                VStack {
                    Spacer()
                    
                    HStack(alignment: .bottom) {
                        // Title
                        Text(video.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        // Add button - shown on hover
                        if isHovering {
                            Button(action: {
                                Task {
                                    await wallpaperManager.addVideo(youtubeURL: video.url)
                                }
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 20))
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
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(10)
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
            .shadow(
                color: Color.black.opacity(isHovering ? 0.3 : 0.15),
                radius: isHovering ? 8 : 4,
                y: isHovering ? 4 : 2
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
        }
        .aspectRatio(16/9, contentMode: .fit)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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

