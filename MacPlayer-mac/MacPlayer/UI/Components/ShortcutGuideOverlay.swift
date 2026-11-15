import SwiftUI

/// Full-screen overlay showing all keyboard shortcuts organized by category.
struct ShortcutGuideOverlay: View {
    @Binding var isPresented: Bool

    private let categories: [(title: String, icon: String, items: [(key: String, label: String)])] = [
        ("Playback", "play.fill", [
            ("Space", "Play / Pause"),
            ("←  →", "Seek ±5s"),
            ("⇧←  ⇧→", "Seek ±30s"),
            (",  .", "Frame Step"),
        ]),
        ("Volume", "speaker.wave.2.fill", [
            ("↑  ↓", "Volume Up / Down"),
            ("Scroll", "Volume (Mouse Wheel)"),
            ("M", "Toggle Mute"),
        ]),
        ("Navigation", "list.bullet", [
            ("N", "Next Track"),
            ("P", "Previous Track"),
            ("⌘O", "Open File"),
        ]),
        ("Loop & Bookmark", "repeat", [
            ("[", "Set Loop A"),
            ("]", "Set Loop B"),
            ("\\", "Clear Loop"),
            ("B", "Add Bookmark"),
            ("\u{21E7}B", "Next Bookmark"),
            ("\u{2325}B", "Previous Bookmark"),
        ]),
        ("View", "rectangle.expand.vertical", [
            ("Return", "Toggle Full Screen"),
            ("⌘P", "Picture in Picture"),
            ("⌘K", "Rotate Video"),
            ("S", "Take Screenshot"),
            ("R", "Cycle Speed"),
        ]),
        ("Tracks", "captions.bubble", [
            ("J", "Cycle Subtitle"),
            ("\u{21E7}J", "Cycle Audio"),
        ]),
        ("Sidebar", "sidebar.right", [
            ("⌘1", "Playlist"),
            ("⌘2", "Filters"),
            ("⌘3", "Info"),
            ("⌘4", "Bookmarks"),
            ("⌘5", "Tracks"),
            ("Esc", "Close Sidebar"),
        ]),
        ("Audio Sync", "waveform.badge.plus", [
            ("^]", "Delay +0.1s"),
            ("^[", "Delay −0.1s"),
            ("^\\", "Reset Delay"),
        ]),
    ]

    var body: some View {
        GeometryReader { geo in
            let useTwoColumns = geo.size.width >= 560

            ZStack {
                // Backdrop — covers entire window
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }

                // Content card — inset with margin, max size capped
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Image(systemName: "keyboard")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("Keyboard Shortcuts")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.5))
                                .frame(width: 22, height: 22)
                                .background(.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 14)

                    Divider()
                        .overlay(Color.white.opacity(0.08))

                    // Content — scrolls if needed
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVGrid(
                            columns: useTwoColumns
                                ? [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)]
                                : [GridItem(.flexible())],
                            alignment: .leading,
                            spacing: 24
                        ) {
                            ForEach(Array(categories.enumerated()), id: \.offset) { _, category in
                                categorySection(category)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                    }
                }
                .frame(maxWidth: 620, maxHeight: 560)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(white: 0.13))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 8)
                .padding(24)
            }
        }
        .transition(.opacity)
    }

    private func categorySection(
        _ category: (title: String, icon: String, items: [(key: String, label: String)])
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange.opacity(0.8))
                Text(category.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            VStack(spacing: 2) {
                ForEach(Array(category.items.enumerated()), id: \.offset) { _, item in
                    shortcutRow(key: item.key, label: item.label)
                }
            }
        }
    }

    private func shortcutRow(key: String, label: String) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach(parseKeys(key), id: \.self) { k in
                    Text(k)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(.white.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                        )
                }
            }
            .frame(width: 90, alignment: .leading)

            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 3)
    }

    private func parseKeys(_ raw: String) -> [String] {
        let parts = raw.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        return parts.isEmpty ? [raw] : parts
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            isPresented = false
        }
    }
}
