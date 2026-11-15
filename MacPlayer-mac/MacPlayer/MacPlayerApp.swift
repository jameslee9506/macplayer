import SwiftUI
import AppKit

@main
struct MacPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The player window is owned by AppKit (PlayerWindowController).
        // SwiftUI supplies the Settings window and the menu commands.
        Settings {
            SettingsView(engine: appDelegate.engine)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    appDelegate.openFile()
                }
                .keyboardShortcut("o")
            }

            CommandGroup(after: .toolbar) {
                Button("Toggle Full Screen") {
                    appDelegate.playerWindowController.toggleFullScreen()
                }
                .keyboardShortcut("f")
            }
        }
    }
}

/// App delegate owns the engine and the player window, and handles file association
/// (double-click to open), the Dock menu, and the default-player prompt.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = PlaybackEngine()

    /// Created on first use — before any file is opened, so the video surface exists by then.
    private(set) lazy var playerWindowController = PlayerWindowController(engine: engine)

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = playerWindowController
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        playerWindowController.showWindow(nil)

        // Prompt to set as default video player on first launch
        promptDefaultPlayerIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Quitting mid-file is the usual way to stop watching: keep the resume position.
        engine.savePlaybackState()
        playerWindowController.teardown()
    }

    /// Clicking the Dock icon brings back a player window that was closed.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            playerWindowController.showWindow(nil)
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        playerWindowController.showWindow(nil)
        Task {
            if urls.count == 1, let url = urls.first {
                await engine.open(url)
            } else if urls.count > 1 {
                let playableURLs = urls.filter { PlaylistManager.isVideoFile($0) || PlaylistManager.isDirectory($0) }
                await engine.openAsPlaylist(playableURLs)
            }
        }
    }

    func openFile() {
        playerWindowController.showWindow(nil)
        engine.openFile()
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
                item.representedObject = record
                menu.addItem(item)
            }
        }

        return menu
    }

    @objc private func openRecentFile(_ sender: NSMenuItem) {
        guard let record = sender.representedObject as? PlaybackRecord else { return }
        playerWindowController.showWindow(nil)
        engine.openRecent(record)
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
