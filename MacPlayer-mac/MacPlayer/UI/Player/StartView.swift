import AppKit
import SwiftUI

/// First screen of the player, shown while nothing is loaded: the open actions, and
/// shortcuts to recently played files.
///
/// The shortcuts come from the playback history. The playlist is the queue of the current
/// session and stays in the sidebar, behind its own button.
///
/// Under the shortcuts, links clear the list and turn it off. Turned off, a line saying so
/// stands in for the shortcuts, with the link that turns the list back on.
struct StartView: View {
    let engine: PlaybackEngine
    @Bindable var ui: PlayerUIState

    @AppStorage(AppSettings.keepRecentFiles.key) private var keepsRecentFiles = AppSettings.keepRecentFiles.defaultValue

    private static let maxColumnWidth: CGFloat = 560
    private static let maxRecentCount = 10
    private static let horizontalMargin: CGFloat = 24
    private static let verticalMargin: CGFloat = 20
    /// Height of everything but the recent rows: heading, buttons, section label, and the gaps between them.
    private static let chromeHeight: CGFloat = 129
    /// Height the links under the recent rows add, with the gap above them.
    private static let footerHeight: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let recents = engine.history.recentRecords(limit: Self.maxRecentCount)
            // Show as many shortcuts as fit; the window can be as short as 270 points.
            let rowRoom = geo.size.height - Self.chromeHeight - Self.footerHeight - Self.verticalMargin * 2
            let fittingRows = max(0, Int(rowRoom / RecentRow.height))
            let visible = recents.prefix(keepsRecentFiles ? fittingRows : 0)
            // Turned off, the notice takes the place of the shortcuts: one row.
            let rowCount = keepsRecentFiles ? visible.count : min(1, fittingRows)
            let recentHeight = rowCount > 0 ? CGFloat(rowCount) * RecentRow.height + Self.footerHeight : 0
            let contentHeight = Self.chromeHeight + recentHeight

            VStack(alignment: .leading, spacing: 0) {
                heading

                actions
                    .padding(.top, 16)

                if keepsRecentFiles && recents.isEmpty {
                    Text("Drop a video file here  \u{00B7}  \u{2318}O")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.top, 26)
                        .allowsHitTesting(false)
                } else if rowCount > 0 {
                    Text("Recent")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 26)
                        .padding(.bottom, 6)
                        .allowsHitTesting(false)

                    if keepsRecentFiles {
                        ForEach(visible) { record in
                            RecentRow(record: record, engine: engine)
                        }
                        // Rows reach past the column by their inset: the text lines up with the heading
                        // and the hover highlight has room around it.
                        .padding(.horizontal, -RecentRow.inset)
                    } else {
                        Text("Turned off. Files you play are not added to this list.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.35))
                            .lineLimit(1)
                            .frame(height: RecentRow.height)
                            .allowsHitTesting(false)
                    }

                    // The list kept from before it was turned off can still be cleared.
                    recentFooter(canClear: !recents.isEmpty)
                }
            }
            .frame(maxWidth: Self.maxColumnWidth, alignment: .leading)
            .padding(.horizontal, Self.horizontalMargin)
            // Sits a little above the middle, like a document that starts near the top.
            .padding(.top, max(Self.verticalMargin, (geo.size.height - contentHeight) * 0.38))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Heading

    // Labels let presses through, so the window can be dragged from anywhere but a button.
    private var heading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("MacPlayer")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("v\(version)")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Recent Footer

    /// Links under the recent section: clear the list, and turn it off or back on.
    private func recentFooter(canClear: Bool) -> some View {
        HStack(spacing: 7) {
            if canClear {
                RecentFooterLink(
                    title: "Clear Recent",
                    help: "Forget the files played so far, and where each was left"
                ) {
                    engine.history.clearHistory()
                }

                Text(verbatim: "\u{00B7}")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.25))
                    .allowsHitTesting(false)
            }

            if keepsRecentFiles {
                RecentFooterLink(
                    title: "Turn Off Recent",
                    help: "Hide this list and stop adding the files you play to it"
                ) {
                    keepsRecentFiles = false
                }
            } else {
                RecentFooterLink(
                    title: "Turn On Recent",
                    help: "Show this list and add the files you play to it"
                ) {
                    keepsRecentFiles = true
                }
            }
        }
        .padding(.top, Self.footerHeight - RecentFooterLink.height)
    }

    // MARK: - Actions

    /// Labelled buttons, or icons alone when the sidebar leaves too little room.
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            actionButtons(showsLabels: true)
            actionButtons(showsLabels: false)
        }
    }

    private func actionButtons(showsLabels: Bool) -> some View {
        HStack(spacing: 10) {
            actionButton("Open", icon: "folder", help: "Open a file or folder (\u{2318}O)", showsLabel: showsLabels) {
                engine.openFile()
            }
            actionButton("Playlist", icon: "list.bullet", help: "Show the playlist", showsLabel: showsLabels) {
                ui.sidebarTab = ui.sidebarTab == .playlist ? nil : .playlist
            }
            actionButton("Shortcuts", icon: "keyboard", help: "Keyboard shortcuts", showsLabel: showsLabels) {
                ui.showShortcutGuide = true
            }
        }
    }

    private func actionButton(
        _ title: LocalizedStringKey,
        icon: String,
        help: LocalizedStringKey,
        showsLabel: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                if showsLabel {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, showsLabel ? 13 : 9)
            .frame(height: 34)
        }
        .buttonStyle(StartActionButtonStyle())
        .help(help)
        .accessibilityLabel(title)
    }
}

// MARK: - Action Button Style

/// Outlined rounded rectangle that brightens under the pointer.
/// The error screen uses it too, for the same look on the same black background.
struct StartActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StartActionButtonBody(configuration: configuration)
    }
}

private struct StartActionButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        configuration.label
            .foregroundStyle(.white.opacity(0.88))
            .background(.white.opacity(isHovered ? 0.1 : 0.04), in: shape)
            .overlay(shape.strokeBorder(.white.opacity(isHovered ? 0.3 : 0.18), lineWidth: 1))
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

// MARK: - Recent Row

/// One shortcut: the title as a link, followed by the folder the file lives in.
private struct RecentRow: View {
    static let height: CGFloat = 26
    static let inset: CGFloat = 6

    private static let linkColor = Color(red: 0.36, green: 0.62, blue: 1)

    let record: PlaybackRecord
    let engine: PlaybackEngine

    @State private var isHovered = false

    var body: some View {
        Button {
            engine.openRecent(record)
        } label: {
            TitleDetailLayout {
                Text(record.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Self.linkColor)
                    .truncationMode(.middle)

                Text(Self.folderPath(of: record.videoURL))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
                    .truncationMode(.head)
            }
            .lineLimit(1)
            .padding(.horizontal, Self.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Self.height)
            .background(.white.opacity(isHovered ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { isHovered = $0 }
        .help(record.videoURL.path)
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([record.videoURL])
            }
            Divider()
            Button("Remove from Recent") {
                engine.history.removeRecord(record)
            }
            Button("Clear Recent") {
                engine.history.clearHistory()
            }
        }
    }

    /// The sandbox reports the app container as the home directory, so the real one
    /// comes from the user database.
    private static let homeDirectory: String = {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return String(cString: directory)
        }
        return NSHomeDirectory()
    }()

    /// Folder of the file, with the home directory shortened to `~`.
    private static func folderPath(of url: URL) -> String {
        let folder = url.deletingLastPathComponent().path
        if folder == homeDirectory { return "~" }
        if folder.hasPrefix(homeDirectory + "/") {
            return "~" + folder.dropFirst(homeDirectory.count)
        }
        return folder
    }
}

// MARK: - Recent Footer Link

/// Small text link under the recent section: dim until the pointer is over it.
private struct RecentFooterLink: View {
    static let height: CGFloat = 20

    let title: LocalizedStringKey
    let help: LocalizedStringKey
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(isHovered ? 0.8 : 0.4))
                .lineLimit(1)
                .frame(height: Self.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

/// Puts a title and the detail that follows it on one line. Both keep their natural width
/// while they fit. When they do not, the detail keeps a share of the line and the title
/// truncates into the rest, so a long title never pushes the detail out.
private struct TitleDetailLayout: Layout {
    private static let spacing: CGFloat = 12
    /// Part of the line the detail may hold on to when the title is too long.
    private static let detailShare: CGFloat = 0.35

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = widths(in: proposal.width, subviews: subviews)
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: widths.title + Self.spacing + widths.detail, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let widths = widths(in: bounds.width, subviews: subviews)
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(width: widths.title, height: bounds.height)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + widths.title + Self.spacing, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(width: widths.detail, height: bounds.height)
        )
    }

    private func widths(in available: CGFloat?, subviews: Subviews) -> (title: CGFloat, detail: CGFloat) {
        guard subviews.count == 2 else { return (0, 0) }
        let title = subviews[0].sizeThatFits(.unspecified).width
        let detail = subviews[1].sizeThatFits(.unspecified).width
        guard let available, title + Self.spacing + detail > available else { return (title, detail) }

        let room = max(0, available - Self.spacing)
        let detailWidth = min(detail, max(room * Self.detailShare, room - title))
        // A truncated title ends on a character boundary, short of the width it was given;
        // the detail follows it directly and takes the slack.
        let titleWidth = subviews[0].sizeThatFits(ProposedViewSize(width: room - detailWidth, height: nil)).width
        return (titleWidth, min(detail, room - titleWidth))
    }
}
