import SwiftUI

/// Everything drawn on top of the video surface: title, control bar, OSD, and the idle,
/// loading, image and error screens.
///
/// The window, the video view and all input are owned by AppKit (`PlayerWindowController`,
/// `PlayerContentView`); this view only renders `PlaybackEngine` and `PlayerUIState`.
struct PlayerOverlayView: View {
    let engine: PlaybackEngine
    @Bindable var ui: PlayerUIState

    var body: some View {
        ZStack {
            // The video view underneath stays mounted at all times (mpv needs its GL context
            // before loadfile), so cover it whenever there is no video to show.
            if !engine.state.isActive {
                Color.black.ignoresSafeArea()
            }

            // Clicks and drags that land on no control go to AppKit.
            PlayerInteractionLayer()
                .ignoresSafeArea()

            switch engine.state {
            case .idle, .stopped:
                idleView

            case .loading:
                ProgressView("Loading...")
                    .foregroundStyle(.white)
                    .allowsHitTesting(false)

            case .playing, .paused:
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

            case .error(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text(message)
                        .foregroundStyle(.white)
                }
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: ui.showControls)
    }

    // MARK: - Title Overlay (top, next to traffic lights)

    private var titleOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if engine.state.isActive || engine.state == .viewingImage {
                    Button {
                        ui.sidebarTab = ui.sidebarTab == .info ? nil : .info
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
        .opacity(ui.showControls ? 1 : 0)
    }

    // MARK: - Sidebar Toggle (top-right, ignores safe area)

    private var sidebarToggleOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer()
                Button(action: {
                    ui.sidebarTab = ui.sidebarTab != nil ? nil : .playlist
                }) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .symbolVariant(ui.sidebarTab != nil ? .fill : .none)
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
        .allowsHitTesting(ui.showControls)
        .opacity(ui.showControls ? 1 : 0)
    }

    // MARK: - Controls Overlay (bottom bar, auto-hides)

    @ViewBuilder
    private var controlsOverlay: some View {
        VStack {
            Spacer()
            ControlBar(engine: engine, sidebarTab: $ui.sidebarTab)
                .opacity(ui.showControls ? 1 : 0)
        }
        .allowsHitTesting(ui.showControls)
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
                    .allowsHitTesting(false)
            }

            // Title overlay
            titleOverlay

            // Sidebar toggle button
            sidebarToggleOverlay
        }
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

                // Labels let presses through, so the window can be dragged from anywhere but a button.
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
                    .allowsHitTesting(false)

                Text("Drop a video file here  \u{00B7}  \u{2318}O")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.top, compact ? 4 : 6)
                    .allowsHitTesting(false)

                HStack(spacing: 12) {
                    idleButton(icon: "folder", label: "Open File") {
                        engine.openFile()
                    }
                    idleButton(icon: "list.bullet", label: "Playlist") {
                        ui.sidebarTab = ui.sidebarTab == .playlist ? nil : .playlist
                    }
                }
                .padding(.top, compact ? 14 : 24)

                Button {
                    ui.showShortcutGuide = true
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
                        .allowsHitTesting(false)
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
}
