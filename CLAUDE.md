# Quarry Menu Bar

macOS menu bar companion for [Quarry](https://github.com/jmf-pobox/quarry-mcp) document search. Communicates with `quarry serve` over localhost HTTP.

## Build System

XcodeGen generates the `.xcodeproj` from `project.yml`. Never edit the Xcode project directly.

```bash
make generate    # Regenerate Xcode project
make format      # SwiftFormat
make lint        # SwiftLint
make build       # Full pipeline: generate + format + lint + build
make test        # Run unit tests
make all         # generate + format + lint + build + test
```

### Prerequisites

```bash
brew install xcodegen swiftformat swiftlint
```

## Architecture

- **macOS 14+ (Sonoma)**, Swift 5.9+
- `MenuBarExtra` with `.window` style for popover panel
- HTTP client talks to `quarry serve` on localhost
- Port discovery via `~/.quarry/data/<db>/serve.port`

### Directory Structure

```
QuarryMenuBar/
  App/             # @main entry point
  Models/          # Codable response types
  ViewModels/      # Observable state
  Views/           # SwiftUI views
  Services/        # QuarryClient, DaemonManager, HotkeyManager
  Resources/       # Assets, entitlements
```

## Standards

- **Tests accompany code.** Every module ships with tests.
- **No force unwraps** in production code.
- **SwiftFormat + SwiftLint** must pass before every commit.
- **Feature branches.** Never commit directly to main.
- **Micro-commits.** One logical change per commit.

## Commit Messages

Format: `type(scope): description`

| Prefix | Use |
|--------|-----|
| `feat:` | New feature |
| `fix:` | Bug fix |
| `refactor:` | Code change, no behavior change |
| `test:` | Adding or updating tests |
| `docs:` | Documentation |
| `chore:` | Build, dependencies, CI |
