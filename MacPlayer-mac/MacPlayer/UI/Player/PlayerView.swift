import SwiftUI
import UniformTypeIdentifiers

/// Main player view composing the Metal video surface with control bar, subtitles, and OSD.
struct PlayerView: View {
    let engine: PlaybackEngine

    @State private var showControls = true
    @State private var sidebarTab: SidebarTab?
    @State private var controlsTimer: Timer?
    @State private var mouseMonitor: Any?
    @State private var scrollMonitor: Any?
    @State private var keyMonitor: Any?
    @State private var clickCount = 0
    @State private var clickTimer: Timer?
    @State private var isTransitioningFullScreen = false
    @State private var fullScreenObservers: [Any] = []
    @State private var showShortcutGuide = false
    private let controlsTimeout: TimeInterval = 1.5

    var body: some View {
        HStack(spacing: 0) {
            // Main player area — takes remaining width
            ZStack {
                Color.black.ignoresSafeArea()

                // Video surface — always present so the GL context exists before loadfile.
                // mpv requires render context to be created before playback starts.
                videoSurface
                    .ignoresSafeArea()
                    .accessibilityLabel("Video player")
                    .opacity(engine.state.isActive ? 1 : 0)
                    .allowsHitTesting(engine.state.isActive)

                switch engine.state {
                case .idle:
                    idleView

                case .loading:
                    ProgressView("Loading...")
                        .foregroundStyle(.white)

                case .playing, .paused:
                    // Invisible tap area — behind controls, on top of video
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            TapGesture(count: 1).onEnded {
                                handleTap()
                            }
                        )

                    // Title overlay — next to traffic light buttons
                    titleOverlay

                    // Sidebar toggle button — top right corner
                    sidebarToggleOverlay

                    // Control bar — auto-hides
                    controlsOverlay

                    // OSD overlay
                    osdOverlay

                case .viewingImage:
                    imageView

                case .stopped:
                    idleView

                case .error(let message):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.yellow)
                        Text(message)
                            .foregroundStyle(.white)
                    }
                }
            }

            // Side panel — pushes video area when visible
            if sidebarTab != nil {
                SidePanel(engine: engine, selectedTab: $sidebarTab)
                    .transition(.move(edge: .trailing))
            }
        }
        .overlay {
            if showShortcutGuide {
                ShortcutGuideOverlay(isPresented: $showShortcutGuide)
            }
        }
        .frame(minWidth: 480, minHeight: 270)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .onAppear {
            engine.setupKeyBindings()
            setupMouseTracking()
            setupSidebarKeyMonitor()
            observeFullScreenTransitions()
        }
        .onDisappear {
            engine.keyBindings.stop()
            tearDownMouseTracking()
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            fullScreenObservers.forEach { NotificationCenter.default.removeObserver($0) }
            fullScreenObservers.removeAll()
        }
        .animation(.easeInOut(duration: 0.3), value: showControls)
        .animation(isTransitioningFullScreen ? nil : .easeInOut(duration: 0.25), value: sidebarTab)
    }

    // MARK: - Video Surface

    private var videoSurface: some View {
        MPVVideoView(engine: engine)
    }

    // MARK: - Tap Handling (single vs double click)

    private func handleTap() {
        clickCount += 1

        if clickCount == 1 {
            clickTimer?.invalidate()
            clickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { _ in
                Task { @MainActor in
                    // Single click: toggle controls visibility
                    withAnimation(.easeOut(duration: 0.3)) {
                        showControls.toggle()
                    }
                    if showControls {
                        resetControlsTimer()
                    } else {
                        controlsTimer?.invalidate()
                        NSCursor.setHiddenUntilMouseMoves(true)
                    }
                    clickCount = 0
                }
            }
        } else if clickCount >= 2 {
            clickTimer?.invalidate()
            clickCount = 0
            NSApp.keyWindow?.toggleFullScreen(nil)
        }
    }

    // MARK: - Title Overlay (top, next to traffic lights)

    private var titleOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if engine.state.isActive || engine.state == .viewingImage {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            sidebarTab = sidebarTab == .info ? nil : .info
                        }
                    } label: {
                        Text(engine.mediaTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 78) // Clear traffic light buttons
                    .padding(.trailing, 44) // Clear sidebar toggle button
                }
                Spacer()
            }
            .frame(height: 28)
            .padding(.top, 1.5)
            Spacer()
        }
        .ignoresSafeArea()
        .opacity(showControls ? 1 : 0)
    }

    // MARK: - Sidebar Toggle (top-right, ignores safe area)

    private var sidebarToggleOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        sidebarTab = sidebarTab != nil ? nil : .playlist
                    }
                }) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .symbolVariant(sidebarTab != nil ? .fill : .none)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlayerControlButtonStyle())
                .padding(.trailing, 8)
            }
            .frame(height: 28)
            .padding(.top, 1.5)
            Spacer()
        }
        .ignoresSafeArea()
        .allowsHitTesting(showControls)
        .opacity(showControls ? 1 : 0)
    }

    // MARK: - Controls Overlay (bottom bar, auto-hides)

    @ViewBuilder
    private var controlsOverlay: some View {
        VStack {
            Spacer()
            ControlBar(engine: engine, sidebarTab: $sidebarTab)
                .opacity(showControls ? 1 : 0)
        }
        .allowsHitTesting(showControls)
    }

    // MARK: - OSD Overlay

    @ViewBuilder
    private var osdOverlay: some View {
        if let message = engine.osd.currentMessage {
            VStack {
                HStack {
                    OSDView(message: message)
                        .padding(.top, 24)
                        .padding(.leading, 12)
                    Spacer()
                }
                Spacer()
            }
            .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .topLeading)))
            .animation(.spring(duration: 0.3, bounce: 0.1), value: engine.osd.currentMessage)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Image View

    private var imageView: some View {
        ZStack {
            if let image = engine.displayedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()
                    .accessibilityLabel("Image viewer")
            }

            // Title overlay
            titleOverlay

            // Sidebar toggle button
            sidebarToggleOverlay
        }
        .gesture(
            TapGesture(count: 1).onEnded {
                handleTap()
            }
        )
    }

    // MARK: - Idle View

    private var idleView: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 360 || geo.size.width < 400
            let logoSize: CGFloat = compact ? 56 : 96
            let cornerRadius: CGFloat = compact ? 14 : 22

            VStack(spacing: 0) {
                Spacer()

                LogoButton(size: logoSize, cornerRadius: cornerRadius)

                Text("MacPlayer")
                    .font(.system(size: compact ? 16 : 20, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.4)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(.top, compact ? 6 : 10)

                Text("Drop a video file here  \u{00B7}  \u{2318}O")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.top, compact ? 4 : 6)

                HStack(spacing: 12) {
                    idleButton(icon: "folder", label: "Open File") {
                        engine.openFile()
                    }
                    idleButton(icon: "list.bullet", label: "Playlist") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            sidebarTab = sidebarTab == .playlist ? nil : .playlist
                        }
                    }
                }
                .padding(.top, compact ? 14 : 24)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showShortcutGuide = true
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 10))
                        Text("Keyboard Shortcuts")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .padding(.top, compact ? 8 : 14)

                Spacer()

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("v\(version)")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.15))
                        .padding(.bottom, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func idleButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.white.opacity(0.08))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - File Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        // Collect all dropped URLs
        let group = DispatchGroup()
        var droppedURLs: [URL] = []
        let lock = NSLock()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                defer { group.leave() }
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil)
                else { return }
                lock.lock()
                droppedURLs.append(url)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            Task { @MainActor in
                guard !droppedURLs.isEmpty else { return }

                // Separate subtitle files from media files
                let subtitleURLs = droppedURLs.filter { PlaylistManager.isSubtitleFile($0) }
                let mediaURLs = droppedURLs.filter { !PlaylistManager.isSubtitleFile($0) }

                // If only subtitle files dropped and media is playing, add them as external subtitles
                if mediaURLs.isEmpty && !subtitleURLs.isEmpty && engine.state.isActive {
                    for url in subtitleURLs {
                        engine.addExternalSubtitle(url: url)
                    }
                    return
                }

                // Handle media files (existing logic)
                let effectiveMediaURLs = mediaURLs.isEmpty ? droppedURLs : mediaURLs

                if effectiveMediaURLs.count == 1, let url = effectiveMediaURLs.first {
                    if PlaylistManager.isDirectory(url) {
                        engine.playlist.replace(folder: url)
                        if let firstURL = engine.playlist.play(at: 0) {
                            await engine.load(url: firstURL)
                        }
                    } else {
                        await engine.load(url: url)
                    }
                } else {
                    var videoURLs: [URL] = []
                    for url in effectiveMediaURLs {
                        if PlaylistManager.isDirectory(url) {
                            let tempManager = PlaylistManager()
                            tempManager.add(folder: url)
                            videoURLs.append(contentsOf: tempManager.items.map(\.url))
                        } else if PlaylistManager.isVideoFile(url) {
                            videoURLs.append(url)
                        } else {
                            videoURLs.append(url)
                        }
                    }

                    if !videoURLs.isEmpty {
                        engine.playlist.replace(urls: videoURLs)
                        if let firstURL = engine.playlist.play(at: 0) {
                            await engine.load(url: firstURL)
                        }
                    }
                }

                // Add any subtitle files that came with media files
                if !mediaURLs.isEmpty {
                    for url in subtitleURLs {
                        engine.addExternalSubtitle(url: url)
                    }
                }
            }
        }
        return true
    }

    // MARK: - Controls Visibility

    private func resetControlsTimer() {
        showControls = true
        controlsTimer?.invalidate()

        guard engine.state == .playing else { return }

        controlsTimer = Timer.scheduledTimer(withTimeInterval: controlsTimeout, repeats: false) { _ in
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.4)) {
                    showControls = false
                }
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
    }

    // MARK: - Mouse Tracking

    private func setupMouseTracking() {
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { event in
            Task { @MainActor in
                resetControlsTimer()
            }
            return event
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [self] event in
            guard event.window == NSApp.windows.first else { return event }

            // Don't adjust volume when scrolling over the sidebar
            if sidebarTab != nil, let contentView = event.window?.contentView {
                let loc = contentView.convert(event.locationInWindow, from: nil)
                if loc.x > contentView.bounds.width - 280 {
                    return event
                }
            }

            Task { @MainActor in
                let delta = Float(event.scrollingDeltaY) * 0.01
                engine.adjustVolume(by: delta)
            }
            return event
        }
    }

    private func tearDownMouseTracking() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
        mouseMonitor = nil
        scrollMonitor = nil
        controlsTimer?.invalidate()
    }

    // MARK: - Sidebar Key Monitor

    private func setupSidebarKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.numericPad, .function])

            // ESC closes shortcut guide or sidebar
            if keyCode == 53 {
                if showShortcutGuide {
                    withAnimation(.easeOut(duration: 0.2)) { showShortcutGuide = false }
                    return nil
                }
                if sidebarTab != nil {
                    withAnimation(.easeInOut(duration: 0.25)) { sidebarTab = nil }
                    return nil
                }
            }

            // Cmd+1/2/3 switches sidebar tabs
            if modifiers == .command {
                let tab: SidebarTab? = switch keyCode {
                case 18: .playlist   // 1
                case 19: .filters    // 2
                case 20: .info       // 3
                case 21: .bookmarks  // 4
                case 23: .tracks     // 5
                default: nil
                }
                if let tab {
                    withAnimation(.easeInOut(duration: 0.25)) { sidebarTab = tab }
                    return nil
                }
            }

            return event
        }
    }

    // MARK: - Full Screen Transition Tracking

    private func observeFullScreenTransitions() {
        let nc = NotificationCenter.default
        let willEnter = nc.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: nil, queue: .main) { _ in
            isTransitioningFullScreen = true
        }
        let didEnter = nc.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: nil, queue: .main) { _ in
            isTransitioningFullScreen = false
        }
        let willExit = nc.addObserver(forName: NSWindow.willExitFullScreenNotification, object: nil, queue: .main) { _ in
            isTransitioningFullScreen = true
        }
        let didExit = nc.addObserver(forName: NSWindow.didExitFullScreenNotification, object: nil, queue: .main) { _ in
            isTransitioningFullScreen = false
        }
        fullScreenObservers = [willEnter, didEnter, willExit, didExit]
    }
}
