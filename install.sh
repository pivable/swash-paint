#!/bin/bash
#
# install.sh — the one command to give people.
#
#     curl -fsSL https://raw.githubusercontent.com/pivable/swash-paint/main/install.sh | bash
#
# WHY THIS SHAPE, AND NOT A DOWNLOADED .app OR A DOUBLE-CLICKABLE SCRIPT.
#
# Everything macOS receives through a browser gets a quarantine flag, and
# Swash Paint is ad-hoc signed rather than notarised by Apple, so Gatekeeper
# refuses it. Since macOS Sequoia the old right-click-to-open shortcut is gone,
# leaving System Settings > Privacy & Security > Open Anyway. That wall applies
# to a downloaded .app, to a downloaded .dmg, and — people are surprised by this
# — to a downloaded .command script too. A script is not a loophole.
#
# What DOES sidestep it, completely and legitimately: building on the machine
# that will run it. A locally built app is never quarantined, because it was
# never downloaded. So this script fetches the SOURCE, builds it here, runs the
# test suite, and only then installs. No warning, no Settings, no 99 dollars.
#
# The honest cost is that it needs Apple's command line tools, which is a free
# but multi-gigabyte download if they are absent. For someone who will not do
# that, the answer is notarisation, not a cleverer script.
#
# The app was called Paintbox until 2 Nov 2026. The bundle is now "Swash Paint.app" — with
# a space, so every path here is quoted — and an old Paintbox.app in the same folder is
# removed once the new one is in (retire_old, below).

set -euo pipefail

REPO="${SWASHPAINT_REPO:-https://github.com/pivable/swash-paint}"
BRANCH="${SWASHPAINT_BRANCH:-main}"
DEST="${SWASHPAINT_DEST:-/Applications}"
APP="Swash Paint.app"

say() { printf '  %s\n' "$*"; }
die() { printf '\n  %s\n\n' "$*" >&2; exit 1; }

# The old installer put Paintbox.app here. Removed only when its bundle ID says it is
# ours: a folder of that name could be somebody else's app, and this runs as whoever ran
# the command, possibly root. Never fatal; an old copy left behind is untidy, not broken.
retire_old() {
    local old="$1/Paintbox.app" id
    [ -d "$old" ] || return 0
    id="$(plutil -extract CFBundleIdentifier raw -o - "$old/Contents/Info.plist" 2>/dev/null || true)"
    if [ "$id" = "com.pivable.paintbox" ]; then
        if rm -rf "$old" 2>/dev/null && [ ! -e "$old" ]; then
            say "Removed the old Paintbox.app from $1; Swash Paint replaces it"
        else
            say "The old Paintbox.app in $1 could not be removed; drag it to the Bin"
        fi
    else
        say "Left $old alone: it is not ours (bundle ID ${id:-unreadable})"
    fi
}

# The self-test's hook: run only the step above against a scratch folder, and stop. It
# is checked before anything else so a test never reaches the network or a compiler.
if [ -n "${SWASHPAINT_RETIRE_ONLY:-}" ]; then
    retire_old "$SWASHPAINT_RETIRE_ONLY"
    exit 0
fi

printf '\n  Swash Paint\n\n'

# ── the two things that make this impossible, checked before anything is downloaded ──

[ "$(uname -s)" = "Darwin" ] || die "Swash Paint is a macOS app. This is $(uname -s)."

major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 14 ] || die "Needs macOS 14 or newer; this is $(sw_vers -productVersion).
  Remove Background uses a Vision capability that arrived in 14."

# `xcode-select -p`, not `command -v swiftc`: /usr/bin/swiftc exists on every Mac, as a
# stub that puts up Apple's install dialog, so asking for it always said yes.
if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find swiftc >/dev/null 2>&1; then
    die "Apple's command line tools are missing, so there is no Swift compiler.

  Run this, let it finish, then run the install command again:

      xcode-select --install

  Xcode itself is NOT needed — this project has no Xcode project."
fi

say "macOS $(sw_vers -productVersion), $(swiftc --version 2>/dev/null | head -1)"

# Checked before a minute of building, not after it.
mkdir -p "$DEST" 2>/dev/null || true
[ -d "$DEST" ] && [ -w "$DEST" ] || die "Could not write to $DEST.
  Either run with a writable destination:  SWASHPAINT_DEST=\"\$HOME/Applications\" ...
  or re-run the same command with sudo."

# ── fetch ──

WORK="$(mktemp -d)"
NEW="$DEST/.$APP.installing.$$"
OLD="$DEST/.$APP.previous.$$"
# Whatever happens, never leave the user with no Swash Paint: if this stops between moving
# the old copy aside and moving the new one in, the old one goes back.
cleanup() {
    rm -rf "$WORK" "$NEW"
    if [ -e "$OLD" ]; then
        if [ -e "$DEST/$APP" ]; then rm -rf "$OLD"; else mv "$OLD" "$DEST/$APP"; fi
    fi
}
trap cleanup EXIT
# A plain kill would otherwise skip the EXIT trap. The app's updater runs this in the
# background, where being stopped is an ordinary event.
trap 'exit 130' INT TERM HUP

say "Fetching the source..."
if command -v git >/dev/null 2>&1; then
    git clone --depth 1 --branch "$BRANCH" "$REPO" "$WORK/swash-paint" >/dev/null 2>&1 \
        || die "Could not clone $REPO"
else
    # No git: fall back to the tarball, which needs nothing extra.
    curl -fsSL "$REPO/archive/refs/heads/$BRANCH.tar.gz" -o "$WORK/source.tar.gz" \
        || die "Could not download $REPO"
    tar xzf "$WORK/source.tar.gz" -C "$WORK" || die "Could not unpack the download from $REPO"
    # GitHub names the one top folder <repo>-<sha>, swash-paint-<sha> now. Taken as
    # whatever single folder came out, so the name is not a second thing to keep in step.
    set -- "$WORK"/*/
    [ $# -eq 1 ] && [ -d "$1" ] || die "The download from $REPO did not unpack into one folder"
    mv "${1%/}" "$WORK/swash-paint"
    # The tarball has no .git, but GitHub writes the commit into its first header, as a
    # pax "comment=<sha>" record: that is how the app later knows which version it is.
    SWASHPAINT_COMMIT="$( (gzip -dc "$WORK/source.tar.gz" | head -c 1024 | tr '\0' '\n' \
        | sed -n 's/^[0-9]* comment=\([0-9a-f]\{40\}\)$/\1/p' | head -1) 2>/dev/null || true)"
    export SWASHPAINT_COMMIT
fi

cd "$WORK/swash-paint"

# ── build, and refuse to install something that does not pass its own tests ──

say "Building..."
./build.sh >/dev/null 2>&1 || { ./build.sh; die "The build failed; its output is above."; }

say "Checking it works..."
if ! "./$APP/Contents/MacOS/SwashPaint" --selftest >"$WORK/selftest.log" 2>&1; then
    cp "$WORK/selftest.log" /tmp/swashpaint-selftest.log
    die "The self-test FAILED, so nothing was installed.
  The log is at /tmp/swashpaint-selftest.log"
fi
say "$(tail -1 "$WORK/selftest.log")"

# ── install ──
#
# The old copy is never deleted before the new one is in place. The new one is copied
# in beside it under a hidden name and its signature checked; only then is the old one
# moved aside, the new one renamed in, and the old one removed. A failure at any step
# leaves the old copy where it was (see cleanup above).

say "Installing to $DEST..."
ditto "$APP" "$NEW" 2>/dev/null || die "Could not write to $DEST.
  Either run with a writable destination:  SWASHPAINT_DEST=\"\$HOME/Applications\" ...
  or re-run the same command with sudo."
codesign --verify "$NEW" 2>/dev/null || die "The copy in $DEST did not verify, so nothing was replaced."

if [ -e "$DEST/$APP" ]; then
    say "Replacing the copy already in $DEST"
    mv "$DEST/$APP" "$OLD" || die "Could not move the old copy aside, so nothing was replaced."
fi
mv "$NEW" "$DEST/$APP" || die "Could not move the new copy into place; the old one is kept."
rm -rf "$OLD"
retire_old "$DEST"

printf '\n  Installed to %s/%s\n' "$DEST" "$APP"
printf '  It opens straight away — an app built on this machine is never quarantined.\n\n'

# The app's own updater sets this: it offers "Relaunch now" itself, and opening the new
# copy here would only bring the old, still-running process to the front.
[ -n "${SWASHPAINT_NO_OPEN:-}" ] || open "$DEST/$APP" 2>/dev/null || true
