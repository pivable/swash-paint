#!/bin/bash
#
# Builds Paintbox.app. This is the only command you need.
#
# There is no Xcode on this machine, only the Command Line Tools, so there is no
# .xcodeproj and no xcodebuild: swiftc compiles the sources straight into the
# bundle's executable, the Info.plist is written by hand, and the bundle is
# ad-hoc signed with codesign.

set -euo pipefail
cd "$(dirname "$0")"

APP="Paintbox.app"
BIN="$APP/Contents/MacOS/Paintbox"
SDK="$(xcrun --show-sdk-path)"

# --universal builds for Intel as well as Apple Silicon. Off by default because
# it doubles the compile and this Mac is arm64; turn it on for anything you hand
# to somebody else, since an arm64-only app does not launch AT ALL on an Intel
# Mac and the failure gives the user nothing to go on.
#
# --package produces Paintbox.zip and prints the one command a recipient runs to
# make the app openable. See the note that command prints for why it is needed.
UNIVERSAL=0
PACKAGE=0
for arg in "$@"; do
    case "$arg" in
        --universal) UNIVERSAL=1 ;;
        --package)   PACKAGE=1 ;;
        -h|--help)   echo "usage: ./build.sh [--universal] [--package]"; exit 0 ;;
        *)           echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

echo "==> Cleaning"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

compile_one() {                     # $1 = target triple, $2 = output path
    swiftc \
        -O \
        -swift-version 5 \
        -target "$1" \
        -sdk "$SDK" \
        -framework AppKit \
        -framework Vision \
        -framework CoreImage \
        -framework UniformTypeIdentifiers \
        -o "$2" \
        Sources/*.swift
}

if [ "$UNIVERSAL" -eq 1 ]; then
    echo "==> Compiling for Apple Silicon and Intel (swiftc, SDK $(xcrun --show-sdk-version))"
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    compile_one "arm64-apple-macos14.0"  "$TMP/arm64"
    compile_one "x86_64-apple-macos14.0" "$TMP/x86_64"
    # lipo glues the two Mach-O files into one binary the loader picks from.
    lipo -create "$TMP/arm64" "$TMP/x86_64" -output "$BIN"
    echo "    architectures: $(lipo -archs "$BIN")"
else
    echo "==> Compiling (swiftc, SDK $(xcrun --show-sdk-version))"
    compile_one "arm64-apple-macos14.0" "$BIN"
fi

# The icon is drawn by the binary just built — see Sources/AppIcon.swift — and packed
# by iconutil, which ships with macOS. No Xcode, no asset catalog, nothing to download,
# so it runs exactly the same inside install.sh on the user's machine. A universal
# binary runs here too: the loader picks this Mac's half.
echo "==> Drawing the app icon"
ICONSET="$(mktemp -d)/Paintbox.iconset"
"$BIN" --iconset "$ICONSET" | sed 's/^/    /'
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Paintbox.icns"
rm -rf "$(dirname "$ICONSET")"

echo "==> Writing Info.plist"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Paintbox</string>
    <key>CFBundleIconFile</key>
    <string>Paintbox</string>
    <key>CFBundleIdentifier</key>
    <string>com.pivable.paintbox</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Paintbox</string>
    <key>CFBundleDisplayName</key>
    <string>Paintbox</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSHumanReadableCopyright</key>
    <string>Paintbox</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Image</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.png</string>
                <string>public.jpeg</string>
                <string>public.tiff</string>
                <string>public.heic</string>
                <string>public.avif</string>
                <string>com.compuserve.gif</string>
                <string>com.microsoft.bmp</string>
                <string>org.webmproject.webp</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Which source this was built from, for About and for Check for Updates. Every push to
# main is a release and nothing bumps a version number, so the commit is the version.
# install.sh passes PAINTBOX_COMMIT when it fetched a tarball, which has no .git; a
# clone answers for itself. git is asked only when this folder IS the top of a work
# tree, so a tarball unpacked inside somebody else's repository does not borrow its
# commit. Anything that is not forty hex digits is left out, and the app then says it
# cannot tell, rather than claiming to be up to date.
COMMIT="${PAINTBOX_COMMIT:-}"
COMMIT_DATE=""
if [ "$(git rev-parse --show-toplevel 2>/dev/null)" = "$(pwd -P)" ]; then
    [ -n "$COMMIT" ] || COMMIT="$(git rev-parse HEAD 2>/dev/null || true)"
    COMMIT_DATE="$(git log -1 --format=%cI "$COMMIT" 2>/dev/null || true)"
fi
if [[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
    plutil -insert PaintboxCommit -string "$COMMIT" "$APP/Contents/Info.plist"
    [ -z "$COMMIT_DATE" ] || plutil -insert PaintboxCommitDate -string "$COMMIT_DATE" "$APP/Contents/Info.plist"
    echo "    commit $COMMIT"
else
    echo "    commit unknown: no git work tree here and no PAINTBOX_COMMIT"
fi
plutil -insert PaintboxBuildDate -string "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$APP/Contents/Info.plist"

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Ad-hoc signing"
codesign --force --sign - --timestamp=none "$APP"
codesign -dv "$APP" 2>&1 | sed 's/^/    /'

echo "==> Built $(pwd)/$APP"

if [ "$PACKAGE" -eq 1 ]; then
    echo "==> Packaging"
    rm -f Paintbox.zip
    # ditto, not zip: it preserves the bundle's extended attributes and its
    # signature. A plain `zip` can break the signature and the app then refuses
    # to launch with an error that blames the wrong thing.
    ditto -c -k --keepParent "$APP" Paintbox.zip
    echo "    $(pwd)/Paintbox.zip  ($(du -h Paintbox.zip | cut -f1))"
    cat <<'NOTE'

    HAND THE RECIPIENT THIS, VERBATIM:

      1. Unzip Paintbox.zip.
      2. Open Terminal and run, with the path to where you put it:

           xattr -dr com.apple.quarantine /Applications/Paintbox.app

      3. Open the app normally.

    WHY STEP 2 EXISTS. Downloading anything attaches a quarantine flag, and this
    app is ad-hoc signed rather than notarised by Apple, so macOS refuses it. The
    old right-click-to-open shortcut was removed in macOS Sequoia, which leaves
    System Settings > Privacy & Security > Open Anyway, or the command above.

    THE WAY TO REMOVE STEP 2 is to join the Apple Developer Program (99 USD a
    year), sign with a Developer ID and notarise. Nothing in the code changes.
    Anyone who BUILDS it themselves never sees this: a locally built app carries
    no quarantine flag at all.
NOTE
fi
