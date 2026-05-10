# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

I am a principal engineer. Every change I make leaves the codebase in a better state than I found it. I do not excuse new problems by pointing at existing ones. I do not defer quality to a future ticket. I do not create tech debt.

## Relationship to Parent Project

This is a **sub-project** of [quarry](https://github.com/punt-labs/quarry) (`../quarry`). Quarry is a Python CLI/MCP server for OCR document search backed by LanceDB. This repo is the macOS menu bar companion app — a native Swift/SwiftUI frontend that talks to `quarry serve` over localhost HTTP.

Both repos share the same development workflow conventions (branch discipline, micro-commits, session close protocol, beads issue tracking). The Python-specific standards (ruff, mypy, uv) do not apply here; the Swift equivalents (SwiftFormat, SwiftLint, xcodebuild) do.

## XcodeGen Toolchain

The project uses **XcodeGen** to generate `.xcodeproj` from `project.yml`. **Never edit the Xcode project directly** — it is gitignored and regenerated on every build.

```bash
brew install xcodegen swiftformat swiftlint   # One-time setup
```

### How XcodeGen Works

`project.yml` declares targets, settings, schemes, and source paths. The `sources` entry uses auto-discovery:

```yaml
sources:
  - path: QuarryMenuBar
    excludes:
      - "**/.DS_Store"
```

This means **any `.swift` file placed under `QuarryMenuBar/` is automatically included** after running `make generate` (or `make build`, which calls generate first). No need to manually add files to the project — just create them in the right directory and regenerate.

**Adding a new file**: Create the `.swift` file in the appropriate subdirectory (`Views/`, `Services/`, `Models/`, etc.), then run `make generate` to pick it up. The `.xcodeproj` is ephemeral.

### Make Targets

```bash
make generate    # Regenerate .xcodeproj from project.yml
make format      # Run SwiftFormat
make lint        # Run SwiftLint
make build       # Full pipeline: generate + format + lint + xcodebuild
make test        # Run unit tests
make coverage    # Tests with line coverage percentage
make all         # generate + format + lint + build + test
make clean       # Remove DerivedData
```

Single test file: `xcodebuild test -scheme QuarryMenuBar -destination 'platform=macOS' -only-testing:QuarryMenuBarTests/QuarryClientTests`

Quality gates before every commit: `make format && make lint && make test`

### Versioning

```bash
make version        # Show current version
make bump-patch     # 0.1.0 → 0.1.1
make bump-minor     # 0.1.0 → 0.2.0
make bump-major     # 0.1.0 → 1.0.0
make bump-build     # Increment build number
```

Version lives in `project.yml` (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`), not in Info.plist.

## Architecture

**macOS 14+ (Sonoma)**, Swift 5.9+, SwiftUI. No third-party dependencies.

### App Lifecycle

`QuarryMenuBarApp` → `MenuBarExtra(.window)` → `ContentPanel` → routes by `DaemonState`:

- `.stopped` → Start button
- `.starting` → ProgressView
- `.running` → `SearchPanel` (the main UI)
- `.error` → `ErrorStateView` with restart

The app is `LSUIElement: YES` (no dock icon, no main menu — menu bar only). Sandbox is disabled (`com.apple.security.app-sandbox: false`) because the app spawns `quarry serve` as a subprocess.

### Port Discovery Flow

This is the critical integration point with the quarry backend:

1. `DaemonManager.start()` spawns `quarry serve --db <name>` as a `Process`
2. The quarry server writes its port to `~/.quarry/data/<db>/serve.port`
3. `QuarryClient.readPort()` reads that file to discover the port
4. All API calls go to `http://127.0.0.1:<port>/<endpoint>`

If the port file doesn't exist, `QuarryClient` throws `.serverNotRunning`. The daemon manager schedules a health check 2 seconds after spawn to verify the server is responsive.

### MVVM + @Observable

The app uses Swift 5.9's `@Observable` macro (not the older `ObservableObject` protocol):

- **Models** (`QuarryModels.swift`): Plain `Codable & Sendable` structs with `snake_case` JSON keys via `convertFromSnakeCase` strategy
- **Services**: `QuarryClient` (Sendable, stateless HTTP), `DaemonManager` (@MainActor @Observable, owns Process lifecycle), `HotkeyManager` (@MainActor, NSEvent monitors)
- **ViewModel**: `SearchViewModel` (@MainActor @Observable) — debounced search with 300ms interval, cancellation support
- **Views**: SwiftUI with `@Bindable` for viewmodel bindings, `@FocusState` for keyboard focus

`QuarryClient` is injected into both `SearchViewModel` and `ResultDetail` to share the same port discovery path.

### Key API Endpoints

| Endpoint | Client Method | Returns |
|----------|--------------|---------|
| `GET /health` | `health()` | `HealthResponse` |
| `GET /search?q=&limit=` | `search(query:limit:collection:)` | `SearchResponse` with `[SearchResult]` |
| `GET /documents?collection=` | `documents(collection:)` | `DocumentsResponse` with file paths |
| `GET /collections` | `collections()` | `CollectionsResponse` |
| `GET /status` | `status()` | `StatusResponse` (db stats) |

### Syntax Highlighting

`SyntaxHighlighter` renders `AttributedString` for display in both list rows and detail views:

- **Python**: Regex-based color overlay (keywords, strings, comments, decorators) — keeps source text intact
- **Markdown**: Strips syntax markers (`###`, backticks, `**`, `[text](url)`) and applies formatting (bold headers, monospace code, blue links) — renders clean prose
- **Generic code**: C-family comment and string coloring

Uses `NSColor.system*` adaptive colors that respect system light/dark appearance.

## Standards

### Code Quality

- **Tests accompany code.** Every module ships with tests. Untested code is unfinished code.
- **All tests must pass.** No exceptions for pre-existing failures. Flaky tests must be fixed to be deterministic.
- **No force unwraps** (`!`) in production code. SwiftLint enforces `force_unwrapping` as an error. Use `guard let`/`if let`. In tests: `try XCTUnwrap()`.
- **No implicitly unwrapped optionals** (`var x: Type!`). Use `lazy var` or regular optionals.
- **No `print()` statements.** Use `os.Logger` (subsystem: `com.puntlabs.quarry-menubar`).
- **Duplication is a design failure.** If you see two copies, extract one abstraction.
- **Legacy code shrinks.** Every change is an opportunity to simplify what surrounds it.
- **Sendable types** for anything crossing actor boundaries. Models are `Codable & Sendable`.
- **@MainActor** on all UI-touching code (view models, daemon manager, hotkey manager).
- **SwiftFormat + SwiftLint must pass** before every commit. Config in `.swiftformat` and `.swiftlint.yml`.

### Code Organization

SwiftFormat's `organizeDeclarations` and `markTypes` rules enforce this structure within types:

```swift
// MARK: - TypeName

struct/class/enum TypeName {
    // MARK: Lifecycle       — init, deinit
    // MARK: Internal        — public/internal properties and methods
    // MARK: Private         — private properties and methods
}
```

Nested types get their own `// MARK: - NestedType` with dash prefix. Extensions: `// MARK: - TypeName ExtensionName`.

### SwiftFormat / SwiftLint Alignment

SwiftFormat and SwiftLint configs must not conflict. If SwiftFormat output fails SwiftLint, fix the `.swiftformat` config — do not disable SwiftLint rules.

Key SwiftFormat settings:

- 4-space indent, max width 120
- `--self remove` (no redundant `self.`)
- `--importgrouping alpha` (alphabetical imports)
- `--funcattributes prev-line` (`@MainActor` on line above `func`)
- `--enable organizeDeclarations, markTypes, sortedImports`
- `--disable trailingCommas`

### SwiftLint Key Rules

- `force_unwrapping`: **error** (banned)
- `implicitly_unwrapped_optional`: **error** (banned)
- Function body: 60 warning, 100 error
- Type body: 400 warning, 500 error
- File length: 750 warning, 1000 error
- Cyclomatic complexity: 15 warning, 25 error

## Development Workflow

### Issue Tracking with Beads

This project uses **beads** (`bd`) for issue tracking, same as the parent quarry project. Beads is a git-native issue tracker stored in `.beads/issues.jsonl`. If an issue discovered here affects multiple repos or requires a standards change, escalate to a [punt-kit bead](https://github.com/punt-labs/punt-kit) instead (see [bead placement scheme](../CLAUDE.md#where-to-create-a-bead)).

```bash
bd ready --limit=99                          # Show ALL issues ready to work (default truncates)
bd show <id>                                 # View issue details
bd create --title="Add feature" --type=task --priority=2  # Create issue
bd update <id> --status=in_progress          # Claim work
bd close <id>                                # Mark complete
bd dep add <child> <parent>                  # Set dependency
bd sync                                      # Sync with git remote
```

| Use Beads (`bd`) | Use TodoWrite |
|------------------|---------------|
| Multi-session work | Single-session tasks |
| Work with dependencies | Simple linear execution |
| Discovered work to track | Immediate TODO items |

**Rule of thumb**: If you might not finish it this session, or if it blocks/is blocked by other work, use beads.

#### Priority Levels

| Priority | Meaning |
|----------|---------|
| P0 | Critical — drop everything |
| P1 | High — do soon |
| P2 | Medium (default) |
| P3 | Low — when time permits |
| P4 | Backlog |

#### Creating Issues for Discovered Work

When you discover work that needs doing but isn't part of the current task:

1. Create a beads issue immediately: `bd create --title="..." --type=task`
2. Add dependencies if relevant: `bd dep add <new-issue> <blocking-issue>`
3. Continue with current work

### Workflow Tiers

Match the workflow to the task's scope. The deciding factor is **design ambiguity**, not size.

| Tier | Tool | When | Tracking |
|------|------|------|----------|
| **T1: Forge** | `/feature-forge` | Epics, cross-cutting work, competing design approaches | Beads with dependencies |
| **T2: Feature Dev** | `/feature-dev` | Features, multi-file, clear goal but needs exploration | Beads + TodoWrite |
| **T3: Direct** | Plan mode or manual | Tasks, bugs, obvious implementation path | Beads |

**Decision flow:**

1. Is there design ambiguity needing multi-perspective input? → **T1: Forge**
2. Does it touch multiple files and benefit from codebase exploration? → **T2: Feature Dev**
3. Otherwise → **T3: Direct** (plan mode if >3 files, manual if fewer)

**Bead type mapping:**

| Bead Scope | Default Tier | Override When |
|------------|-------------|---------------|
| Epic (multi-bead, dependencies) | T1: Forge | Design decisions already settled → T2 |
| Feature (new capability) | T2: Feature Dev | Cross-cutting with design ambiguity → T1 |
| Task (focused, single-concern) | T3: Direct | Scope expands during work → escalate to T2 |
| Bug | T3: Direct | Root-cause unclear across subsystems → T2 |

**Escalation only goes up.** If T3 reveals unexpected scope, escalate to T2. If T2 reveals competing design approaches, escalate to T1. Never demote mid-flight.

**Ralph-loop** is a tool *within* tiers, not a tier itself. Use it in any tier when a sub-task has clear, testable success criteria and may need iteration.

### Branch Discipline

All code changes go on feature branches. Never commit directly to main.

```bash
git checkout -b feat/short-description main
```

| Prefix | Use |
|--------|-----|
| `feat/` | New features |
| `fix/` | Bug fixes |
| `refactor/` | Code improvements |
| `docs/` | Documentation only |

### Micro-Commits

One logical change per commit. 1-5 files, under 100 lines. Quality gates pass before every commit.

Format: `type(scope): description`

| Prefix | Use |
|--------|-----|
| `feat:` | New feature |
| `fix:` | Bug fix |
| `refactor:` | Code change, no behavior change |
| `test:` | Adding or updating tests |
| `docs:` | Documentation |
| `chore:` | Build, dependencies, CI |

### GitHub Operations

Use the GitHub MCP server tools for all GitHub operations (creating PRs, merging, reading PR comments, issues). Git operations (commit, push, branch) use the Bash tool.

### Documentation Discipline

Three documents track different aspects of the project. Each has a clear trigger for when it must be updated — if the trigger fires and the PR diff does not include the update, the PR is not ready to merge.

**CHANGELOG.md** — Entries are written in the PR branch, before merge — not retroactively on main. If a PR changes user-facing behavior and the diff does not include a CHANGELOG entry, the PR is not ready to merge. Follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. Add entries under `## [Unreleased]`. Categories: Added, Changed, Deprecated, Removed, Fixed, Security.

**README.md** — Update when user-facing behavior changes: new flags, commands, defaults, configuration options, or changed workflows. The README is the first thing a user reads; it must reflect the current state of the software, not a past version.

**prfaq.tex** — Update when a change shifts product direction or validates/invalidates a risk assumption from the PR/FAQ. The PR/FAQ lives in the `../prfaq/` repo; cross-repo updates can be tracked with a punt-kit bead if they can't land in the same session.

### Pre-PR Checklist

- [ ] **CHANGELOG entry** in the PR diff (see Documentation Discipline above)
- [ ] **README updated** if user-facing behavior changed
- [ ] **PR/FAQ updated** if product direction or risk assumptions shifted
- [ ] **Quality gates pass**: `make format && make lint && make test`
- [ ] **Live demo** for features: launch against a real `quarry serve` instance and exercise the feature end-to-end

### Code Review Flow

Do **not** merge immediately after creating a PR. Expect **2–6 review cycles** before merging.

1. **Create PR** — push branch, open PR via `mcp__github__create_pull_request`. Prefer MCP GitHub tools over `gh` CLI.
2. **Request Copilot review** — use `mcp__github__request_copilot_review`.
3. **Watch for feedback in the background** — `gh pr checks <number> --watch` in a background task or separate session. Do not stop waiting. Copilot and Bugbot may take 1–3 minutes after CI completes.
4. **Read all feedback** via MCP: `mcp__github__pull_request_read` with `get_reviews` and `get_review_comments`.
5. **Take every comment seriously.** Do not dismiss feedback as "unrelated to the change" or "pre-existing." If you disagree, explain why in a reply.
6. **Fix and re-push** — commit fixes, push, re-run quality gates.
7. **Repeat steps 3–6** until the latest review is **uneventful** — zero new comments, all checks green.
8. **Merge only when the last review was clean** — use `mcp__github__merge_pull_request` (not `gh pr merge`).

### Session Close Protocol

```bash
git status                  # Check for uncommitted work
git add <files>             # Stage changes
git commit -m "..."         # Commit with quality gates passing
bd sync                     # Sync beads with git
git push                    # Push to remote
git status                  # Must show "up to date with origin"
```

Work is NOT complete until `git push` succeeds.

### Executable Resolution

GUI apps don't inherit the shell's PATH, so `/usr/bin/env quarry` fails at runtime. `ExecutableResolver` searches well-known install locations at startup:

1. `~/.local/bin/quarry` (uv tool install)
2. `/usr/local/bin/quarry`
3. `/opt/homebrew/bin/quarry`

The resolved path is passed to both `DaemonManager` and `CLIDatabaseDiscovery`. If quarry isn't found at any known location, the app falls back to `/usr/bin/env` (will only work if PATH is set, e.g. when launched from a terminal).

To add a new search path, edit `ExecutableResolver.searchPaths`.

### Testing Against Live Backend

```bash
make run    # Build and launch the app
```

The app auto-starts `quarry serve` for the persisted database (default: "default"). To test with a specific database, switch via the database picker in the menu bar header — no code changes needed.

**Prerequisite**: `quarry` must be installed with `serve` and `databases` commands. Install from the parent project:

```bash
cd ../ocr && uv tool install --force .
```

## Ethos & Delegation

Identity: `agent: claude` per `.punt-labs/ethos.yaml`. Sub-agent calls (`Agent(subagent_type=…)`) match ethos identity handles.

quarry-menubar is a native macOS Swift/SwiftUI menu-bar app that drives a `quarry serve` subprocess and renders results. Three concerns: (1) Swift/SwiftUI implementation discipline (XcodeGen, SwiftFormat/Lint, @Observable MVVM); (2) the cross-process integration with the quarry HTTP backend (port discovery, lifecycle, executable resolution); (3) macOS-specific surface (menu bar, hotkeys, Dock-less UIElement, sandbox config). Worker and evaluator must be distinct handles with no shared role. Claude is the leader, never the evaluator.

| Task type | Worker | Evaluator |
|-----------|--------|-----------|
| Swift/SwiftUI view code, MVVM, @Observable | `csl` (Lattner) | `srn` (Naroff) |
| Concurrency, Sendable, @MainActor boundaries | `srn` | `csl` |
| XcodeGen `project.yml`, build settings, schemes | `csl` | `adb` (Lovelace) |
| SwiftFormat / SwiftLint config alignment | `csl` | `mdm` (Pike) |
| Daemon lifecycle (`Process`, port file, health check) | `srn` | `bwk` (Pike — Go context for cross-process patterns) |
| HTTP client / Codable / API contract with quarry | `srn` | `rmh` (Hettinger) |
| Executable resolution / install-path search | `csl` | `adb` |
| Hotkey / NSEvent monitor / global accessibility | `srn` | `dna` (Norman) |
| Visual / menu-bar UX / search panel layout | `dna` | `edt` (Tufte) |
| Syntax highlighting / `AttributedString` rendering | `csl` | `dna` |
| Cross-repo coordination with `quarry` HTTP API | `srn` | `rmh` |

Use the `standard` pipeline for new views, new endpoints, or daemon-lifecycle changes. Use `quick` for SwiftLint fixes or single-file refactors. The "Live demo" Pre-PR check is non-negotiable — every feature must be exercised against a real `quarry serve` before review.

## Scratch Files

Use `.tmp/` at the project root for scratch and temporary files — never `/tmp`. The `TMPDIR` environment variable is set via `.envrc` so that `tempfile` and subprocesses automatically use it. Contents are gitignored; only `.gitkeep` is tracked.
