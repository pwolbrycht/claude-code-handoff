---
name: wrap
description: End-of-session hygiene — survey what changed, propose updates to session state, memory, and docs, apply approved ones before /exit
---

# Wrap session

The user is preparing to end this session. Goal: leave the persistence layer current so the next fresh session picks up cold.

> **Conventions assumed below:** session-state file at `temp/status.md`, documentation directory at `documentation/`. These match the stop hook's `STATUS_FILE_REL` and `TRACKED_FILES_REGEX` defaults — adjust the references in this skill if you've changed those.

## Steps

### 1. Survey what changed

- Run `git status` to see uncommitted changes.
- Run `git log --oneline origin/main..HEAD` if anything was committed during the session.
- Scan the session transcript (`~/.claude/projects/<sanitized-cwd>/<session_id>.jsonl`) for Edit/Write tool calls — list the files touched. `<sanitized-cwd>` is the absolute cwd path with `/` replaced by `-` (e.g. `/Users/alice/code/myapp` → `-Users-alice-code-myapp`).
- Note any user corrections, preferences, or surprising learnings from this session.

### 2. Detect mid-task handoff (WIP)

Before mapping settled changes, decide: is the user ending **at a natural boundary** (sub-task done) or **mid-task** (warning fired, forced to wrap)?

Signals it's WIP:
- Uncommitted partial work in files that don't compile / pass linters / pass type-checks
- The last few turns were debugging or implementing something not yet complete
- The user said something like "I'm stopping here" mid-thought, "have to wrap", or the Stop hook alarm fired
- `git status` shows changes but no recent commits this session

If WIP, propose a **"Currently in progress"** section in `temp/status.md` capturing:

```markdown
## Currently in progress — <session-name>
- **Working on:** <one line — what task>
- **Tried:** <bullets — approaches attempted, what worked, what didn't>
- **Next step:** <one line — specific next action>
- **Partial work in:** <file paths + line ranges, commit status>
- **Blockers / open questions:** <if any>
```

Goal: a fresh session reading this should be able to continue without asking "where were we?"

Wipe the section once the task completes (in a later session's `/wrap`).

### 3. Map other changes to the right destination

- **`temp/status.md`** — also update for: open work added/closed, blockers cleared/discovered, deployment-readiness changed, new backlog items, completed items removed.
- **Memory** (`~/.claude/projects/<sanitized-cwd>/memory/`) — Save **surprising** learnings only. New user preferences, project facts not derivable from code, gotchas. Rare — most sessions don't warrant a new memory file. Use existing types: user / feedback / project / reference.
- **`documentation/<file>.md`** — Promote if it's now settled knowledge: architecture decision, convention, gotcha, troubleshooting recipe. Prefer extending an existing doc over creating a new one.
- **No destination?** Skip silently.

### 4. Propose changes one at a time

For each proposed change, show:
- **Where:** file path + section/heading
- **What:** the exact text to add or edit (diff style)
- **Why:** one line

Wait for the user's y/n. Don't batch. Don't apply without approval.

### 5. Apply approved changes

In a single pass after the user has approved each proposal.

### 6. Confirm clean exit

Output a short tally:
- What was updated (one line each, file + section)
- What was deliberately skipped (and why, briefly — e.g. "no material changes to status.md")
- "Clear to /exit."

## Heuristics

- If `temp/status.md` mtime hasn't moved this session and Edit/Write touched files matching the hook's tracked-files pattern, that's a strong signal the session-state file needs an update.
- If a user correction came up ("don't X", "stop doing Y") OR a non-obvious approach was confirmed ("yes, that was the right call"), check whether it's worth a feedback memory.
- For trivial sessions (debugging, exploration with no edits), skip the ritual — just say "nothing material; clear to /exit."
- Prefer extending an existing doc over creating a new one.
- Never propose changes that touch production resources without explicit confirmation.

## Skip the ritual when

- User says "skip wrap, just exit"
- Zero edits, zero settled-decision discussions, nothing surprising
