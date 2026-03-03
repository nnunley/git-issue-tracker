# Git-Issue MCP Server

Model Context Protocol (MCP) server for git-issue-tracker, enabling AI-powered project management through Claude Code and other MCP clients.

## Overview

This MCP server wraps the git-issue-tracker shell scripts, providing:

- **AI-Enhanced Issue Management**: Let Claude analyze issue complexity, suggest priorities, and recommend next tasks
- **Smart Project Insights**: Get AI-powered project health assessments and progress tracking
- **Natural Language Interface**: Create and manage issues through conversational AI
- **Git-Native Storage**: All data remains in git notes - no external dependencies
- **Shell Script Foundation**: Reliable, battle-tested shell scripts underneath

## Architecture

```
AI Clients (Claude, etc.)
    ↓ MCP Protocol
MCP Server (Node.js/TypeScript) ← This project
    ↓ Shell Script Execution
git-issue-tracker Scripts (Bash)
    ↓ Git Commands  
Git Repository Storage (git notes)
```

## Installation

### Prerequisites

- Node.js 18+ 
- git-issue-tracker installed and in PATH
- Git repository (or XDG directory for standalone usage)

### Install

```bash
# From git-issue-tracker root directory
make install-mcp

# Or manually
cd mcp
npm install
npm run build
npm install --global
```

### Verify Installation

```bash
git-issue-mcp-server --version
which git-issue-mcp-server
```

## Configuration

### Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "git-issue": {
      "command": "git-issue-mcp-server"
    }
  }
}
```

### Other MCP Clients

The server runs on stdio transport and follows the MCP specification. Configure according to your client's documentation.

## Available Tools

### Core Issue Management

| Tool | Purpose | Example Usage |
|------|---------|---------------|
| `create_issue` | Create new issues | "Create an issue for user authentication" |
| `list_issues` | List/filter issues | "Show me all high priority open issues" |
| `show_issue` | Get issue details | "Show me details for issue abc123" |
| `update_issue` | Modify issues | "Mark issue abc123 as completed" |

### AI Analysis Tools

| Tool | Purpose | Example Usage |
|------|---------|---------------|
| `get_issue_context` | Rich data for AI analysis | "Analyze the complexity of issue abc123" |
| `get_project_status` | Project metrics | "What's my project's current health?" |

## Example Workflows

### Issue Analysis

```
You: "Analyze issue abc123 and tell me how complex it is"

Claude: I'll get the issue context and analyze it for you.
[Calls get_issue_context with issueId: "abc123"]

Based on the issue details, this appears to be a medium complexity task because:
- It touches 2 different modules (auth and UI)
- Has dependencies on the user management system  
- Requires both backend and frontend changes
- Similar issues in your project took 4-6 hours

I estimate this will take about 5 hours and recommend breaking it into these subtasks:
1. Backend API changes (2 hours)
2. Frontend integration (2 hours)  
3. Testing and edge cases (1 hour)

Would you like me to create these as separate issues?
```

### Project Planning

```
You: "What should I work on next?"

Claude: Let me check your current project status.
[Calls get_project_status and list_issues]

Based on your project state:
- You have 2 critical issues that are blocking other work
- 3 issues are currently in review and don't need immediate attention  
- 1 issue marked as blocked is waiting on external dependency

I recommend prioritizing issue def456 "Fix database connection pool" because:
- It's marked critical priority
- 2 other issues depend on it
- It's a focused backend fix that shouldn't take long

This will unblock the most other work. Would you like me to get more details about this issue?
```

## Development

### Project Structure

```
mcp/
├── src/
│   ├── index.ts              # Main MCP server
│   ├── services/
│   │   └── GitIssueService.ts # Shell script wrapper
│   └── tools/
│       └── ToolRegistry.ts    # MCP tool definitions
├── dist/                     # Built JavaScript
├── package.json
└── tsconfig.json
```

### Building

```bash
npm run build      # Compile TypeScript
npm run dev        # Watch mode
npm run test       # Run tests
npm run lint       # Check code style
```

### Adding New Tools

1. Add tool definition to `ToolRegistry.ts`:

```typescript
this.registerTool({
  name: "my_new_tool",
  description: "Description for AI clients",
  inputSchema: z.object({
    param: z.string()
  }),
  handler: async (args) => {
    const result = await this.gitIssueService.executeGitIssue("command", [args.param]);
    return { success: true, data: result.stdout };
  }
});
```

2. Rebuild and test:

```bash
npm run build
npm test
```

## Design Philosophy

### MCP Server Responsibilities

✅ **Data Retrieval**: Execute shell scripts, parse output  
✅ **Action Execution**: Create, update, delete operations  
✅ **Structured Output**: Format data for AI consumption  
✅ **Error Handling**: Graceful failure and recovery  

### Claude Code Responsibilities  

✅ **Analysis**: Complexity assessment, priority recommendations  
✅ **Planning**: Task breakdown, dependency identification  
✅ **Decision Making**: What to work on next, how to approach problems  
✅ **Content Generation**: Issue descriptions, documentation  

### Clean Separation

The MCP server doesn't try to do AI analysis - it provides rich, structured data that Claude Code can analyze effectively. This keeps the server focused and reliable while leveraging Claude's reasoning capabilities.

## Troubleshooting

### Common Issues

**"git-issue command not found"**
- Ensure git-issue-tracker is installed and in PATH
- Try `which git-issue` or `git issue --version`

**"MCP server not responding"**  
- Check Claude Desktop logs
- Verify server starts: `git-issue-mcp-server` (should wait for input)
- Test in git repository with existing issues

**"Tool execution failed"**
- Check current directory has git repository or XDG setup
- Verify git-issue commands work directly: `git issue list`
- Check server logs for specific error messages

### Debug Mode

```bash
# Run server with debug output
DEBUG=1 git-issue-mcp-server

# Test individual git-issue commands
git issue list --debug
```

## Contributing

This MCP server follows the same contribution guidelines as the main git-issue-tracker project. See the main README.md for details.

## License

MIT License - same as git-issue-tracker project.