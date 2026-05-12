#!/usr/bin/env bash
# Stop hook for Claude Code. Fires once per escalation:
#   ctx > CTX_THRESHOLD_LOW   -> gentle red    (default 40%)
#   ctx > CTX_THRESHOLD_MID   -> bold red      (default 65%)
#   ctx > CTX_THRESHOLD_HIGH  -> bold red + reverse video alarm (default 85%)
# Plus a one-shot tracked-file nudge if Edit/Write touched a path matching
# TRACKED_FILES_REGEX and STATUS_FILE_REL was not modified this session.
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
infra_fired=no
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

# Detect Edit/Write on tracked files. Skip when state already says yes
# (cached) or we've already fired — both make a re-scan pointless.
# Note: grep without -q is deliberate. With `set -o pipefail`, `grep -q` exits
# on first match and SIGPIPE'd jq returns 141, which flips the if-branch to
# false. Reading jq's full output (whose cost we already pay) avoids that.
if [[ "$infra_edited" == "no" && "$infra_fired" == "no" \
      && -n "$transcript_path" && -f "$transcript_path" ]]; then
  if jq -r 'select(.type == "assistant") | .message?.content?[]? | select(.type == "tool_use" and (.name == "Edit" or .name == "Write")) | .input?.file_path? // empty' "$transcript_path" 2>/dev/null \
       | grep -E "$TRACKED_FILES_REGEX" >/dev/null 2>&1; then
    infra_edited=yes
  fi
fi

R=$'\033[1;91m'
# Bold red + reverse video. Blink (SGR 5) is silently ignored by many modern
# terminals (Ghostty etc.), which made level 3 indistinguishable from level 2.
B=$'\033[1;91;7m'
N=$'\033[0m'

lines=()
if (( level > last_level )); then
  case "$level" in
    1) lines+=("${R}💡 Context ${ctx_pct}% · consider /wrap before /exit${N}") ;;
    2) lines+=("${R}⚠️  Context ${ctx_pct}% · /wrap soon or you'll hit compaction${N}") ;;
    3) lines+=("${B}🚨 Context ${ctx_pct}% · /wrap NOW${N}") ;;
  esac
fi

if [[ "$infra_edited" == "yes" && "$status_recent" == "no" && "$infra_fired" == "no" ]]; then
  lines+=("${R}📝 Tracked files edited this session — /wrap before /exit to update ${STATUS_FILE_REL}${N}")
  infra_fired=yes
fi

(( level > last_level )) && last_level=$level
{
  echo "last_level=$last_level"
  echo "infra_fired=$infra_fired"
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
