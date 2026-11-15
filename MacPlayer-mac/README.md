# MacPlayer

A native macOS media player built with Swift and SwiftUI, powered by [mpv/libmpv](https://mpv.io/) for broad codec support and high-quality rendering.

**Repository:** [jameslee9506/macplayer](https://github.com/jameslee9506/macplayer)

## Features

- **Broad format support** — Plays virtually any video/audio format via mpv/libmpv (MKV, MP4, AVI, FLAC, etc.)
- **OpenGL rendering** — CAOpenGLLayer backed by mpv's render API with vsync
- **HDR support** — PQ (HDR10), HLG detection with mpv native tone mapping (`tone-mapping=auto`)
- **Subtitle support** — mpv native rendering with SRT, ASS, VTT and automatic file matching (`sub-auto=fuzzy`)
- **A-B loop** — Set loop points for segment repetition
- **Frame-by-frame navigation** — Step forward and backward through individual frames
- **Customizable keyboard shortcuts** — Fully rebindable key bindings with a visual key recorder
- **Thumbnail preview** — Seek bar scrubbing with pre-generated thumbnail previews
- **Bookmarks** — Timestamp bookmarks with optional screenshot thumbnails, persisted in SQLite
- **Video filters** — Real-time brightness, contrast, saturation, sharpen, and deband
- **Picture-in-Picture** — Native macOS PiP via `PIPViewController`
- **Playback history** — SQLite-backed history with per-file settings (position, audio delay, rotation, filters)
- **Playlist** — Folder scanning, drag-to-reorder, next/previous navigation
- **System integration** — Now Playing (Control Center), Touch Bar, media keys, sleep prevention
- **Screenshot capture** — Full-frame PNG capture

## Requirements

- macOS 15.0 (Sequoia) or later
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [Homebrew](https://brew.sh/) (for mpv dependency)

## Building from Source

### 1. Install dependencies

```bash
brew install xcodegen mpv ffmpeg
```

### 2. Bundle mpv dylibs

The project bundles mpv and its transitive dependencies as dylibs. Run the bundling script to copy and rewrite rpaths:

```bash
cd MacPlayer-mac
./scripts/bundle_dylibs.sh
```

This copies dylibs from Homebrew into `MacPlayer/deps/lib/` and rewrites their install names for app-relative loading.

### 3. Generate Xcode project

```bash
xcodegen generate
```

### 4. Build and run

Open `MacPlayer.xcodeproj` in Xcode and build (Cmd+R), or:

```bash
xcodebuild -project MacPlayer.xcodeproj -scheme MacPlayer -configuration Debug build
```

> **Note:** After any changes to `project.yml`, re-run `xcodegen generate`.

## Architecture

```
MacPlayer/
├── Core/
│   ├── Engine/          # MPVDecoder, PlaybackEngine
│   ├── Model/           # PlayerState, MediaInfo, WindowState, PerFileSettings
│   └── Renderer/        # MPVVideoLayer (CAOpenGLLayer), MPVVideoNSView, ScreenshotCapture
├── Features/
│   ├── Bookmark/        # Timestamp bookmarks with thumbnails
│   ├── Filter/          # Video filter pipeline (brightness, contrast, etc.)
│   ├── HDR/             # HDR detection and state management
│   ├── PiP/             # Picture-in-Picture via PIPViewController
│   ├── Playback/        # A-B loop manager
│   ├── Playlist/        # Playlist and playback history managers
│   ├── Subtitle/        # Subtitle configuration (mpv native rendering)
│   └── Thumbnail/       # Pre-generation and on-demand thumbnail generation
├── Infrastructure/
│   ├── KeyBinding/      # Customizable keyboard shortcut system
│   ├── Persistence/     # SQLite database layer
│   └── SystemIntegration/  # Now Playing, Touch Bar, sleep prevention
├── UI/
│   ├── Components/      # SeekBar, VolumeSlider, ThumbnailPreview, OSD, etc.
│   ├── Player/          # PlayerOverlayView, ControlBar, PlayerUIState
│   ├── Settings/        # Settings views, key binding editor
│   ├── Sidebar/         # Playlist sidebar
│   └── Window/          # AppKit window layer: window controller, content view, input handling
└── deps/                # Bundled mpv headers and dylibs (not compiled)
```

### Single Decoder Architecture

MacPlayer uses `MPVDecoder` as its sole playback backend, powered by libmpv's C API. It handles all format decoding, subtitle rendering, tone mapping, and video filtering.

- **Decoding & Rendering** — `mpv_render_context_render()` draws into a `CAOpenGLLayer` (`MPVVideoLayer`) with vsync
- **Subtitles** — mpv native rendering with `sub-auto=fuzzy` for automatic file matching
- **HDR** — mpv handles all tone mapping (`tone-mapping=auto`, `hdr-compute-peak=auto`)
- **PiP** — Uses Apple's `PIPViewController` (private API), works with any `NSView` including mpv's OpenGL layer

The `PlaybackEngine` is the central coordinator that owns the decoder and all feature managers (playlists, bookmarks, filters, etc.) as `@Observable` sub-managers for direct SwiftUI binding.

### Concurrency

The project uses Swift strict concurrency throughout:

- `@MainActor` on decoders, engine, and UI-bound managers
- `nonisolated(unsafe)` for state accessed from mpv's C callbacks
- `async`/`await` for loading, seeking, and playlist navigation

## Default Keyboard Shortcuts

| Action | Key |
|---|---|
| Play / Pause | `Space` |
| Seek backward / forward | `Left` / `Right` |
| Large seek | `Shift+Left` / `Shift+Right` |
| Volume up / down | `Up` / `Down` |
| Mute | `M` |
| Fullscreen | `F` |
| Frame step backward / forward | `[` / `]` |
| Set A point / B point | `A` / `B` |
| Clear A-B loop | `Ctrl+B` |
| Screenshot | `S` |
| Next / Previous track | `>` / `<` |
| Cycle playback rate | `R` |
| Rotate video | `Cmd+K` |
| Audio delay +/- | `Shift+Plus` / `Shift+Minus` |

All shortcuts are fully customizable in Settings.

## Tech Stack

| Component | Technology |
|---|---|
| Language | Swift 6 (strict concurrency) |
| UI Framework | AppKit (window, input) + SwiftUI (controls) |
| Video Backend | mpv / libmpv |
| GPU Rendering | OpenGL (CAOpenGLLayer via mpv render API) |
| Database | SQLite |
| Build System | XcodeGen |

## License

This project's source code is publicly available. See [LICENSE](../LICENSE) for details.

## Acknowledgments

- [mpv](https://mpv.io/) — the backbone of MacPlayer's playback engine
- [IINA](https://iina.io/) — inspiration for macOS-native media player design
