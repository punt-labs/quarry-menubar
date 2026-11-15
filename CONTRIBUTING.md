# Contributing

## Setup

The project needs macOS 14 or later and Xcode. Install the build tools:

```bash
brew install xcodegen swiftformat swiftlint
```

Generate the Xcode project from `project.yml`:

```bash
make generate
```

The Xcode project is generated and gitignored; do not edit it. New `.swift`
files under `QuarryMenuBar/` are picked up the next time you run
`make generate`.

## Build and Run

Build and launch the app:

```bash
make run
```

Format, lint, build, and test in one step:

```bash
make all
```

The app needs a running Quarry connection to get past the connection screen.
See the README's [Setup](README.md#setup) section.

## Quality Gates

These must pass before every commit:

```bash
make format
```

```bash
make lint
```

```bash
make test
```

## Project Structure

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

See [How the App Finds Quarry](docs/architecture.md) for the connection model
and app structure, and [DESIGN.md](DESIGN.md) for design decisions.
