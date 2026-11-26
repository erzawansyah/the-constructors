---
inclusion: always
---

# Project Rules — The Constructors

These are hard rules that apply to all development work on The Constructors.

## Config-driven thresholds

**All psychometric thresholds, loop bounds, and procedure parameters MUST be read from `app-config/psychometric-procedure.yaml`.**

- Never hardcode cut-off values (I-CVI, k*, c, d, wTO, stability, feedback tiers, loop limits, etc.) in code or prompts.
- If a config value is `null`, **STOP and ask the owner** for a decision. Do not invent, estimate, or use "reasonable defaults".
- When implementing agent logic that uses thresholds, always load from config and handle `null` explicitly.

Example config reference pattern:
```typescript
const procedure = loadConfig('psychometric-procedure.yaml');
if (procedure.panel.i_cvi_threshold === null) {
  throw new Error('I-CVI threshold not set. Owner decision required.');
}
```

## Runtime vs dev-time separation

| Path | Purpose | Committed |
|------|---------|-----------|
| `.kiro/` | Development harness: steering, specs, hooks | ✅ Yes — never add to `.gitignore` |
| `app-config/` | Runtime configuration: thresholds, model configs, copy text | ✅ Yes |
| `src/agents/prompts/` | Agent prompt templates | ✅ Yes |
| `notes/` | Development journal, scratch | ✅ Yes (journal is a project artifact) |

**Rule:** `.kiro/` steering files may **reference** runtime files (e.g. `#[[file:app-config/psychometric-procedure.yaml]]`) but never duplicate their content.

## Deployment architecture

The app consists of three services:

1. **Next.js app** — Docker container
2. **Supabase** — self-hosted Docker container (not Supabase cloud)
3. **R statistics service** — separate process on the same host (plumber JSON API, default `localhost:8000`)

Orchestration: `docker-compose.yml` at root.

**Rule:** All service URLs and ports must be configurable via environment variables.

## Strands Agents TypeScript SDK

This project uses **Strands Agents TypeScript SDK** (`@strands-agents/sdk`), not the Python version.

Key patterns:
- **Graph** for the fixed pipeline with bounded loops
- **Decision models** (`LLMDecisionModel.ask`) for closed-choice judgements (always pass explicit model)
- **Interrupts** for mid-pipeline questions to creators
- **Zod schemas** for structured outputs

Known risks (verify during implementation):
- Decision model support for non-Bedrock providers may be undocumented
- Graph structured-output nodes may forward tool-use blocks to next node (open issue)
- Graph uses AND-join semantics (node runs only when all incoming edges complete)

## Traceability requirement

Every agent execution must log:
- Model ID and version
- Temperature and sampling parameters
- Prompt version identifier
- Decision rationale (when agent decides without asking)
- Timestamp and execution context

This satisfies NFR-1 and supports the validity ladder reporting.

## No assumptions on open questions

PRD §14 lists open questions (model provider, exact thresholds, formulas, etc.). **Do not make assumptions or implementations for items marked as open questions unless the owner has decided.**

If a spec or task requires an open-question answer, stop and ask.

## Ethics and labeling

- Simulation data is **never** shown to respondents or used as norms.
- Label LLM content screening results as **"LLM content screening"**, never "content validity".
- Label smoke test results as **"technical rehearsal (smoke test) — not validation"**.
- No diagnostic language for respondents (never "high/low risk" or condition names).
- Clinical constructs: redirect Business users to non-clinical alternatives; warn Scientists before proceeding.

## Code quality baseline

- TypeScript strict mode enabled
- All database queries use parameterized queries (no string interpolation)
- Secrets only in environment variables, never committed
- Error handling: fail explicitly with actionable messages
- Tests: statistical modules tested against known results (NFR-7), not just "does not crash"
