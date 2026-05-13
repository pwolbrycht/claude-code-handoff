# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A distribution of three coupled Claude Code artifacts, not an application:

- `.claude/scripts/stop-hook-wrap-reminder.sh` — `Stop` hook. Fires a colored pill in the terminal at three context-fill thresholds, plus a teal pill when tracked files are edited.
- `.claude/scripts/statusline.sh` — companion statusline. Always visible at the bottom of the UI; same color palette as the hook plus an action message keyed to ctx %.
- `.claude/skills/wrap.md` — the `/wrap` skill the hook and statusline are nudging the user toward.

There is no build, test suite, or linter wired up. Sanity check: `shellcheck .claude/scripts/*.sh`. A copy-pasteable demo loop that walks both scripts through all four threshold ranges is in the README's verification section.

## The two couplings that must stay in sync

**Hook ↔ skill** — share three knobs. Change either side without the other and the system breaks silently:

| Concept | Hook | Skill |
|---|---|---|
| Session-state file path | `STATUS_FILE_REL` (default `temp/status.md`) | Conventions note + step 3 |
| Tracked-files pattern | `TRACKED_FILES_REGEX` | Heuristics section |
| Context thresholds | `CTX_THRESHOLD_LOW/MID/HIGH` | Implicit — the skill is what fires after the alarm |

**Hook ↔ statusline** — share both the three context thresholds (`CTX_THRESHOLD_LOW/MID/HIGH` knobs at the top of each script) and the RGB pill palette (inline SGR strings in the tier branches). Edit one side without the other and the "same yellow at the same %" guarantee breaks. Palette:

- `255;235;130` light yellow — ctx ≥ 40%
- `255;140;0` orange — ctx ≥ 65%
- `180;30;30` volcano red — ctx ≥ 85%
- `72;161;192` teal — tracked-files nudge (hook only)

## Multi-fire counter logic

Each threshold fires up to 3 times per session, then goes silent. State per-session at `~/.claude/state/claude-stop-hook-<session_id>.state` holds `level1_count`, `level2_count`, `level3_count`, `infra_count`, plus `last_level` and the `infra_edited` cache. Crossing into a higher tier starts that tier's counter fresh — escalation is not suppressed by a maxed-out lower tier. Delete the sentinel to replay a session.

## Institutional knowledge — don't re-derive

These came from real debugging and are documented in inline comments in the hook. Read before "simplifying":

- **`grep -q` is banned in the tracked-files scan.** `set -o pipefail` + `grep -q` SIGPIPEs the upstream `jq` (exit 141), flipping the if-branch. Read jq's full output instead.
- **`set -e` is deliberately omitted.** A transient `jq` parse error should yield partial info, not block Claude's turn. Each branch handles its own failure mode.
- **BSD `date -j -f` rejects fractional-second + `Z`.** Timestamps are sliced to the first 19 chars before parsing.
- **Live ctx % is preferred over the transcript-bytes fallback.** The transcript grows monotonically across `/compact`; the byte heuristic overestimates after compaction.
- **Blink (SGR 5) is silently ignored by Ghostty et al.** Pre-v1.2 worked around this with reverse video for level 3; v1.2 dropped both in favor of distinct RGB pill backgrounds.

## Portability

Tested on macOS. Linux fall-throughs via `||` mean only the tracked-files nudge can over-fire (no session-start vs status-file-mtime comparison).
