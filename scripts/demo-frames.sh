#!/usr/bin/env bash
# Drives the hook + statusline through each visual state for README screenshots.
# Feeds synthetic JSON payloads to the real scripts so what you see is exactly
# what Claude Code shows. Run from the repo root.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/.claude/scripts/stop-hook-wrap-reminder.sh"
STATUSLINE="$REPO_ROOT/.claude/scripts/statusline.sh"

# Use the real repo path as the displayed cwd so screenshots show
# ~/GitHub/claude-code-handoff and the git branch segment renders.
# The hook's temp/status.md probe stays "missing" as long as no real
# /wrap has run here; the dynamic NOW timestamp below guards the case
# where it has (file mtime would be older than session_start).
DEMO_CWD="$REPO_ROOT"
SANDBOX="$(mktemp -d)"
T_PLAIN="$SANDBOX/transcript-plain.jsonl"
T_TRACKED="$SANDBOX/transcript-tracked.jsonl"

NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

# Plain transcript: one assistant turn with no tool use. Used for frames where
# the teal "tracked file edited" nudge should NOT fire.
jq -nc --arg ts "$NOW_ISO" \
  '{type:"assistant", timestamp:$ts, message:{content:[{type:"text", text:"ok"}]}}' \
  >"$T_PLAIN"

# Tracked-edit transcript: Edit on a .sh path (matches TRACKED_FILES_REGEX).
# Used for the teal-nudge frame.
jq -nc --arg ts "$NOW_ISO" \
  '{type:"assistant", timestamp:$ts, message:{content:[{type:"tool_use", name:"Edit", input:{file_path:"/repo/infra/main.sh"}}]}}' \
  >"$T_TRACKED"

frame() {
  local label="$1" ctx="$2" session="$3" transcript="$4"
  # Fresh state per frame so per-tier counters start at 0.
  rm -f "$HOME/.claude/state/claude-stop-hook-${session}.state"

  printf '\n\033[1m── Frame: %s (ctx=%s%%) ──\033[0m\n\n' "$label" "$ctx"

  local payload
  payload=$(jq -nc \
    --arg sid "$session" \
    --arg tp "$transcript" \
    --arg cwd "$DEMO_CWD" \
    --argjson ctx "$ctx" \
    '{session_id:$sid, transcript_path:$tp, cwd:$cwd, context_window:{used_percentage:$ctx}}')
  # Hook pills go to stderr; discard the systemMessage JSON on stdout.
  bash "$HOOK" <<<"$payload" >/dev/null

  local sl_payload
  sl_payload=$(jq -nc \
    --arg cwd "$DEMO_CWD" \
    --argjson ctx "$ctx" \
    '{context_window:{used_percentage:$ctx}, model:{display_name:"Opus 4.7"}, workspace:{current_dir:$cwd}}')
  bash "$STATUSLINE" <<<"$sl_payload"
  printf '\n\n[press enter for next frame]'
  read -r
}

clear
echo "Demo: 5 frames for README screenshots. Resize terminal to ~120 cols first."
echo "Press enter to start."
read -r

frame "A — baseline (dim, all clear)"          30 demo-a "$T_PLAIN"
frame "C — yellow tier"                        50 demo-c "$T_PLAIN"
frame "E — orange tier"                        72 demo-e "$T_PLAIN"
frame "G — red tier"                           90 demo-g "$T_PLAIN"
frame "F — orange + teal (tracked-file nudge)" 72 demo-f "$T_TRACKED"

echo
echo "Done. Sandbox cwd was: $DEMO_CWD"
