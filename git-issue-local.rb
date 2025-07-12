class GitIssueLocal < Formula
  desc "Git-native issue tracking using hash-based IDs and git notes"
  homepage "https://github.com/your-username/git-issue-tracker"
  version "1.0.0-dev"
  license "MIT"

  depends_on "git"

  def install
    # Install directly from current directory
    source_dir = "/Users/ndn/development/git-issue-tracker"
    
    bin.install "#{source_dir}/bin/git-issue"
    bin.install "#{source_dir}/bin/git-issue-status"
    bin.install "#{source_dir}/bin/git-note-commit"
    
    # Install documentation
    doc.install Dir["#{source_dir}/docs/*"]
    doc.install "#{source_dir}/README.md"
    doc.install "#{source_dir}/LICENSE"
    
    # Install examples if they exist
    if Dir.exist?("#{source_dir}/examples")
      pkgshare.install "#{source_dir}/examples"
    end
  end

  test do
    # Test in a temporary directory to avoid git repo detection
    testpath_isolated = testpath/"isolated"
    testpath_isolated.mkpath
    cd testpath_isolated do
      # Set up git user for testing
      system "git", "config", "--global", "user.name", "Test User"
      system "git", "config", "--global", "user.email", "test@example.com"
      
      # Test basic functionality
      system bin/"git-issue", "create", "Test issue from Homebrew"
      assert_match "Test issue from Homebrew", shell_output("#{bin}/git-issue list")
      
      # Test status command
      assert_match "Issue Status Report", shell_output("#{bin}/git-issue-status")
    end
  end
end