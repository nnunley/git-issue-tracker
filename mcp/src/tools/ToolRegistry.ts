import { Tool } from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";
import { GitIssueService } from "../services/GitIssueService.js";

/**
 * Tool definition with schema validation
 */
export interface ToolDefinition<T = any> {
  name: string;
  description: string;
  inputSchema: z.ZodSchema<T>;
  handler: (args: T) => Promise<any>;
}

/**
 * Registry for all MCP tools that wrap git-issue functionality
 */
export class ToolRegistry {
  private tools: Map<string, ToolDefinition> = new Map();

  constructor(private gitIssueService: GitIssueService) {
    this.registerBuiltInTools();
  }

  /**
   * Register a tool
   */
  registerTool<T>(tool: ToolDefinition<T>): void {
    this.tools.set(tool.name, tool);
  }

  /**
   * Execute a tool by name
   */
  async executeTool(name: string, args: any): Promise<any> {
    const tool = this.tools.get(name);
    if (!tool) {
      throw new Error(`Unknown tool: ${name}`);
    }

    // Validate input with Zod
    const validatedArgs = tool.inputSchema.parse(args);
    
    // Execute the tool
    return await tool.handler(validatedArgs);
  }

  /**
   * Get all tool definitions for MCP protocol
   */
  getAllToolDefinitions(): Tool[] {
    return Array.from(this.tools.values()).map(tool => ({
      name: tool.name,
      description: tool.description,
      inputSchema: this.zodToJsonSchema(tool.inputSchema),
    }));
  }

  /**
   * Convert Zod schema to JSON Schema for MCP
   */
  private zodToJsonSchema(schema: z.ZodSchema): any {
    // Basic conversion - in production you'd use a library like zod-to-json-schema
    if (schema instanceof z.ZodObject) {
      const shape = schema.shape;
      const properties: any = {};
      const required: string[] = [];

      for (const [key, value] of Object.entries(shape)) {
        properties[key] = this.zodToJsonSchema(value as z.ZodSchema);
        if (!(value as any).isOptional()) {
          required.push(key);
        }
      }

      return {
        type: "object",
        properties,
        required: required.length > 0 ? required : undefined,
      };
    }

    if (schema instanceof z.ZodString) {
      return { type: "string" };
    }

    if (schema instanceof z.ZodNumber) {
      return { type: "number" };
    }

    if (schema instanceof z.ZodBoolean) {
      return { type: "boolean" };
    }

    if (schema instanceof z.ZodArray) {
      return {
        type: "array",
        items: this.zodToJsonSchema(schema.element),
      };
    }

    if (schema instanceof z.ZodEnum) {
      return {
        type: "string",
        enum: schema.options,
      };
    }

    return { type: "string" }; // Fallback
  }

  /**
   * Register built-in tools
   */
  private registerBuiltInTools(): void {
    // Issue management tools
    this.registerTool({
      name: "create_issue",
      description: "Create a new issue using git-issue",
      inputSchema: z.object({
        title: z.string().min(1, "Title is required"),
        description: z.string().optional(),
        priority: z.enum(["low", "medium", "high", "critical"]).optional(),
        state: z.enum(["open", "in-progress", "review", "done", "blocked"]).optional(),
        labels: z.array(z.string()).optional(),
      }),
      handler: async (args) => {
        const cmdArgs = [args.title];
        
        if (args.description) {
          cmdArgs.push("--description", args.description);
        }
        if (args.priority) {
          cmdArgs.push("--priority", args.priority);
        }
        if (args.state) {
          cmdArgs.push("--state", args.state);
        }
        if (args.labels && args.labels.length > 0) {
          cmdArgs.push("--labels", args.labels.join(","));
        }

        const result = await this.gitIssueService.executeGitIssue("add", cmdArgs);
        
        return {
          success: result.exitCode === 0,
          message: result.stdout,
          issueId: this.extractIssueId(result.stdout),
        };
      },
    });

    this.registerTool({
      name: "list_issues",
      description: "List issues with optional filtering",
      inputSchema: z.object({
        state: z.enum(["open", "in-progress", "review", "done", "blocked", "all"]).optional(),
        priority: z.enum(["low", "medium", "high", "critical"]).optional(),
        author: z.string().optional(),
        limit: z.number().min(1).max(100).optional(),
      }),
      handler: async (args) => {
        const cmdArgs: string[] = [];
        
        if (args.state && args.state !== "all") {
          cmdArgs.push("--state", args.state);
        }
        if (args.priority) {
          cmdArgs.push("--priority", args.priority);
        }
        if (args.author) {
          cmdArgs.push("--author", args.author);
        }
        if (args.limit) {
          cmdArgs.push("--limit", args.limit.toString());
        }

        const result = await this.gitIssueService.executeGitIssue("list", cmdArgs);
        const issues = this.gitIssueService.parseIssueList(result.stdout);
        
        return {
          issues,
          total: issues.length,
          filters: args,
        };
      },
    });

    this.registerTool({
      name: "show_issue",
      description: "Get detailed information about a specific issue",
      inputSchema: z.object({
        issueId: z.string().min(1, "Issue ID is required"),
      }),
      handler: async (args) => {
        const result = await this.gitIssueService.executeGitIssue("show", [args.issueId]);
        const issue = this.gitIssueService.parseIssueShow(result.stdout);
        
        if (!issue) {
          throw new Error(`Issue not found: ${args.issueId}`);
        }
        
        return {
          issue,
          rawOutput: result.stdout,
        };
      },
    });

    this.registerTool({
      name: "update_issue",
      description: "Update an existing issue",
      inputSchema: z.object({
        issueId: z.string().min(1, "Issue ID is required"),
        title: z.string().optional(),
        description: z.string().optional(),
        state: z.enum(["open", "in-progress", "review", "done", "blocked"]).optional(),
        priority: z.enum(["low", "medium", "high", "critical"]).optional(),
      }),
      handler: async (args) => {
        const cmdArgs = [args.issueId];
        
        if (args.title) {
          cmdArgs.push("--title", args.title);
        }
        if (args.description) {
          cmdArgs.push("--description", args.description);
        }
        if (args.state) {
          cmdArgs.push("--state", args.state);
        }
        if (args.priority) {
          cmdArgs.push("--priority", args.priority);
        }

        const result = await this.gitIssueService.executeGitIssue("edit", cmdArgs);
        
        return {
          success: result.exitCode === 0,
          message: result.stdout,
          issueId: args.issueId,
        };
      },
    });

    this.registerTool({
      name: "get_project_status",
      description: "Get overall project status and metrics",
      inputSchema: z.object({}),
      handler: async () => {
        const allIssues = await this.gitIssueService.executeGitIssue("list", []);
        const issues = this.gitIssueService.parseIssueList(allIssues.stdout);
        
        const gitStatus = await this.gitIssueService.getGitStatus();
        
        const statusCounts = issues.reduce((acc, issue) => {
          const state = issue.state || "open";
          acc[state] = (acc[state] || 0) + 1;
          return acc;
        }, {} as Record<string, number>);

        const priorityCounts = issues.reduce((acc, issue) => {
          const priority = issue.priority || "medium";
          acc[priority] = (acc[priority] || 0) + 1;
          return acc;
        }, {} as Record<string, number>);
        
        return {
          totalIssues: issues.length,
          statusBreakdown: statusCounts,
          priorityBreakdown: priorityCounts,
          gitStatus,
          projectHealth: this.calculateProjectHealth(statusCounts),
        };
      },
    });

    this.registerTool({
      name: "get_issue_context",
      description: "Get comprehensive context for issue analysis by Claude Code",
      inputSchema: z.object({
        issueId: z.string().min(1, "Issue ID is required"),
        includeRelated: z.boolean().default(true),
        includeProjectMetrics: z.boolean().default(true),
      }),
      handler: async (args) => {
        // Get the main issue
        const issueResult = await this.gitIssueService.executeGitIssue("show", [args.issueId]);
        const issue = this.gitIssueService.parseIssueShow(issueResult.stdout);
        
        if (!issue) {
          throw new Error(`Issue not found: ${args.issueId}`);
        }

        const context: any = {
          issue,
          analysisFramework: {
            complexityFactors: [
              "scope", 
              "technical_difficulty", 
              "dependencies", 
              "unknowns", 
              "integration_complexity"
            ],
            estimationGuidelines: "Consider similar issues, scope, and technical complexity",
            priorityFactors: ["business_impact", "user_impact", "technical_debt", "risk"],
          }
        };

        // Include related issues if requested
        if (args.includeRelated) {
          const allIssues = await this.gitIssueService.executeGitIssue("list", []);
          const allIssuesList = this.gitIssueService.parseIssueList(allIssues.stdout);
          
          context.relatedIssues = allIssuesList.filter(i => 
            i.id !== args.issueId && 
            (i.title.toLowerCase().includes(issue.title.toLowerCase().split(' ')[0]) ||
             i.state === issue.state)
          ).slice(0, 5);
        }

        // Include project metrics if requested
        if (args.includeProjectMetrics) {
          const allIssues = await this.gitIssueService.executeGitIssue("list", []);
          const issues = this.gitIssueService.parseIssueList(allIssues.stdout);
          
          context.projectMetrics = {
            totalIssues: issues.length,
            averageComplexity: "medium", // Could be calculated
            commonPatterns: this.identifyCommonPatterns(issues),
          };
        }

        return context;
      },
    });
  }

  /**
   * Extract issue ID from git-issue command output
   */
  private extractIssueId(output: string): string | null {
    const match = output.match(/([a-f0-9]{6,})/);
    return match ? match[1] : null;
  }

  /**
   * Calculate simple project health score
   */
  private calculateProjectHealth(statusCounts: Record<string, number>): string {
    const total = Object.values(statusCounts).reduce((sum, count) => sum + count, 0);
    if (total === 0) return "unknown";
    
    const done = statusCounts.done || 0;
    const blocked = statusCounts.blocked || 0;
    
    const completionRate = done / total;
    const blockedRate = blocked / total;
    
    if (completionRate > 0.8) return "excellent";
    if (completionRate > 0.6 && blockedRate < 0.1) return "good";
    if (blockedRate > 0.2) return "concerning";
    return "fair";
  }

  /**
   * Identify common patterns in issues for analysis context
   */
  private identifyCommonPatterns(issues: any[]): string[] {
    const patterns: string[] = [];
    
    // Find common title words
    const words = issues.flatMap(i => i.title.toLowerCase().split(' '));
    const wordCounts = words.reduce((acc, word) => {
      if (word.length > 3) {
        acc[word] = (acc[word] || 0) + 1;
      }
      return acc;
    }, {} as Record<string, number>);
    
    // Find frequently mentioned topics
    Object.entries(wordCounts)
      .filter(([_, count]) => (count as number) >= 2)
      .sort(([_, a], [__, b]) => (b as number) - (a as number))
      .slice(0, 3)
      .forEach(([word]) => patterns.push(`Frequent topic: ${word}`));
    
    return patterns;
  }
}