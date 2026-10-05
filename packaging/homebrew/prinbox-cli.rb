class PrinboxCli < Formula
  desc "Command-line inbox for the pull requests waiting on you, through the GitHub CLI"
  homepage "https://github.com/creeonix/prinbox"
  url "https://github.com/creeonix/prinbox/releases/download/v@VERSION@/prinbox-@VERSION@-macos.tar.gz"
  sha256 "@CLI_SHA256@"
  version "@VERSION@"
  license "MIT"

  depends_on :macos
  depends_on "gh"

  def install
    bin.install "prinbox"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/prinbox --version")
  end
end
