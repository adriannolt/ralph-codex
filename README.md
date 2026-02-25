# Ralph

![Ralph](ralph.webp)

Ralph is an autonomous AI agent loop that repeatedly runs Codex CLI until all PRD items are complete. Each iteration is a fresh instance with clean context. Memory persists via git history, `progress.txt`, and `prd.json`.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

## Prerequisites

- [Codex CLI](https://help.openai.com/en/articles/11369540-codex-cli) installed and authenticated
- `jq` installed (`brew install jq` on macOS)
- A git repository for your project

## Setup

Copy Ralph into your project:

```bash
# From your project root
mkdir -p scripts/ralph
cp /path/to/ralph/ralph.sh scripts/ralph/
cp /path/to/ralph/CODEX.md scripts/ralph/CODEX.md

chmod +x scripts/ralph/ralph.sh
```

## Workflow (Codex)

### 1. Create a PRD

Write a detailed PRD for your feature. Keep each story small enough to finish in a single iteration.

### 2. Convert PRD to Ralph format

Create `prd.json` with user stories and `passes: false` for all items. See `prd.json.example` for the schema.

### 3. Run Ralph

```bash
./scripts/ralph/ralph.sh --tool codex --codex-profile ralph_workspace_write [max_iterations]
```

Default is 10 iterations.

Ralph will:
1. Create a feature branch (from PRD `branchName`)
2. Pick the highest priority story where `passes: false`
3. Implement that single story
4. Run quality checks (typecheck, tests)
5. Commit if checks pass
6. Update `prd.json` to mark story as `passes: true`
7. Append learnings to `progress.txt`
8. Repeat until all stories pass or max iterations reached

### 4. Choose Codex Mode (Optional)

Codex supports three approval modes. In this loop, `full-auto` is the default, but you can switch per run:

```bash
# Review-only (suggest mode): no automatic edits or commands
./scripts/ralph/ralph.sh --tool codex --codex-mode suggest --codex-profile ralph_workspace_write 5

# Auto-edit: edits files automatically, still asks before running commands
./scripts/ralph/ralph.sh --tool codex --codex-mode auto-edit --codex-profile ralph_workspace_write 10

# Full-auto: edits + commands inside a sandbox (default)
./scripts/ralph/ralph.sh --tool codex --codex-mode full-auto --codex-profile ralph_workspace_write 10
```

### 5. Sandbox + Approval Policies (Optional)

You can pass official Codex sandbox and approval flags via `--codex-extra-args`:

```bash
# Read-only, non-interactive (CI-style)
./scripts/ralph/ralph.sh --tool codex --codex-mode suggest --codex-extra-args "--sandbox read-only --ask-for-approval never" 5

# Workspace-write with on-request approvals (matches --full-auto default behavior)
./scripts/ralph/ralph.sh --tool codex --codex-mode full-auto --codex-extra-args "--sandbox workspace-write --ask-for-approval on-request" 10
```

### 6. Non-Interactive Runner (Optional)

Use `codex exec` for strictly non-interactive runs:

```bash
./scripts/ralph/ralph.sh --tool codex --codex-runner exec --codex-mode full-auto --codex-profile ralph_workspace_write 10
```

### 7. Profiles (Optional)

Create a default profile that limits writes to the project root, but allows autonomous reads and writes within the sandbox:

```toml
# ~/.codex/config.toml
[profiles.ralph_workspace_write]
approval_policy = "on-request"
sandbox_mode    = "workspace-write"
```

Then select it per run:

```bash
./scripts/ralph/ralph.sh --tool codex --codex-profile ralph_workspace_write 5
```

## Key Files

| File | Purpose |
|------|---------|
| `ralph.sh` | The bash loop that spawns fresh Codex CLI instances |
| `CODEX.md` | Prompt template for Codex CLI |
| `prd.json` | User stories with `passes` status (the task list) |
| `prd.json.example` | Example PRD format for reference |
| `progress.txt` | Append-only learnings for future iterations |
| `flowchart/` | Interactive visualization of how Ralph works |

## Critical Concepts

### Each Iteration = Fresh Context

Each iteration spawns a **new Codex instance** with clean context. The only memory between iterations is:
- Git history (commits from previous iterations)
- `progress.txt` (learnings and context)
- `prd.json` (which stories are done)

### Small Tasks

Each PRD item should be small enough to complete in one context window.

Right-sized stories:
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic
- Add a filter dropdown to a list

Too big (split these):
- "Build the entire dashboard"
- "Add authentication"
- "Refactor the API"

### AGENTS.md Updates Are Critical

After each iteration, Ralph updates the relevant `AGENTS.md` files with learnings. This is key because AI coding tools automatically read these files, so future iterations (and future human developers) benefit from discovered patterns, gotchas, and conventions.

Examples of what to add to AGENTS.md:
- Patterns discovered ("this codebase uses X for Y")
- Gotchas ("do not forget to update Z when changing W")
- Useful context ("the settings panel is in component X")

### Feedback Loops

Ralph only works if there are feedback loops:
- Typecheck catches type errors
- Tests verify behavior
- CI must stay green (broken code compounds across iterations)

### Browser Verification for UI Stories

Frontend stories must include "Verify in browser" in acceptance criteria. Codex should navigate to the page, interact with the UI, and confirm changes work.

### Stop Condition

When all stories have `passes: true`, Ralph outputs `<promise>COMPLETE</promise>` and the loop exits.

## Debugging

Check current state:

```bash
# See which stories are done
cat prd.json | jq '.userStories[] | {id, title, passes}'

# See learnings from previous iterations
cat progress.txt

# Check git history
git log --oneline -10
```

## Customizing the Prompt

After copying `CODEX.md` to your project, customize it for your project:
- Add project-specific quality check commands
- Include codebase conventions
- Add common gotchas for your stack

## Archiving

Ralph automatically archives previous runs when you start a new feature (different `branchName`). Archives are saved to `archive/YYYY-MM-DD-feature-name/`.

## Other Tools (Optional)

Ralph also supports Amp and Claude Code. See `prompt.md`, `CLAUDE.md`, and `ralph.sh` if you want to switch tools.

## References

- [Geoffrey Huntley's Ralph article](https://ghuntley.com/ralph/)
- [Codex CLI docs](https://help.openai.com/en/articles/11369540-codex-cli)
