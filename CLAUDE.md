# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

I am a principal engineer. Every change I make leaves the codebase in a better state than I found it. I do not excuse new problems by pointing at existing ones. I do not defer quality to a future ticket. I do not create tech debt.

## Relationship to Parent Project

This is a **sub-project** of [quarry](https://github.com/punt-labs/quarry) (`../quarry`). Quarry is a Python CLI/MCP server for OCR document search backed by LanceDB. This repo is the macOS menu bar companion app — a native Swift/SwiftUI frontend that talks to Quarry over the current connection model (local TLS on `localhost` or a configured remote server).

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

**macOS 14+ (Sonoma)**, Swift 5.9+, SwiftUI. One third-party package: `HighlightSwift`.

### App Lifecycle

`QuarryMenuBarApp` → `MenuBarExtra(.window)` → `ContentPanel` → routes by `ConnectionState`:

- `.idle` / `.connecting` → ProgressView
- `.connected` → `SearchPanel` (the main UI)
- `.unavailable` → `ErrorStateView` with retry
- `.misconfigured` → `ErrorStateView` with config guidance

The app is `LSUIElement: YES` (no dock icon, no main menu — menu bar only). Sandbox is disabled (`com.apple.security.app-sandbox: false`) so the app can make network requests freely and reveal local files in Finder when connected to local Quarry.

### Connection Resolution Flow

This is the critical integration point with the Quarry backend:

1. `ConnectionProfileLoader` checks `~/.punt-labs/mcp-proxy/quarry.toml`
2. If a remote profile exists, the app uses that server as authoritative
3. Otherwise the app falls back to local Quarry at `https://localhost:8420`
4. `QuarryClient` talks to the resolved base URL with optional Bearer auth and a pinned CA

There is no subprocess ownership, no `serve.port` discovery, and no runtime dependency on the `quarry` CLI being on `PATH`.

### MVVM + @Observable

The app uses Swift 5.9's `@Observable` macro (not the older `ObservableObject` protocol):

- **Models** (`QuarryModels.swift`): Plain `Codable & Sendable` structs with `snake_case` JSON keys via `convertFromSnakeCase` strategy
- **Services**: `QuarryClient` (HTTP(S), auth, pinned CA), `ConnectionManager` (@MainActor @Observable, owns connection state), `ConnectionProfileLoader` (parses Quarry config), `HotkeyManager` (@MainActor, NSEvent monitors)
- **ViewModel**: `SearchViewModel` (@MainActor @Observable) — debounced search with 300ms interval, cancellation support
- **Views**: SwiftUI with `@Bindable` for viewmodel bindings, `@FocusState` for keyboard focus

`QuarryClient` is injected into both `SearchViewModel` and `ResultDetail` so search and detail rendering share the same resolved connection.

### Key API Endpoints

| Endpoint | Client Method | Returns |
|----------|--------------|---------|
| `GET /health` | `health()` | `HealthResponse` |
| `GET /search?q=&limit=` | `search(query:limit:collection:)` | `SearchResponse` with `[SearchResult]` |
| `GET /documents?collection=` | `documents(collection:)` | `DocumentsResponse` with file paths |
| `GET /collections` | `collections()` | `CollectionsResponse` |
| `GET /status` | `status()` | `StatusResponse` (db stats) |
| `GET /databases` | `databases()` | `DatabasesResponse` for the active server database |
| `GET /show?document=&page=` | `show(document:page:collection:)` | `ShowPageResponse` with full page text |

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

### Review Tools vs Standards

Copilot, Bugbot, local review agents, and other automated reviewers are advisory. Repo rules in this file, parent-workspace guidance, and the project's Swift/macOS standards win when they conflict with a review suggestion.

Treat review feedback seriously, but do not cargo-cult it. If you decline a suggestion, document the exact reason with a code reference.

### Verify Outputs, Not Just Gates

Passing `make format`, `make lint`, and `make test` is necessary, not sufficient. After changing behavior:

- Open the touched files and read the resulting code.
- Launch the app or exercise the changed path against a real Quarry connection.
- Compare the actual behavior with the intended behavior before declaring the work complete.

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
bd vc status                                 # Inspect beads database VC state
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

### Session Queue

When you claim a batch of beads for one session, mirror the active subset in a session-local plan or task list. Beads are the durable cross-session source of truth; the session plan is the live queue you monitor while executing.

Workflow:

1. Pick a realistic batch from `bd ready`.
2. Claim or mark the selected beads in progress.
3. Create one session-local task per bead using the available planning tool.
4. Close the bead and mark the session task complete together.
5. Leave unfinished work as open beads; no extra carry-forward bookkeeping is needed.

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

### PR Boundaries

Split work by **rollback granularity**, not by diff size. Ask: if this broke in production, what would need to be reverted together? That is one PR.

Valid reasons to split:

- Independent rollback paths
- Sequential dependency where one change must land before another
- Clear product or operational boundary

Invalid reasons to split:

- "The diff is large"
- "This feels cleaner as a separate concern"
- "Reviewers can look at smaller chunks later"

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
- [ ] **Live demo** for features: launch against a real Quarry connection and exercise the feature end-to-end
- [ ] **Local review agents run on the full diff** and their findings are resolved
- [ ] **Human IDE review** completed on the full diff

### Development Loop

Two nested loops govern all non-trivial changes.

#### Inner loop — one coherent change

Run this loop after each sizeable implementation step or delegated mission:

1. Implement the change or delegate it to the right specialist.
2. Run the relevant local checks. For production code changes, that means the full gate: `make format && make lint && make test`.
3. Exercise the changed behavior manually against a real Quarry connection when the change affects runtime behavior.
4. Run local review agents on the mission diff. Minimum: one general code-review pass and one silent-failure / edge-case pass.
5. Fix every finding. To dismiss one, record the exact finding, the reason it does not apply, and the code reference.
6. Re-run local reviewers until the first clean round.
7. Commit.

#### Outer loop — one PR

After all coherent changes for the branch are committed:

1. Run the full quality gates on the accumulated diff.
2. Run both local review agents on the complete diff.
3. Perform a human IDE review of the full diff.
4. Run the complete user-facing flow end-to-end against a real Quarry connection.
5. Open the PR only after the local review loop is clean.

A PR opened before the outer loop is clean is a process failure, not a "draft for later cleanup."

### Code Review Flow

Do **not** merge immediately after creating a PR. Expect **2–6 review cycles** before merging.

1. **Create PR** — after the outer loop above is clean, push branch and open the PR via `mcp__github__create_pull_request`. Prefer MCP GitHub tools over `gh` CLI.
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
git push -u origin <branch> # First push on a new branch
# OR
git pull --rebase           # If the branch already tracks a remote
git push                    # Push to remote
git status                  # Must show "up to date with origin"
```

Work is NOT complete until `git push` succeeds.

### Testing Against Live Backend

```bash
make run    # Build and launch the app
```

The app follows Quarry's active connection. For local testing, install Quarry and start the service. For remote testing, point Quarry at a remote server with `quarry login <host> --api-key <token>`, or set `QUARRY_API_KEY` before running `quarry login <host>`.

**Prerequisite**: `quarry` must be installed and configured. Install from the parent project:

```bash
cd ../quarry && uv tool install --force .
```

## Ethos & Delegation

Identity: `agent: claude` per `.punt-labs/ethos.yaml`. Sub-agent calls (`Agent(subagent_type=…)`) match ethos identity handles.

quarry-menubar is a native macOS Swift/SwiftUI menu-bar app that follows Quarry's connection model and renders results. Three concerns: (1) Swift/SwiftUI implementation discipline (XcodeGen, SwiftFormat/Lint, @Observable MVVM); (2) the HTTP(S) integration with Quarry (connection resolution, TLS/auth, current endpoint contracts); (3) macOS-specific surface (menu bar, hotkeys, Dock-less UIElement, local-vs-remote capability gating). Within each row, the worker and evaluator must be distinct handles. Claude is the leader, never the evaluator.

| Task type | Worker | Evaluator |
|-----------|--------|-----------|
| Swift/SwiftUI view code, MVVM, @Observable | `csl` (Lattner) | `srn` (Naroff) |
| Concurrency, Sendable, @MainActor boundaries | `srn` | `csl` |
| XcodeGen `project.yml`, build settings, schemes | `csl` | `adb` (Lovelace) |
| SwiftFormat / SwiftLint config alignment | `csl` | `mdm` (Pike) |
| Connection resolution / config parsing / state | `srn` | `rmh` (Hettinger) |
| HTTP client / Codable / TLS/auth contract with quarry | `srn` | `rmh` (Hettinger) |
| Hotkey / NSEvent monitor / global accessibility | `srn` | `dna` (Norman) |
| Visual / menu-bar UX / search panel layout | `dna` | `edt` (Tufte) |
| Syntax highlighting / `AttributedString` rendering | `csl` | `dna` |
| Cross-repo coordination with `quarry` HTTP API | `srn` | `rmh` |

Use the `standard` pipeline for new views, new endpoints, or connection-model changes. Use `quick` for SwiftLint fixes or single-file refactors. The "Live demo" Pre-PR check is non-negotiable — every feature must be exercised against a real Quarry connection before review.

## Scratch Files

Use `.tmp/` at the project root for scratch and temporary files — never `/tmp`. The `TMPDIR` environment variable is set via `.envrc` so that `tempfile` and subprocesses automatically use it. Contents are gitignored; only `.gitkeep` is tracked.
