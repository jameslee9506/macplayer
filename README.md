# MacPlayer

A native macOS media player built with Swift and SwiftUI, powered by mpv/libmpv.

MacPlayer supports a wide range of video and audio formats, subtitles, HDR tone mapping, Picture-in-Picture, playlists, bookmarks, playback history, customizable shortcuts, and screenshot capture.

## Build the macOS app

Requires macOS 15 or later, Xcode 16 or later, and Homebrew.

```sh
git clone https://github.com/jameslee9506/macplayer.git
cd macplayer
brew install xcodegen mpv ffmpeg
cd MacPlayer-mac
./scripts/bundle_dylibs.sh
xcodegen generate
open MacPlayer.xcodeproj
```

Select the **MacPlayer** scheme in Xcode and run it. The bundling script prepares the required headers and libraries locally. See the [app README](MacPlayer-mac/README.md) for architecture and keyboard shortcuts.

## Website

The `web/` directory contains the React Router website.

```sh
cd web
npm ci
npm run dev
```

Run `npm run typecheck` and `npm run build` to validate the website. Downloads link to [GitHub releases](https://github.com/jameslee9506/macplayer/releases); build from source until a MacPlayer binary is published. Configure your own site domain and explicit `CLOUDFLARE_ACCOUNT_ID` before deploying.

## License

See [LICENSE](LICENSE). MacPlayer uses [mpv](https://mpv.io/) and [FFmpeg](https://ffmpeg.org/), and takes inspiration from [IINA](https://iina.io/).
