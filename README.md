# quarry-menubar

macOS menu bar app for [Quarry](https://github.com/punt-labs/quarry) document search. Search your indexed documents from anywhere with a keyboard shortcut.

## What It Does

Quarry Menu Bar sits in your menu bar and gives you instant access to your Quarry knowledge base. Click the icon (or press the hotkey) to search across all your indexed documents without switching apps.

- **Semantic search** across all indexed documents
- **Database switching** between named databases
- **Syntax-highlighted results** for code, Markdown, and prose
- **Detail view** with full page context for each result

The app manages its own `quarry serve` process — no manual server setup needed.

## Requirements

- macOS 14 (Sonoma) or later
- [quarry-mcp](https://github.com/punt-labs/quarry) installed with at least one indexed database

```bash
pip install quarry-mcp
quarry install
quarry ingest ~/Documents/my-notes.md
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

```
QuarryMenuBar/
  App/                  # App entry point, lifecycle
  Models/               # Codable JSON models for API responses
  Services/             # DaemonManager, DatabaseManager, QuarryClient, HotkeyManager
  Utilities/            # SyntaxHighlighter
  ViewModels/           # SearchViewModel (debounced search)
  Views/                # SwiftUI views (ContentPanel, SearchPanel, ResultDetail, ...)
QuarryMenuBarTests/     # Unit tests (mirrors source structure)
project.yml             # XcodeGen project definition
Makefile                # Build, test, format, lint, version targets
```

The Xcode project is generated from `project.yml` and gitignored. New `.swift` files placed in the source directories are auto-discovered on `make generate`.

## Architecture

The app spawns `quarry serve --db <name>` as a subprocess and communicates over localhost HTTP. Port discovery works through a file at `~/.quarry/data/<db>/serve.port`.

```
QuarryMenuBarApp
  -> DaemonManager (spawns quarry serve, monitors health)
  -> DatabaseManager (discovers databases via quarry databases --json)
  -> SearchViewModel (debounced search via QuarryClient)
  -> ContentPanel (routes UI by daemon state)
```

No third-party dependencies. Pure SwiftUI with `@Observable` (Swift 5.9+).

## Roadmap

- [ ] Register folders for sync directly from menu bar
- [ ] Trigger sync from menu bar
- [ ] Collection filtering in search
- [ ] Ingest files via drag-and-drop
- [ ] Global keyboard shortcut configuration
- [ ] Status indicator for sync/ingest progress
