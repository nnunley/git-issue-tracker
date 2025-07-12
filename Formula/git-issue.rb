class GitIssue < Formula
  desc "Git-native issue tracking using hash-based IDs and git notes"
  homepage "https://github.com/your-username/git-issue-tracker"
  # For local development, install directly from source
  url "file:///dev/null"  # Dummy URL for local install
  version "1.0.0-dev"
  
  # Override source location for local development
  def source_dir
    "/Users/ndn/development/git-issue-tracker"
  end
  license "MIT"
  head "https://github.com/your-username/git-issue-tracker.git"

  depends_on "git"

  def install
    bin.install "bin/git-issue"
    bin.install "bin/git-issue-status"
    bin.install "bin/git-note-commit"
    
    # Install documentation
    doc.install Dir["docs/*"]
    doc.install "README.md"
    doc.install "LICENSE"
    
    # Install examples
    pkgshare.install "examples"
  end

  test do
    # Test in a temporary directory to avoid git repo detection
    testpath_isolated = testpath/"isolated"
    testpath_isolated.mkpath
    cd testpath_isolated do
      # Test basic functionality
      system bin/"git-issue", "create", "Test issue from Homebrew"
      assert_match "Test issue from Homebrew", shell_output("#{bin}/git-issue list")
      
      # Test status command
      assert_match "Issue Status Report", shell_output("#{bin}/git-issue-status")
    end
  end
end