PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
DOCDIR = $(PREFIX)/share/doc/git-issue

.PHONY: install uninstall test test-deps clean install-mcp uninstall-mcp test-mcp build-mcp clean-mcp

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

test-all: test-unit test-integration test test-deps

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