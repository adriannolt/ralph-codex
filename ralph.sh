#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.sh [--tool amp|claude|codex] [--codex-mode suggest|auto-edit|full-auto] [--codex-runner cli|exec] [--codex-profile name] [max_iterations]

set -e

# Parse arguments
TOOL="amp"  # Default to amp for backwards compatibility
MAX_ITERATIONS=10
CODEX_MODE="${CODEX_MODE:-full-auto}"
CODEX_RUNNER="${CODEX_RUNNER:-cli}"
CODEX_PROFILE="${CODEX_PROFILE:-}"
CODEX_EXTRA_ARGS="${CODEX_EXTRA_ARGS:-}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --tool=*)
      TOOL="${1#*=}"
      shift
      ;;
    --codex-mode)
      CODEX_MODE="$2"
      shift 2
      ;;
    --codex-mode=*)
      CODEX_MODE="${1#*=}"
      shift
      ;;
    --codex-profile)
      CODEX_PROFILE="$2"
      shift 2
      ;;
    --codex-profile=*)
      CODEX_PROFILE="${1#*=}"
      shift
      ;;
    --codex-runner)
      CODEX_RUNNER="$2"
      shift 2
      ;;
    --codex-runner=*)
      CODEX_RUNNER="${1#*=}"
      shift
      ;;
    --codex-exec)
      CODEX_RUNNER="exec"
      shift
      ;;
    --codex-extra-args)
      CODEX_EXTRA_ARGS="$2"
      shift 2
      ;;
    --codex-extra-args=*)
      CODEX_EXTRA_ARGS="${1#*=}"
      shift
      ;;
    *)
      # Assume it's max_iterations if it's a number
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift
      ;;
  esac
done

# Validate tool choice
if [[ "$TOOL" != "amp" && "$TOOL" != "claude" && "$TOOL" != "codex" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'amp', 'claude', or 'codex'."
  exit 1
fi

# Validate Codex mode
if [[ "$TOOL" == "codex" ]]; then
  if [[ -z "$CODEX_PROFILE" ]]; then
    CODEX_PROFILE="ralph_workspace_write"
  fi
  if [[ "$CODEX_MODE" != "suggest" && "$CODEX_MODE" != "auto-edit" && "$CODEX_MODE" != "full-auto" ]]; then
    echo "Error: Invalid Codex mode '$CODEX_MODE'. Must be 'suggest', 'auto-edit', or 'full-auto'."
    exit 1
  fi
  if [[ "$CODEX_RUNNER" != "cli" && "$CODEX_RUNNER" != "exec" ]]; then
    echo "Error: Invalid Codex runner '$CODEX_RUNNER'. Must be 'cli' or 'exec'."
    exit 1
  fi
  if [[ "$CODEX_RUNNER" == "exec" && "$CODEX_MODE" == "auto-edit" ]]; then
    echo "Error: Codex runner 'exec' does not support 'auto-edit'. Use 'suggest' or 'full-auto'."
    exit 1
  fi
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"

# Archive previous run if branch changed
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")
  
  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    # Archive the previous run
    DATE=$(date +%Y-%m-%d)
    # Strip "ralph/" prefix from branch name for folder
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"
    
    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"
    
    # Reset progress file for new run
    echo "# Ralph Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

echo "Starting Ralph - Tool: $TOOL - Max iterations: $MAX_ITERATIONS"

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $i of $MAX_ITERATIONS ($TOOL)"
  echo "==============================================================="

  # Run the selected tool with the ralph prompt
  if [[ "$TOOL" == "amp" ]]; then
    OUTPUT=$(cat "$SCRIPT_DIR/prompt.md" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
  elif [[ "$TOOL" == "claude" ]]; then
    # Claude Code: use --dangerously-skip-permissions for autonomous operation, --print for output
    OUTPUT=$(claude --dangerously-skip-permissions --print < "$SCRIPT_DIR/CLAUDE.md" 2>&1 | tee /dev/stderr) || true
  else
    # Codex CLI: select autonomy mode and optional profile. Reads prompt from stdin.
    CODEX_ARGS=()
    if [[ "$CODEX_RUNNER" == "exec" ]]; then
      # codex exec supports full-auto; suggest is the default when omitted.
      if [[ "$CODEX_MODE" == "full-auto" ]]; then
        CODEX_ARGS+=(--full-auto)
      fi
    else
      if [[ "$CODEX_MODE" == "auto-edit" ]]; then
        CODEX_ARGS+=(--auto-edit)
      elif [[ "$CODEX_MODE" == "full-auto" ]]; then
        CODEX_ARGS+=(--full-auto)
      fi
    fi
    if [[ -n "$CODEX_PROFILE" ]]; then
      CODEX_ARGS+=(--profile "$CODEX_PROFILE")
    fi
    if [[ -n "$CODEX_EXTRA_ARGS" ]]; then
      read -r -a CODEX_EXTRA_ARRAY <<< "$CODEX_EXTRA_ARGS"
      CODEX_ARGS+=("${CODEX_EXTRA_ARRAY[@]}")
    fi
    if [[ "$CODEX_RUNNER" == "exec" ]]; then
      OUTPUT=$(cat "$SCRIPT_DIR/CODEX.md" | codex exec "${CODEX_ARGS[@]}" - 2>&1 | tee /dev/stderr) || true
    else
      OUTPUT=$(cat "$SCRIPT_DIR/CODEX.md" | codex "${CODEX_ARGS[@]}" 2>&1 | tee /dev/stderr) || true
    fi
  fi
  
  # Check for completion signal
  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "Ralph completed all tasks!"
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    exit 0
  fi
  
  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."
exit 1
