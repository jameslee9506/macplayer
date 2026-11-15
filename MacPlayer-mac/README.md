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
- **Watch heatmap** — A graph above the seek bar shows which parts of a video you have played most, built up over every session
- **Bookmarks** — Timestamp bookmarks with optional screenshot thumbnails, persisted in SQLite
- **Video filters** — Real-time brightness, contrast, saturation, sharpen, and deband
- **Picture-in-Picture** — Native macOS PiP via `PIPViewController`
- **Playback history** — SQLite-backed history with per-file settings (position, audio delay, rotation, filters)
- **Recent files** — Start screen and Dock menu shortcuts to recently played files, reopened inside the sandbox through security-scoped bookmarks. The list can be cleared or turned off from the start screen
- **Playlist** — Folder scanning, drag-to-reorder, next/previous navigation
- **System integration** — Now Playing (Control Center), Touch Bar, media keys, sleep prevention
- **Screenshot capture** — Full-frame PNG capture

## Requirements

- macOS 26.0 (Tahoe) or later (the bundled Homebrew libraries require macOS 26)
- Xcode 27+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [Homebrew](https://brew.sh/) (for mpv, FFmpeg, and SQLite)

## Building from Source

### 1. Install dependencies

```bash
cd MacPlayer-mac
brew bundle --file Brewfile
```

### 2. Bundle libraries

The project bundles mpv, FFmpeg, SQLite, and their transitive dependencies. Run the bundling script to copy the installed headers and libraries:

```bash
./scripts/bundle_dylibs.sh
```

The script replaces `MacPlayer/deps/` only after every library has been relocated, ad-hoc signed, and verified. It also generates linker aliases and `deps/manifest.json`, which records exact package versions and library hashes. Xcode copies the libraries into `Contents/Frameworks/MacPlayerDependencies/`, removes stale files from that directory, and saves the manifest as `Contents/Resources/DependencyManifest.json`.

SQLite is imported as `MacPlayerSQLite` using the bundled headers and library, independently of the SQLite version shipped with macOS.

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

### Updating dependencies

```bash
brew update
brew bundle --file Brewfile
./scripts/bundle_dylibs.sh
./scripts/bundle_dylibs.sh --verify
xcodegen generate
xcodebuild -project MacPlayer.xcodeproj -scheme MacPlayer -configuration Debug clean build
```

Use a clean build after updating dependencies to remove files from older bundle layouts; upgrading Homebrew alone does not update an existing app bundle. The November 2026 update uses mpv 0.42.0, FFmpeg 9.0.2, libplacebo 7.387.0, libass 0.17.5, OpenSSL 4.1.0, SQLite 3.54.1, and XcodeGen 2.46.0. See the generated manifest for the complete installed versions.

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
│   ├── Stats/           # Watch tracking and the watch heatmap
│   ├── Subtitle/        # Subtitle configuration (mpv native rendering)
│   └── Thumbnail/       # Pre-generation and on-demand thumbnail generation
├── Infrastructure/
│   ├── KeyBinding/      # Customizable keyboard shortcut system
│   ├── Persistence/     # SQLite database layer
│   └── SystemIntegration/  # Now Playing, Touch Bar, sleep prevention
├── UI/
│   ├── Components/      # SeekBar, VolumeSlider, ThumbnailPreview, OSD, etc.
│   ├── Player/          # PlayerOverlayView, StartView, ControlBar, PlayerUIState
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
