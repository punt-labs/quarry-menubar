# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- Homebrew distribution: `brew install punt-labs/homebrew-tap/quarry-menubar` installs a prebuilt, universal (arm64 + x86_64) app from a GitHub Release. Because it ships as a formula (not a cask), Homebrew does not quarantine the download, so the ad-hoc-signed app launches without notarization or a Developer ID certificate. A `release.yml` GitHub Actions workflow builds the universal app on tag push (`v*`), packages it as an attribute-stripped zip, and publishes the release.

### Changed

- Replatformed the menu bar app onto Quarry's connection model so it attaches to the active local or remote Quarry server instead of trying to manage its own daemon.

### Fixed

- Hid the Dock icon so the app runs menu-bar-only. `LSUIElement` now lives in the XcodeGen `info.properties` block (the source of the authoritative `Info.plist`); the previously-set `INFOPLIST_KEY_LSUIElement` build setting was inert because the target ships an explicit `INFOPLIST_FILE`. The built app now registers as a `UIElement` accessory instead of a `Foreground` app.
- Restored localhost HTTPS support by trusting Quarry's pinned PEM CA and validating private-CA certificates correctly.
- Fixed connection fallback and refresh handling so stale refreshes do not overwrite newer state and logged-out proxy configs fall back to local Quarry again.
- Classified TLS trust failures as configuration issues, restored the detail copy action, and tightened remote login guidance for authenticated Quarry servers.
- Fixed local connections showing "Unavailable" against a healthy server: the app now dials local Quarry over `127.0.0.1` instead of `localhost`, avoiding the IPv6 (`::1`) loopback that the IPv4-only server does not listen on. Host display and TLS host validation are unchanged.
