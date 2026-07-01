#!/bin/sh
# Install quarry-menubar — macOS menu bar app for Quarry document search.
# Usage: fetch, review, then run (the app is unsigned/non-notarized — do not
# pipe this straight into a shell):
#   curl -fsSL https://raw.githubusercontent.com/punt-labs/quarry-menubar/main/install.sh -o install.sh
#   less install.sh
#   bash install.sh
set -eu

# --- Colors (disabled when not a terminal) ---
if [ -t 1 ]; then
  BOLD='\033[1m' GREEN='\033[32m' YELLOW='\033[33m' RED='\033[31m' NC='\033[0m'
else
  BOLD='' GREEN='' YELLOW='' RED='' NC=''
fi

info() { printf '%b▶%b %s\n' "$BOLD" "$NC" "$1"; }
ok()   { printf '  %b✓%b %s\n' "$GREEN" "$NC" "$1"; }
warn() { printf '  %b!%b %s\n' "$YELLOW" "$NC" "$1"; }
fail() { printf '  %b✗%b %s\n' "$RED" "$NC" "$1"; exit 1; }

TAP="punt-labs/homebrew-tap"
TAP_SHORT="punt-labs/tap"
FORMULA="punt-labs/homebrew-tap/quarry-menubar"
BINARY="quarry-menubar"
APP="QuarryMenuBar.app"

# --- Step 1: Prerequisites ---

info "Checking prerequisites..."

if [ "$(uname -s)" = "Darwin" ]; then
  ok "macOS detected"
else
  fail "quarry-menubar is a macOS app — this installer only runs on macOS."
fi

if command -v brew >/dev/null 2>&1; then
  ok "Homebrew found"
else
  fail "'brew' not found. Install Homebrew first: https://brew.sh"
fi

# --- Step 2: Add tap ---
# Idempotent: `brew tap` on an already-tapped repo is a clean no-op.

info "Adding Homebrew tap..."

taps="$(brew tap)" || fail "Could not list Homebrew taps"
if printf '%s\n' "$taps" | grep -qx "$TAP_SHORT"; then
  ok "tap already added ($TAP_SHORT)"
else
  brew tap "$TAP" || fail "Failed to add tap $TAP"
  ok "tap added ($TAP_SHORT)"
fi

# --- Step 3: Trust tap ---
# Homebrew refuses to load formulae from an untrusted third-party tap when
# HOMEBREW_REQUIRE_TAP_TRUST is set. `brew trust` on an already-trusted tap
# prints "Already trusted tap" and exits 0, so this is idempotent.

info "Trusting tap..."

brew trust "$TAP_SHORT" || fail "Failed to trust tap $TAP_SHORT"
ok "tap trusted"

# --- Step 4: Install or upgrade ---
# `brew upgrade` on an up-to-date formula prints a warning and exits 0, so a
# re-run is a clean no-op.

if brew list "$BINARY" >/dev/null 2>&1; then
  info "Upgrading $BINARY..."
  brew upgrade "$BINARY" || fail "Failed to upgrade $BINARY"
  ok "$BINARY is up to date"
else
  info "Installing $BINARY..."
  brew install "$FORMULA" || fail "Failed to install $FORMULA"
  ok "$BINARY installed"
fi

# --- Step 5: Link into ~/Applications ---
# The Homebrew formula cannot create this symlink itself: Homebrew's install
# sandbox forbids writes to $HOME, and auto-linking into /Applications is a
# cask-only feature. quarry-menubar ships as a formula (not a cask) to avoid
# notarization, so the symlink is a required post-install step. `ln -sfn`
# makes it idempotent — an existing link is replaced in place.
#
# NON-FATAL: by this point the app is installed and launchable via
# `open -a QuarryMenuBar`, so a symlink failure is a warning with recovery
# guidance, not a fatal error. The whole compound is the `if` condition so
# `set -e` does not abort on a prefix/mkdir/ln failure; any of them routes to
# the same warning and the script still exits 0.

info "Linking $APP into ~/Applications..."

if PREFIX="$(brew --prefix "$BINARY")" && mkdir -p "$HOME/Applications" && ln -sfn "$PREFIX/$APP" "$HOME/Applications/$APP"; then
  ok "$HOME/Applications/$APP -> $PREFIX/$APP"
else
  warn "Could not link $APP into ~/Applications."
  warn "$BINARY is installed and works now: open -a QuarryMenuBar"
  warn "Without the link it will not appear in Spotlight or Launchpad. To add it, run:"
  # Literal recovery command for the user to copy — the $(...) must not expand here.
  # shellcheck disable=SC2016
  warn '  ln -sfn "$(brew --prefix quarry-menubar)/QuarryMenuBar.app" ~/Applications/QuarryMenuBar.app'
fi

# --- Done ---

printf '\n%b%b%s is ready!%b\n\n' "$GREEN" "$BOLD" "$BINARY" "$NC"
printf '%s is a menu-bar-only accessory — no Dock icon.\n' "$APP"
printf 'Look for its icon in the macOS menu bar (top-right of the screen).\n\n'
printf 'Launch it:\n'
printf '  open -a QuarryMenuBar\n'
printf '  (or use Spotlight, or double-click %s in ~/Applications —\n' "$APP"
printf '   do not run the .app bundle path directly)\n\n'
printf 'It follows your active Quarry connection: the remote profile in\n'
printf '%s/.punt-labs/mcp-proxy/quarry.toml when present, otherwise local\n' "$HOME"
printf 'Quarry at https://127.0.0.1:8420.\n\n'
