#!/bin/bash
#
# install.sh — the one command to give people.
#
#     curl -fsSL https://raw.githubusercontent.com/pivable/paintbox/main/install.sh | bash
#
# WHY THIS SHAPE, AND NOT A DOWNLOADED .app OR A DOUBLE-CLICKABLE SCRIPT.
#
# Everything macOS receives through a browser gets a quarantine flag, and
# Paintbox is ad-hoc signed rather than notarised by Apple, so Gatekeeper
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

set -euo pipefail

REPO="${PAINTBOX_REPO:-https://github.com/pivable/paintbox}"
BRANCH="${PAINTBOX_BRANCH:-main}"
DEST="${PAINTBOX_DEST:-/Applications}"

say() { printf '  %s\n' "$*"; }
die() { printf '\n  %s\n\n' "$*" >&2; exit 1; }

printf '\n  Paintbox\n\n'

# ── the two things that make this impossible, checked before anything is downloaded ──

[ "$(uname -s)" = "Darwin" ] || die "Paintbox is a macOS app. This is $(uname -s)."

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
  Either run with a writable destination:  PAINTBOX_DEST=\"\$HOME/Applications\" ...
  or re-run the same command with sudo."

# ── fetch ──

WORK="$(mktemp -d)"
NEW="$DEST/.Paintbox.app.installing.$$"
OLD="$DEST/.Paintbox.app.previous.$$"
# Whatever happens, never leave the user with no Paintbox: if this stops between moving
# the old copy aside and moving the new one in, the old one goes back.
cleanup() {
    rm -rf "$WORK" "$NEW"
    if [ -e "$OLD" ]; then
        if [ -e "$DEST/Paintbox.app" ]; then rm -rf "$OLD"; else mv "$OLD" "$DEST/Paintbox.app"; fi
    fi
}
trap cleanup EXIT
# A plain kill would otherwise skip the EXIT trap. The app's updater runs this in the
# background, where being stopped is an ordinary event.
trap 'exit 130' INT TERM HUP

say "Fetching the source..."
if command -v git >/dev/null 2>&1; then
    git clone --depth 1 --branch "$BRANCH" "$REPO" "$WORK/paintbox" >/dev/null 2>&1 \
        || die "Could not clone $REPO"
else
    # No git: fall back to the tarball, which needs nothing extra.
    curl -fsSL "$REPO/archive/refs/heads/$BRANCH.tar.gz" -o "$WORK/source.tar.gz" \
        || die "Could not download $REPO"
    tar xzf "$WORK/source.tar.gz" -C "$WORK" || die "Could not unpack the download from $REPO"
    mv "$WORK"/paintbox-* "$WORK/paintbox"
    # The tarball has no .git, but GitHub writes the commit into its first header, as a
    # pax "comment=<sha>" record: that is how the app later knows which version it is.
    PAINTBOX_COMMIT="$( (gzip -dc "$WORK/source.tar.gz" | head -c 1024 | tr '\0' '\n' \
        | sed -n 's/^[0-9]* comment=\([0-9a-f]\{40\}\)$/\1/p' | head -1) 2>/dev/null || true)"
    export PAINTBOX_COMMIT
fi

cd "$WORK/paintbox"

# ── build, and refuse to install something that does not pass its own tests ──

say "Building..."
./build.sh >/dev/null 2>&1 || { ./build.sh; die "The build failed; its output is above."; }

say "Checking it works..."
if ! ./Paintbox.app/Contents/MacOS/Paintbox --selftest >"$WORK/selftest.log" 2>&1; then
    cp "$WORK/selftest.log" /tmp/paintbox-selftest.log
    die "The self-test FAILED, so nothing was installed.
  The log is at /tmp/paintbox-selftest.log"
fi
say "$(tail -1 "$WORK/selftest.log")"

# ── install ──
#
# The old copy is never deleted before the new one is in place. The new one is copied
# in beside it under a hidden name and its signature checked; only then is the old one
# moved aside, the new one renamed in, and the old one removed. A failure at any step
# leaves the old copy where it was (see cleanup above).

say "Installing to $DEST..."
ditto Paintbox.app "$NEW" 2>/dev/null || die "Could not write to $DEST.
  Either run with a writable destination:  PAINTBOX_DEST=\"\$HOME/Applications\" ...
  or re-run the same command with sudo."
codesign --verify "$NEW" 2>/dev/null || die "The copy in $DEST did not verify, so nothing was replaced."

if [ -e "$DEST/Paintbox.app" ]; then
    say "Replacing the copy already in $DEST"
    mv "$DEST/Paintbox.app" "$OLD" || die "Could not move the old copy aside, so nothing was replaced."
fi
mv "$NEW" "$DEST/Paintbox.app" || die "Could not move the new copy into place; the old one is kept."
rm -rf "$OLD"

printf '\n  Installed to %s/Paintbox.app\n' "$DEST"
printf '  It opens straight away — an app built on this machine is never quarantined.\n\n'

# The app's own updater sets this: it offers "Relaunch now" itself, and opening the new
# copy here would only bring the old, still-running process to the front.
[ -n "${PAINTBOX_NO_OPEN:-}" ] || open "$DEST/Paintbox.app" 2>/dev/null || true
