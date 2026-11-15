export interface BlogPost {
  slug: string;
  title: string;
  description: string;
  date: string;
  tag: string;
  readTime: string;
  content: string;
}

export const blogPosts: BlogPost[] = [
  {
    slug: "why-we-built-macplayer",
    title: "Why We Built MacPlayer",
    description: "The story behind MacPlayer — what's wrong with existing Mac video players and how we set out to fix it.",
    date: "2025-02-16",
    tag: "Story",
    readTime: "4 min",
    content: `
Every Mac user has experienced the frustration. You download a video file — maybe an MKV from a friend, a WebM clip, or an AVI from an old archive — and double-click it. QuickTime opens, thinks for a moment, and tells you it can't play the file.

So you install VLC. It plays everything, but the interface feels like it was designed for Windows XP. It doesn't respect macOS conventions — no native title bar, no proper fullscreen animation, no system integration.

Then you discover IINA. Beautiful interface, plays everything thanks to mpv under the hood. But it hasn't seen a major update in a while, the UI can feel sluggish during panel animations, and there's no bookmark system.

**That's why we built MacPlayer.**

## The Vision

We wanted a video player that combines the best of all worlds:

- **IINA's engine** — mpv/libmpv for universal format support and buttery-smooth playback
- **QuickTime's polish** — a native macOS interface that feels right at home
- **Features nobody else offers** — timestamp bookmarks with thumbnails, persistent per-file settings, A-B loop

## What Makes It Different

MacPlayer is built with **SwiftUI** for the entire interface. Not AppKit wrappers, not Cocoa bindings — pure SwiftUI with \`@Observable\` for reactive state management. This means the UI is modern, responsive, and follows Apple's latest design patterns.

Under the hood, the **mpv engine** handles decoding. This gives us support for virtually every video format in existence: MKV, WebM, AVI, MP4, FLAC audio, VP9, AV1, H.265 — you name it.

## Core Principles

1. **Play everything** — No more "format not supported" dialogs
2. **Feel native** — SwiftUI interface that respects macOS conventions
3. **Stay fast** — Hardware-accelerated decoding, efficient rendering
4. **Respect privacy** — 100% offline, no telemetry, no network requests
5. **Free forever** — Open source, no ads, no subscriptions

MacPlayer isn't just another video player. It's the player macOS deserves.
    `,
  },
  {
    slug: "inside-the-mpv-engine",
    title: "Inside the mpv Engine: Why We Chose libmpv",
    description: "A deep dive into why we integrated libmpv as our playback engine and what it means for format support and performance.",
    date: "2025-02-15",
    tag: "Engineering",
    readTime: "6 min",
    content: `
When we started MacPlayer, we built it entirely on Apple's AVFoundation framework. It seemed like the right choice — native, well-documented, hardware-accelerated. But we quickly hit walls.

## The AVFoundation Problem

AVFoundation is great for MP4 and MOV files. But try to play an MKV file? Not supported. WebM? Nope. AVI with DivX? Forget it.

The format limitations are just the beginning:

| Feature | AVFoundation | mpv |
|---------|-------------|-----|
| MKV support | ❌ | ✅ |
| WebM/VP9 | ❌ | ✅ |
| AVI/DivX | ❌ | ✅ |
| ASS subtitles | ❌ | ✅ (styled) |
| Audio codecs | AAC, MP3 | Opus, Vorbis, FLAC, DTS, everything |
| A/V sync modes | Automatic only | Advanced (audio/display-sync) |

We initially tried to work around AVFoundation's limitations with NV12 native output, Metal shaders, and render thread isolation. These optimizations helped — we eliminated ~1.9 GB/s of CPU bandwidth for 4K60 content. But the format support problem remained unsolvable.

## Enter libmpv

mpv is the engine behind IINA, the most popular third-party video player on macOS. It's built on FFmpeg for demuxing and decoding, with VideoToolbox hardware acceleration on macOS.

We integrated **libmpv** — mpv's embeddable library — directly into MacPlayer. Here's what that gives us:

### Universal Format Support
mpv plays virtually everything. MKV, WebM, AVI, FLV, OGM, TS — every container format. H.264, H.265, VP8, VP9, AV1, VC-1, DivX — every codec. Opus, Vorbis, FLAC, DTS, AC3 — every audio format.

### Hardware Decoding
mpv uses \`--hwdec=auto\` to automatically detect and use VideoToolbox hardware decoding. This means H.264, H.265, VP9, and AV1 are all decoded by the GPU, keeping CPU usage minimal.

### Built-in Subtitle Rendering
mpv includes **libass** for full ASS/SSA subtitle rendering. This means styled subtitles with fonts, colors, positioning, and animations — all rendered directly in the video output. No separate subtitle overlay needed.

## The Integration

We use mpv's **OpenGL Render API**. mpv renders frames to an OpenGL framebuffer object (FBO), which is displayed through a \`CAOpenGLLayer\`. This follows IINA's proven approach.

The key components:

- **MPVDecoder** — Wraps the libmpv C API with a Swift interface
- **MPVVideoLayer** — A \`CAOpenGLLayer\` subclass that provides the OpenGL surface for mpv to render into
- **MPVVideoView** — A SwiftUI \`NSViewRepresentable\` wrapper

The render loop follows IINA's battle-tested pattern:

1. mpv signals a new frame via \`mpv_render_context_set_update_callback\`
2. We dispatch to a dedicated render queue (\`mpvGLQueue\`, \`.userInteractive\` QoS)
3. \`mpv_render_context_update()\` confirms the frame is ready
4. We read the actual FBO and viewport from OpenGL state
5. \`mpv_render_context_render()\` draws the frame
6. \`mpv_render_context_report_swap()\` tells mpv the frame was displayed

## Single Backend Architecture

MacPlayer uses mpv as its **sole playback backend**. There's no protocol abstraction or fallback decoder — \`MPVDecoder\` handles everything directly.

For Apple-specific features like Picture-in-Picture, we use \`PIPViewController\` (Apple's private API), which works with any \`NSView\` — including mpv's OpenGL layer. No \`AVPlayer\` required.

The result? **IINA-level format support and performance**, with a modern SwiftUI interface on top.
    `,
  },
  {
    slug: "dual-path-rendering-architecture",
    title: "The Rendering Architecture: mpv + OpenGL",
    description: "How MacPlayer renders video through mpv's OpenGL pipeline — from VideoToolbox decoding to CAOpenGLLayer display.",
    date: "2025-02-14",
    tag: "Engineering",
    readTime: "5 min",
    content: `
MacPlayer's rendering is built on a single, highly optimized path: mpv renders directly through OpenGL into a \`CAOpenGLLayer\`. No intermediate copies, no context switches, no Metal fallbacks.

## The mpv OpenGL Pipeline

mpv handles the entire rendering pipeline internally — YUV to RGB conversion, scaling, subtitle compositing, tone mapping — in a single GPU pass via GLSL shaders.

This is the same approach used by IINA, and it's incredibly efficient. mpv's renderer is highly optimized with:
- Automatic BT.601/BT.709/BT.2020 color space detection
- Hardware-accelerated decoding via VideoToolbox
- Native HDR tone mapping (\`tone-mapping=auto\`)
- Built-in ASS subtitle rendering via libass

## How It Works

The render loop follows IINA's battle-tested pattern:

1. mpv signals a new frame via \`mpv_render_context_set_update_callback\`
2. We dispatch to a dedicated render queue (\`mpvGLQueue\`, \`.userInteractive\` QoS)
3. \`mpv_render_context_update()\` confirms the frame is ready
4. We read the actual FBO and viewport from OpenGL state
5. \`mpv_render_context_render()\` draws the frame into the \`CAOpenGLLayer\`
6. \`mpv_render_context_report_swap()\` tells mpv the frame was displayed

The key components:

- **MPVDecoder** — Wraps the libmpv C API, manages the render context
- **MPVVideoLayer** — A \`CAOpenGLLayer\` subclass that provides the OpenGL surface
- **MPVVideoView** — A SwiftUI \`NSViewRepresentable\` wrapper

## Why OpenGL Instead of Metal?

mpv's render API is built around OpenGL. While Apple has deprecated OpenGL on macOS, it remains fully functional and mpv's GLSL shader pipeline is heavily optimized for it. The alternative — extracting pixel buffers from mpv and re-rendering through Metal — would add an unnecessary copy and negate mpv's rendering optimizations.

We silence the deprecation warnings with \`GL_SILENCE_DEPRECATION=1\` and accept the tradeoff: proven, battle-tested rendering performance over a "modern" API that would actually be slower for our use case.

## Render Thread Isolation

All rendering happens on a **dedicated dispatch queue** (\`mpvGLQueue\`) with \`.userInteractive\` QoS. The main thread handles UI updates only.

This ensures the SwiftUI interface remains responsive even during heavy 4K playback — a lesson learned from IINA, which found that main-thread rendering caused side panel animations to stutter.

## Video Filters

Video filters (brightness, contrast, saturation, sharpen, deband) are applied through mpv's built-in filter system. mpv processes these in the same GPU pass as the main rendering — no separate filter pipeline, no additional overhead.

Filter settings are saved per-file in SQLite, so your adjustments persist across sessions.

## HDR Tone Mapping

For HDR content (PQ/HDR10, HLG), mpv handles all tone mapping natively:

- \`tone-mapping=auto\` — Adaptive tone mapping algorithm
- \`hdr-compute-peak=auto\` — Dynamic peak detection
- \`target-colorspace-hint=auto\` — Display hint for HDR-capable monitors

MacPlayer's HDRManager observes mpv's \`video-params/primaries\` and \`video-params/gamma\` properties to detect HDR content and update the UI state, but all the actual tone mapping work is done by mpv.

## The Result

This single-path architecture keeps things simple and fast. mpv's renderer is purpose-built for video — it handles color conversion, scaling, filtering, subtitles, and tone mapping in one GPU pass. By not adding intermediate layers or framework abstractions, MacPlayer matches IINA's rendering performance while keeping the codebase lean.
    `,
  },
  {
    slug: "playing-everything",
    title: "Playing Everything: MKV, WebM, and Beyond",
    description: "How MacPlayer achieves universal format support — every container, every codec, every audio format.",
    date: "2025-02-12",
    tag: "Features",
    readTime: "4 min",
    content: `
"Format not supported." Four words that no one should see in 2025. MacPlayer plays everything.

## The Format Landscape

Video formats are complicated. There's the **container** (the file format — MKV, MP4, WebM) and the **codec** (the compression method — H.264, VP9, AV1). A single MKV file might contain H.265 video, Opus audio, and ASS subtitles — three completely different technologies wrapped in one container.

QuickTime only supports Apple's preferred combinations: MP4/MOV containers with H.264/H.265 video and AAC audio. That's a tiny slice of what's out there.

## What MacPlayer Supports

### Video Containers
MKV, MP4, MOV, WebM, AVI, FLV, OGM, TS, M2TS — every major container format.

### Video Codecs
- **H.264 / AVC** — The most common codec (hardware accelerated)
- **H.265 / HEVC** — 4K/HDR standard (hardware accelerated)
- **VP9** — YouTube's codec of choice (hardware accelerated)
- **AV1** — The next-generation codec (hardware accelerated on Apple Silicon)
- **VP8** — WebM legacy
- **VC-1** — Blu-ray legacy
- **DivX / Xvid** — AVI-era classics
- And dozens more via FFmpeg's codec library

### Audio Codecs
- **AAC** — Standard MP4 audio
- **Opus** — Modern, efficient codec (WebM, Discord)
- **Vorbis** — Open-source alternative to MP3
- **FLAC** — Lossless audio
- **DTS / DTS-HD** — Surround sound
- **AC3 / E-AC3** — Dolby Digital
- **MP3** — Legacy standard
- **PCM / ALAC** — Uncompressed / Apple Lossless

### Subtitle Formats
- **SRT** — Simple timed text
- **ASS / SSA** — Styled subtitles with fonts, colors, positioning
- **VTT** — Web subtitle format
- **PGS** — Blu-ray bitmap subtitles

## Hardware Acceleration

Universal format support doesn't mean slow software decoding. mpv uses **VideoToolbox** for hardware-accelerated decoding on macOS:

| Codec | Hardware Accel | Notes |
|-------|---------------|-------|
| H.264 | ✅ | All Macs |
| H.265 | ✅ | 2017+ Macs |
| VP9 | ✅ | Apple Silicon |
| AV1 | ✅ | M3+ chips |

When hardware acceleration isn't available (rare codecs), mpv falls back to optimized software decoding — still fast enough for smooth playback.

## Why This Matters

You shouldn't need to think about video formats. Download a file, double-click it, watch it. That's the experience MacPlayer delivers.

No more converting files. No more installing codec packs. No more "format not supported." Just drag, drop, and play.
    `,
  },
  {
    slug: "smart-subtitles",
    title: "Smart Subtitles: SRT, ASS, and Automatic Matching",
    description: "How MacPlayer handles subtitles — from automatic file matching to styled ASS rendering with mpv's built-in engine.",
    date: "2025-02-11",
    tag: "Features",
    readTime: "4 min",
    content: `
Subtitles seem simple on the surface. Display text at the right time. But getting them right involves file detection, format handling, encoding, styling, and precise timing synchronization.

## Automatic Subtitle Matching

MacPlayer uses mpv's \`sub-auto=fuzzy\` option for automatic subtitle file matching. When you open a video, mpv scans the same directory for subtitle files with similar names.

For example, if you open:
\`\`\`
Movie.2024.1080p.BluRay.mkv
\`\`\`

mpv will automatically find and load:
\`\`\`
Movie.2024.1080p.BluRay.srt
Movie.2024.BluRay.eng.srt
Movie.2024.srt
\`\`\`

The fuzzy matching tolerates differences in quality tags, language codes, and minor naming variations.

## Subtitle Formats

All subtitle rendering is handled by **mpv natively** — no custom parsers needed.

### SRT (SubRip)
The most common format. Plain text with timestamps. mpv handles multi-line entries, HTML-style formatting tags, and various timestamp formats.

### ASS / SSA (Advanced SubStation Alpha)
The most powerful subtitle format. ASS files contain styling information — fonts, colors, sizes, positioning, fade effects, and even animations.

mpv's built-in **libass** renderer displays ASS subtitles exactly as the author intended. This is critical for anime fansubs and professionally styled subtitles where positioning and typography matter.

### VTT (WebVTT)
The web standard for subtitles, commonly found with streaming content.

### PGS (Presentation Graphic Stream)
Bitmap-based subtitles from Blu-ray discs. mpv handles these natively when embedded in MKV containers.

## Encoding Detection

Subtitle files come in many encodings — UTF-8, Latin-1, EUC-KR, Shift_JIS, GB2312. mpv's subtitle pipeline handles encoding detection automatically, for both external and embedded subtitle files.

## Audio Delay Compensation

Sometimes subtitles are in sync but the audio isn't. MacPlayer supports **audio delay adjustment** — shift the audio track forward or backward in 100ms increments, up to ±5 seconds. This is applied through mpv's \`audio-delay\` property, which adjusts the A/V sync without re-encoding.

## Why mpv Native Subtitles?

By delegating all subtitle rendering to mpv, we get:

- **No separate overlay** — Subtitles are composited directly in the render pipeline
- **Full ASS styling** — libass support with all style tags, fonts, and animations
- **Embedded subtitles** — MKV files with built-in subtitle tracks just work
- **Multiple tracks** — Switch between subtitle tracks on the fly
- **PGS support** — Bitmap subtitles from Blu-ray discs
- **Zero maintenance** — No custom parsers to maintain or debug

Early versions of MacPlayer had custom SRT, ASS, and VTT parsers with a SwiftUI subtitle overlay. We removed all of that in favor of mpv's native rendering — it's more capable, more reliable, and handles edge cases we'd never think to test.
    `,
  },
  {
    slug: "swiftui-meets-video",
    title: "SwiftUI Meets Video: Building a Native macOS Player",
    description: "How we built a video player with pure SwiftUI — @Observable state, strict concurrency, and 16 composable managers.",
    date: "2025-02-10",
    tag: "Engineering",
    readTime: "6 min",
    content: `
Most video players on macOS use AppKit or even cross-platform frameworks. MacPlayer is built entirely with **SwiftUI** for the interface layer. Here's how we made it work — and why it matters.

## Why SwiftUI?

IINA uses AppKit with Cocoa bindings and XIB files. VLC uses a custom cross-platform toolkit. We chose SwiftUI because:

1. **Declarative UI** — Describe what the interface looks like, not how to build it
2. **Reactive state** — UI updates automatically when data changes
3. **Modern macOS design** — Built-in support for vibrancy, Dark Mode, and system conventions
4. **Less code** — SwiftUI eliminates boilerplate that AppKit requires

The result is a clean, responsive interface that feels native to macOS.

## The @Observable Architecture

MacPlayer uses Swift's \`@Observable\` macro (not the older \`ObservableObject\` protocol) for state management. This means fine-grained observation — SwiftUI only re-renders views that depend on properties that actually changed.

The central **PlaybackEngine** class is the single source of truth:

\`\`\`swift
@MainActor @Observable
final class PlaybackEngine {
    var state: PlayerState = .idle
    var currentTime: Double = 0
    var duration: Double = 0
    var mediaTitle: String = ""
    var volume: Float = 1.0
    // ... more observable state
}
\`\`\`

Every SwiftUI view reads directly from \`PlaybackEngine\`. No bindings, no publishers, no Combine pipelines. When \`currentTime\` changes, only views displaying the time re-render. When \`volume\` changes, only the volume slider updates.

## Composition Over Inheritance

PlaybackEngine doesn't subclass anything. Instead, it **composes 16 independent managers**:

\`\`\`
PlaybackEngine
├── decoder (MPVDecoder)
├── osd (OSDManager)
├── windowState (WindowState)
├── playlist (PlaylistManager)
├── bookmarks (BookmarkManager)
├── history (PlaybackHistoryManager)
├── filters (FilterManager)
├── hdr (HDRManager)
├── nowPlaying (NowPlayingManager)
├── sleepPreventer (SleepPreventer)
├── abLoop (ABLoopManager)
├── pip (PiPManager)
├── thumbnails (ThumbnailGenerator)
├── keyBindings (KeyBindingManager)
└── perFileStore (PerFileSettingsStore)
\`\`\`

Each manager is independently testable and replaceable. The engine orchestrates them without any manager needing to know about the others.

## Strict Concurrency

MacPlayer uses **Swift Strict Concurrency** (\`SWIFT_STRICT_CONCURRENCY: complete\`). Every class is annotated with its isolation domain:

- **\`@MainActor\`** — PlaybackEngine, all managers, SwiftUI views
- **\`nonisolated\`** — Render callbacks, mpv event handlers
- **\`nonisolated(unsafe)\`** — C callback bridges, mpv event handlers

This catches concurrency bugs at compile time. The mpv integration required careful annotation since mpv callbacks fire from arbitrary threads:

\`\`\`swift
// mpv event handler — fires on eventQueue, not main thread
nonisolated private func handlePropertyChange(_ name: String, _ prop: mpv_event_property) {
    // Read the property on eventQueue
    let time = data.assumingMemoryBound(to: Double.self).pointee
    // Dispatch to main actor for state update
    DispatchQueue.main.async { [weak self] in
        self?.currentTime = time
    }
}
\`\`\`

## SwiftUI + CAOpenGLLayer

One challenge: mpv renders via OpenGL, but SwiftUI doesn't directly support OpenGL views. Our solution:

1. **MPVVideoLayer** — A \`CAOpenGLLayer\` subclass where mpv renders frames
2. **MPVVideoNSView** — An \`NSView\` that hosts the \`MPVVideoLayer\`
3. **MPVVideoView** — An \`NSViewRepresentable\` that bridges to SwiftUI

\`\`\`swift
struct MPVVideoView: NSViewRepresentable {
    let engine: PlaybackEngine

    func makeNSView(context: Context) -> MPVVideoNSView {
        let view = MPVVideoNSView()
        // Set up the OpenGL layer for mpv rendering
        return view
    }
}
\`\`\`

The video surface is always present in the view hierarchy so the OpenGL context exists before mpv starts loading a file.

## The UI Components

Every control is a SwiftUI view:

- **ControlBar** — Play/pause, seek, volume, playlist toggle
- **SeekBar** — Precision seeking with thumbnail preview on hover
- **OSD** — Animated on-screen display for volume, seek, speed changes
- **SidePanel** — Playlist and filter adjustments
- **SettingsView** — All preferences in a native sheet

All of these react to \`PlaybackEngine\` state changes automatically. No manual UI refresh, no delegate callbacks, no notification observers.

## ~6,200 Lines of Code

The entire application — engine, renderer, UI, features, infrastructure — is about **6,200 lines of Swift code**. For comparison, IINA is over 50,000 lines. SwiftUI's declarative approach dramatically reduces the code needed to build a full-featured video player.
    `,
  },
  {
    slug: "power-features",
    title: "Power Features: Bookmarks, A-B Loop, Filters, and More",
    description: "A tour of MacPlayer's unique features — timestamp bookmarks with thumbnails, A-B loop, real-time filters, and per-file settings.",
    date: "2025-02-09",
    tag: "Features",
    readTime: "5 min",
    content: `
A great video player doesn't just play video. It gives you control. Here are the features that make MacPlayer stand out.

## Timestamp Bookmarks with Thumbnails

Ever wanted to mark a specific moment in a video and come back to it later? MacPlayer lets you **save bookmarks at any timestamp**, each with a thumbnail preview.

- Press a keyboard shortcut to bookmark the current position
- Each bookmark captures a thumbnail of the current frame
- Bookmarks are persisted in a local SQLite database
- Jump back to any bookmark instantly
- Bookmarks are organized per-video

This is something neither QuickTime, VLC, nor IINA offers. It's perfect for studying, reviewing footage, or marking favorite scenes.

## A-B Loop

Need to watch a specific section on repeat? Set an **A point** and a **B point**, and MacPlayer will loop that section continuously.

- Visual markers on the seek bar: green line for A, red line for B
- Blue highlighted region shows the active loop range
- Clear the loop with one keystroke
- Perfect for language learning, music practice, or analyzing specific scenes

## Real-Time Video Filters

Five GPU-accelerated filters, adjustable in real-time:

| Filter | Range | What It Does |
|--------|-------|-------------|
| Brightness | -1.0 to 1.0 | Lighten or darken the image |
| Contrast | 0.0 to 3.0 | Increase or decrease tonal range |
| Saturation | 0.0 to 3.0 | Color intensity adjustment |
| Sharpen | 0.0 to 2.0 | Enhance edge detail |
| Deband | 0.0 to 128.0 | Remove color banding artifacts |

All filters are processed through mpv's built-in filter system. No CPU overhead, no frame drops.

Filter settings are **saved per-file** — adjust the brightness for a dark movie, and it's remembered the next time you open that file.

## Per-File Settings

Speaking of per-file settings, MacPlayer remembers your preferences for every video:

- **Rotation** — 0°, 90°, 180°, 270° saved per file
- **Filter values** — Your brightness/contrast/saturation adjustments
- **Audio delay** — A/V sync offset per file
- **Playback position** — Resume where you left off

All stored in a local SQLite database with a 90-day TTL. Open a file weeks later and pick up exactly where you left off with all your adjustments intact.

## Playlist Management

Drag and drop multiple files or entire folders. MacPlayer builds a playlist and plays them in sequence.

- Drag-and-drop reordering
- Auto-detection of video files in folders
- Current playback position saved per track
- Auto-advance to next track at end of video
- Keyboard shortcuts for next/previous

## Instant Seek Preview

Hover over the seek bar and you get an instant thumbnail preview of that position — no loading spinner, no delay. MacPlayer **pre-generates thumbnails** across the entire video timeline as soon as you open a file.

- Thumbnails are generated at adaptive intervals based on video duration (2s for short clips, up to 12s for movies)
- Pre-generation runs in the background immediately after loading, using batched processing to keep the UI responsive
- Cached thumbnails are served instantly on hover — no async loading visible to the user
- Flicker-free transitions: the display only updates when you move to a different time region

This is the same approach used by professional video editing tools. The result is a seek experience that feels as responsive as scrubbing through a local photo library.

## Playback Speed Control

Cycle through playback speeds with a single key: **0.25x → 0.5x → 0.75x → 1.0x → 1.25x → 1.5x → 2.0x → 3.0x → 4.0x**.

Speed changes are instant with no audio artifacts — mpv handles the time-stretching internally.

## Frame-by-Frame Navigation

Step forward or backward one frame at a time. Essential for video analysis, finding the exact right frame for a screenshot, or studying animation.

## Screenshots

Capture the current frame as a PNG image. Saved to \`~/Pictures/MacPlayer Screenshots/\` with timestamps. The mpv backend uses mpv's native screenshot command for pixel-perfect capture.

## Keyboard-Driven

Every feature is accessible via keyboard shortcuts:

- **Space** — Play/Pause
- **←/→** — Seek 5 seconds
- **↑/↓** — Volume
- **F** — Fullscreen
- **[/]** — Playback speed
- **./,** — Frame step forward/backward
- **B** — Add bookmark

All shortcuts are customizable. Power users can rebind everything to their preference.

## HDR Support

MacPlayer detects HDR content (PQ and HLG transfer functions) and configures the display accordingly. On HDR-capable displays, content is shown in Extended Dynamic Range with proper tone mapping.

## Now Playing Integration

macOS Control Center shows what's playing with play/pause and seek controls. Lock screen media controls work too — MacPlayer integrates with the system \`MPNowPlayingInfoCenter\`.

## Sleep Prevention

Playing a long movie? MacPlayer automatically prevents your Mac from sleeping during playback using IOKit power assertions. When you pause, sleep is allowed again.

---

These aren't gimmicks — they're features that make a real difference in daily use. MacPlayer is designed for people who actually watch video on their Mac, not just people who occasionally double-click an MP4.
    `,
  },
];

export function getBlogPost(slug: string): BlogPost | undefined {
  return blogPosts.find((post) => post.slug === slug);
}
