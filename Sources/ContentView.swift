import SwiftUI

struct ContentView: View {
    @ObservedObject var wallpaperManager: VideoWallpaperManager
    @State private var showingURLInput = false
    @State private var showingSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Wallpapers")
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
            
            Divider()
            
            // Content
            if showingURLInput {
                URLInputView(wallpaperManager: wallpaperManager, isPresented: $showingURLInput)
            } else {
                LibraryView(wallpaperManager: wallpaperManager, showingURLInput: $showingURLInput)
            }
        }
        .frame(width: 420, height: 360)
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

