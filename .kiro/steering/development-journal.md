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

## Example entry

```markdown
## 2026-11-26 — Decided on multi-vendor panel configuration

**Context:** FR-PANEL-3 requires judges from different vendors for content screening

**Decision:** Use 2 OpenAI models (gpt-4o + o1) and 2 Anthropic models (claude-3-5-sonnet + opus) = 4 total judges. Owner confirmed single vendor + multi-model is acceptable for intra-vendor diversity, but ≥2 vendors required overall.

**Impact:** Config structure in `app-config/model-config.yaml` must support per-judge vendor + model specification. Panel aggregation logic must handle vendor metadata for reporting.

**References:** PRD FR-PANEL-3, Spec 8 (content-panel-agent.md), interview session 2026-11-26
```

## Access from steering

When you need context from past decisions, reference the journal with:

```markdown
See `#[[file:notes/kiro-journal.md]]` for the history of [decision topic].
```

## Git workflow

The journal is committed to git as part of the project history. Each significant decision should be journaled before committing related code changes, so the git history shows *why* alongside *what*.
