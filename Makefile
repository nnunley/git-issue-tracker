PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
DOCDIR = $(PREFIX)/share/doc/git-issue

.PHONY: install uninstall test clean

install:
	@echo "Installing git-issue..."
	install -d $(BINDIR)
	install -d $(DOCDIR)
	install -m 755 bin/git-issue $(BINDIR)/
	install -m 755 bin/git-issue-status $(BINDIR)/
	install -m 755 bin/git-note-commit $(BINDIR)/
	install -m 644 docs/* $(DOCDIR)/ 2>/dev/null || true
	@echo "Installation complete!"
	@echo ""
	@echo "You can now use:"
	@echo "  git issue create 'Fix the navbar bug'"
	@echo "  git issue list"
	@echo "  git issue-status"

uninstall:
	@echo "Uninstalling git-issue..."
	rm -f $(BINDIR)/git-issue
	rm -f $(BINDIR)/git-issue-status  
	rm -f $(BINDIR)/git-note-commit
	rm -rf $(DOCDIR)
	@echo "Uninstall complete!"

test:
	@echo "Running git-issue tests..."
	@if command -v git-issue >/dev/null 2>&1; then \
		echo "✅ git-issue found in PATH"; \
		git issue create "Test issue from Makefile" && \
		echo "✅ Issue creation test passed"; \
	else \
		echo "❌ git-issue not found in PATH"; \
		exit 1; \
	fi

clean:
	@echo "Cleaning up..."
	find . -name "*.tmp" -delete
	find . -name "*~" -delete

.PHONY: help
help:
	@echo "git-issue Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  install    Install git-issue to $(PREFIX)"
	@echo "  uninstall  Remove git-issue from system"
	@echo "  test       Test installation"
	@echo "  clean      Clean up temporary files"
	@echo "  help       Show this help"
	@echo ""
	@echo "Variables:"
	@echo "  PREFIX     Installation prefix (default: /usr/local)"