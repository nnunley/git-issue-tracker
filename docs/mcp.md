# AI integration (MCP server)


**Optional AI-powered features** via Model Context Protocol (MCP) - requires Node.js.

### Installation

```bash
# Install MCP server (requires Node.js 18+)
make install-mcp

# Or build manually
cd mcp && npm install && npm run build
npm install --global
```

### Claude Desktop Integration

Add to your Claude Desktop configuration (`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "git-issue": {
      "command": "git-issue-mcp-server"
    }
  }
}
```

### AI-Powered Features

Once configured, you can ask Claude to:

- **Analyze issue complexity**: "Analyze the complexity of issue abc123"
- **Suggest next tasks**: "What should I work on next based on my current issues?"
- **Create issues from descriptions**: "Create an issue for implementing user authentication"
- **Get project insights**: "Give me an overview of my project's current status"
- **Prioritize work**: "Help me prioritize these open issues"

### Available MCP Tools

| Tool | Description |
|------|-------------|
| `create_issue` | Create new issues with AI-guided structure |
| `list_issues` | List and filter issues |
| `show_issue` | Get detailed issue information |
| `update_issue` | Update issue properties |
| `get_project_status` | Project health and metrics |
| `get_issue_context` | Rich context for AI analysis |

### Example AI Workflow

```
You: "Analyze my current project and suggest what I should work on next"

Claude: I'll check your project status and analyze your issues.
[Uses get_project_status and list_issues tools]

Based on your project, I can see you have:
- 3 critical priority issues 
- 2 issues currently blocked
- 1 issue in review

I recommend focusing on issue abc123 "Fix authentication bug" because:
- It's marked critical priority
- It's blocking 2 other issues
- Based on the description, it appears to be a focused fix

Would you like me to create a detailed plan for tackling this issue?
```

### MCP Commands

```bash
# Test MCP server
make test-mcp

# Rebuild after changes
make build-mcp

# Remove MCP server
make uninstall-mcp
```
