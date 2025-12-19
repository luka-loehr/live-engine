import SwiftUI

struct ContentView: View {
    @ObservedObject var wallpaperManager: VideoWallpaperManager
    @State private var showingURLInput = false
    @State private var showingSettings = false
    @State private var selectedTab: TabSelection = .myWallpaper
    
    enum TabSelection {
        case myWallpaper
        case explore
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Tabs
            VStack(spacing: 0) {
                HStack {
                    Text(selectedTab == .myWallpaper ? "My Wallpapers" : "Explore")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    
                    Button(action: { showingSettings.toggle() }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingSettings) {
                        SettingsView(wallpaperManager: wallpaperManager)
                            .frame(width: 220)
                    }
                    
                    Button(action: { NSApplication.shared.terminate(nil) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
                
                // Tab Bar
                HStack(spacing: 0) {
                    TabButton(title: "My Wallpapers", isSelected: selectedTab == .myWallpaper) {
                        selectedTab = .myWallpaper
                    }
                    TabButton(title: "Explore", isSelected: selectedTab == .explore) {
                        selectedTab = .explore
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
            }
            
            Divider()
            
            // Content
            if showingURLInput {
                URLInputView(wallpaperManager: wallpaperManager, isPresented: $showingURLInput)
            } else {
                if selectedTab == .myWallpaper {
                    LibraryView(wallpaperManager: wallpaperManager, showingURLInput: $showingURLInput)
                } else {
                    ExploreView(wallpaperManager: wallpaperManager)
                }
            }
        }
        .frame(width: 420, height: 360)
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .primary : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
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
                Text("Add Wallpaper")
                    .font(.title3)
                    .fontWeight(.medium)
                
                VStack(spacing: 16) {
                    TextField("Paste YouTube link", text: $urlInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($isInputFocused)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                        .cornerRadius(8)
                        .onSubmit(startDownload)
                    
                    HStack(spacing: 12) {
                        Button("Cancel") {
                            isPresented = false
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        
                        Button(action: startDownload) {
                            Text("Add")
                                .fontWeight(.medium)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(urlInput.isEmpty)
                    }
                }
                .frame(maxWidth: 280)
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
        GridItem(.adaptive(minimum: 130), spacing: 14)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                AddWallpaperCard(showingURLInput: $showingURLInput)
                
                ForEach(wallpaperManager.videoEntries) { entry in
                    VideoEntryCard(entry: entry, wallpaperManager: wallpaperManager)
                }
            }
            .padding(12)
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
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                        )
                        .foregroundColor(isHovering ? .accentColor.opacity(0.8) : .secondary.opacity(0.3))
                        .animation(.easeInOut(duration: 0.2), value: isHovering)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .ultraLight))
                        .foregroundColor(isHovering ? .accentColor : .secondary.opacity(0.6))
                        .animation(.easeInOut(duration: 0.2), value: isHovering)
                }
                .frame(width: geometry.size.width, height: geometry.size.width * 9/16)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .aspectRatio(16/9, contentMode: .fit)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
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
            // Thumbnail with title overlay
            GeometryReader { geometry in
                ZStack(alignment: .bottomLeading) {
                    if let thumbnail = entry.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.width * 9/16)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: geometry.size.width, height: geometry.size.width * 9/16)
                    }
                    
                    // Single background bar with title and trash icon - only on hover
                    if isHovering {
                        VStack {
                            Spacer()
                            HStack(alignment: .center, spacing: 8) {
                                // Title - left side
                                if isEditingTitle {
                                    TextField("Title", text: $editedTitle)
                                        .font(.system(size: 10))
                                        .textFieldStyle(.plain)
                                        .multilineTextAlignment(.leading)
                                        .foregroundColor(.white)
                                        .onSubmit {
                                            if !editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                wallpaperManager.renameEntry(entry, newName: editedTitle.trimmingCharacters(in: .whitespacesAndNewlines))
                                            }
                                            isEditingTitle = false
                                        }
                                        .onAppear {
                                            editedTitle = entry.name
                                        }
                                } else {
                                    Text(entry.name)
                                        .font(.system(size: 10))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .foregroundColor(.white)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .onTapGesture {
                                            isEditingTitle = true
                                            editedTitle = entry.name
                                        }
                                }
                                
                                Spacer()
                                
                                // Delete button - right side
                                Button(action: {
                                    wallpaperManager.deleteEntry(entry)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                        .foregroundColor(isHoveringTrash ? .red : .white)
                                        .frame(width: 20, height: 20)
                                        .opacity(isHoveringTrash ? 1.0 : 0.8)
                                }
                                .buttonStyle(.plain)
                                .onHover { hovering in
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isHoveringTrash = hovering
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(Color.black.opacity(0.7))
                        }
                        .transition(.opacity)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.width * 9/16)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isHoveringTrash ? Color.red.opacity(0.8) : 
                            (isHovering ? Color.white.opacity(0.6) : Color.clear),
                            lineWidth: 2
                        )
                        .animation(.easeInOut(duration: 0.2), value: isHovering)
                        .animation(.easeInOut(duration: 0.2), value: isHoveringTrash)
                )
                .overlay(
                    // Download progress overlay
                    entry.isDownloading ? 
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.black.opacity(0.3))
                                    .frame(height: 3)
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(width: geo.size.width * min(entry.downloadProgress, 1.0), height: 3)
                                    .animation(.easeInOut(duration: 0.3), value: entry.downloadProgress)
                            }
                        }
                        .padding(.bottom, 8)
                    } : nil
                )
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
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var wallpaperManager: VideoWallpaperManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $wallpaperManager.audioEnabled) {
                HStack {
                    Image(systemName: wallpaperManager.audioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .frame(width: 16)
                    Text("Audio")
                }
                .font(.system(size: 12))
            }
            .toggleStyle(.switch)
            
            Divider()
            
            Button(action: {
                let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                let videosDirectory = appSupport.appendingPathComponent("MacLiveWallpaper/Videos", isDirectory: true)
                NSWorkspace.shared.open(videosDirectory)
            }) {
                HStack {
                    Image(systemName: "folder")
                        .frame(width: 16)
                    Text("Open Videos Folder")
                }
                .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            
            Divider()
            
            Text("v1.0.0")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(12)
    }
}

// MARK: - Explore View

struct ExploreView: View {
    @ObservedObject var wallpaperManager: VideoWallpaperManager
    @State private var exploreVideos: [ExploreVideo] = []
    @State private var isLoading = true
    @State private var selectedVideoID: String? = nil
    
    let columns = [
        GridItem(.adaptive(minimum: 130), spacing: 14)
    ]
    
    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .padding(.top, 100)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(exploreVideos) { video in
                        ExploreVideoCard(
                            video: video,
                            wallpaperManager: wallpaperManager,
                            isSelected: selectedVideoID == video.id,
                            onSelect: {
                                if selectedVideoID == video.id {
                                    selectedVideoID = nil
                                } else {
                                    selectedVideoID = video.id
                                }
                            }
                        )
                    }
                }
                .padding(12)
            }
        }
        .task {
            await loadExploreVideos()
        }
        .onTapGesture {
            // Deselect when clicking empty space
            selectedVideoID = nil
        }
    }
    
    private func loadExploreVideos() async {
        var jsonURL: URL?
        
        // Try bundle first
        if let bundlePath = Bundle.main.path(forResource: "explore", ofType: "json") {
            jsonURL = URL(fileURLWithPath: bundlePath)
        } else {
            // Try current directory
            let currentDir = FileManager.default.currentDirectoryPath
            let filePath = currentDir + "/explore.json"
            if FileManager.default.fileExists(atPath: filePath) {
                jsonURL = URL(fileURLWithPath: filePath)
            } else {
                // Try workspace root
                let workspacePath = "/Users/luka/Documents/mac-live/explore.json"
                if FileManager.default.fileExists(atPath: workspacePath) {
                    jsonURL = URL(fileURLWithPath: workspacePath)
                }
            }
        }
        
        guard let jsonURL = jsonURL, FileManager.default.fileExists(atPath: jsonURL.path) else {
            print("explore.json not found")
            await MainActor.run {
                isLoading = false
            }
            return
        }
        
        do {
            let data = try Data(contentsOf: jsonURL)
            let decoder = JSONDecoder()
            let result = try decoder.decode(ExploreJSON.self, from: data)
            
            await MainActor.run {
                exploreVideos = result.videos
                isLoading = false
            }
            
            // Load thumbnails for all videos
            for video in result.videos {
                await loadThumbnail(for: video)
            }
        } catch {
            print("Failed to load explore.json: \(error)")
            await MainActor.run {
                isLoading = false
            }
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
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                if let thumbnail = video.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.width * 9/16)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: geometry.size.width, height: geometry.size.width * 9/16)
                }
                
                // Darkened overlay when selected and hovering
                Rectangle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: geometry.size.width, height: geometry.size.width * 9/16)
                    .opacity(isSelected && isHovering ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.2), value: isSelected && isHovering)
                
                // Title overlay - only on hover (when not selected)
                VStack {
                    Spacer()
                    HStack {
                        Text(video.title)
                            .font(.system(size: 10))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.7))
                }
                .opacity(isHovering && !isSelected ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.2), value: isHovering && !isSelected)
                
                // Add to Library button - shown when selected and hovering
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            Task {
                                await wallpaperManager.addVideo(youtubeURL: video.url)
                                onSelect() // Deselect after adding
                            }
                        }) {
                            Text("Add to Library")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.accentColor)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    Spacer()
                }
                .opacity(isSelected && isHovering ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.2), value: isSelected && isHovering)
            }
            .frame(width: geometry.size.width, height: geometry.size.width * 9/16)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isHovering && !isSelected ? Color.white.opacity(0.6) : Color.clear,
                        lineWidth: 2
                    )
                    .animation(.easeInOut(duration: 0.2), value: isHovering)
                    .animation(.easeInOut(duration: 0.2), value: isSelected)
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    onSelect()
                }
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
                // Deselect when hovering stops
                if !hovering && isSelected {
                    onSelect()
                }
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

