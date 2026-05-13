# claude-code-handoff

A Claude Code [Stop hook](https://docs.claude.com/en/docs/claude-code/hooks) + [statusline](https://docs.claude.com/en/docs/claude-code/statusline) + [skill](https://docs.claude.com/en/docs/claude-code/skills) trio that nudges you to run a `/wrap` ritual before `/exit`. Color-coded pills track how full your context is, escalating from light-yellow → orange → volcano-red as it fills. Each warning fires up to 3 times per threshold — once is easy to miss.

Claude Code's `/wrap` ritual — closing out a session by flushing the next-fresh-session-friendly state back to disk — is easy to forget after a long debugging stretch, especially when `/compact` resets your sense of how full context is. This is a small, opinionated nag layer that fixes that.

## What's in the repo

Three components that work together:

| Component | When it appears | What it does |
|---|---|---|
| **Stop hook** (`.claude/scripts/stop-hook-wrap-reminder.sh`) | After each assistant turn when a threshold is crossed | "Moment of attention" — bright colored pill in the terminal output |
| **Statusline** (`.claude/scripts/statusline.sh`) | Always visible at the bottom of the Claude Code UI | "Ambient awareness" — persistent pill that re-renders every prompt |
| **/wrap skill** (`.claude/skills/wrap.md`) | When you type `/wrap` | Walks the actual end-of-session ritual: survey what changed, propose updates, apply on approval |

The hook gets your attention at the moment context crosses a threshold; the statusline keeps the state visible so you can't tune it out; the skill walks the actual ritual when you're ready.

## The Stop hook

Fires at the end of every assistant turn. Prints a color-coded pill in your terminal when any of the following first becomes true:

| Trigger | Pill | Message |
|---|---|---|
| Context ≥ 40% | light yellow, bold black text | `💡 Context X% · consider /wrap before /exit` |
| Context ≥ 65% | orange, bold black text | `⚠️ Context X% · /wrap soon or you'll hit compaction` |
| Context ≥ 85% | volcano red, bold white text | `🚨 Context X% · /wrap NOW` |
| Edit/Write on a tracked file path | teal, bold black text | `📝 Tracked files edited this session — /wrap before /exit to update <STATUS_FILE_REL>` |

Each warning fires up to **3 times at its threshold** — after that the level goes silent for the rest of the session. Escalating to a higher tier (e.g. 50% → 70%) starts the new tier fresh at count 1; lower tiers don't double-fire.

State is tracked per-session at `~/.claude/state/claude-stop-hook-<session_id>.state` and includes the per-level fire counts plus a cached transcript-scan result so the expensive `jq` scan only runs until the first detection.

## The statusline

Always-visible at the bottom of the Claude Code UI. Same color tiers as the hook, plus a persistent action message keyed to the current context %:

```
alice@laptop:~/code/example  main ·  ctx:50% · 💡 /wrap before /exit  · Opus 4.7
```

Unlike the hook (which prints once per threshold crossing and then scrolls off as you continue), the statusline re-renders on every prompt — so you can't miss the state by scrolling past it. The pill's color and message change as you fill up. Below 40%, the segment dims to `all clear` so the slot stays consistent.

## The /wrap skill

When you type `/wrap`, Claude walks an end-of-session checklist: surveys what changed via `git status` + transcript scan, detects mid-task handoffs, proposes updates to your session-state file / memory / docs one at a time for your approval, applies on confirmation. Designed as the bridge between sessions — what gets saved here is what the next fresh session picks up cold.

## What's opinionated (and what you'll probably want to tune)

A handful of things are baked in. All live as top-of-script variables; see **Customize**.

- **The thresholds (40 / 65 / 85)** — calibrated for typical Opus 4.7 sessions. Tune for your model (smaller context window = lower numbers) or task profile (heavy tool-output sessions fill faster = lower numbers).
- **The fire count (3)** — chosen so the cost of missing the first one is bounded but you're not getting nagged forever. Tune up if you're easily distracted; tune down if 3 feels like spam.
- **The tracked-files regex** — defaults to a Terraform/Packer/shell-script project (`*.tf`, `*.sh`, `*.pkr.hcl`, `documentation/*`). Edit for your stack.
- **The session-state file path** — defaults to `temp/status.md`. This is what the `/wrap` skill writes session state and progress notes into. Pick whatever convention fits your project.
- **The statusline display name/host** — the script uses `$USER` and `hostname -s` by default. If you want a Starship-style nickname (e.g. you display `alice@laptop` instead of `alice.lastname@something.local`), edit the `display_user` and `display_host` lines near the top of `statusline.sh`.

## How context % is computed

The hook and statusline both read `.context_window.used_percentage` from Claude Code's stdin payload — the same number the default statusline shows. The hook additionally falls back to a transcript byte heuristic (`bytes / 110000`) if the field is absent, but in practice the live number is always present.

The byte fallback overestimates because the transcript grows monotonically across `/compact`, while the actual context window resets. Keep the live path as the primary.

## Why we drop `grep -q` in the infra-edit scan

`set -o pipefail` + `grep -q` is a hidden footgun. `grep -q` early-exits on first match, sending SIGPIPE to the upstream `jq` (exit 141). With pipefail, the whole pipeline returns 141, the `if` branch fails, and the assignment inside it never runs. The fix: read jq's full output without `-q`. The short-circuit saved nearly nothing — jq still streams the whole transcript regardless; grep only sees the extracted file paths — and silently broke detection.

## Why `set -e` is deliberately omitted

The script runs `set -uo pipefail` but not `set -e`. A transient `jq` parse error mid-session should yield partial info (maybe skip the tracked-files detection for that turn) rather than abort the whole hook and block Claude's turn from completing. Each downstream branch handles its own failure mode with sensible defaults, so `set -e` would add brittleness without buying any safety.

## Portability

Tested on macOS. On Linux the BSD `date -j -f` / `stat -f` calls fall back silently; the only degradation is the tracked-files nudge potentially over-firing (can't detect session-state file mtime vs. session start, so treats it as un-modified). Hook and statusline stay functional.

## Installation

0. Install prerequisites. The hook and statusline both depend on `jq` (JSON parsing) and `bash`. On macOS: `brew install jq`. On Debian/Ubuntu: `sudo apt install jq`. `bash` is standard.

1. Clone this repo.

2. The components install differently:

   - **Stop hook + /wrap skill** — copy `.claude/` into your project's root (or merge with an existing `.claude/`). These are project-level — different projects can have different threshold settings, tracked-files regexes, etc.
   - **Statusline** — copy `.claude/scripts/statusline.sh` to `~/.claude/statusline.sh` so it applies to every Claude Code session globally. (Or keep it project-level if you prefer — just reference it from the project's `.claude/settings.json` instead of `~/.claude/settings.json`.)

3. Wire the Stop hook by creating or extending `.claude/settings.json` in your project:

   ```json
   {
     "$schema": "https://json.schemastore.org/claude-code-settings.json",
     "hooks": {
       "Stop": [
         {
           "hooks": [
             {
               "type": "command",
               "command": "bash .claude/scripts/stop-hook-wrap-reminder.sh",
               "timeout": 10
             }
           ]
         }
       ]
     }
   }
   ```

4. Wire the statusline by creating or extending `~/.claude/settings.json`:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "~/.claude/statusline.sh"
     }
   }
   ```

5. Make the statusline executable: `chmod +x ~/.claude/statusline.sh`.

6. Adjust the top-of-script variables in both scripts for your stack (see **Customize**).

7. Reload Claude Code via `/hooks` and `/statusline`, or restart the session.

Disable either piece any time by removing the corresponding block from `settings.json`, or set `"disableAllHooks": true` to silence the hook side wholesale.

## Customize

### Stop hook (`.claude/scripts/stop-hook-wrap-reminder.sh`)

| Variable | What it does |
|---|---|
| `CTX_THRESHOLD_LOW` | First-tier context % (default `40`) — light yellow pill |
| `CTX_THRESHOLD_MID` | Second-tier context % (default `65`) — orange pill |
| `CTX_THRESHOLD_HIGH` | Third-tier context % (default `85`) — volcano red pill |
| `TRACKED_FILES_REGEX` | `grep -E` pattern; file paths matching this trigger the tracked-files nudge |
| `STATUS_FILE_REL` | Path (relative to cwd) of the session-state file the nudge expects |

The "fire up to 3 times" count is the literal `< 3` in each `case` branch — search the file for `level1_count < 3` and adjust if you want a different ceiling.

If you change `STATUS_FILE_REL`, update the `/wrap` skill at `.claude/skills/wrap.md` to reference the same path — the skill's "what changed → where to put it" mapping is the human-readable side of the same convention.

### Statusline (`.claude/scripts/statusline.sh` or `~/.claude/statusline.sh`)

The color tiers and thresholds are copies of the hook's; keep them in sync or pick deliberately different values if you want the statusline to escalate earlier/later than the hook. Two display-only knobs:

| Variable | What it does |
|---|---|
| `display_user` | Shown in the `user@host` segment. Defaults to `$USER` — replace with a literal nickname if you want |
| `display_host` | Shown in the `user@host` segment. Defaults to `hostname -s` — replace with a literal name if you want |

Other things you might want to edit in either script:

- **Pill colors** — the RGB values in the `ctx_color` assignments. Defaults are calibrated for dark terminal themes; pick brighter values if you're on a light background.
- **Message strings** — the lines in each `case` branch and the tracked-files block. Reword if the defaults don't fit your project's idiom.

## Provenance

Built with Claude Code's help, reviewed and adapted by me. The script's institutional knowledge — SIGPIPE / `grep -q` interaction, BSD `date -j -f` strictness, deliberate `set -e` omission, multi-fire counter logic — emerged from real debugging and is preserved in the inline comments.

## License

MIT. See `LICENSE`.
