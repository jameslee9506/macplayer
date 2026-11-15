import SwiftUI
import UniformTypeIdentifiers

// MARK: - Dark Thin Scroller

/// Custom NSScroller with a thin, dark-toned knob that blends with the sidebar.
private class DarkOverlayScroller: NSScroller {
    override class func scrollerWidth(
        for controlSize: NSControl.ControlSize,
        scrollerStyle: NSScroller.Style
    ) -> CGFloat { 8 }

    override func draw(_ dirtyRect: NSRect) {
        drawKnob()
    }

    override func drawKnob() {
        let r = rect(for: .knob)
        guard !r.isEmpty else { return }
        let path = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 2, yRadius: 2)
        NSColor.white.withAlphaComponent(0.15).setFill()
        path.fill()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
}

/// Background helper that swaps the sibling NSScrollView's scroller to the dark thin variant.
/// `.background()` places this view as a sibling of the ScrollView, not inside it,
/// so we walk UP to find a common ancestor, then search DOWN for NSScrollView.
private struct DarkScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // asyncAfter: view hierarchy needs a layout pass to be fully connected
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Self.applyDarkScroller(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private static func applyDarkScroller(from view: NSView) {
        // Walk up a few levels to find a common SwiftUI container,
        // then search its subtree for the NSScrollView sibling.
        var ancestor: NSView? = view
        for _ in 0..<6 {
            guard let parent = ancestor?.superview else { break }
            if let scrollView = findScrollView(in: parent) {
                scrollView.scrollerStyle = .overlay
                let scroller = DarkOverlayScroller()
                scroller.controlSize = .mini
                scrollView.verticalScroller = scroller
                return
            }
            ancestor = parent
        }
    }

    private static func findScrollView(in view: NSView) -> NSScrollView? {
        for subview in view.subviews {
            if let sv = subview as? NSScrollView {
                return sv
            }
            if let found = findScrollView(in: subview) {
                return found
            }
        }
        return nil
    }
}

extension View {
    /// Apply thin dark-toned overlay scrollbar matching the sidebar design.
    func darkScrollbar() -> some View {
        self.background(DarkScrollerConfigurator())
    }
}

/// Sidebar tab selection.
enum SidebarTab: Hashable {
    case playlist
    case filters
    case info
    case bookmarks
    case highlights
    case tracks
}

/// Tabbed sidebar panel that slides in from the right.
/// Contains playlist and filter/adjustments tabs.
struct SidePanel: View {
    /// Panel width. `PlayerContentView` reserves exactly this much beside the video.
    static let width: CGFloat = 280

    let engine: PlaybackEngine
    @Binding var selectedTab: SidebarTab?

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar + close button
            header

            // Tab content
            Group {
                switch selectedTab {
                case .playlist:
                    playlistContent
                case .filters:
                    filtersContent
                case .info:
                    mediaInfoContent
                case .bookmarks:
                    bookmarksContent
                case .highlights:
                    highlightsContent
                case .tracks:
                    tracksContent
                case .none:
                    EmptyView()
                }
            }
        }
        .ignoresSafeArea()
        .frame(width: Self.width)
        .background(.black.opacity(0.85))
        .background(.ultraThinMaterial)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header (single-row tabs)

    /// One fixed row: the selected tab shows icon + label at its natural width,
    /// the rest collapse to icons and share the remaining width equally.
    private var header: some View {
        HStack(spacing: 4) {
            tabButton("Playlist", icon: "list.bullet", tab: .playlist)
            tabButton("Filters", icon: "slider.horizontal.3", tab: .filters)
            tabButton("Info", icon: "info.circle", tab: .info)
            tabButton("Bookmarks", icon: "bookmark.fill", tab: .bookmarks)
            tabButton("Highlights", icon: "star.fill", tab: .highlights)
            tabButton("Tracks", icon: "captions.bubble", tab: .tracks)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func tabButton(_ title: String, icon: String, tab: SidebarTab) -> some View {
        let isActive = selectedTab == tab
        return Button(action: { selectedTab = tab }) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                if isActive {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(isActive ? .white : .white.opacity(0.45))
            .padding(.horizontal, isActive ? 10 : 0)
            .frame(maxWidth: isActive ? nil : .infinity)
            .frame(height: 26)
            .contentShape(Rectangle())
            .background(isActive ? .white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    // MARK: - Playlist Content

    private var playlistContent: some View {
        VStack(spacing: 0) {
            // Item count
            HStack {
                Text("\(engine.playlist.items.count) items")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if engine.playlist.items.isEmpty {
                playlistEmptyState
            } else {
                playlistItemList
            }
        }
    }

    private var playlistEmptyState: some View {
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { i in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.07))
                        .frame(width: 16, height: 14)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.07))
                        .frame(height: 14)
                        .frame(maxWidth: .infinity)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.05))
                        .frame(width: 44, height: 14)
                }
                .padding(.horizontal, 8)
                .frame(height: 40)
                .opacity(1.0 - Double(i) * 0.2)
            }

            Text("No items")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.15))
                .padding(.top, 12)

            Spacer()
        }
    }

    private var playlistItemList: some View {
        List {
            ForEach(Array(engine.playlist.items.enumerated()), id: \.element.id) { index, item in
                PlaylistRow(
                    item: item,
                    isPlaying: engine.playlist.currentIndex == index,
                    index: index
                )
                .listRowBackground(
                    engine.playlist.currentIndex == index
                        ? Color.white.opacity(0.1)
                        : Color.clear
                )
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                .contentShape(Rectangle())
                .onTapGesture {
                    Task {
                        if let url = engine.playlist.play(at: index) {
                            await engine.load(url: url)
                        }
                    }
                }
            }
            .onMove { source, destination in
                engine.playlist.move(from: source, to: destination)
            }
            .onDelete { offsets in
                engine.playlist.remove(at: offsets)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .darkScrollbar()
        .environment(\.defaultMinListRowHeight, 36)
    }

    // MARK: - Filters Content

    private var filtersContent: some View {
        Group {
            if !engine.state.isActive {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.15))
                    Text("No media loaded")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.25))
                    Spacer()
                }
            } else {
                filtersControls
            }
        }
    }

    private var filtersControls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Filters
                sectionHeader("Filters")
                ForEach(engine.filters.filters.indices, id: \.self) { i in
                    filterRow(index: i)
                }

                Divider().padding(.vertical, 8).opacity(0.3)

                // Rotation
                sectionHeader("Rotation")
                HStack {
                    Text("\(engine.videoRotation)\u{00B0}")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 36, alignment: .trailing)
                    Spacer()
                    Button("\u{2212}90") { engine.rotateBy(-90) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("+90") { engine.rotateBy(90) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Reset") { engine.setRotation(0) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(engine.videoRotation == 0)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

                Divider().padding(.vertical, 8).opacity(0.3)

                // Audio Sync
                sectionHeader("Audio Sync")
                HStack(spacing: 8) {
                    Text(audioDelayLabel)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 52, alignment: .trailing)
                    Slider(
                        value: audioDelayBinding,
                        in: -5...5,
                        step: 0.05
                    )
                    Button("Reset") { engine.setAudioDelay(0) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(engine.audioDelay == 0)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

                Divider().padding(.vertical, 4).opacity(0.3)

                // Reset All
                Button {
                    engine.resetAllAdjustments()
                } label: {
                    Text("Reset All")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(hasAnyAdjustment ? .white.opacity(0.85) : .white.opacity(0.25))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(hasAnyAdjustment ? .white.opacity(0.1) : .white.opacity(0.04),
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(!hasAnyAdjustment)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                // Per-file notice
                HStack(spacing: 7) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.blue.opacity(0.7))
                    Text("Adjustments are saved per file")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.blue.opacity(0.15), lineWidth: 0.5))
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .darkScrollbar()
    }

    // MARK: - Bookmarks Content

    private var currentBookmarks: [Bookmark] {
        guard let url = engine.currentURL else { return [] }
        return engine.bookmarks.bookmarks(for: url)
    }

    private var bookmarksContent: some View {
        VStack(spacing: 0) {
            // Item count
            HStack {
                Text("\(currentBookmarks.count) bookmarks")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if !currentBookmarks.isEmpty {
                    Button {
                        if let url = engine.currentURL {
                            engine.bookmarks.removeAllBookmarks(for: url)
                        }
                    } label: {
                        Text("Clear All")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if currentBookmarks.isEmpty {
                bookmarksEmptyState
            } else {
                bookmarksList
            }
        }
    }

    private var bookmarksEmptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "bookmark")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.15))
            Text("No bookmarks")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.25))
            Text("Press B to add")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.15))
            Spacer()
        }
    }

    private var bookmarksList: some View {
        List {
            ForEach(currentBookmarks) { bookmark in
                BookmarkRow(bookmark: bookmark) {
                    engine.bookmarks.removeBookmark(bookmark)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                .contentShape(Rectangle())
                .onTapGesture {
                    Task { await engine.seek(to: bookmark.time) }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .darkScrollbar()
        .environment(\.defaultMinListRowHeight, 48)
    }

    // MARK: - Highlights Content

    private var currentHighlightSegments: [HighlightSegment] {
        guard let url = engine.currentURL else { return [] }
        return engine.highlights.segments(for: url)
    }

    private var highlightsContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(currentHighlightSegments.count) highlights")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if !currentHighlightSegments.isEmpty {
                    Button {
                        engine.toggleHighlights()
                    } label: {
                        Text(engine.highlights.isEnabled ? "ON" : "OFF")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(engine.highlights.isEnabled ? .yellow : .white.opacity(0.4))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                engine.highlights.isEnabled ? Color.yellow.opacity(0.15) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 3)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        if let url = engine.currentURL {
                            engine.highlights.removeAllSegments(for: url)
                        }
                    } label: {
                        Text("Clear All")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if currentHighlightSegments.isEmpty {
                highlightsEmptyState
            } else {
                highlightsList
            }
        }
    }

    private var highlightsEmptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "star")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.15))
            Text("No highlights")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.25))
            Text("Shift+H to start, Option+H to end")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.15))
            Spacer()
        }
    }

    private var highlightsList: some View {
        List {
            ForEach(currentHighlightSegments) { segment in
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow.opacity(0.6))

                    Text("\(formatTime(segment.startTime)) – \(formatTime(segment.endTime))")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))

                    Spacer()

                    Button {
                        engine.highlights.removeSegment(segment)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                .contentShape(Rectangle())
                .onTapGesture {
                    Task { await engine.seek(to: segment.startTime) }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .darkScrollbar()
        .environment(\.defaultMinListRowHeight, 32)
    }

    // MARK: - Tracks Content

    private var tracksContent: some View {
        Group {
            if !engine.state.isActive {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "captions.bubble")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.15))
                    Text("No media loaded")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.25))
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Subtitle tracks
                        sectionHeader("Subtitles")

                        if engine.tracks.subtitleTracks.isEmpty {
                            HStack {
                                Text("No subtitle tracks")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.35))
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                        } else {
                            // "Off" option
                            trackRow(
                                label: "Off",
                                detail: nil,
                                isSelected: engine.tracks.currentSubtitleID == 0,
                                action: { engine.setSubtitleTrack(id: 0) }
                            )

                            // Internal subtitles
                            let internalSubs = engine.tracks.subtitleTracks.filter { !$0.isExternal }
                            let externalSubs = engine.tracks.subtitleTracks.filter { $0.isExternal }

                            if !internalSubs.isEmpty {
                                subtitleGroupHeader("Internal")
                                ForEach(internalSubs) { track in
                                    trackRow(
                                        label: track.displayLabel,
                                        detail: trackDetail(track),
                                        isSelected: engine.tracks.currentSubtitleID == track.id,
                                        action: { engine.setSubtitleTrack(id: track.id) }
                                    )
                                }
                            }

                            // External subtitles
                            if !externalSubs.isEmpty {
                                subtitleGroupHeader("External")
                                ForEach(externalSubs) { track in
                                    externalSubtitleRow(track: track)
                                }
                            }
                        }

                        // Add Subtitle File button
                        addSubtitleButton

                        Divider().padding(.vertical, 8).opacity(0.3)

                        // Audio tracks
                        sectionHeader("Audio")

                        if engine.tracks.audioTracks.isEmpty {
                            HStack {
                                Text("No audio tracks")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.35))
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                        } else {
                            ForEach(engine.tracks.audioTracks) { track in
                                trackRow(
                                    label: track.displayLabel,
                                    detail: trackDetail(track),
                                    isSelected: engine.tracks.currentAudioID == track.id,
                                    action: { engine.setAudioTrack(id: track.id) }
                                )
                            }
                        }

                        // Keyboard shortcut hint
                        Divider().padding(.vertical, 8).opacity(0.3)

                        HStack(spacing: 7) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.35))
                            Text("J — cycle subtitle  |  ⇧J — cycle audio")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                    }
                }
                .darkScrollbar()
            }
        }
    }

    private func subtitleGroupHeader(_ title: String) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(height: 0.5)
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
                .textCase(.uppercase)
            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(height: 0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func externalSubtitleRow(track: MediaTrack) -> some View {
        let isSelected = engine.tracks.currentSubtitleID == track.id
        return Button(action: { engine.setSubtitleTrack(id: track.id) }) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? .blue : .white.opacity(0.25))

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.displayLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.75))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let detail = trackDetail(track) {
                        Text(detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isSelected {
                    Text("Active")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                }

                // Remove button for external subtitles
                Button {
                    engine.removeSubtitle(id: track.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(isSelected ? .white.opacity(0.06) : .clear)
        }
        .buttonStyle(.plain)
    }

    private var addSubtitleButton: some View {
        Button {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = PlaylistManager.subtitleExtensions.compactMap {
                UTType(filenameExtension: $0)
            }
            panel.allowsMultipleSelection = true
            panel.message = "Select subtitle files"

            guard panel.runModal() == .OK else { return }
            for url in panel.urls {
                engine.addExternalSubtitle(url: url)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 11, weight: .medium))
                Text("Add Subtitle File...")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func trackRow(label: String, detail: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? .blue : .white.opacity(0.25))

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.75))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let detail {
                        Text(detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isSelected {
                    Text("Active")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(isSelected ? .white.opacity(0.06) : .clear)
        }
        .buttonStyle(.plain)
    }

    private func trackDetail(_ track: MediaTrack) -> String? {
        var parts: [String] = []
        if let codec = track.codec { parts.append(codec) }
        if track.isDefault { parts.append("default") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Media Info Content

    private var mediaInfoContent: some View {
        Group {
            if let info = engine.mediaInfo {
                ScrollView {
                    VStack(spacing: 10) {
                        // File info card
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.35))

                            // Clickable title — reveals in Finder
                            if let url = engine.currentURL {
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(info.filename)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.9))
                                            .lineLimit(2)
                                            .truncationMode(.middle)
                                            .multilineTextAlignment(.leading)
                                        Image(systemName: "arrow.up.forward.square")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.white.opacity(0.3))
                                    }
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(info.filename)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                            }

                            if info.fileSize != nil || info.container != nil {
                                HStack(spacing: 10) {
                                    if let size = info.fileSize {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Size")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.white.opacity(0.35))
                                            Text(formatFileSize(size))
                                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(.white.opacity(0.85))
                                        }
                                    }
                                    if let container = info.container {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Format")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.white.opacity(0.35))
                                            Text(container.uppercased())
                                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(.white.opacity(0.85))
                                        }
                                    }
                                    Spacer()
                                }
                            }

                            // File dates
                            if info.createdAt != nil || info.modifiedAt != nil {
                                VStack(alignment: .leading, spacing: 4) {
                                    if let created = info.createdAt {
                                        HStack(spacing: 4) {
                                            Text("Created")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.white.opacity(0.35))
                                                .frame(width: 52, alignment: .leading)
                                            Text(formatDate(created))
                                                .font(.system(size: 10))
                                                .foregroundStyle(.white.opacity(0.55))
                                        }
                                    }
                                    if let modified = info.modifiedAt {
                                        HStack(spacing: 4) {
                                            Text("Modified")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.white.opacity(0.35))
                                                .frame(width: 52, alignment: .leading)
                                            Text(formatDate(modified))
                                                .font(.system(size: 10))
                                                .foregroundStyle(.white.opacity(0.55))
                                        }
                                    }
                                }
                                .padding(.top, 2)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 10)
                        .padding(.top, 4)

                        // Video card
                        if info.videoCodec != nil {
                            infoCard(icon: "film", title: "Video") {
                                if let codec = info.videoCodec {
                                    infoRow("Codec", codec)
                                }
                                if let w = info.width, let h = info.height {
                                    infoRow("Resolution", "\(w)\u{00D7}\(h)")
                                }
                                if let fps = info.fps {
                                    infoRow("FPS", String(format: "%.3f", fps))
                                }
                                if let bitrate = info.videoBitrate, bitrate > 0 {
                                    infoRow("Bitrate", formatBitrate(bitrate))
                                }
                                if let pf = info.pixelFormat {
                                    infoRow("Pixel Fmt", pf)
                                }
                            }
                        }

                        // Audio card
                        if info.audioCodec != nil {
                            infoCard(icon: "waveform", title: "Audio") {
                                if let codec = info.audioCodec {
                                    infoRow("Codec", codec)
                                }
                                if let ch = info.audioChannels {
                                    infoRow("Channels", formatChannels(ch))
                                }
                                if let sr = info.audioSampleRate {
                                    infoRow("Sample Rate", formatSampleRate(sr))
                                }
                                if let bitrate = info.audioBitrate, bitrate > 0 {
                                    infoRow("Bitrate", formatBitrate(bitrate))
                                }
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }
                .darkScrollbar()
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "film")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.15))
                    Text("No media loaded")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.25))
                    Spacer()
                }
            }
        }
    }

    private func infoCard(icon: String, title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
            }
            .padding(.bottom, 2)

            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 10)
    }

    private func infoBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .textSelection(.enabled)
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatBitrate(_ bps: Int64) -> String {
        let kbps = Double(bps) / 1000.0
        if kbps >= 1000 {
            return String(format: "%.1f Mbps", kbps / 1000.0)
        }
        return String(format: "%.0f kbps", kbps)
    }

    private func formatChannels(_ count: Int64) -> String {
        switch count {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(count)ch"
        }
    }

    private func formatSampleRate(_ hz: Int64) -> String {
        if hz % 1000 == 0 {
            return "\(hz / 1000) kHz"
        }
        return String(format: "%.1f kHz", Double(hz) / 1000.0)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.4))
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .padding(.top, 8)
    }

    private func filterRow(index: Int) -> some View {
        let filter = engine.filters.filters[index]
        let param = filter.parameters[0]
        return HStack(spacing: 6) {
            Toggle("", isOn: Binding(
                get: { engine.filters.filters[index].isEnabled },
                set: {
                    engine.filters.filters[index].isEnabled = $0
                    engine.syncFiltersToMPV()
                    engine.needsFrameRefresh = true
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Text(filter.name)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 60, alignment: .leading)

            Slider(
                value: Binding(
                    get: { engine.filters.filters[index].parameters[0].value },
                    set: {
                        engine.filters.filters[index].parameters[0].value = $0
                        if !engine.filters.filters[index].isEnabled {
                            engine.filters.filters[index].isEnabled = true
                        }
                        engine.syncFiltersToMPV()
                        engine.needsFrameRefresh = true
                    }
                ),
                in: param.minValue...param.maxValue
            )

            Text(paramLabel(param))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 1)
    }

    // MARK: - Helpers

    private var audioDelayBinding: Binding<Double> {
        Binding(
            get: { engine.audioDelay },
            set: { engine.setAudioDelay($0) }
        )
    }

    private var audioDelayLabel: String {
        let d = engine.audioDelay
        if d == 0 { return "0.00s" }
        let sign = d > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", d))s"
    }

    private func paramLabel(_ param: FilterParameter) -> String {
        if param.defaultValue == 0 {
            return String(format: "%.2f", param.value)
        } else {
            return String(format: "%.1f", param.value)
        }
    }

    private var hasAnyAdjustment: Bool {
        engine.filters.hasActiveFilters
            || engine.videoRotation != 0
            || engine.audioDelay != 0
    }
}

// MARK: - Playlist Row

private struct PlaylistRow: View {
    let item: PlaylistItem
    let isPlaying: Bool
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            if isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.blue)
                    .frame(width: 14)
            } else {
                Text("\(index + 1)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(width: 14)
            }

            Text(item.title)
                .font(.system(size: 12))
                .foregroundStyle(isPlaying ? .white : .white.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if let dur = item.duration, dur > 0 {
                Text(formatTime(dur))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Bookmark Row

private struct BookmarkRow: View {
    let bookmark: Bookmark
    var onDelete: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            // Thumbnail
            if let data = bookmark.thumbnailData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                    )
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.08))
                    .frame(width: 64, height: 36)
                    .overlay(
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.2))
                    )
            }

            // Time
            Text(formatTime(bookmark.time))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.orange.opacity(0.9))

            Spacer()

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.arrow.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
