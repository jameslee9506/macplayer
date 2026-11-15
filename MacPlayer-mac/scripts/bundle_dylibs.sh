#!/bin/zsh
# Bundle libmpv and all its non-system dylib dependencies into MacPlayer/deps/lib/
# Rewrites install names to use @rpath for app embedding.

set -euo pipefail

BREW_PREFIX="$(brew --prefix)"
MPV_PREFIX="$(brew --prefix mpv)"
FFMPEG_PREFIX="$(brew --prefix ffmpeg)"
APP_DIR="$(cd "$(dirname "$0")/../MacPlayer" && pwd)"
DEST_DIR="$APP_DIR/deps/lib"
INCLUDE_DIR="$APP_DIR/deps/include"
mkdir -p "$DEST_DIR" "$INCLUDE_DIR"

# Headers and libraries are generated locally and are not committed.
cp -R "$MPV_PREFIX/include/mpv" "$INCLUDE_DIR/"
for component in libavformat libavcodec libswscale libavutil; do
    cp -R "$FFMPEG_PREFIX/include/$component" "$INCLUDE_DIR/"
done

# Clean destination
rm -f "$DEST_DIR"/*.dylib 2>/dev/null || true

# Use a temp file to track seen libraries
SEEN_FILE=$(mktemp)
trap "rm -f $SEEN_FILE" EXIT

collect_deps() {
    local lib="$1"
    local real_lib
    real_lib="$(realpath "$lib" 2>/dev/null || echo "$lib")"

    # Skip if already seen
    grep -qxF "$real_lib" "$SEEN_FILE" 2>/dev/null && return
    echo "$real_lib" >> "$SEEN_FILE"

    # Only process Homebrew libraries (skip system frameworks and /usr/lib)
    if [[ "$real_lib" != "$BREW_PREFIX"* ]]; then
        return
    fi

    echo "Processing: $real_lib"

    # Copy to dest
    local bname
    bname="$(basename "$real_lib")"
    cp -f "$real_lib" "$DEST_DIR/$bname"
    chmod 755 "$DEST_DIR/$bname"

    # Recurse into dependencies
    otool -L "$real_lib" | tail -n +2 | awk '{print $1}' | while read -r dep; do
        if [[ "$dep" == "$BREW_PREFIX"* ]]; then
            collect_deps "$dep"
        fi
    done
}

collect_deps "$MPV_PREFIX/lib/libmpv.dylib"
for component in libavformat libavcodec libswscale libavutil; do
    collect_deps "$FFMPEG_PREFIX/lib/$component.dylib"
done

echo ""
echo "Collected $(ls "$DEST_DIR"/*.dylib 2>/dev/null | wc -l | tr -d ' ') dylibs"

# Now rewrite install names
echo ""
echo "Rewriting install names..."

for dylib in "$DEST_DIR"/*.dylib; do
    bname="$(basename "$dylib")"

    # Change the library's own install name to @rpath
    install_name_tool -id "@rpath/$bname" "$dylib" 2>/dev/null || true

    # Rewrite all Homebrew dependencies to @rpath
    otool -L "$dylib" | tail -n +2 | awk '{print $1}' | while read -r dep; do
        if [[ "$dep" == "$BREW_PREFIX"* ]]; then
            dep_basename="$(basename "$dep")"
            # Resolve to real filename
            if [[ -f "$DEST_DIR/$dep_basename" ]]; then
                install_name_tool -change "$dep" "@rpath/$dep_basename" "$dylib" 2>/dev/null || true
            else
                real_dep="$(realpath "$dep" 2>/dev/null || echo "$dep")"
                real_basename="$(basename "$real_dep")"
                if [[ -f "$DEST_DIR/$real_basename" ]]; then
                    install_name_tool -change "$dep" "@rpath/$real_basename" "$dylib" 2>/dev/null || true
                fi
            fi
        fi
    done
done

echo ""
echo "Verifying libmpv..."
otool -L "$DEST_DIR/libmpv.2.dylib" | head -10

echo ""
echo "Done! Bundled dylibs in $DEST_DIR"
