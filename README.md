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
- Otherwise connect to local Quarry at `https://localhost:8420` with the pinned CA in `~/.punt-labs/quarry/tls/ca.crt`

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
