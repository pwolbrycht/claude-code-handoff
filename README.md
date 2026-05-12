# claude-code-wrap-reminder

A Claude Code [Stop hook](https://docs.claude.com/en/docs/claude-code/hooks) + [skill](https://docs.claude.com/en/docs/claude-code/skills) that nudges you to run a `/wrap` ritual before `/exit`. Escalating reminders fire as context fills; a one-shot reminder fires the first time you edit tracked files in a session.

Claude Code's `/wrap` ritual — closing out a session by flushing the next-fresh-session-friendly state back to disk — is easy to forget after a long debugging stretch, especially when `/compact` resets your sense of how full context is. This is a small, opinionated nag layer that fixes that.

## What it does

A `Stop` hook runs at the end of every assistant turn. It prints a bright-red reminder in your terminal when **any** of the following first becomes true in a session:

| Trigger | Style | Message |
|---|---|---|
| Context ≥ 40% | red | `💡 Context X% · consider /wrap before /exit` |
| Context ≥ 65% | red bold | `⚠️ Context X% · /wrap soon or you'll hit compaction` |
| Context ≥ 85% | red bold + reverse | `🚨 Context X% · /wrap NOW` |
| Edit/Write on a tracked file path | red | `📝 Tracked files edited this session — /wrap before /exit to update <STATUS_FILE_REL>` |

Each condition fires **once per session**. A sentinel file at `~/.claude/state/claude-stop-hook-<session_id>.state` prevents nag-loops.

When you actually run `/wrap` (handled by the bundled skill at `.claude/skills/wrap.md`), Claude walks an end-of-session checklist: survey what changed, decide what to save to a session-state file vs. memory vs. documentation, propose changes one at a time for approval, apply on confirmation.

## What's opinionated (and what you'll probably want to tune)

Three things are baked in:

- **The thresholds (40 / 65 / 85)** — calibrated for typical Opus 4.7 sessions. Tune for your model (smaller context window = lower numbers) or task profile (heavy tool-output sessions fill faster = lower numbers).
- **The tracked-files regex** — defaults to a Terraform/Packer/shell-script project (`*.tf`, `*.sh`, `*.pkr.hcl`, `documentation/*`). Edit for your stack.
- **The session-state file path** — defaults to `temp/status.md`. This is what the `/wrap` skill writes session state and progress notes into. Pick whatever convention fits your project.

All three live as top-of-script variables in `.claude/scripts/stop-hook-wrap-reminder.sh`; see **Customize**.

## How context % is computed

The hook reads `.context_window.used_percentage` from Claude Code's stdin payload — the same number the statusline shows. Falls back to a transcript byte heuristic (`bytes / 110000`) if the field is absent, but in practice the live number is always present.

The byte fallback overestimates because the transcript grows monotonically across `/compact`, while the actual context window resets. Keep the live path as the primary.

## Why we drop `grep -q` in the infra-edit scan

`set -o pipefail` + `grep -q` is a hidden footgun. `grep -q` early-exits on first match, sending SIGPIPE to the upstream `jq` (exit 141). With pipefail, the whole pipeline returns 141, the `if` branch fails, and the assignment inside it never runs. The fix: read jq's full output without `-q`. The short-circuit saved nearly nothing — jq still streams the whole transcript regardless; grep only sees the extracted file paths — and silently broke detection.

## Why `set -e` is deliberately omitted

The script runs `set -uo pipefail` but not `set -e`. A transient `jq` parse error mid-session should yield partial info (maybe skip the tracked-files detection for that turn) rather than abort the whole hook and block Claude's turn from completing. Each downstream branch handles its own failure mode with sensible defaults, so `set -e` would add brittleness without buying any safety.

## Portability

Tested on macOS. On Linux the BSD `date -j -f` / `stat -f` calls fall back silently; the only degradation is the tracked-files nudge potentially over-firing (can't detect session-state file mtime vs. session start, so treats it as un-modified). Hook stays functional.

## Installation

0. Install prerequisites. The hook depends on `jq` (JSON parsing) and `bash`. On macOS: `brew install jq`. On Debian/Ubuntu: `sudo apt install jq`. `bash` is standard.

1. Clone this repo.
2. Copy the `.claude/` directory into your project's root (or merge with an existing `.claude/`).
3. Create or extend `.claude/settings.json` to wire the Stop hook:

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

4. Adjust the top-of-script variables in `.claude/scripts/stop-hook-wrap-reminder.sh` for your stack (see **Customize**).
5. Reload via Claude Code's `/hooks` menu — no restart needed.

Disable any time by removing the `hooks.Stop` block or setting `"disableAllHooks": true` in `settings.json`.

## Customize

All knobs live at the top of `.claude/scripts/stop-hook-wrap-reminder.sh`:

| Variable | What it does |
|---|---|
| `CTX_THRESHOLD_LOW` | First-tier context % (default `40`) — gentle reminder |
| `CTX_THRESHOLD_MID` | Second-tier context % (default `65`) — bold reminder |
| `CTX_THRESHOLD_HIGH` | Third-tier context % (default `85`) — alarm |
| `TRACKED_FILES_REGEX` | `grep -E` pattern; file paths matching this trigger the tracked-files nudge |
| `STATUS_FILE_REL` | Path (relative to cwd) of the session-state file the nudge expects |

If you change `STATUS_FILE_REL`, update the `/wrap` skill at `.claude/skills/wrap.md` to reference the same path — the skill's "what changed → where to put it" mapping is the human-readable side of the same convention.

Other things you might want to edit:
- **Colors** — the `R` (red) and `B` (red + reverse) ANSI vars near the bottom of the script.
- **Message strings** — the four lines in the `case` statement and the tracked-files block. Reword if the defaults don't fit your project's idiom.

## Provenance

Built with Claude Code's help, reviewed and adapted by me. The script's institutional knowledge — SIGPIPE / `grep -q` interaction, BSD `date -j -f` strictness, deliberate `set -e` omission — emerged from real debugging and is preserved in the inline comments.

## License

MIT. See `LICENSE`.
