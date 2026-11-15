import Cocoa
import OpenGL.GL
import OpenGL.GL3

/// CAOpenGLLayer subclass that renders mpv video frames via the mpv render API.
/// Follows IINA's ViewLayer pattern — uses a dedicated GL render thread with userInteractive QoS.
final class MPVVideoLayer: CAOpenGLLayer {

    weak var mpvDecoder: MPVDecoder?

    /// Dedicated render thread for mpv GL work — same pattern as IINA's mpvGLQueue.
    private let mpvGLQueue = DispatchQueue(label: "io.github.jameslee9506.macplayer.mpv.gl", qos: .userInteractive)

    /// When true, drawing will proceed even if mpv indicates nothing needs to be done.
    nonisolated(unsafe) private var forceDraw = false

    /// Tracks the FBO used by CAOpenGLLayer's backing store.
    private var fbo: GLint = 1

    override init() {
        super.init()
        isOpaque = true
        isAsynchronous = false
        backgroundColor = NSColor.black.cgColor
        autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        needsDisplayOnBoundsChange = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - CAOpenGLLayer

    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        let attrs: [CGLPixelFormatAttribute] = [
            kCGLPFADoubleBuffer,
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
            kCGLPFAAccelerated,
            kCGLPFAAllowOfflineRenderers,
            CGLPixelFormatAttribute(0)
        ]

        var pix: CGLPixelFormatObj?
        var num: GLint = 0
        CGLChoosePixelFormat(attrs, &pix, &num)
        return pix!
    }

    override func copyCGLContext(forPixelFormat pf: CGLPixelFormatObj) -> CGLContextObj {
        let ctx = super.copyCGLContext(forPixelFormat: pf)

        // Enable multi-threaded GL engine and vsync
        var swapInterval: GLint = 1
        CGLSetParameter(ctx, kCGLCPSwapInterval, &swapInterval)
        CGLEnable(ctx, kCGLCEMPEngine)

        // Initialize mpv render context on first GL context creation
        CGLSetCurrentContext(ctx)
        mpvDecoder?.initRenderContext { _, name -> UnsafeMutableRawPointer? in
            guard let name else { return nil }
            let symbol = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingASCII)
            let id = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString)
            let addr = CFBundleGetFunctionPointerForName(id, symbol)
            return unsafeBitCast(addr, to: UnsafeMutableRawPointer?.self)
        }

        return ctx
    }

    override func canDraw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj, forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) -> Bool {
        // Use mpv_render_context_update to properly check if a frame is ready (IINA pattern)
        return forceDraw || (mpvDecoder?.shouldRenderUpdateFrame() ?? false)
    }

    override func draw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj, forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) {
        forceDraw = false

        guard let mpvDecoder else { return }

        CGLSetCurrentContext(ctx)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

        // Read actual FBO and viewport from OpenGL state (not hardcoded!)
        // CAOpenGLLayer uses its own framebuffer, not necessarily FBO 0.
        var currentFBO: GLint = 0
        glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &currentFBO)
        var viewport: [GLint] = [0, 0, 0, 0]
        glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)

        if currentFBO != 0 { fbo = currentFBO }

        let w = viewport[2]
        let h = viewport[3]
        guard w > 0, h > 0 else { return }

        mpvDecoder.render(fbo: Int32(fbo), width: Int32(w), height: Int32(h))
        glFlush()

        // Report swap to mpv (required for advanced_control)
        mpvDecoder.reportSwap()
    }

    // MARK: - Display (IINA pattern)

    /// Reload the content of this layer.
    /// Uses explicit CATransaction when not on main thread (IINA pattern, issue #5038).
    override func display() {
        if Thread.isMainThread {
            super.display()
        } else {
            CATransaction.begin()
            super.display()
            CATransaction.commit()
        }
        CATransaction.flush()
    }

    /// Called by the mpv render update callback when a new frame is available.
    /// Dispatches to mpvGLQueue and calls display() — same as IINA's `update()`.
    func update(force: Bool = false) {
        mpvGLQueue.async { [self] in
            if force { forceDraw = true }
            display()
        }
    }
}
