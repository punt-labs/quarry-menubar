# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Fixed

- Restored connectivity against Quarry 3.x. Quarry 3.0 dropped three size fields the app decoded as hard requirements: `GET /v1/status` no longer emits `database_size_bytes`, and `GET /v1/databases` entries no longer carry `size_bytes` or `size_description` (the daemon deliberately reports no on-disk size, since producing it requires an O(seconds) tree walk any client could trigger). Because `StatusResponse.databaseSizeBytes`, `DatabaseSummary.sizeBytes`, and `DatabaseSummary.sizeDescription` were non-optional, JSON decoding threw during the connect handshake and the app dead-ended on "Quarry Unavailable". The three fields are now optional, so the size-less 3.x payloads decode and the app connects; no UI surfaced these values, so nothing is displayed differently.

## [0.6.2] - 2026-08-01

### Added

- `DESIGN.md` — architecture decision records (ADRs) for the client/connection design, testability posture, and TLS pinning, with rejected alternatives. README architecture diagram updated to show app-scope connection ownership.

### Fixed

- Fixed the app landing on "Quarry Unavailable — The operation couldn't be completed. (Swift.CancellationError error 1.)" instead of connecting. The initial connect ran inside the `ContentPanel` `.task`, which `MenuBarExtra(.window)` cancels whenever the panel window is torn down (panel close, first-open re-render). A cancelled request surfaces (via the client's `URLError.cancelled` mapping) as `CancellationError`, and the connection manager's catch-all presented that cancellation as a user-facing "Unavailable" — a dead end, because the panel's `if case .idle` guard then blocked any auto-retry. The connect now runs at app scope from `applicationDidFinishLaunching` in a `ConnectionManager`-owned task that outlives every panel, so panel teardown can no longer cancel it and the app resolves its connection at launch. `CancellationError`/`URLError.cancelled` are also caught explicitly and reset the manager to `.idle` (never `.unavailable`/`.misconfigured`), so an abandoned attempt never masquerades as a real failure.

## [0.6.1] - 2026-07-29

### Fixed

- Restored connectivity against Quarry 2.0 (`quarryd`, DES-031 v2.2). Quarry 2.0 moved every engine endpoint under `/v1/` (only `/health` stays at the root) and now requires the daemon's `serve.token` bearer on loopback requests; the app was calling endpoints at the root (404) and presenting no loopback bearer (401). The client now prefixes `search`/`show`/`status`/`databases`/`documents`/`collections` with `/v1/`, and connection resolution mirrors the `quarry` CLI's `TargetResolver`: a remote `quarry.toml` login wins, otherwise the local daemon is resolved on `127.0.0.1` from `serve.port` plus the live `serve.token` in the startup database's run dir (`~/.punt-labs/quarry/data/<db>/`). A loopback `quarry.toml` falls through to the `serve.token` path. A down daemon (no `serve.port`), a present-but-unreadable/invalid `serve.port`, an unreadable/empty `serve.token`, or a broken `config.toml` each surface a distinct, clear configuration error pointing at the daemon rather than silently reading the wrong run directory. The `[default] database` name in `config.toml` is resolved the way the `quarry` CLI resolves it (absent or empty means the `default` database), tolerating an inline `# comment` and single-quoted values. TLS/host validation is unchanged (loopback still pins the local CA and dials the IPv4 literal).

## [0.6.0] - 2026-07-03

### Added

- `install.sh` wrapper that runs the full Homebrew flow in one idempotent command — `brew tap`, `brew trust`, install-or-upgrade, and the required `~/Applications` symlink. The symlink is a documented required step because the Homebrew formula cannot create it: Homebrew's install sandbox forbids writes to `$HOME`, and auto-linking into `~/Applications` is a cask-only feature the formula avoids to skip notarization.
- Homebrew distribution: `brew install punt-labs/homebrew-tap/quarry-menubar` installs a prebuilt, universal (arm64 + x86_64) app from a GitHub Release. Because it ships as a formula (not a cask), Homebrew does not quarantine the download, so the ad-hoc-signed app launches without notarization or a Developer ID certificate. A `release.yml` GitHub Actions workflow builds the universal app on tag push (`v*`), packages it as an attribute-stripped zip, and publishes the release.

### Changed

- Replatformed the menu bar app onto Quarry's connection model so it attaches to the active local or remote Quarry server instead of trying to manage its own daemon.
- Detail view now renders page text exactly as Quarry returns it; removed the app-side reflow/de-wrap heuristics (paragraph reconstruction moves upstream to Quarry's extraction).

### Removed

- `ExtractedTextFormatter` — the app-side PDF reflow/de-wrap utility. Paragraph reconstruction now happens upstream in Quarry's extraction.

### Fixed

- Hid the Dock icon so the app runs menu-bar-only. `LSUIElement` now lives in the XcodeGen `info.properties` block (the source of the authoritative `Info.plist`); the previously-set `INFOPLIST_KEY_LSUIElement` build setting was inert because the target ships an explicit `INFOPLIST_FILE`. The built app now registers as a `UIElement` accessory instead of a `Foreground` app.
- Restored localhost HTTPS support by trusting Quarry's pinned PEM CA and validating private-CA certificates correctly.
- Fixed connection fallback and refresh handling so stale refreshes do not overwrite newer state and logged-out proxy configs fall back to local Quarry again.
- Classified TLS trust failures as configuration issues, restored the detail copy action, and tightened remote login guidance for authenticated Quarry servers.
- Fixed local connections showing "Unavailable" against a healthy server: the app now dials local Quarry over `127.0.0.1` instead of `localhost`, avoiding the IPv6 (`::1`) loopback that the IPv4-only server does not listen on. Host display and TLS host validation are unchanged.
