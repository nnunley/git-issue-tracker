class GitIssue < Formula
  desc "Git-native issue tracking using hash-based IDs and git notes"
  homepage "https://github.com/nnunley/git-issue-tracker"
  head "https://github.com/nnunley/git-issue-tracker.git", branch: "main"
  version "1.0.0-dev"
  license "MIT"

  depends_on "git"
  depends_on "jq"

  def install
    bin.install "bin/git-issue"
    bin.install "bin/git-issue-status"
    bin.install "bin/git-note-commit"
    bin.install "bin/gh-to-git-issue"
    bin.install "bin/git-issue-to-gh"

    doc.install Dir["docs/*"]
    doc.install "README.md"
    doc.install "LICENSE"

    pkgshare.install "examples"
  end

  test do
    testpath_repo = testpath/"test-repo"
    testpath_repo.mkpath
    cd(testpath_repo) do
      system "git", "init"
      system "git", "config", "user.name", "Test"
      system "git", "config", "user.email", "test@test.com"
      (testpath_repo/"README.md").write("# Test")
      system "git", "add", "README.md"
      system "git", "commit", "-m", "init"

      system bin/"git-issue", "create", "Test issue from Homebrew"
      assert_match "Test issue from Homebrew", shell_output("#{bin}/git-issue list")
    end
  end
end
