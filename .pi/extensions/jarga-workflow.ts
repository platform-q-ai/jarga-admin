/**
 * Jarga Admin Workflow Extension — Enforces a TDD Red-Green-Refactor
 * development workflow as an interactive todo checklist in Pi.
 *
 * Adapted from jarga-commerce for the Phoenix/Elixir admin dashboard.
 *
 * The workflow has 16 steps:
 *  1. Understand the issue and plan approach               [PLAN]
 *  2. Write/update unit tests                               [RED]
 *  3. Write/update LiveView tests                           [RED]
 *  4. Ensure new/modified tests FAIL (RED)                  [RED]
 *  5. Implement context/domain layer (GREEN)                [GREEN]
 *  6. Implement LiveView/controllers (GREEN)                [GREEN]
 *  7. Ensure all tests PASS (GREEN)                         [GREEN]
 *  8. Refactor (clean code, performance, security)          [REFACTOR]
 *  9. Ensure tests still PASS (GREEN)                       [GREEN]
 * 10. Run `mix precommit` (compile, format, test)           [CI/CD]
 * 11. Commit                                                [CI/CD]
 * 12. Push                                                  [CI/CD]
 * 13. Create PR                                             [CI/CD]
 * 14. Dispatch reviewers in parallel (arch, sec, perf)      [REVIEW]
 * 15. Fix all valid review concerns and push                [REVIEW]
 * 16. Merge, close issue, pick next issue, reset workflow   [CI/CD]
 *
 * Features:
 * - `/workflow` command opens an interactive checklist UI
 * - `workflow` tool lets the LLM check/uncheck/reset/query steps
 * - `workflow` tool accepts an optional `issue` param to set/clear the active issue
 * - Widget above editor shows current progress + active issue at a glance
 * - Blocks git commit if RED/GREEN/REFACTOR steps aren't done
 * - Blocks git push if commit step isn't done
 * - Injects workflow awareness + step-specific guidance into system prompt
 *   (every step mentions the active issue by number and title)
 * - On agent_end: fires a follow-up nudge when all 16 steps are done,
 *   telling the agent exactly what to do next (close issue, pick next, reset)
 *   Toggle with /workflow-nudge or Ctrl+Shift+N (default: ON)
 * - State persists across session restarts via tool result details
 */

import { StringEnum } from "@mariozechner/pi-ai";
import type { ExtensionAPI, ExtensionContext, Theme } from "@mariozechner/pi-coding-agent";
import { isToolCallEventType } from "@mariozechner/pi-coding-agent";
import { matchesKey, Text, truncateToWidth } from "@mariozechner/pi-tui";
import { Type } from "@sinclair/typebox";

// ─── Workflow definition ───────────────────────────────────────────────

interface WorkflowStep {
	id: number;
	label: string;
	phase: "plan" | "red" | "green" | "refactor" | "review" | "ci";
	done: boolean;
}

/** The active GitHub issue being worked on this cycle. */
interface ActiveIssue {
	number: number;
	title: string;
}

const WORKFLOW_TEMPLATE: Omit<WorkflowStep, "done">[] = [
	{ id: 1,  label: "Understand the issue and plan approach",              phase: "plan"     },
	{ id: 2,  label: "Write/update unit tests",                             phase: "red"      },
	{ id: 3,  label: "Write/update LiveView tests",                         phase: "red"      },
	{ id: 4,  label: "Ensure new/modified tests FAIL (RED)",                phase: "red"      },
	{ id: 5,  label: "Implement context/domain layer (GREEN)",              phase: "green"    },
	{ id: 6,  label: "Implement LiveView/controllers (GREEN)",              phase: "green"    },
	{ id: 7,  label: "Ensure all tests PASS (GREEN)",                       phase: "green"    },
	{ id: 8,  label: "Refactor (clean code, performance, security)",        phase: "refactor" },
	{ id: 9,  label: "Ensure tests still PASS (GREEN)",                     phase: "green"    },
	{ id: 10, label: "Run `mix precommit`",                                 phase: "ci"       },
	{ id: 11, label: "Commit",                                              phase: "ci"       },
	{ id: 12, label: "Push",                                                phase: "ci"       },
	{ id: 13, label: "Create PR",                                           phase: "ci"       },
	{ id: 14, label: "Dispatch reviewers in parallel (architecture-reviewer, security-reviewer and performance-reviewer sub agents)", phase: "review"   },
	{ id: 15, label: "Fix all valid review concerns and push",              phase: "review"   },
	{ id: 16, label: "Merge, close issue, pick next issue, reset workflow", phase: "ci"       },
];

function freshSteps(): WorkflowStep[] {
	return WORKFLOW_TEMPLATE.map((s) => ({ ...s, done: false }));
}

// ─── Tool details shape (for state persistence) ───────────────────────

interface WorkflowDetails {
	action: "status" | "check" | "uncheck" | "reset" | "skip" | "set_issue" | "clear_issue";
	steps: WorkflowStep[];
	activeIssue?: ActiveIssue;
	error?: string;
}

// ─── Phase colors ─────────────────────────────────────────────────────

function phaseColor(phase: string, theme: Theme): (t: string) => string {
	switch (phase) {
		case "plan":     return (t) => theme.fg("accent",  t);
		case "red":      return (t) => theme.fg("error",   t);
		case "green":    return (t) => theme.fg("success", t);
		case "refactor": return (t) => theme.fg("warning", t);
		case "review":   return (t) => theme.fg("muted",   t);
		case "ci":       return (t) => theme.fg("accent",  t);
		default:         return (t) => t;
	}
}

function phaseLabel(phase: string): string {
	switch (phase) {
		case "plan":     return "PLAN";
		case "red":      return "RED";
		case "green":    return "GREEN";
		case "refactor": return "REFACTOR";
		case "review":   return "REVIEW";
		case "ci":       return "CI/CD";
		default:         return phase;
	}
}

// ─── Interactive checklist component ──────────────────────────────────

class WorkflowChecklist {
	private steps: WorkflowStep[];
	private activeIssue: ActiveIssue | undefined;
	private theme: Theme;
	private onClose: (steps: WorkflowStep[]) => void;
	private selected: number = 0;
	private cachedWidth?: number;
	private cachedLines?: string[];

	constructor(
		steps: WorkflowStep[],
		activeIssue: ActiveIssue | undefined,
		theme: Theme,
		onClose: (steps: WorkflowStep[]) => void,
	) {
		this.steps = steps.map((s) => ({ ...s }));
		this.activeIssue = activeIssue;
		this.theme = theme;
		this.onClose = onClose;
	}

	handleInput(data: string): void {
		if (matchesKey(data, "escape") || matchesKey(data, "ctrl+c")) {
			this.onClose(this.steps);
			return;
		}
		if (matchesKey(data, "up") || data === "k") {
			this.selected = Math.max(0, this.selected - 1);
			this.invalidate();
			return;
		}
		if (matchesKey(data, "down") || data === "j") {
			this.selected = Math.min(this.steps.length - 1, this.selected + 1);
			this.invalidate();
			return;
		}
		if (matchesKey(data, "return") || data === " " || data === "x") {
			this.steps[this.selected].done = !this.steps[this.selected].done;
			this.invalidate();
			return;
		}
		if (data === "r" || data === "R") {
			this.steps.forEach((s) => (s.done = false));
			this.invalidate();
			return;
		}
	}

	render(width: number): string[] {
		if (this.cachedLines && this.cachedWidth === width) return this.cachedLines;

		const th = this.theme;
		const lines: string[] = [];

		lines.push("");
		const title = th.fg("accent", th.bold(" Jarga Admin Dev Workflow "));
		const bar = th.fg("borderMuted", "─".repeat(3)) + title + th.fg("borderMuted", "─".repeat(Math.max(0, width - 29)));
		lines.push(truncateToWidth(bar, width));
		lines.push(truncateToWidth(`  ${th.fg("dim", "Plan → TDD Red → Green → Refactor → Review → CI/CD")}`, width));

		if (this.activeIssue) {
			lines.push(truncateToWidth(
				`  ${th.fg("accent", th.bold(`Issue #${this.activeIssue.number}`))} ${th.fg("muted", this.activeIssue.title)}`,
				width,
			));
		}
		lines.push("");

		const done  = this.steps.filter((s) => s.done).length;
		const total = this.steps.length;
		const pct   = Math.round((done / total) * 100);
		const barLen = Math.min(30, width - 20);
		const filled = Math.round((done / total) * barLen);
		const progressBar = th.fg("success", "█".repeat(filled)) + th.fg("dim", "░".repeat(barLen - filled));
		lines.push(truncateToWidth(`  ${progressBar} ${th.fg("muted", `${done}/${total} (${pct}%)`)}`, width));
		lines.push("");

		let lastPhase = "";
		for (let i = 0; i < this.steps.length; i++) {
			const step = this.steps[i];
			if (step.phase !== lastPhase) {
				lastPhase = step.phase;
				const colorFn = phaseColor(step.phase, th);
				lines.push(truncateToWidth(`  ${colorFn(th.bold(phaseLabel(step.phase)))}`, width));
			}
			const isSel   = i === this.selected;
			const check   = step.done ? th.fg("success", "✓") : th.fg("dim", "○");
			const num     = th.fg("accent", `${step.id.toString().padStart(2)}.`);
			const text    = step.done ? th.fg("dim", step.label) : th.fg("text", step.label);
			const pointer = isSel ? th.fg("accent", "▸ ") : "  ";
			lines.push(truncateToWidth(`  ${pointer}${check} ${num} ${text}`, width));
		}

		lines.push("");
		lines.push(truncateToWidth(`  ${th.fg("dim", "↑↓ navigate  ·  Enter/Space toggle  ·  R reset  ·  Esc close")}`, width));
		lines.push("");

		this.cachedWidth  = width;
		this.cachedLines  = lines;
		return lines;
	}

	invalidate(): void {
		this.cachedWidth  = undefined;
		this.cachedLines  = undefined;
	}
}

// ─── Extension entry point ────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
	let steps: WorkflowStep[]        = freshSteps();
	let activeIssue: ActiveIssue | undefined = undefined;
	let autoComplete                  = false;
	let completionNudgeEnabled        = true;

	/** True when all steps were complete at the end of the previous agent
	 *  turn — used to fire the completion nudge exactly once per cycle. */
	let completionNudgeFired = false;

	// ── State reconstruction ──────────────────────────────────────────

	const reconstructState = (ctx: ExtensionContext) => {
		steps       = freshSteps();
		activeIssue = undefined;

		const entries = ctx.sessionManager.getBranch();
		let lastToolResultIdx = -1;
		let lastAppendIdx     = -1;

		for (let i = 0; i < entries.length; i++) {
			const entry = entries[i];
			if (entry.type === "message") {
				const msg = entry.message;
				if (msg.role === "toolResult" && msg.toolName === "workflow") {
					const details = msg.details as WorkflowDetails | undefined;
					if (details?.steps) {
						steps       = details.steps.map((s) => ({ ...s }));
						activeIssue = details.activeIssue;
						lastToolResultIdx = i;
					}
				}
			}
			if (entry.type === "custom" && entry.customType === "workflow-state") {
				lastAppendIdx = i;
			}
		}

		if (lastAppendIdx > lastToolResultIdx) {
			const entry = entries[lastAppendIdx];
			if (entry.type === "custom" && entry.data?.steps) {
				steps       = (entry.data.steps as WorkflowStep[]).map((s) => ({ ...s }));
				activeIssue = entry.data.activeIssue as ActiveIssue | undefined;
			}
		}

		// Don't re-fire the nudge for an already-complete cycle on resume
		completionNudgeFired = steps.every((s) => s.done);

		updateWidget(ctx);
	};

	pi.on("session_start",  async (_event, ctx) => reconstructState(ctx));
	pi.on("session_switch", async (_event, ctx) => reconstructState(ctx));
	pi.on("session_fork",   async (_event, ctx) => reconstructState(ctx));
	pi.on("session_tree",   async (_event, ctx) => reconstructState(ctx));

	// ── Widget ────────────────────────────────────────────────────────

	const updateWidget = (ctx: ExtensionContext) => {
		const done  = steps.filter((s) => s.done).length;
		const total = steps.length;
		if (done === 0 && !activeIssue) { ctx.ui.setWidget("workflow", undefined); return; }

		const pct     = Math.round((done / total) * 100);
		const current = steps.find((s) => !s.done);
		const currentInfo = current
			? `→ Step ${current.id}: ${current.label} [${phaseLabel(current.phase)}]`
			: "✓ Workflow complete!";

		ctx.ui.setWidget("workflow", (_tui, theme) => {
			const barLen = 15;
			const filled = Math.round((done / total) * barLen);
			const bar =
				theme.fg("success", "█".repeat(filled)) +
				theme.fg("dim",    "░".repeat(barLen - filled));

			const issuePart = activeIssue
				? theme.fg("accent", theme.bold(` #${activeIssue.number}`)) +
				  theme.fg("dim", ` ${activeIssue.title.slice(0, 40)}${activeIssue.title.length > 40 ? "…" : ""} `)
				: " ";

			const line =
				theme.fg("accent", theme.bold("Workflow")) +
				issuePart +
				bar +
				theme.fg("muted", ` ${done}/${total} (${pct}%) `) +
				theme.fg("dim", currentInfo);
			return new Text(line, 0, 0);
		});
	};

	// ── Guard: block git commit if steps 1-9 incomplete ──────────────

	pi.on("tool_call", async (event, _ctx) => {
		if (!isToolCallEventType("bash", event)) return;
		const cmd = event.input.command?.trim() ?? "";
		if (!/\bgit\s+commit\b/.test(cmd)) return;

		const incomplete = steps.filter((s) => s.id <= 10 && !s.done);
		if (incomplete.length === 0) return;

		const firstMissing = incomplete[0];
		return {
			block: true,
			reason: `Workflow violation: go back to Step ${firstMissing.id} "${firstMissing.label}" [${phaseLabel(firstMissing.phase)}] — complete all steps 1-10 before committing. Use the workflow tool to check off steps as you complete them.`,
		};
	});

	// ── Guard: block git push if step 11 (commit) not done ───────────

	pi.on("tool_call", async (event, _ctx) => {
		if (!isToolCallEventType("bash", event)) return;
		const cmd = event.input.command?.trim() ?? "";
		if (!/\bgit\s+push\b/.test(cmd)) return;

		const incomplete = steps.filter((s) => s.id <= 11 && !s.done);
		if (incomplete.length === 0) return;

		const firstMissing = incomplete[0];
		return {
			block: true,
			reason: `Workflow violation: go back to Step ${firstMissing.id} "${firstMissing.label}" [${phaseLabel(firstMissing.phase)}] — complete all steps 1-11 before pushing. Use the workflow tool to check off steps as you complete them.`,
		};
	});

	// ── System prompt injection ───────────────────────────────────────

	pi.on("before_agent_start", async (event, _ctx) => {
		const done    = steps.filter((s) => s.done).length;
		const total   = steps.length;
		const current = steps.find((s) => !s.done);

		// Issue context string used throughout the injection
		const issueCtx = activeIssue
			? `issue #${activeIssue.number}: "${activeIssue.title}"`
			: "the current issue";
		const issueNum = activeIssue ? `#${activeIssue.number}` : "<issue-number>";

		let injection = `\n\n## Active Development Workflow (Jarga Admin TDD Workflow)\n`;
		injection += `Progress: ${done}/${total} steps complete.\n`;

		if (activeIssue) {
			injection += `Active issue: #${activeIssue.number} — ${activeIssue.title}\n`;
		}

		if (current) {
			injection += `CURRENT STEP → ${current.id}. ${current.label} [${phaseLabel(current.phase)}]\n`;
			injection += `\nYou MUST follow the TDD Red-Green-Refactor process.\n`;
			injection += `Use the \`workflow\` tool to check off steps as you complete them.\n`;
			injection += `Do NOT skip ahead — complete steps in order.\n`;

			if (current.id === 1) {
				injection += `\n### Step 1: Plan\n`;
				injection += `You are implementing ${issueCtx}.\n`;
				injection += `This is a Phoenix 1.8 + LiveView admin dashboard app.\n`;
				injection += `Key modules:\n`;
				injection += `  - lib/jarga_admin/ — domain/context layer (API client, TabStore, UiSpec, Renderer)\n`;
				injection += `  - lib/jarga_admin_web/ — web layer (LiveViews, components, router)\n`;
				injection += `  - test/ — ExUnit tests (unit + LiveView integration)\n`;
				injection += `Read the issue, understand what's needed, identify which files to change.\n`;
				injection += `Check todo.md for broader project context.\n`;
				if (!activeIssue) {
					injection += `\n⚠️ No active issue set. Call workflow(action="set_issue", issueNumber=<n>, issueTitle="...") to record which GitHub issue this cycle is for.\n`;
					injection += `Run: gh issue list --repo platform-q-ai/jarga-admin --state open\n`;
				}
			}

			if (current.id === 2) {
				injection += `\n### Step 2: Unit Tests (RED)\n`;
				injection += `Working on ${issueCtx}.\n`;
				injection += `Write ExUnit tests for the context/domain layer:\n`;
				injection += `  - test/jarga_admin/ — unit tests for context modules\n`;
				injection += `  - Use Bypass for mocking HTTP calls to the Jarga Commerce API\n`;
				injection += `  - Test pure functions, data transformations, error handling\n`;
				injection += `Tests should FAIL at this point — we haven't implemented anything yet.\n`;
			}

			if (current.id === 3) {
				injection += `\n### Step 3: LiveView Tests (RED)\n`;
				injection += `Working on ${issueCtx}.\n`;
				injection += `Write Phoenix.LiveViewTest tests:\n`;
				injection += `  - test/jarga_admin_web/live/ — LiveView integration tests\n`;
				injection += `  - Use element/2, has_element/2 for assertions (never raw HTML)\n`;
				injection += `  - Test user interactions, form submissions, navigation\n`;
				injection += `  - Always reference DOM IDs set in templates\n`;
				injection += `Tests should FAIL at this point.\n`;
			}

			if (current.id === 4) {
				injection += `\n### Step 4: Verify Tests FAIL (RED)\n`;
				injection += `Working on ${issueCtx}.\n`;
				injection += `Run: mix test\n`;
				injection += `Confirm that the new tests you wrote in steps 2-3 FAIL.\n`;
				injection += `If they pass, the tests are not testing the right thing — fix them.\n`;
			}

			if (current.id === 5) {
				injection += `\n### Step 5: Context/Domain Layer (GREEN)\n`;
				injection += `Working on ${issueCtx}.\n`;
				injection += `Implement the domain logic in lib/jarga_admin/:\n`;
				injection += `  - Context modules (API client wrappers, data processing)\n`;
				injection += `  - Keep business logic separate from web concerns\n`;
				injection += `  - Use Req for HTTP calls to the backend API\n`;
				injection += `  - Handle errors gracefully with {:ok, result} / {:error, reason}\n`;
			}

			if (current.id === 6) {
				injection += `\n### Step 6: LiveView/Controllers (GREEN)\n`;
				injection += `Working on ${issueCtx}.\n`;
				injection += `Implement the web layer in lib/jarga_admin_web/:\n`;
				injection += `  - LiveViews with proper mount/handle_event/handle_info\n`;
				injection += `  - Use LiveView streams for collections\n`;
				injection += `  - Use <Layouts.app flash={@flash}> wrapper\n`;
				injection += `  - Use <.input> and <.form> components from core_components\n`;
				injection += `  - Add proper DOM IDs for testability\n`;
				injection += `  - Follow Tailwind CSS styling guidelines\n`;
			}

			if (current.id === 7) {
				injection += `\n### Step 7: Verify Tests PASS (GREEN)\n`;
				injection += `Working on ${issueCtx}.\n`;
				injection += `Run: mix test\n`;
				injection += `All tests (including the ones from steps 2-3) should now PASS.\n`;
				injection += `If any fail, fix the implementation — NOT the tests.\n`;
			}

			if (current.id === 8) {
				injection += `\n### Step 8: Refactor\n`;
				injection += `Working on ${issueCtx}.\n`;
				injection += `Focus on:\n`;
				injection += `  - Clean code: clear naming, small functions, single responsibility\n`;
				injection += `  - Performance: avoid N+1 queries, use streams for collections\n`;
				injection += `  - Security: validate inputs, no atom leaks from user input\n`;
				injection += `  - File size: keep files manageable\n`;
				injection += `  - Phoenix conventions: proper use of assigns, handle_params, etc.\n`;
			}

			if (current.id === 9) {
				injection += `\n### Step 9: Verify Tests Still PASS\n`;
				injection += `Working on ${issueCtx}.\n`;
				injection += `Run: mix test\n`;
				injection += `Ensure refactoring didn't break anything.\n`;
			}

			if (current.id === 10) {
				injection += `\n### Step 10: Run Precommit Checks\n`;
				injection += `Working on ${issueCtx}.\n`;
				injection += `Run: mix precommit\n`;
				injection += `This runs: compile --warning-as-errors, deps.unlock --unused, format, test\n`;
				injection += `Fix any warnings, formatting issues, or test failures.\n`;
			}

			if (current.id === 11) {
				injection += `\n### Step 11: Commit\n`;
				injection += `Working on ${issueCtx}.\n`;
				injection += `Stage and commit your changes with a descriptive commit message.\n`;
				injection += `Convention: use conventional commits (feat:, fix:, refactor:, etc.)\n`;
			}

			if (current.id === 12) {
				injection += `\n### Step 12: Push\n`;
				injection += `Working on ${issueCtx}.\n`;
				injection += `Push your branch to origin.\n`;
			}

			if (current.id === 13) {
				injection += `\n### Step 13: Create PR\n`;
				injection += `Working on ${issueCtx}.\n`;
				injection += `Create a PR via: \`gh pr create --title "..." --body "Closes #${activeIssue?.number ?? "<n>"}"\`\n`;
				injection += `Link the PR to the issue.\n`;
			}

			if (current.id === 14) {
				injection += `\n### Step 14: Dispatch Reviewer Subagents\n`;
				injection += `Working on ${issueCtx}.\n`;
				injection += `Use the \`subagent\` tool in parallel mode to dispatch all three reviewers simultaneously.\n`;
				injection += `Get the PR number first: \`gh pr view --json number -q .number\`\n`;
				injection += `Each reviewer will post inline GitHub review comments on the PR using the **GitHub GraphQL API** (\`gh api graphql\`).\n`;
				injection += `Reviewers MUST use GraphQL mutations (addPullRequestReview with threads array) — NEVER the REST API.\n`;
				injection += `\nExample:\n`;
				injection += "```json\n";
				injection += `{\n`;
				injection += `  "tasks": [\n`;
				injection += `    { "agent": "architecture-reviewer", "task": "Review PR #<pr-number> in platform-q-ai/jarga-admin for Phoenix architecture, context boundaries, LiveView patterns, and separation of concerns. This PR implements ${issueCtx}. Submit a formal GitHub PR review using gh api graphql (addPullRequestReview mutation with threads array) — inline comments only, never REST." },\n`;
				injection += `    { "agent": "security-reviewer",     "task": "Review PR #<pr-number> in platform-q-ai/jarga-admin for input validation, XSS risks, auth enforcement, atom leaks, and data exposure. This PR implements ${issueCtx}. Submit a formal GitHub PR review using gh api graphql (addPullRequestReview mutation with threads array) — inline comments only, never REST." },\n`;
				injection += `    { "agent": "performance-reviewer",  "task": "Review PR #<pr-number> in platform-q-ai/jarga-admin for N+1 patterns, memory leaks, unbounded assigns, LiveView process efficiency, and ETS usage. This PR implements ${issueCtx}. Submit a formal GitHub PR review using gh api graphql (addPullRequestReview mutation with threads array) — inline comments only, never REST." }\n`;
				injection += `  ]\n`;
				injection += `}\n`;
				injection += "```\n";
			}

			if (current.id === 15) {
				injection += `\n### Step 15: Fix Review Concerns\n`;
				injection += `Working on ${issueCtx}.\n`;
				injection += `Fetch all review threads using GraphQL:\n`;
				injection += "```bash\n";
				injection += `gh api graphql -f query='query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100){nodes{id isResolved comments(first:10){nodes{body author{login} path position}}}}}}}' -f owner="platform-q-ai" -f repo="jarga-admin" -F number=<pr-number>\n`;
				injection += "```\n";
				injection += `For each [arch], [critical], [high], [regression] comment:\n`;
				injection += `  1. Assess if the concern is valid\n`;
				injection += `  2. Fix valid concerns in the codebase\n`;
				injection += `  3. Reply to the thread using GraphQL (addPullRequestReviewThreadReply mutation)\n`;
				injection += `  4. Resolve the thread using GraphQL (resolveReviewThread mutation)\n`;
				injection += `Run mix precommit, then push the fixes.\n`;
				injection += `\n**Always** use \`gh api graphql\` for replying and resolving — never REST.\n`;
			}

			if (current.id === 16) {
				injection += `\n### Step 16: Merge, Close Issue, Pick Next\n`;
				if (activeIssue) {
					injection += `You have just completed all work for issue #${activeIssue.number}: "${activeIssue.title}".\n`;
				}
				injection += `1. Merge the PR: \`gh pr merge <pr-number> --squash --delete-branch\`\n`;
				injection += `2. Pull main: \`git checkout main && git pull origin main\`\n`;
				if (activeIssue) {
					injection += `3. Close the issue: \`gh issue close ${activeIssue.number} --repo platform-q-ai/jarga-admin\`\n`;
				} else {
					injection += `3. Close the issue: \`gh issue close ${issueNum} --repo platform-q-ai/jarga-admin\`\n`;
				}
				injection += `4. List open issues: \`gh issue list --repo platform-q-ai/jarga-admin --state open --limit 20\`\n`;
				injection += `5. Pick the oldest open issue (lowest number) and announce it\n`;
				injection += `6. Record the new issue: call \`workflow\` tool with action="set_issue", issueNumber=<n>, issueTitle="..."\n`;
				injection += `7. Reset the workflow: call \`workflow\` tool with action="reset"\n`;
				injection += `The next issue is now the subject of the new workflow cycle — begin Step 1 immediately.\n`;
			}
		} else {
			injection += `All ${total} steps complete for ${issueCtx}.\n`;
			injection += `Proceed to Step 16: merge, close the issue, pick the next one, and reset the workflow.\n`;
		}

		return { systemPrompt: event.systemPrompt + injection };
	});

	// ── Completion nudge: fires once when all steps are done ─────────

	// Tracks the checked-step count when we last nudged. We only re-nudge
	// when the agent makes progress (checks off a new step). This prevents
	// infinite nudge loops while still allowing the nudge to fire once per
	// step advancement across the entire workflow run.
	let lastNudgeDoneCount = -1;

	pi.on("agent_end", async (event, ctx) => {
		// Detect if the agent was aborted (ESC). The last assistant message
		// will have stopReason "aborted". Never send follow-ups after an
		// abort — respect the user's intent to stop.
		const lastMsg = event.messages[event.messages.length - 1];
		const wasAborted = event.messages.length === 0
			|| (lastMsg as any)?.stopReason === "aborted";
		if (wasAborted) return;

		// Don't nudge if the agent already has queued messages (it's continuing on its own).
		if (ctx.hasPendingMessages()) return;

		const allDone = steps.every((s) => s.done);

		// Auto-continue nudge for mid-cycle use (when /workflow-auto is on)
		if (autoComplete && !allDone) {
			const done    = steps.filter((s) => s.done).length;
			const total   = steps.length;
			const current = steps.find((s) => !s.done);

			// Only nudge when progress has been made (a new step was checked
			// off since the last nudge). Prevents infinite loops.
			if (done <= lastNudgeDoneCount) return;
			lastNudgeDoneCount = done;

			if (current && done > 0) {
				pi.sendUserMessage(
					`Workflow incomplete (${done}/${total}). Continue with the next incomplete step. ` +
					`Use the workflow tool to check off steps as you complete them. ` +
					`Respond with just the word DONE (no other text) when all ${total} steps are checked off.`,
					{ deliverAs: "followUp" },
				);
			}
			return;
		}

		// Auto-disable autoComplete when all steps are done.
		if (autoComplete && allDone) {
			autoComplete = false;
			ctx.ui.notify("Workflow auto-continue OFF — all steps complete", "success");
		}

		// Completion nudge: exactly once per cycle, fires when the last step is checked
		if (allDone && !completionNudgeFired && completionNudgeEnabled) {
			completionNudgeFired = true;

			const closeCmd = activeIssue
				? `gh issue close ${activeIssue.number} --repo platform-q-ai/jarga-admin`
				: `gh issue close <issue-number> --repo platform-q-ai/jarga-admin`;

			const issueLine = activeIssue
				? `You have completed all workflow steps for issue #${activeIssue.number}: "${activeIssue.title}". `
				: `You have completed all workflow steps. `;

			pi.sendUserMessage(
				issueLine +
				`Now do the following in order:\n` +
				`1. Merge the PR: \`gh pr merge --squash --delete-branch\`\n` +
				`2. Pull main: \`git checkout main && git pull origin main\`\n` +
				`3. Close the issue: \`${closeCmd}\`\n` +
				`4. List open issues: \`gh issue list --repo platform-q-ai/jarga-admin --state open --limit 20\`\n` +
				`5. Pick the lowest-numbered open issue and announce it — if no open issues exist, respond with just the word NONE\n` +
				`6. Record it: call the \`workflow\` tool with action="set_issue", issueNumber=<n>, issueTitle="..."\n` +
				`7. Reset the checklist: call the \`workflow\` tool with action="reset"\n` +
				`8. Begin Step 1 immediately: understand the new issue and plan the approach`,
				{ deliverAs: "followUp" },
			);
		}

		// Reset the guard when the workflow is no longer complete (e.g. after reset)
		if (!allDone) {
			completionNudgeFired = false;
		}
	});

	// ── Tool: LLM-callable workflow management ────────────────────────

	const WorkflowParams = Type.Object({
		action: StringEnum(["status", "check", "uncheck", "reset", "skip", "set_issue", "clear_issue"] as const),
		step:        Type.Optional(Type.Number({ description: "Step number 1-16 (required for check/uncheck/skip)" })),
		issueNumber: Type.Optional(Type.Number({ description: "GitHub issue number (required for set_issue)" })),
		issueTitle:  Type.Optional(Type.String({ description: "GitHub issue title (required for set_issue)" })),
	});

	pi.registerTool({
		name: "workflow",
		label: "Workflow",
		description: [
			"Manage the Jarga Admin TDD development workflow checklist.",
			"Actions:",
			"  status      — Show all steps and current progress",
			"  check       — Mark a step as done (requires step number)",
			"  uncheck     — Unmark a step (requires step number)",
			"  reset       — Reset all steps for a new cycle (keeps active issue until set_issue is called)",
			"  skip        — Mark a step as done even if previous steps are incomplete (requires step number)",
			"  set_issue   — Record the GitHub issue this cycle is for (requires issueNumber + issueTitle)",
			"  clear_issue — Clear the active issue (use before reset if starting fresh with no issue yet)",
			"",
			"Steps should be completed in order. The workflow enforces:",
			"  1:     PLAN phase (understand issue, plan approach)",
			"  2-4:   RED phase (write tests, verify they fail)",
			"  5-7:   GREEN phase (implement domain, web layer, verify tests pass)",
			"  8-9:   REFACTOR phase (clean up, verify tests still pass)",
			"  10-13: CI/CD (precommit, commit, push, PR)",
			"  14-15: REVIEW (dispatch reviewers, fix concerns)",
			"  16:    CI/CD (merge, close issue + pick next + reset)",
		].join("\n"),
		parameters: WorkflowParams,

		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const makeDetails = (
				action: WorkflowDetails["action"],
				error?: string,
			): WorkflowDetails => ({
				action,
				steps:       steps.map((s) => ({ ...s })),
				activeIssue: activeIssue ? { ...activeIssue } : undefined,
				error,
			});

			const formatStatus = (): string => {
				const done  = steps.filter((s) => s.done).length;
				const total = steps.length;
				let text = `Workflow: ${done}/${total} complete\n`;
				if (activeIssue) text += `Active issue: #${activeIssue.number} — ${activeIssue.title}\n`;
				text += "\n";
				let lastPhase = "";
				for (const s of steps) {
					if (s.phase !== lastPhase) {
						lastPhase = s.phase;
						text += `\n[${phaseLabel(s.phase)}]\n`;
					}
					text += `  [${s.done ? "x" : " "}] ${s.id}. ${s.label}\n`;
				}
				const current = steps.find((s) => !s.done);
				if (current) text += `\n→ Next: Step ${current.id} — ${current.label}`;
				else         text += `\n✓ All steps complete!`;
				return text;
			};

			switch (params.action) {
				case "status": {
					updateWidget(ctx);
					return { content: [{ type: "text", text: formatStatus() }], details: makeDetails("status") };
				}

				case "set_issue": {
					if (params.issueNumber === undefined || !params.issueTitle) {
						return {
							content: [{ type: "text", text: "Error: issueNumber and issueTitle are required for set_issue" }],
							details: makeDetails("set_issue", "issueNumber and issueTitle required"),
						};
					}
					activeIssue = { number: params.issueNumber, title: params.issueTitle };
					pi.appendEntry("workflow-state", { steps: steps.map((s) => ({ ...s })), activeIssue: { ...activeIssue } });
					updateWidget(ctx);
					return {
						content: [{ type: "text", text: `🎯 Active issue set: #${activeIssue.number} — ${activeIssue.title}` }],
						details: makeDetails("set_issue"),
					};
				}

				case "clear_issue": {
					activeIssue = undefined;
					pi.appendEntry("workflow-state", { steps: steps.map((s) => ({ ...s })), activeIssue: undefined });
					updateWidget(ctx);
					return {
						content: [{ type: "text", text: "Active issue cleared" }],
						details: makeDetails("clear_issue"),
					};
				}

				case "check": {
					if (params.step === undefined) {
						return { content: [{ type: "text", text: "Error: step number required" }], details: makeDetails("check", "step number required") };
					}
					const step = steps.find((s) => s.id === params.step);
					if (!step) {
						return { content: [{ type: "text", text: `Error: no step #${params.step}` }], details: makeDetails("check", `no step #${params.step}`) };
					}
					const prev = steps.filter((s) => s.id < step.id && !s.done);
					let warning = "";
					if (prev.length > 0) warning = `\n⚠️ Warning: ${prev.length} earlier step(s) still incomplete`;
					step.done = true;
					updateWidget(ctx);
					return {
						content: [{ type: "text", text: `✓ Step ${step.id} checked: ${step.label}${warning}` }],
						details: makeDetails("check"),
					};
				}

				case "uncheck": {
					if (params.step === undefined) {
						return { content: [{ type: "text", text: "Error: step number required" }], details: makeDetails("uncheck", "step number required") };
					}
					const step = steps.find((s) => s.id === params.step);
					if (!step) {
						return { content: [{ type: "text", text: `Error: no step #${params.step}` }], details: makeDetails("uncheck", `no step #${params.step}`) };
					}
					step.done = false;
					updateWidget(ctx);
					return {
						content: [{ type: "text", text: `○ Step ${step.id} unchecked: ${step.label}` }],
						details: makeDetails("uncheck"),
					};
				}

				case "skip": {
					if (params.step === undefined) {
						return { content: [{ type: "text", text: "Error: step number required" }], details: makeDetails("skip", "step number required") };
					}
					const step = steps.find((s) => s.id === params.step);
					if (!step) {
						return { content: [{ type: "text", text: `Error: no step #${params.step}` }], details: makeDetails("skip", `no step #${params.step}`) };
					}
					step.done = true;
					updateWidget(ctx);
					return {
						content: [{ type: "text", text: `⏭ Step ${step.id} skipped: ${step.label}` }],
						details: makeDetails("skip"),
					};
				}

				case "reset": {
					steps = freshSteps();
					// Keep activeIssue across reset so it can be used in the set_issue call right after
					completionNudgeFired = false;
					updateWidget(ctx);
					const issuePart = activeIssue
						? ` (still tracking issue #${activeIssue.number} — call set_issue once you have picked the next one)`
						: "";
					return {
						content: [{ type: "text", text: `Workflow reset — all ${steps.length} steps cleared for new cycle${issuePart}` }],
						details: makeDetails("reset"),
					};
				}

				default:
					return {
						content: [{ type: "text", text: `Unknown action: ${params.action}` }],
						details: makeDetails("status", `unknown action: ${params.action}`),
					};
			}
		},

		renderCall(args, theme) {
			let text = theme.fg("toolTitle", theme.bold("workflow ")) + theme.fg("muted", args.action);
			if (args.step !== undefined)        text += ` ${theme.fg("accent", `#${args.step}`)}`;
			if (args.issueNumber !== undefined) text += ` ${theme.fg("accent", `#${args.issueNumber}`)}`;
			if (args.issueTitle)               text += ` ${theme.fg("dim", args.issueTitle)}`;
			return new Text(text, 0, 0);
		},

		renderResult(result, { expanded }, theme) {
			const details = result.details as WorkflowDetails | undefined;
			if (!details) {
				const text = result.content[0];
				return new Text(text?.type === "text" ? text.text : "", 0, 0);
			}
			if (details.error) return new Text(theme.fg("error", `Error: ${details.error}`), 0, 0);

			const done  = details.steps.filter((s) => s.done).length;
			const total = details.steps.length;
			const pct   = Math.round((done / total) * 100);

			switch (details.action) {
				case "set_issue": {
					const msg = result.content[0];
					return new Text(
						theme.fg("accent", "🎯 ") + theme.fg("muted", msg?.type === "text" ? msg.text : ""),
						0, 0,
					);
				}
				case "clear_issue":
					return new Text(theme.fg("dim", "Issue cleared"), 0, 0);

				case "status": {
					let text = theme.fg("muted", `${done}/${total} (${pct}%)`);
					if (details.activeIssue) {
						text += theme.fg("accent", ` #${details.activeIssue.number}`);
					}
					const current = details.steps.find((s) => !s.done);
					if (current) {
						const colorFn = phaseColor(current.phase, theme);
						text += ` → ${colorFn(phaseLabel(current.phase))} Step ${current.id}`;
					} else {
						text += " " + theme.fg("success", "✓ Complete!");
					}
					if (expanded) {
						let lastPhase = "";
						for (const s of details.steps) {
							if (s.phase !== lastPhase) {
								lastPhase = s.phase;
								const colorFn = phaseColor(s.phase, theme);
								text += `\n  ${colorFn(theme.bold(phaseLabel(s.phase)))}`;
							}
							const check = s.done ? theme.fg("success", "✓") : theme.fg("dim", "○");
							const label = s.done ? theme.fg("dim", s.label) : theme.fg("text", s.label);
							text += `\n  ${check} ${theme.fg("accent", `${s.id}.`)} ${label}`;
						}
					}
					return new Text(text, 0, 0);
				}
				case "check":
				case "skip": {
					const msg = result.content[0];
					return new Text(theme.fg("success", "✓ ") + theme.fg("muted", msg?.type === "text" ? msg.text : ""), 0, 0);
				}
				case "uncheck": {
					const msg = result.content[0];
					return new Text(theme.fg("warning", "○ ") + theme.fg("muted", msg?.type === "text" ? msg.text : ""), 0, 0);
				}
				case "reset":
					return new Text(theme.fg("warning", "↺ ") + theme.fg("muted", "Workflow reset"), 0, 0);
			}
		},
	});

	// ── Command: /workflow — interactive checklist ─────────────────────

	pi.registerCommand("workflow", {
		description: "Open the Jarga Admin TDD workflow checklist",
		handler: async (_args, ctx) => {
			if (!ctx.hasUI) {
				const done = steps.filter((s) => s.done).length;
				const issuePart = activeIssue ? ` | Issue #${activeIssue.number}` : "";
				ctx.ui.notify(`Workflow: ${done}/${steps.length} steps complete${issuePart}`, "info");
				return;
			}
			const updatedSteps = await ctx.ui.custom<WorkflowStep[]>((_tui, theme, _kb, done) => {
				return new WorkflowChecklist(steps, activeIssue, theme, (result) => done(result));
			});
			if (updatedSteps) {
				steps = updatedSteps;
				pi.appendEntry("workflow-state", { steps: steps.map((s) => ({ ...s })), activeIssue: activeIssue ? { ...activeIssue } : undefined });
				updateWidget(ctx);
			}
		},
	});

	// ── Shortcut: Ctrl+Shift+W ────────────────────────────────────────

	pi.registerShortcut("ctrl+shift+w", {
		description: "Open Jarga Admin workflow checklist",
		handler: async (ctx) => {
			if (!ctx.hasUI) return;
			const updatedSteps = await ctx.ui.custom<WorkflowStep[]>((_tui, theme, _kb, done) => {
				return new WorkflowChecklist(steps, activeIssue, theme, (result) => done(result));
			});
			if (updatedSteps) {
				steps = updatedSteps;
				pi.appendEntry("workflow-state", { steps: steps.map((s) => ({ ...s })), activeIssue: activeIssue ? { ...activeIssue } : undefined });
				updateWidget(ctx);
			}
		},
	});

	// ── Command: /workflow-auto ───────────────────────────────────────

	pi.registerCommand("workflow-auto", {
		description: "Toggle auto-continue: nudge agent to keep going until all workflow steps are done",
		handler: async (_args, ctx) => {
			autoComplete = !autoComplete;
			ctx.ui.notify(
				autoComplete
					? "Workflow auto-continue ON — agent will be nudged to complete all steps"
					: "Workflow auto-continue OFF",
				"info",
			);
		},
	});

	// ── Shortcut: Ctrl+Shift+A ────────────────────────────────────────

	pi.registerShortcut("ctrl+shift+a", {
		description: "Toggle workflow auto-continue",
		handler: async (ctx) => {
			autoComplete = !autoComplete;
			ctx.ui.notify(
				autoComplete
					? "Workflow auto-continue ON — agent will be nudged to complete all steps"
					: "Workflow auto-continue OFF",
				"info",
			);
		},
	});

	// ── Command: /workflow-nudge ──────────────────────────────────────

	pi.registerCommand("workflow-nudge", {
		description: "Toggle completion nudge: prompt agent to pick next issue when all steps are done",
		handler: async (_args, ctx) => {
			completionNudgeEnabled = !completionNudgeEnabled;
			ctx.ui.notify(
				completionNudgeEnabled
					? "Workflow completion nudge ON — agent will be prompted to pick next issue on cycle complete"
					: "Workflow completion nudge OFF — agent will stop after final step",
				"info",
			);
		},
	});

	// ── Shortcut: Ctrl+Shift+N ────────────────────────────────────────

	pi.registerShortcut("ctrl+shift+n", {
		description: "Toggle workflow completion nudge",
		handler: async (ctx) => {
			completionNudgeEnabled = !completionNudgeEnabled;
			ctx.ui.notify(
				completionNudgeEnabled
					? "Workflow completion nudge ON"
					: "Workflow completion nudge OFF",
				"info",
			);
		},
	});
}
