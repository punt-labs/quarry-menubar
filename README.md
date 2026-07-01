# quarry-menubar

[![License](https://img.shields.io/github/license/punt-labs/quarry-menubar)](LICENSE)
[![CI](https://img.shields.io/github/actions/workflow/status/punt-labs/quarry-menubar/ci.yml?label=CI)](https://github.com/punt-labs/quarry-menubar/actions/workflows/ci.yml)
[![Platform](https://img.shields.io/badge/platform-macOS_14+-black)](https://developer.apple.com/macos/)
[![Swift](https://img.shields.io/badge/swift-5.9-F05138)](https://www.swift.org)

macOS menu bar app for [Quarry](https://github.com/punt-labs/quarry) document search. Search your indexed documents from anywhere with a keyboard shortcut.

## What It Does

Quarry Menu Bar sits in your menu bar and gives you instant access to your Quarry knowledge base. Click the icon to search across all your indexed documents without switching apps.

- **Semantic search** across all indexed documents
- **Connection-aware UI** for local or remote Quarry
- **Syntax-highlighted results** for code, Markdown, and prose
- **Detail view** with full page context for each result

The app does **not** manage Quarry itself. It follows Quarry's current connection model:

- Use the remote profile in `~/.punt-labs/mcp-proxy/quarry.toml` when present
- Otherwise connect to local Quarry at `https://127.0.0.1:8420` with the pinned CA in `~/.punt-labs/quarry/tls/ca.crt`

## Install via Homebrew

### Recommended: one command

`install.sh` runs the full flow — tap, trust, install/upgrade, and the required
`~/Applications` symlink — and is idempotent, so re-running it upgrades in
place. Because the app is unsigned and non-notarized, fetch and review the
script before running it rather than piping it blindly into a shell:

```bash
# Fetch, review, then run
curl -fsSL https://raw.githubusercontent.com/punt-labs/quarry-menubar/main/install.sh -o install.sh
less install.sh          # review before running
sh install.sh
```

Or clone the repo and run it from there:

```bash
git clone https://github.com/punt-labs/quarry-menubar.git
cd quarry-menubar && ./install.sh
```

### Manual: four steps

1. **Add the tap.**

   ```bash
   brew tap punt-labs/homebrew-tap
   ```

2. **Trust the tap.** Homebrew refuses to load formulae from an untrusted
   third-party tap (`Refusing to load formula ... from untrusted tap`). Trust
   is a one-time, per-tap action.

   ```bash
   brew trust punt-labs/homebrew-tap
   ```

3. **Install (and, later, upgrade).**

   ```bash
   brew install punt-labs/homebrew-tap/quarry-menubar
   ```

4. **Symlink into `~/Applications` (required).** The formula installs the app
   into the Homebrew prefix but cannot create this symlink itself — Homebrew's
   install sandbox forbids writes to `$HOME`, so without this step the app
   never appears in Spotlight or Launchpad.

   ```bash
   mkdir -p ~/Applications && ln -sfn "$(brew --prefix quarry-menubar)/QuarryMenuBar.app" ~/Applications/QuarryMenuBar.app
   ```

### Notes

This installs a prebuilt, universal (Apple Silicon + Intel) `QuarryMenuBar.app`
from the latest GitHub Release. It is a **formula, not a cask**, so Homebrew
does not quarantine the download: the app is ad-hoc signed but **not
notarized**, and it still launches with no Gatekeeper prompt and no Developer
ID certificate. No Xcode or build tools are required.

It is a menu-bar-only app — no Dock icon; look for the icon in the menu bar.
Launch it with `open -a QuarryMenuBar`, Spotlight, or a double-click in
`~/Applications` (not by running the `.app` bundle path directly). It follows
your active Quarry connection (remote profile in
`~/.punt-labs/mcp-proxy/quarry.toml` if present, otherwise local Quarry at
`https://127.0.0.1:8420`).

## Requirements

- macOS 14 (Sonoma) or later
- [quarry](https://github.com/punt-labs/quarry) installed and configured

```bash
pip install quarry-mcp
quarry install
quarry ingest ~/Documents/my-notes.md
```

For remote Quarry:

```bash
quarry login <host> --api-key <token>
# or set QUARRY_API_KEY before running: quarry login <host>
```

## Development

### Setup

```bash
brew install xcodegen swiftformat swiftlint
make generate   # Create .xcodeproj from project.yml
```

### Build and Run

```bash
make run        # Build and launch the menu bar app
make test       # Run unit tests
make all        # Format, lint, build, and test
```

### Quality Gates

Must pass before every commit:

```bash
make format && make lint && make test
```

### Project Structure

```text
QuarryMenuBar/
  App/                  # App entry point, lifecycle
  Models/               # Codable JSON models for API responses
  Services/             # ConnectionManager, ConnectionProfileLoader, QuarryClient, HotkeyManager
  Utilities/            # SyntaxHighlighter
  ViewModels/           # SearchViewModel (debounced search)
  Views/                # SwiftUI views (ContentPanel, SearchPanel, ResultDetail, ...)
QuarryMenuBarTests/     # Unit tests (mirrors source structure)
project.yml             # XcodeGen project definition
Makefile                # Build, test, format, lint, version targets
```

The Xcode project is generated from `project.yml` and gitignored. New `.swift` files placed in the source directories are auto-discovered on `make generate`.

## Architecture

The app is a Quarry client. It resolves the active connection, talks to Quarry over HTTP(S), and adapts the UI to local vs remote capabilities.

```text
QuarryMenuBarApp
  -> ConnectionProfileLoader (reads quarry.toml or falls back to local TLS)
  -> ConnectionManager (resolves profile, probes health/status/databases)
  -> QuarryClient (HTTP(S) + Bearer auth + pinned CA)
  -> SearchViewModel (debounced search via QuarryClient)
  -> ContentPanel (routes UI by connection state)
```

Dependencies:

- `HighlightSwift` for syntax highlighting themes
- Pure SwiftUI + `@Observable` for app state and UI composition

## Roadmap

- [ ] Register folders for sync directly from menu bar
- [ ] Trigger sync from menu bar
- [ ] Ingest files via drag-and-drop
- [ ] Global keyboard shortcut configuration
- [ ] Status indicator for sync/ingest progress
