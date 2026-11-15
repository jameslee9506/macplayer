import SwiftUI
import UniformTypeIdentifiers
import AppKit

@main
struct MacPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            PlayerView(engine: appDelegate.engine)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    appDelegate.openFile()
                }
                .keyboardShortcut("o")
            }

            CommandGroup(after: .toolbar) {
                Button("Toggle Full Screen") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f")
            }
        }

        Settings {
            SettingsView(engine: appDelegate.engine)
        }
    }
}

/// App delegate handles file association (double-click to open) and NSOpenPanel.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = PlaybackEngine()
    private var touchBarManager: TouchBarManager?
    private var windowObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainWindow()
        engine.setupKeyBindings()

        // Setup Touch Bar
        touchBarManager = TouchBarManager(engine: engine)

        // Prompt to set as default video player on first launch
        promptDefaultPlayerIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        touchBarManager?.teardown()
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task {
            if urls.count == 1, let url = urls.first {
                if PlaylistManager.isDirectory(url) {
                    engine.playlist.replace(folder: url)
                    if let firstURL = engine.playlist.play(at: 0) {
                        await engine.load(url: firstURL)
                    }
                } else {
                    await engine.load(url: url)
                }
            } else if urls.count > 1 {
                let videoURLs = urls.filter { PlaylistManager.isVideoFile($0) || PlaylistManager.isDirectory($0) }
                var allURLs: [URL] = []
                for url in videoURLs {
                    if PlaylistManager.isDirectory(url) {
                        let temp = PlaylistManager()
                        temp.add(folder: url)
                        allURLs.append(contentsOf: temp.items.map(\.url))
                    } else {
                        allURLs.append(url)
                    }
                }
                if !allURLs.isEmpty {
                    engine.playlist.replace(urls: allURLs)
                    if let firstURL = engine.playlist.play(at: 0) {
                        await engine.load(url: firstURL)
                    }
                }
            }
        }
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .movie, .video, .mpeg4Movie, .quickTimeMovie, .avi,
            .image, .png, .jpeg, .gif, .tiff, .heic, .bmp, .webP
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true

        guard panel.runModal() == .OK else { return }

        let urls = panel.urls
        guard !urls.isEmpty else { return }

        Task {
            if urls.count == 1, let url = urls.first {
                if PlaylistManager.isDirectory(url) {
                    engine.playlist.replace(folder: url)
                    if let firstURL = engine.playlist.play(at: 0) {
                        await engine.load(url: firstURL)
                    }
                } else {
                    // Single file: load directly (existing behavior)
                    await engine.load(url: url)
                }
            } else {
                // Multiple selections: build playlist
                var allURLs: [URL] = []
                for url in urls {
                    if PlaylistManager.isDirectory(url) {
                        let temp = PlaylistManager()
                        temp.add(folder: url)
                        allURLs.append(contentsOf: temp.items.map(\.url))
                    } else {
                        allURLs.append(url)
                    }
                }
                if !allURLs.isEmpty {
                    engine.playlist.replace(urls: allURLs)
                    if let firstURL = engine.playlist.play(at: 0) {
                        await engine.load(url: firstURL)
                    }
                }
            }
        }
    }

    // MARK: - Dock Menu

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let recentFiles = engine.history.recentRecords(limit: 10)
        if recentFiles.isEmpty {
            let item = NSMenuItem(title: "No Recent Files", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for record in recentFiles {
                let item = NSMenuItem(
                    title: record.title,
                    action: #selector(openRecentFile(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = record.videoURL
                menu.addItem(item)
            }
        }

        return menu
    }

    @objc private func openRecentFile(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        Task {
            await engine.load(url: url)
        }
    }

    // MARK: - Window Configuration

    private func configureMainWindow() {
        guard let window = NSApp.windows.first else { return }

        // Set ourselves as window delegate for custom fullscreen animations
        window.delegate = self

        // IINA-style transparent titlebar
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)

        // Window appearance
        window.backgroundColor = .black
        window.minSize = NSSize(width: 480, height: 270)

        // Restore saved window frame
        if let savedFrame = engine.windowState.loadSavedFrame() {
            window.setFrame(savedFrame, display: true)
        }

        // Set Touch Bar on the window
        if let tbManager = touchBarManager {
            window.touchBar = tbManager.makeTouchBar()
        }

        // Observe window move/resize for auto-save (only save when not in fullscreen)
        let moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.engine.windowState.isFullscreen,
                  let window = self.mainWindow else { return }
            self.engine.windowState.saveFrame(window.frame)
        }
        windowObservers.append(moveObserver)

        let resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.engine.windowState.isFullscreen,
                  let window = self.mainWindow else { return }
            self.engine.windowState.saveFrame(window.frame)
        }
        windowObservers.append(resizeObserver)
    }

    private var mainWindow: NSWindow? {
        NSApp.windows.first
    }

    // MARK: - Default Player Prompt

    private static let hasPromptedDefaultPlayerKey = "MacPlayer.hasPromptedDefaultPlayer"

    private func promptDefaultPlayerIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.hasPromptedDefaultPlayerKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.hasPromptedDefaultPlayerKey)

        let alert = NSAlert()
        alert.messageText = "Set MacPlayer as default video player?"
        alert.informativeText = "Video files will open with MacPlayer when double-clicked in Finder."
        alert.addButton(withTitle: "Set as Default")
        alert.addButton(withTitle: "Not Now")
        alert.alertStyle = .informational

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        setAsDefaultVideoPlayer()
    }

    private func setAsDefaultVideoPlayer() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }

        let videoTypes: [String] = [
            "public.movie",
            "public.video",
            "public.mpeg-4",
            "com.apple.quicktime-movie",
            "com.apple.m4v-video",
            "public.avi",
            "public.mpeg",
            "public.mpeg-2-video",
            "public.mpeg-2-transport-stream",
            "public.3gpp",
            "public.3gpp2",
            "org.matroska.mkv",
            "org.webmproject.webm",
            "com.microsoft.windows-media-wmv",
            "public.flv",
            "org.xiph.ogv",
        ]

        for type in videoTypes {
            LSSetDefaultRoleHandlerForContentType(
                type as CFString,
                .viewer,
                bundleID as CFString
            )
        }
    }
}

// MARK: - Custom Fullscreen Animation (like IINA)

extension AppDelegate: NSWindowDelegate {

    // Tell AppKit we handle fullscreen animation ourselves — prevents bitmap snapshot zoom
    func customWindowsToEnterFullScreen(for window: NSWindow) -> [NSWindow]? {
        [window]
    }

    func customWindowsToExitFullScreen(for window: NSWindow) -> [NSWindow]? {
        [window]
    }

    // Smooth enter: animate window frame to fill screen
    func window(_ window: NSWindow, startCustomAnimationToEnterFullScreenOn screen: NSScreen, withDuration duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(screen.frame, display: true, animate: true)
        }
    }

    // Smooth exit: animate window frame back to prior windowed size
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
        // Save windowed frame before entering fullscreen
        if let window = notification.object as? NSWindow {
            engine.windowState.priorWindowedFrame = window.frame
        }
        engine.windowState.isFullscreen = true
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        // isFullscreen already set in willEnter
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        // Animation about to start
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        engine.windowState.isFullscreen = false
    }
}
