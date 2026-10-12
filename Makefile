PREFIX ?= /usr/local
DESTDIR ?=
BINDIR = $(DESTDIR)$(PREFIX)/bin
DOCDIR = $(DESTDIR)$(PREFIX)/share/doc/git-issue
SHAREDIR = $(DESTDIR)$(PREFIX)/share/git-issue
MAN1DIR = $(DESTDIR)$(PREFIX)/share/man/man1
MAN8DIR = $(DESTDIR)$(PREFIX)/share/man/man8

.PHONY: install uninstall test test-deps test-content-safety test-dispatch test-layout test-flags test-registry bench-deps clean install-mcp uninstall-mcp test-mcp build-mcp clean-mcp

install:
	@echo "Installing git-issue..."
	install -d $(BINDIR)
	install -d $(DOCDIR)
	install -m 755 bin/git-issue $(BINDIR)/
	ln -sf git-issue $(BINDIR)/git-issue-status
	install -m 755 bin/git-note-commit $(BINDIR)/
	install -m 755 bin/git-issue-compile-statuses $(BINDIR)/
	install -d $(SHAREDIR)
	install -m 644 share/git-issue/statuses.default $(SHAREDIR)/
	install -m 644 share/git-issue/statuses.beads $(SHAREDIR)/
	install -d $(SHAREDIR)/awk
	install -m 644 share/git-issue/awk/*.awk $(SHAREDIR)/awk/
	install -d $(SHAREDIR)/emacs
	install -m 644 share/git-issue/emacs/*.el $(SHAREDIR)/emacs/
	install -d $(SHAREDIR)/hooks
	install -m 755 hooks/post-merge $(SHAREDIR)/hooks/
	install -m 755 hooks/pre-push $(SHAREDIR)/hooks/
	install -m 644 docs/* $(DOCDIR)/ 2>/dev/null || true
	install -d $(MAN1DIR)
	install -d $(MAN8DIR)
	install -m 644 man/man1/*.1 $(MAN1DIR)/
	install -m 644 man/man8/*.8 $(MAN8DIR)/
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
	rm -f $(BINDIR)/git-issue-compile-statuses
	rm -rf $(DOCDIR)
	rm -rf $(SHAREDIR)
	rm -f $(MAN1DIR)/git-issue.1 $(MAN1DIR)/git-issue-status.1
	rm -f $(MAN1DIR)/git-issue-compile-statuses.1 $(MAN1DIR)/git-note-commit.1
	rm -f $(MAN1DIR)/gh-to-git-issue.1 $(MAN1DIR)/git-issue-to-gh.1
	rm -f $(MAN8DIR)/git-issue.8
	@echo "Uninstall complete!"

test:
	@echo "Running git-issue tests..."
	@if command -v git-issue >/dev/null 2>&1; then \
		echo "✅ git-issue found in PATH"; \
		echo "Running comprehensive test suite..."; \
		chmod +x tests/*.sh; \
		./tests/test_runner.sh; \
	else \
		echo "❌ git-issue not found in PATH"; \
		exit 1; \
	fi

test-unit:
	@echo "Running unit tests..."
	chmod +x tests/unit_tests.sh
	./tests/unit_tests.sh

test-integration:
	@echo "Running integration tests..."
	chmod +x tests/integration_tests.sh
	./tests/integration_tests.sh

test-deps:
	@echo "Running dependency graph tests..."
	chmod +x tests/test_deps.sh
	./tests/test_deps.sh

test-content-safety:
	@echo "Running content safety tests..."
	chmod +x tests/test_content_safety.sh
	./tests/test_content_safety.sh

test-dispatch:
	@echo "Running dispatch tests..."
	chmod +x tests/test_dispatch.sh
	./tests/test_dispatch.sh

test-layout:
	@echo "Running install layout smoke test..."
	chmod +x tests/test_install_layout.sh
	./tests/test_install_layout.sh

test-flags:
	@echo "Running update flag tests..."
	chmod +x tests/test_git_style_flags.sh
	./tests/test_git_style_flags.sh

test-registry:
	@echo "Running multi-project registry tests..."
	chmod +x tests/test_registry.sh
	./tests/test_registry.sh

test-porcelain: ## Run porcelain output tests
	chmod +x tests/test_porcelain.sh
	./tests/test_porcelain.sh

test-merge-doc: ## Run issue document merge and diff unit tests
	chmod +x tests/test_merge_doc.sh
	./tests/test_merge_doc.sh

test-sync: ## Run multi-user sync and history tests
	chmod +x tests/test_sync_merge.sh
	./tests/test_sync_merge.sh

test-emacs-core: ## Run the Elisp core ERT suite (Emacs only, no magit)
	PATH="$(CURDIR)/bin:$$PATH" emacs -Q --batch -L share/git-issue/emacs -l ert -l contrib/emacs/test/git-issue-test.el -f ert-run-tests-batch-and-exit

test-emacs-ui: ## Run the magit UI ERT suite (downloads magit into a scratch dir)
	chmod +x contrib/emacs/test/run-ui-tests.sh
	./contrib/emacs/test/run-ui-tests.sh

bench-deps:
	@echo "Running dependency benchmark..."
	chmod +x tests/bench_deps.sh
	./tests/bench_deps.sh $(COUNT)

test-all: test-unit test-integration test test-deps test-content-safety test-dispatch test-layout test-flags test-registry test-porcelain test-merge-doc test-sync test-emacs-core

# Single source of the release version: VERSION, the GIT_ISSUE_VERSION
# constant in bin/git-issue, and every man page .TH line must agree.
# Usage: make bump VERSION=1.0.0
.PHONY: bump
bump:
	@test -n "$(VERSION)" || { echo "usage: make bump VERSION=x.y.z"; exit 1; }
	@printf '%s\n' "$(VERSION)" > VERSION
	@sed -e 's/^GIT_ISSUE_VERSION=".*"$$/GIT_ISSUE_VERSION="$(VERSION)"/' bin/git-issue > bin/git-issue.bump.tmp
	@mv bin/git-issue.bump.tmp bin/git-issue
	@chmod 755 bin/git-issue
	@d=`date +%Y-%m-%d`; \
	for m in man/man1/*.1 man/man8/*.8; do \
		sed -e "s/^\(\.TH [^\"]*\)\"[^\"]*\" \"git-issue [^\"]*\"/\1\"$$d\" \"git-issue $(VERSION)\"/" "$$m" > "$$m.bump.tmp"; \
		mv "$$m.bump.tmp" "$$m"; \
	done
	@echo "bumped to $(VERSION):"
	@grep -h '^GIT_ISSUE_VERSION=' bin/git-issue
	@head -1 man/man1/git-issue.1

clean:
	@echo "Cleaning up..."
	find . -name "*.tmp" -delete
	find . -name "*~" -delete

# MCP Server targets
build-mcp:
	@echo "Building MCP server..."
	@if command -v npm >/dev/null 2>&1; then \
		cd mcp && npm install && npm run build; \
		echo "✅ MCP server built successfully"; \
	else \
		echo "❌ npm not found - please install Node.js to build MCP server"; \
		exit 1; \
	fi

install-mcp: build-mcp
	@echo "Installing MCP server..."
	@if command -v npm >/dev/null 2>&1; then \
		cd mcp && npm install --global; \
		echo "✅ MCP server installed globally as 'git-issue-mcp-server'"; \
		echo ""; \
		echo "To use with Claude Desktop, add to your config:"; \
		echo '{'; \
		echo '  "mcpServers": {'; \
		echo '    "git-issue": {'; \
		echo '      "command": "git-issue-mcp-server"'; \
		echo '    }'; \
		echo '  }'; \
		echo '}'; \
	else \
		echo "❌ npm not found - please install Node.js"; \
		exit 1; \
	fi

uninstall-mcp:
	@echo "Uninstalling MCP server..."
	@if command -v npm >/dev/null 2>&1; then \
		npm uninstall --global git-issue-mcp-server; \
		echo "✅ MCP server uninstalled"; \
	else \
		echo "❌ npm not found"; \
	fi

test-mcp: build-mcp
	@echo "Testing MCP server..."
	@if command -v npm >/dev/null 2>&1; then \
		cd mcp && npm test; \
		echo "✅ MCP server tests passed"; \
	else \
		echo "❌ npm not found"; \
		exit 1; \
	fi

clean-mcp:
	@echo "Cleaning MCP server build..."
	rm -rf mcp/dist mcp/node_modules
	@echo "✅ MCP server cleaned"

.PHONY: help
help:
	@echo "git-issue Makefile"
	@echo ""
	@echo "Core Targets:"
	@echo "  install       Install git-issue to $(PREFIX)"
	@echo "  uninstall     Remove git-issue from system"
	@echo "  test          Test installation"
	@echo "  clean         Clean up temporary files"
	@echo ""
	@echo "MCP Server Targets:"
	@echo "  build-mcp     Build MCP server (requires Node.js)"
	@echo "  install-mcp   Install MCP server globally"
	@echo "  uninstall-mcp Remove MCP server"
	@echo "  test-mcp      Test MCP server"
	@echo "  clean-mcp     Clean MCP build files"
	@echo ""
	@echo "  help          Show this help"
	@echo ""
	@echo "Variables:"
	@echo "  PREFIX     Installation prefix (default: /usr/local)"