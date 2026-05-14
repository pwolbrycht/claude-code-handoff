#!/usr/bin/env bash
# Stop hook for Claude Code. Each tier fires up to 3 times per session:
#   ctx >= CTX_THRESHOLD_LOW   -> light yellow pill  (default 40%)
#   ctx >= CTX_THRESHOLD_MID   -> orange pill        (default 65%)
#   ctx >= CTX_THRESHOLD_HIGH  -> volcano red pill   (default 85%)
# Plus a tracked-file nudge (also up to 3 times) if Edit/Write touched a path
# matching TRACKED_FILES_REGEX and STATUS_FILE_REL was not modified this session.
#
# Wired in .claude/settings.json under hooks.Stop.
# State per-session: ~/.claude/state/claude-stop-hook-<session_id>.state
# -e deliberately omitted: a transient jq parse error should yield partial
# info, not a blocked Claude turn.
set -uo pipefail

# --- Configurable knobs (top-of-script) -----------------------------------
# Files whose edits should trigger a wrap reminder. Adjust for your stack —
# defaults match a Terraform/Packer/shell-script project.
TRACKED_FILES_REGEX='\.(tf|sh)$|\.pkr\.hcl$|/documentation/'

# Path (relative to cwd) of the session-state file the /wrap ritual updates.
# If its mtime hasn't moved since session start, the tracked-files nudge fires.
STATUS_FILE_REL="temp/status.md"

# Context-fill thresholds. Calibrated for typical Opus 4.7 sessions; tune for
# model (smaller context window = lower numbers) or task profile (heavy
# tool-output sessions fill faster = lower numbers).
CTX_THRESHOLD_LOW=40
CTX_THRESHOLD_MID=65
CTX_THRESHOLD_HIGH=85
# --------------------------------------------------------------------------

payload=$(cat)
session_id=$(jq -r '.session_id // "unknown"' <<<"$payload")
transcript_path=$(jq -r '.transcript_path // empty' <<<"$payload")
cwd=$(jq -r '.cwd // "."' <<<"$payload")

mkdir -p "${HOME}/.claude/state"
state_file="${HOME}/.claude/state/claude-stop-hook-${session_id}.state"
last_level=0
level1_count=0
level2_count=0
level3_count=0
infra_count=0
infra_edited=no
# shellcheck disable=SC1090
[[ -f "$state_file" ]] && . "$state_file"

# Prefer the live ctx % from Claude Code's payload (same field the statusline uses).
# Fall back to a transcript-bytes heuristic if absent. The transcript grows
# monotonically across /compact, so the fallback overestimates after compaction.
ctx_pct=$(jq -r '.context_window.used_percentage // empty' <<<"$payload")
if [[ -z "$ctx_pct" ]]; then
  if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    bytes=$(stat -f%z "$transcript_path" 2>/dev/null || stat -c%s "$transcript_path" 2>/dev/null || echo 0)
    ctx_pct=$(( bytes / 110000 ))
  else
    ctx_pct=0
  fi
fi
ctx_pct=$(printf '%.0f' "$ctx_pct" 2>/dev/null || echo 0)

level=0
(( ctx_pct >= CTX_THRESHOLD_LOW ))  && level=1
(( ctx_pct >= CTX_THRESHOLD_MID ))  && level=2
(( ctx_pct >= CTX_THRESHOLD_HIGH )) && level=3

# Was the session-state file modified after session start?
status_md="${cwd}/${STATUS_FILE_REL}"
status_recent=no
if [[ -f "$status_md" && -n "$transcript_path" && -f "$transcript_path" ]]; then
  first_ts=$(jq -r 'select(.timestamp) | .timestamp' "$transcript_path" 2>/dev/null | head -1)
  if [[ -n "$first_ts" ]]; then
    # BSD date -j -f rejects the fractional-second + Z suffix (e.g. ...01.234Z), so strip to 19 chars.
    session_start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${first_ts:0:19}" +%s 2>/dev/null || echo 0)
    status_mtime=$(stat -f%m "$status_md" 2>/dev/null || stat -c%Y "$status_md" 2>/dev/null || echo 0)
    (( status_mtime > session_start_epoch )) && status_recent=yes
  fi
fi

# Detect Edit/Write on tracked files. Skip once the cache (infra_edited)
# says yes — that's a permanent decision for this session. Firing count
# is tracked separately via infra_count.
# Note: grep without -q is deliberate. With `set -o pipefail`, `grep -q` exits
# on first match and SIGPIPE'd jq returns 141, which flips the if-branch to
# false. Reading jq's full output (whose cost we already pay) avoids that.
if [[ "$infra_edited" == "no" && -n "$transcript_path" && -f "$transcript_path" ]]; then
  if jq -r 'select(.type == "assistant") | .message?.content?[]? | select(.type == "tool_use" and (.name == "Edit" or .name == "Write")) | .input?.file_path? // empty' "$transcript_path" 2>/dev/null \
       | grep -E "$TRACKED_FILES_REGEX" >/dev/null 2>&1; then
    infra_edited=yes
  fi
fi

# Pill styles — bold text on RGB backgrounds with space-padded content
# so the background extends past the text edges.
PILL_LOW=$'\033[1;30;48;2;255;235;130m'   # light yellow bg, black text
PILL_MID=$'\033[1;30;48;2;255;140;0m'     # orange bg, black text
PILL_HIGH=$'\033[1;97;48;2;180;30;30m'    # volcano red bg, white text
PILL_INFO=$'\033[1;30;48;2;72;161;192m'   # teal bg, black text (infra nudge)
N=$'\033[0m'

lines=()
case "$level" in
  1)
    if (( level1_count < 3 )); then
      lines+=("${PILL_LOW} 💡 Context ${ctx_pct}% · consider /wrap before /exit ${N}")
      level1_count=$((level1_count + 1))
    fi
    ;;
  2)
    if (( level2_count < 3 )); then
      lines+=("${PILL_MID} ⚠️  Context ${ctx_pct}% · /wrap soon or you'll hit compaction ${N}")
      level2_count=$((level2_count + 1))
    fi
    ;;
  3)
    if (( level3_count < 3 )); then
      lines+=("${PILL_HIGH} 🚨 Context ${ctx_pct}% · /wrap NOW ${N}")
      level3_count=$((level3_count + 1))
      # TODO(2.1.141): emit out-of-band nudge via `terminalSequence` field in
      # hook JSON output — window title (OSC 2), terminal bell, and/or desktop
      # notification (OSC 9). Holding until Anthropic documents the field's
      # exact schema (string vs object, per-capability syntax).
    fi
    ;;
esac

if [[ "$infra_edited" == "yes" && "$status_recent" == "no" && "$infra_count" -lt 3 ]]; then
  lines+=("${PILL_INFO} 📝 Tracked files edited this session — /wrap before /exit to update ${STATUS_FILE_REL} ${N}")
  infra_count=$((infra_count + 1))
fi

# last_level: persisted for diagnostic value (highest tier reached this session); not used for control flow.
(( level > last_level )) && last_level=$level
{
  echo "last_level=$last_level"
  echo "level1_count=$level1_count"
  echo "level2_count=$level2_count"
  echo "level3_count=$level3_count"
  echo "infra_count=$infra_count"
  echo "infra_edited=$infra_edited"
} > "$state_file"

if (( ${#lines[@]} > 0 )); then
  for line in "${lines[@]}"; do
    printf '%s\n' "$line" >&2
  done
  joined=$(printf '%s\n' "${lines[@]}" | sed -E $'s/\x1b\\[[0-9;]*m//g')
  jq -nc --arg m "$joined" '{systemMessage: $m}'
fi

exit 0
