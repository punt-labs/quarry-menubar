# quarry-menubar

> macOS menu bar search for a Quarry document index.

[![License](https://img.shields.io/github/license/punt-labs/quarry-menubar)](LICENSE)
[![CI](https://img.shields.io/github/actions/workflow/status/punt-labs/quarry-menubar/ci.yml?label=CI)](https://github.com/punt-labs/quarry-menubar/actions/workflows/ci.yml)

quarry-menubar is a macOS menu bar app that searches the documents you have
indexed with [Quarry](https://github.com/punt-labs/quarry). Quarry's background
service, `quarryd`, does the indexing and search; this app is a search window
for it. The app connects to `quarryd` on your Mac or to a remote Quarry server,
and it never starts, stops, or configures Quarry itself.

**Platforms:** macOS 14 (Sonoma) or later, Apple Silicon and Intel

## Quick Start

You need [Homebrew](https://brew.sh) and a working Quarry install (see
[Setup](#setup)).

The install script adds the Punt Labs Homebrew tap, installs or upgrades the
app, and links it into `~/Applications`. Running it again upgrades in place.
Download the script and read it before you run it.

Download the script:

```bash
curl -fsSL https://raw.githubusercontent.com/punt-labs/quarry-menubar/1bc6b48/install.sh -o install.sh
```

Read it:

```bash
less install.sh
```

Run it:

```bash
sh install.sh
```

Open the app:

```bash
open -a QuarryMenuBar
```

The app has no Dock icon. Look for its magnifying-glass icon in the menu bar.

### Manual Install

Add the Punt Labs tap:

```bash
brew tap punt-labs/homebrew-tap
```

Trust the tap. Homebrew can refuse to load formulas from a third-party tap
until you trust it (`Refusing to load formula ... from untrusted tap`). You do
this once per tap.

```bash
brew trust punt-labs/homebrew-tap
```

Install the app. Run `brew upgrade quarry-menubar` later to update it.

```bash
brew install punt-labs/homebrew-tap/quarry-menubar
```

Link the app into `~/Applications`. Homebrew installs the app inside its own
prefix and is not allowed to write to your home folder, so it cannot make this
link itself. Without the link, the app does not appear in Spotlight or
Launchpad.

```bash
mkdir -p ~/Applications && ln -sfn "$(brew --prefix quarry-menubar)/QuarryMenuBar.app" ~/Applications/QuarryMenuBar.app
```

### What Gets Installed

Homebrew downloads a prebuilt universal (Apple Silicon and Intel)
`QuarryMenuBar.app` from the latest
[GitHub Release](https://github.com/punt-labs/quarry-menubar/releases). No
Xcode or build tools are needed.

The app is ad-hoc signed but not notarized, and it has no Developer ID
certificate. It is installed as a Homebrew formula, not a cask, so Homebrew
does not mark the download as quarantined and macOS opens it without a
Gatekeeper prompt. Install it only from the `punt-labs/homebrew-tap` tap.

Start the app with `open -a QuarryMenuBar`, with Spotlight, or by
double-clicking it in `~/Applications`. Do not run the executable inside the
`.app` bundle directly.

## Features

- **Search from the menu bar**: results update as you type, grouped by file
  type (Python, Markdown, PDF, and so on).
- **Collection filter**: search all collections or just one. A collection is
  a named group of documents in Quarry.
- **Full-page view**: open a result to read the whole page it came from, and
  copy that text.
- **Syntax highlighting**: code and Markdown are colored, with six color
  themes.
- **Reveal in Finder**: show a result's source file in Finder (local Quarry
  only).
- **Local or remote**: connect to `quarryd` on your Mac or to a remote Quarry
  server.
- **Connection status**: the panel shows whether the app is connected, and
  when it cannot connect it shows the error and the Quarry command that fixes
  it.

## Using the App

Click the menu bar icon to open the search panel. The header shows the server
you are connected to, the active Quarry database, and the connection status
(Connecting, Connected, Unavailable, or Config Error). If the app cannot
connect, the menu bar icon changes to a warning triangle.

| Action | How |
|--------|-----|
| Open the search panel | Click the menu bar icon |
| Search | Type in the search field; results update as you type |
| Search only one collection | Choose a collection from the folder menu to the left of the search field |
| Move through results | Up and Down arrow keys |
| Open a result | Click it, or highlight it and press Return |
| Copy the page text | Click **Copy** in the result view |
| Show the source file in Finder | Click **Reveal in Finder** in the result view (local Quarry only) |
| Go back to the results | Click **Back** or press Escape |
| Clear the search and close the panel | Press Escape from the results list |
| Change the color theme | Click the paintbrush menu in the header |
| Reconnect to Quarry | Click **Refresh** at the bottom of the panel, or **Retry** / **Reload Config** on an error screen |
| Quit | Click **Quit** or press Command-Q while the panel is open |

The result view loads the full page from Quarry. If that request fails, the
app shows the search excerpt instead, with a warning.

## Setup

The app needs a Quarry server to search. Install Quarry by following its
[Quick Start](https://github.com/punt-labs/quarry#quick-start), and index some
documents. For example, to index a folder:

```bash
quarry register ~/Documents/notes
```

**Local Quarry.** The app connects to the `quarryd` service on your Mac
automatically. There is nothing to configure. Quarry does not support Intel
Macs, so on an Intel Mac the app can only connect to a remote server.

**Remote Quarry.** Log in to the server with the Quarry command-line tool. The
app then connects to that server instead of the local one.

```bash
quarry login <host> --api-key <token>
```

You can set the `QUARRY_API_KEY` environment variable instead of passing
`--api-key`. To go back to local Quarry, run `quarry logout`, then click
**Refresh** in the app.

**If the app cannot connect.** The panel shows the reason and the command to
run next. The common cases are that `quarryd` is not running or that Quarry has
not been set up on this Mac; `quarry install` sets it up. After you fix the
problem, click **Retry** or **Reload Config**.

## Documentation

[How the App Finds Quarry](docs/architecture.md) |
[Design Decisions](DESIGN.md) |
[Contributing](CONTRIBUTING.md) |
[Changelog](CHANGELOG.md)

## License

MIT
