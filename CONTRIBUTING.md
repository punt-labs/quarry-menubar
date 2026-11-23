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

Use `make format` to fix formatting, then run the non-mutating source
checks and the macOS tests before committing:

```bash
make check
```

### Ethos agent checks

Use [Ethos v5.2.0 or later](https://github.com/punt-labs/ethos/releases/tag/v5.2.0)
and the matching Claude Code plugin; v5.1.1 cannot run these checks. After
upgrading, run `ethos seed` and `ethos enable` to refresh the bundle and Git
hooks, then restart Claude Code to regenerate the agents. Install `shellcheck`
if you edit shell scripts.

Swift edits get file-scoped formatting and lint feedback; shell edits get
ShellCheck feedback. The [Ethos-generated edit hooks][ethos-generator] report
check failures as advice. Edits are not blocked if a check or the hook fails.
If feedback is missing, check that `ethos` is on `PATH` and that the Ethos
operator kill switch (`~/.punt-hooks-kill`) is not active.

Commits check staged Swift paths and an editing agent's handoff runs
`make check`, which generates the ignored Xcode project but does not rewrite
source. Stage or stash any unstaged changes to a checked Swift file before
committing.

[ethos-generator]: https://github.com/punt-labs/ethos/blob/v5.2.0/internal/hook/generate_agents.go

## Project Structure

```text
QuarryMenuBar/
  App/                  # App entry point, lifecycle
  Models/               # Codable JSON models for API responses
  Services/             # ConnectionManager, ConnectionProfileLoader, QuarryClient
  Utilities/            # SyntaxHighlighter
  ViewModels/           # SearchViewModel (debounced search)
  Views/                # SwiftUI views (ContentPanel, SearchPanel, ResultDetail, ...)
QuarryMenuBarTests/     # Unit tests (mirrors source structure)
project.yml             # XcodeGen project definition
Makefile                # Build, test, format, lint, version targets
```

See [How the App Finds Quarry](docs/architecture.md) for the connection model
and app structure, and [DESIGN.md](DESIGN.md) for design decisions.
