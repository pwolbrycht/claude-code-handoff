#!/usr/bin/env bash
# Claude Code statusline: full info + persistent action message keyed to ctx%.
# Wired in ~/.claude/settings.json under "statusLine" (or in a project's
# .claude/settings.json for per-project use).
set -uo pipefail

# --- Configurable knobs (top-of-script) -----------------------------------
# Keep these in sync with .claude/scripts/stop-hook-wrap-reminder.sh.
CTX_THRESHOLD_LOW=40
CTX_THRESHOLD_MID=65
CTX_THRESHOLD_HIGH=85
# --------------------------------------------------------------------------

payload=$(cat)
ctx_pct=$(jq -r '.context_window.used_percentage // 0' <<<"$payload")
ctx_pct=$(printf '%.0f' "$ctx_pct" 2>/dev/null || echo 0)
model=$(jq -r '.model.display_name // "Claude"' <<<"$payload")
effort=$(jq -r '.effort.level // ""' <<<"$payload")
cwd=$(jq -r '.workspace.current_dir // "."' <<<"$payload")
display_cwd="${cwd/#$HOME/~}"

# Git branch (cheap — reads .git/HEAD, no network)
branch=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null || echo "")
fi

# Display name + host (cosmetic; defaults to environment values).
# Override with literals like display_user="alice" if you want a custom prompt.
display_user="${USER}"
display_host="$(hostname -s 2>/dev/null || echo "")"

# Colors
green=$'\033[32m'
blue=$'\033[34m'
purple=$'\033[35m'
dim=$'\033[2m'
reset=$'\033[0m'

# Nerd Font branch glyph (U+E0A0 in UTF-8)
branch_glyph=$(printf '\xee\x82\xa0')

# Context tiers — colored backgrounds with action messages, same palette as the hook
if (( ctx_pct >= CTX_THRESHOLD_HIGH )); then
  ctx_color=$'\033[1;97;48;2;180;30;30m'
  action='🚨 /wrap NOW'
elif (( ctx_pct >= CTX_THRESHOLD_MID )); then
  ctx_color=$'\033[1;30;48;2;255;140;0m'
  action='⚠️  /wrap soon'
elif (( ctx_pct >= CTX_THRESHOLD_LOW )); then
  ctx_color=$'\033[1;30;48;2;255;235;130m'
  action='💡 /wrap before /exit'
else
  ctx_color=$'\033[2m'
  action='all clear'
fi

# Segments
user_host="${green}${display_user}@${display_host}${reset}"
path_seg="${blue}${display_cwd}${reset}"
branch_seg=""
[[ -n "$branch" ]] && branch_seg=" ${purple}${branch_glyph} ${branch}${reset}"
ctx_seg="${ctx_color} ctx:${ctx_pct}% · ${action} ${reset}"
model_seg="${dim}${model}${reset}"
effort_seg=""
[[ -n "$effort" ]] && effort_seg=" · ${dim}effort:${effort}${reset}"

printf '%s:%s%s · %s · %s%s' "$user_host" "$path_seg" "$branch_seg" "$ctx_seg" "$model_seg" "$effort_seg"
