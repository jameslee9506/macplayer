import AppKit
import SwiftUI

/// Content view of the player window.
///
/// AppKit owns the regions (video surface, sidebar, shortcut guide) and receives the raw input;
/// SwiftUI renders the content inside each region. Input is forwarded to `PlayerWindowController`,
/// which decides what it means.
///
/// ```
/// PlayerContentView
/// ├── surfaceView                 shrinks from the trailing edge when the sidebar opens
/// │   ├── videoContainer → MPVVideoNSView
/// │   └── NSHostingView<PlayerOverlayView>
/// ├── SidebarContainerView        mounted only while the sidebar is open
/// └── NSHostingView<ShortcutGuideOverlay>   mounted only while the guide is shown
/// ```
final class PlayerContentView: NSView {
    private let engine: PlaybackEngine
    private let ui: PlayerUIState

    private let surfaceView = NSView()
    private lazy var surfaceTrailing = surfaceView.trailingAnchor.constraint(equalTo: trailingAnchor)
    private var sidebarView: SidebarContainerView?
    /// Counts sidebar toggles so a superseded slide does not unmount the sidebar.
    private var sidebarTransition = 0
    private var shortcutGuideView: NSView?

    private var playerController: PlayerWindowController? {
        window?.windowController as? PlayerWindowController
    }

    init(engine: PlaybackEngine, ui: PlayerUIState) {
        self.engine = engine
        self.ui = ui
        super.init(frame: .zero)
        wantsLayer = true

        buildSurface()
        registerForDraggedTypes([.fileURL])
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    private func buildSurface() {
        surfaceView.wantsLayer = true
        surfaceView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surfaceView)
        NSLayoutConstraint.activate([
            surfaceView.leadingAnchor.constraint(equalTo: leadingAnchor),
            surfaceView.topAnchor.constraint(equalTo: topAnchor),
            surfaceView.bottomAnchor.constraint(equalTo: bottomAnchor),
            surfaceTrailing,
        ])

        // The video view gets a container of its own so PiP can lift it out and put it back
        // without disturbing the overlay stacked above it.
        let videoContainer = NSView()
        let videoView = MPVVideoNSView(engine: engine)
        videoView.setAccessibilityElement(true)
        videoView.setAccessibilityLabel("Video player")

        let overlay = NSHostingView(rootView: PlayerOverlayView(engine: engine, ui: ui))
        overlay.sizingOptions = []

        surfaceView.addSubview(videoContainer)
        videoContainer.addSubview(videoView)
        surfaceView.addSubview(overlay)
        Self.pin(videoContainer, to: surfaceView)
        Self.pin(videoView, to: videoContainer)
        Self.pin(overlay, to: surfaceView)
    }

    private static func pin(_ view: NSView, to container: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    // MARK: - Sidebar

    private static let sidebarSlideDuration: TimeInterval = 0.3
    /// Ease-out: leaves fast, settles slowly. Opening and closing both run this same curve
    /// rather than closing with its mirror image.
    private static let sidebarSlideCurve = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)

    /// Slides the sidebar in or out. The video region resizes with it, frame by frame.
    func setSidebarVisible(_ visible: Bool, animated: Bool) {
        if visible, sidebarView == nil { installSidebar() }
        let trailing: CGFloat = visible ? -SidePanel.width : 0

        sidebarTransition += 1
        let transition = sidebarTransition
        Task {
            // Going through the animator even when not animating cancels a slide already in flight.
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = animated ? Self.sidebarSlideDuration : 0
                context.timingFunction = Self.sidebarSlideCurve
                surfaceTrailing.animator().constant = trailing
            }
            // Unmount only after the latest slide-out; a newer toggle owns the sidebar otherwise.
            if !visible, transition == sidebarTransition { removeSidebar() }
        }
    }

    private func installSidebar() {
        let sidebar = SidebarContainerView(rootView: SidebarRootView(engine: engine, ui: ui))
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sidebar, positioned: .above, relativeTo: surfaceView)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: surfaceView.trailingAnchor),
            sidebar.topAnchor.constraint(equalTo: topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: SidePanel.width),
        ])
        // Settle it just past the trailing edge so the slide starts from there.
        layoutSubtreeIfNeeded()
        sidebarView = sidebar
    }

    private func removeSidebar() {
        sidebarView?.removeFromSuperview()
        sidebarView = nil
    }

    // MARK: - Shortcut Guide

    /// Fades the keyboard shortcut guide in or out over the whole window.
    func setShortcutGuideVisible(_ visible: Bool) {
        if visible {
            guard shortcutGuideView == nil else { return }
            let guide = NSHostingView(
                rootView: ShortcutGuideOverlay(isPresented: Bindable(ui).showShortcutGuide)
            )
            guide.sizingOptions = []
            guide.alphaValue = 0
            addSubview(guide)
            Self.pin(guide, to: self)
            shortcutGuideView = guide
            Task { await Self.fade(guide, to: 1) }
        } else if let guide = shortcutGuideView {
            shortcutGuideView = nil
            Task {
                await Self.fade(guide, to: 0)
                guide.removeFromSuperview()
            }
        }
    }

    private static func fade(_ view: NSView, to alpha: CGFloat) async {
        await NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.animator().alphaValue = alpha
        }
    }

    // MARK: - Pointer

    override func mouseMoved(with event: NSEvent) {
        playerController?.pointerMoved()
    }

    /// Scroll events bubble up to here from the video surface and from any overlay that
    /// did not consume them. The sidebar stops its own (see `SidebarContainerView`).
    override func scrollWheel(with event: NSEvent) {
        playerController?.surfaceScrolled(with: event)
    }

    // MARK: - File Drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.fileURLs(from: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = Self.fileURLs(from: sender)
        guard !urls.isEmpty, let playerController else { return false }
        playerController.filesDropped(urls)
        return true
    }

    private static func fileURLs(from info: NSDraggingInfo) -> [URL] {
        let objects = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
        return objects as? [URL] ?? []
    }
}

// MARK: - Sidebar Hosting

/// Hosts the SwiftUI sidebar. Scroll events its content does not consume stop here,
/// so scrolling over the sidebar never reaches the volume gesture of the video surface.
private final class SidebarContainerView: NSView {
    init(rootView: some View) {
        super.init(frame: .zero)
        let host = NSHostingView(rootView: rootView)
        host.sizingOptions = []
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func scrollWheel(with event: NSEvent) {}
}

/// Root of the sidebar's hosting view. Shows the last selected tab while the panel slides out.
private struct SidebarRootView: View {
    let engine: PlaybackEngine
    let ui: PlayerUIState

    var body: some View {
        SidePanel(
            engine: engine,
            selectedTab: Binding(
                get: { ui.sidebarTab ?? ui.lastSidebarTab },
                set: { ui.sidebarTab = $0 }
            )
        )
        .animation(.easeInOut(duration: 0.25), value: ui.lastSidebarTab)
    }
}
