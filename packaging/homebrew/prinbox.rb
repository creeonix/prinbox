cask "prinbox" do
  version "@VERSION@"
  sha256 "@DMG_SHA256@"

  url "https://github.com/creeonix/prinbox/releases/download/v#{version}/PRInbox-#{version}.dmg"
  name "PRInbox"
  desc "Menu-bar inbox for the pull requests waiting on you, signed in through the GitHub CLI"
  homepage "https://github.com/creeonix/prinbox"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "PRInbox.app"

  uninstall quit: "io.github.creeonix.prinbox"

  zap trash: [
    "~/.config/prinbox",
    "~/Library/Application Support/prinbox",
    "~/Library/Caches/io.github.creeonix.prinbox",
  ]

  caveats <<~EOS
    PRInbox is signed ad hoc, not with an Apple Developer ID, so macOS blocks the first launch.
    Either install with
      brew install --cask --no-quarantine creeonix/tap/prinbox
    or right-click PRInbox in Applications once and choose Open.

    PRInbox needs the GitHub CLI, signed in:
      brew install gh && gh auth login
  EOS
end
