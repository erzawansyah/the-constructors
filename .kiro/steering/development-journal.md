---
inclusion: manual
---

# Development Journal Reference

This steering file directs you to the project development journal.

## Location

`notes/kiro-journal.md`

## Purpose

The journal is a living record of:

- Design decisions and rationales
- Blockers and resolutions
- Sprint progress and milestones
- Technical discoveries and gotchas
- Owner decisions on open questions
- Traceability for major architectural choices

## When to update

- After completing a spec or major milestone
- When a blocker is encountered or resolved
- When an open question from PRD §14 is decided by the owner
- When a significant technical risk materializes or is mitigated
- At the end of each development session (via `journal-remind` hook)

## Format

The journal uses a structured format for clarity:

```markdown
## YYYY-MM-DD — Entry Title

**Context:** Brief description of what triggered this entry

**Decision/Progress/Blocker:** Main content

**Impact:** What this affects downstream

**References:** Links to specs, steering files, PRD sections, or commits
```

Entries are **append-only** (don't edit past entries, add new ones for updates).

## Access from steering

When you need context from past decisions, reference the journal with:

```markdown
See `#[[file:notes/kiro-journal.md]]` for the history of [decision topic].
```

## Git workflow

notes/ is private and git-ignored. Never commit anything inside notes/.
