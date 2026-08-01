# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Fixed

- Restored connectivity against Quarry 2.0 (`quarryd`, DES-031 v2.2). Quarry 2.0 moved every engine endpoint under `/v1/` (only `/health` stays at the root) and now requires the daemon's `serve.token` bearer on loopback requests; the app was calling endpoints at the root (404) and presenting no loopback bearer (401). The client now prefixes `search`/`show`/`status`/`databases`/`documents`/`collections` with `/v1/`, and connection resolution mirrors the `quarry` CLI's `TargetResolver`: a remote `quarry.toml` login wins, otherwise the local daemon is resolved on `127.0.0.1` from `serve.port` plus the live `serve.token` in the startup database's run dir (`~/.punt-labs/quarry/data/<db>/`). A loopback `quarry.toml` falls through to the `serve.token` path. A down daemon (no `serve.port`) or an unreadable/empty `serve.token` now surfaces a clear configuration error pointing at the daemon. TLS/host validation is unchanged (loopback still pins the local CA and dials the IPv4 literal).

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
