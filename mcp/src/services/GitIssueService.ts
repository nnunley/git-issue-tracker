import { spawn } from "child_process";
import { promisify } from "util";

/**
 * Result from executing a shell command
 */
export interface ShellResult {
  stdout: string;
  stderr: string;
  exitCode: number;
  command: string;
  args: string[];
}

/**
 * Parsed issue data from git-issue output
 */
export interface IssueData {
  id: string;
  hash: string;
  title: string;
  description?: string;
  state?: string;
  priority?: string;
  author?: string;
  created?: string;
  updated?: string;
  labels?: string[];
  assignee?: string;
}

/**
 * Service for executing git-issue shell commands and parsing results
 */
export class GitIssueService {
  private gitIssueBin: string;

  constructor(gitIssueBin: string = "git-issue") {
    this.gitIssueBin = gitIssueBin;
  }

  /**
   * Execute a git-issue command
   */
  async executeGitIssue(command: string, args: string[] = []): Promise<ShellResult> {
    return this.executeCommand(this.gitIssueBin, [command, ...args]);
  }

  /**
   * Execute a raw shell command
   */
  async executeCommand(command: string, args: string[] = []): Promise<ShellResult> {
    return new Promise((resolve, reject) => {
      const child = spawn(command, args, {
        stdio: ["ignore", "pipe", "pipe"],
        shell: false,
        cwd: process.cwd(),
        env: process.env,
      });

      let stdout = "";
      let stderr = "";

      child.stdout?.on("data", (data) => {
        stdout += data.toString();
      });

      child.stderr?.on("data", (data) => {
        stderr += data.toString();
      });

      child.on("close", (code) => {
        const result: ShellResult = {
          stdout: stdout.trim(),
          stderr: stderr.trim(),
          exitCode: code || 0,
          command,
          args,
        };

        if (code === 0) {
          resolve(result);
        } else {
          reject(new Error(`Command failed with exit code ${code}: ${stderr || stdout}`));
        }
      });

      child.on("error", (error) => {
        reject(new Error(`Failed to execute ${command}: ${error.message}`));
      });
    });
  }

  /**
   * Parse git-issue list output into structured data
   */
  parseIssueList(output: string): IssueData[] {
    const issues: IssueData[] = [];
    const lines = output.split("\n").filter(line => line.trim());

    for (const line of lines) {
      // Parse different git-issue output formats
      // Format: "HASH-PREFIX TITLE [STATE] [PRIORITY]"
      const match = line.match(/^([a-f0-9]+)\s+(.+?)(?:\s+\[([^\]]+)\])?(?:\s+\[([^\]]+)\])?$/);
      
      if (match) {
        const [, hash, title, state, priority] = match;
        issues.push({
          id: hash,
          hash,
          title: title.trim(),
          state,
          priority,
        });
      }
    }

    return issues;
  }

  /**
   * Parse git-issue show output into structured data
   */
  parseIssueShow(output: string): IssueData | null {
    const lines = output.split("\n");
    const issue: Partial<IssueData> = {};

    for (const line of lines) {
      const trimmed = line.trim();
      
      if (trimmed.startsWith("ID:")) {
        issue.id = trimmed.replace("ID:", "").trim();
        issue.hash = issue.id;
      } else if (trimmed.startsWith("Title:")) {
        issue.title = trimmed.replace("Title:", "").trim();
      } else if (trimmed.startsWith("State:")) {
        issue.state = trimmed.replace("State:", "").trim();
      } else if (trimmed.startsWith("Priority:")) {
        issue.priority = trimmed.replace("Priority:", "").trim();
      } else if (trimmed.startsWith("Author:")) {
        issue.author = trimmed.replace("Author:", "").trim();
      } else if (trimmed.startsWith("Created:")) {
        issue.created = trimmed.replace("Created:", "").trim();
      } else if (trimmed.startsWith("Description:")) {
        // Multi-line description handling
        const descIndex = lines.indexOf(line);
        const descLines = lines.slice(descIndex + 1);
        issue.description = descLines.join("\n").trim();
        break;
      }
    }

    return issue.id && issue.title ? issue as IssueData : null;
  }

  /**
   * Get current working directory git status
   */
  async getGitStatus(): Promise<{isGitRepo: boolean; branch?: string}> {
    try {
      const result = await this.executeCommand("git", ["branch", "--show-current"]);
      return {
        isGitRepo: true,
        branch: result.stdout.trim() || "main"
      };
    } catch {
      return { isGitRepo: false };
    }
  }

  /**
   * Check if git-issue is available
   */
  async checkGitIssueAvailable(): Promise<boolean> {
    try {
      await this.executeCommand(this.gitIssueBin, ["--version"]);
      return true;
    } catch {
      try {
        // Try with full path
        await this.executeCommand("git", ["issue", "--version"]);
        this.gitIssueBin = "git issue";
        return true;
      } catch {
        return false;
      }
    }
  }
}