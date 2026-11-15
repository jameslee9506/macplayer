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
                StartView(engine: engine, ui: ui)

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
}
