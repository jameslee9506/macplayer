import SwiftUI
import AppKit

/// SwiftUI wrapper for the mpv OpenGL video rendering surface.
struct MPVVideoView: NSViewRepresentable {
    let engine: PlaybackEngine

    func makeNSView(context: Context) -> MPVVideoNSView {
        MPVVideoNSView(engine: engine)
    }

    func updateNSView(_ nsView: MPVVideoNSView, context: Context) {}
}

/// NSView hosting an MPVVideoLayer for mpv OpenGL rendering.
final class MPVVideoNSView: NSView {
    private let engine: PlaybackEngine
    private var videoLayer: MPVVideoLayer?

    init(engine: PlaybackEngine) {
        self.engine = engine
        super.init(frame: .zero)
        wantsLayer = true
        // Match IINA's VideoView settings
        wantsBestResolutionOpenGLSurface = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeBackingLayer() -> CALayer {
        let layer = MPVVideoLayer()
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        videoLayer = layer
        return layer
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard let window else { return }

        videoLayer?.contentsScale = window.backingScaleFactor

        // Connect the layer to the decoder
        if let mpvDecoder = engine.decoder as? MPVDecoder {
            videoLayer?.mpvDecoder = mpvDecoder

            // Set up render update callback — calls layer.update() like IINA's mpvUpdateCallback
            mpvDecoder.onRenderUpdate = { [weak self] in
                self?.videoLayer?.update()
            }
        }

        // Register this view for PiP (works with any backend)
        engine.pip.setup(videoView: self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Always pass clicks through — SwiftUI handles all interaction
        nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        if engine.pip.isActive { return }
        super.setFrameSize(newSize)
    }

    override func layout() {
        super.layout()
        videoLayer?.frame = bounds
        // Force redraw so paused video redraws at the new size
        videoLayer?.update(force: true)
    }
}
