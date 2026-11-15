import AppKit

/// Owns the player window and the parts AppKit does best: window chrome, full-screen
/// transitions, frame persistence, and the keyboard and pointer input policy.
///
/// The views inside the window (`PlayerContentView`, `PlayerInteractionView`) forward raw input
/// here; SwiftUI overlays read and write `PlayerUIState`.
@MainActor
final class PlayerWindowController: NSWindowController {
    private let engine: PlaybackEngine
    private let ui: PlayerUIState
    private let playerView: PlayerContentView
    private let touchBarManager: TouchBarManager

    private var hideControlsTask: Task<Void, Never>?
    private var singleClickTask: Task<Void, Never>?
    private var isTransitioningFullScreen = false

    private static let minimumSize = NSSize(width: 480, height: 270)
    private static let defaultSize = NSSize(width: 960, height: 540)

    private static let escapeKeyCode: UInt16 = 53
    /// ⌘1–⌘5 select a sidebar tab. The window takes these ahead of the key bindings,
    /// so `KeyBindingManager` refuses to bind an action to them.
    static let sidebarTabKeyCodes: [UInt16: SidebarTab] = [
        18: .playlist, 19: .filters, 20: .info, 21: .bookmarks, 23: .tracks,
    ]

    init(engine: PlaybackEngine) {
        let ui = PlayerUIState()
        self.engine = engine
        self.ui = ui
        self.playerView = PlayerContentView(engine: engine, ui: ui)
        self.touchBarManager = TouchBarManager(engine: engine)

        let window = PlayerWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        configure(window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(_ window: PlayerWindow) {
        // IINA-style chrome: the content runs under a transparent, untitled title bar.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = Self.minimumSize
        window.collectionBehavior = [.fullScreenPrimary]
        // Window drags start explicitly in PlayerInteractionView, so controls never move the window.
        window.isMovableByWindowBackground = false
        // Closing hides the window; the Dock icon brings the same player back.
        window.isReleasedWhenClosed = false
        // WindowState persists the frame.
        window.isRestorable = false

        window.contentView = playerView
        window.touchBar = touchBarManager.makeTouchBar()
        window.keyDownHandler = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }

        if let savedFrame = engine.windowState.loadSavedFrame() {
            window.setFrame(savedFrame, display: false)
        } else {
            window.center()
        }
        window.delegate = self

        ui.onSidebarVisibilityChange = { [weak self] visible in
            guard let self else { return }
            self.playerView.setSidebarVisible(visible, animated: !self.isTransitioningFullScreen)
        }
        ui.onShortcutGuideVisibilityChange = { [weak self] visible in
            self?.playerView.setShortcutGuideVisible(visible)
        }
    }

    func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    func teardown() {
        touchBarManager.teardown()
    }

    // MARK: - Controls Visibility

    /// Shows the controls and, during playback, schedules them to hide again.
    private func revealControls() {
        // This runs on every pointer move; write only on change so the overlay is not invalidated each time.
        if !ui.showControls {
            ui.showControls = true
        }
        hideControlsTask?.cancel()

        guard engine.state == .playing else { return }
        hideControlsTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AppSettings.controlsAutoHideDelay.value))
            guard !Task.isCancelled else { return }
            self?.hideControlsAfterTimeout()
        }
    }

    private func hideControlsAfterTimeout() {
        // A button held in this app means a scrub or slider drag is in progress; keep the controls up.
        guard !(NSApp.isActive && NSEvent.pressedMouseButtons != 0) else {
            revealControls()
            return
        }
        ui.showControls = false
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    private func toggleControls() {
        if ui.showControls {
            hideControlsTask?.cancel()
            ui.showControls = false
            NSCursor.setHiddenUntilMouseMoves(true)
        } else {
            revealControls()
        }
    }

    // MARK: - Pointer Input

    /// The pointer moved anywhere inside the window.
    func pointerMoved() {
        revealControls()
    }

    /// A press on the bare video area ended without turning into a window drag.
    func surfaceClicked(with event: NSEvent) {
        guard let window, engine.state.isActive || engine.state == .viewingImage else { return }
        // The strip under the transparent title bar behaves like a title bar: it drags, it does not click.
        guard event.locationInWindow.y <= window.contentLayoutRect.maxY else { return }

        switch event.clickCount {
        case 1:
            // Hold the single click for the system double-click interval, so a double-click
            // toggles full screen without also flashing the controls.
            singleClickTask?.cancel()
            singleClickTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
                guard !Task.isCancelled else { return }
                self?.toggleControls()
            }
        case 2:
            singleClickTask?.cancel()
            window.toggleFullScreen(nil)
        default:
            break
        }
    }

    /// A scroll that no overlay consumed: adjust the volume.
    func surfaceScrolled(with event: NSEvent) {
        engine.adjustVolume(by: Float(event.scrollingDeltaY) * 0.01)
    }

    /// Files were dropped on the window.
    func filesDropped(_ urls: [URL]) {
        let subtitleURLs = urls.filter { PlaylistManager.isSubtitleFile($0) }
        let mediaURLs = urls.filter { !PlaylistManager.isSubtitleFile($0) }

        // Subtitles dropped on a playing video attach to it.
        if mediaURLs.isEmpty, engine.state.isActive {
            for url in subtitleURLs {
                engine.addExternalSubtitle(url: url)
            }
            return
        }

        Task {
            await engine.open(urls: mediaURLs.isEmpty ? urls : mediaURLs)
            // Subtitles that arrived together with media apply to the file just opened.
            if !mediaURLs.isEmpty {
                for url in subtitleURLs {
                    engine.addExternalSubtitle(url: url)
                }
            }
        }
    }

    // MARK: - Keyboard Input

    /// Called by `PlayerWindow` for every key press before normal dispatch.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // Text editing keeps its keys.
        guard let window, !(window.firstResponder is NSTextView) else { return false }
        return handlePanelKey(event) || engine.keyBindings.handle(event)
    }

    /// Esc dismisses the shortcut guide, then the sidebar; ⌘1–⌘5 select a sidebar tab.
    private func handlePanelKey(_ event: NSEvent) -> Bool {
        if event.keyCode == Self.escapeKeyCode {
            if ui.showShortcutGuide {
                ui.showShortcutGuide = false
                return true
            }
            if ui.sidebarTab != nil {
                ui.sidebarTab = nil
                return true
            }
            return false
        }

        if event.modifierFlags.shortcutModifiers == .command, let tab = Self.sidebarTabKeyCodes[event.keyCode] {
            ui.sidebarTab = tab
            return true
        }
        return false
    }

    private func saveFrameIfWindowed() {
        guard let window, !engine.windowState.isFullscreen else { return }
        engine.windowState.saveFrame(window.frame)
    }
}

// MARK: - NSWindowDelegate

extension PlayerWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        saveFrameIfWindowed()
    }

    func windowDidResize(_ notification: Notification) {
        saveFrameIfWindowed()
    }

    func windowWillClose(_ notification: Notification) {
        // The window is only hidden, so stop the sound of a player nobody can see.
        if engine.state == .playing {
            engine.pause()
        }
    }

    // MARK: Custom Full-Screen Animation (like IINA)

    // Tell AppKit we animate full screen ourselves — prevents the bitmap snapshot zoom.
    func customWindowsToEnterFullScreen(for window: NSWindow) -> [NSWindow]? {
        [window]
    }

    func customWindowsToExitFullScreen(for window: NSWindow) -> [NSWindow]? {
        [window]
    }

    // Smooth enter: animate the window frame to fill the screen.
    func window(_ window: NSWindow, startCustomAnimationToEnterFullScreenOn screen: NSScreen, withDuration duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(screen.frame, display: true, animate: true)
        }
    }

    // Smooth exit: animate the window frame back to its prior windowed size.
    func window(_ window: NSWindow, startCustomAnimationToExitFullScreenWithDuration duration: TimeInterval) {
        let targetFrame = engine.windowState.priorWindowedFrame
            ?? engine.windowState.loadSavedFrame()
            ?? NSRect(x: 200, y: 200, width: 1280, height: 720)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(targetFrame, display: true, animate: true)
        }
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        // Remember the windowed frame so the exit animation can return to it.
        if let window {
            engine.windowState.priorWindowedFrame = window.frame
        }
        engine.windowState.isFullscreen = true
        isTransitioningFullScreen = true
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        isTransitioningFullScreen = false
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        isTransitioningFullScreen = true
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        engine.windowState.isFullscreen = false
        isTransitioningFullScreen = false
    }
}
