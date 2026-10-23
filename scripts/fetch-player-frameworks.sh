#!/bin/sh
# Downloads the in-app player's prebuilt frameworks (KSPlayer + FFmpegKit, Apple TV slices only)
# into Vendor/PlayerFrameworks. Device builds link them; simulator builds use the AVPlayer stub.
# Fetches only these files, not the repos' multi-gigabyte history.
set -eu

KSPLAYER_REVISION=7d6b4ced6f6b0d3b54cde84c77314a3fa6d927b0
# FFmpegKit 9.0.2, pinned to its commit because a tag can move.
FFMPEGKIT_TAG=9.0.2
FFMPEGKIT_REVISION=20e3ba2a4c36978fed7b12a56839fadd92e901ea
# The dynamic frameworks KSPlayer loads. FFmpegKit's static ones are already linked into these.
FFMPEG_FRAMEWORKS="Libavcodec Libavdevice Libavfilter Libavformat Libavutil Libswresample Libswscale
libfribidi libplacebo libzvbi"

root=$(cd "$(dirname "$0")/.." && pwd)
dest="$root/Vendor/PlayerFrameworks"
work=$(mktemp -d)
staged="$dest.partial"
previous="$dest.previous"
trap 'rm -rf "$work" "$staged"' EXIT

# fetch <repo url> <ref> <dir> <sparse pattern>...
fetch() {
    url=$1 ref=$2 dir=$3
    shift 3
    git init -q "$dir"
    git -C "$dir" remote add origin "$url"
    git -C "$dir" sparse-checkout set --no-cone "$@"
    git -C "$dir" fetch -q --depth 1 --filter=blob:none origin "$ref"
    git -C "$dir" checkout -q FETCH_HEAD
}

fetch https://github.com/kingslay/KSPlayer "$KSPLAYER_REVISION" "$work/KSPlayer" \
    "/Sources/KSPlayer.xcframework/tvos-arm64/"

patterns=""
for name in $FFMPEG_FRAMEWORKS; do
    patterns="$patterns /Sources/$name.xcframework/tvos-arm64/"
done
# shellcheck disable=SC2086
fetch https://github.com/kingslay/FFmpegKit "$FFMPEGKIT_REVISION" "$work/FFmpegKit" $patterns

# Assembled beside the destination, on the same disk, so the swap is two renames, not a copy. A failed
# run leaves the installed set untouched. VERSION is written last; the build's embed step requires it.
rm -rf "$staged" "$previous"
mkdir -p "$staged"
cp -R "$work/KSPlayer/Sources/KSPlayer.xcframework/tvos-arm64/KSPlayer.framework" "$staged/"
for name in $FFMPEG_FRAMEWORKS; do
    cp -R "$work/FFmpegKit/Sources/$name.xcframework/tvos-arm64/$name.framework" "$staged/"
done
echo "$KSPLAYER_REVISION $FFMPEGKIT_TAG" > "$staged/VERSION"
if [ -d "$dest" ]; then mv "$dest" "$previous"; fi
if ! mv "$staged" "$dest"; then
    if [ -d "$previous" ]; then mv "$previous" "$dest"; fi
    exit 1
fi
rm -rf "$previous"
echo "Player frameworks ready in Vendor/PlayerFrameworks."
