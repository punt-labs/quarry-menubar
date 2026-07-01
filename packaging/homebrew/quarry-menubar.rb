# typed: false
# frozen_string_literal: true

# Homebrew formula for the Quarry macOS menu bar app.
#
# Installs a prebuilt, universal (arm64 + x86_64) QuarryMenuBar.app from a
# GitHub Release. The app is ad-hoc signed ("Sign to Run Locally") but NOT
# notarized. Because this is a FORMULA (not a cask), Homebrew does not apply
# com.apple.quarantine to the download, so the app launches without a
# Developer ID certificate or notarization and without a Gatekeeper prompt.
#
# The release asset is a zip that wraps the .app one directory deep and is
# built with `ditto --norsrc --noextattr --noacl` so no AppleDouble ._* files
# survive extraction to break the code-signature seal (see the release
# workflow .github/workflows/release.yml in the punt-labs/quarry-menubar repo).
class QuarryMenubar < Formula
  desc "Menu bar app for Quarry document search"
  homepage "https://github.com/punt-labs/quarry-menubar"
  url "https://github.com/punt-labs/quarry-menubar/releases/download/v0.5.0/QuarryMenuBar-v0.5.0-macos-universal.zip"
  sha256 "7a5132405f73f67fe9ed941ca81d4607b33d16504e5fdb96765dc9bc02f08ea4"
  license "MIT"

  depends_on macos: :sonoma

  def install
    # The release zip wraps the bundle one directory deep, so Homebrew's
    # single-level staging descent lands on the wrapper and the .app is here.
    prefix.install "QuarryMenuBar.app"
  end

  def caveats
    <<~EOS
      QuarryMenuBar.app was installed to the Homebrew prefix:
        #{opt_prefix}/QuarryMenuBar.app

      To make it visible in Spotlight and Launchpad, symlink it into
      ~/Applications (Homebrew's build sandbox cannot write there for you):
        mkdir -p ~/Applications && ln -sfn "#{opt_prefix}/QuarryMenuBar.app" ~/Applications/QuarryMenuBar.app

      It is a menu bar app - no Dock icon; look for the icon in the menu bar.
      It follows your active Quarry connection: a remote profile in
      ~/.punt-labs/mcp-proxy/quarry.toml if present, otherwise local Quarry
      at https://127.0.0.1:8420.

      Security note: this is an unsigned, non-notarized build. Installed as a
      formula (not a cask), it is not Gatekeeper-quarantined and launches
      without a prompt. Install it only from the official punt-labs tap.
    EOS
  end

  test do
    assert_path_exists prefix/"QuarryMenuBar.app/Contents/MacOS/QuarryMenuBar"
  end
end
