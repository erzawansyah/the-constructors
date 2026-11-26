---
inclusion: always
---

# Strands Agents TypeScript SDK Guide

This project uses **Strands Agents TypeScript SDK** (`@strands-agents/sdk`) for the multi-agent psychometric pipeline.

## Package and version

```bash
npm install @strands-agents/sdk
```

Current development against: **v1.25.0** (November 2026)

**Important:** This is the TypeScript SDK, not the Python SDK. All examples and patterns must be TypeScript-compatible.

## Core patterns

### 1. Graph orchestration (fixed pipeline)

The psychometric procedure is a **directed acyclic graph with bounded loops**:

```
Interviewer → Literature → Item Writer → Language Review → Content Panel ⤴
                                                                        ↓
                                                            (revision loop, bounded)
                                                                        ↓
                                                        Structural Screening → Simulation → Reporter
```

Use **Strands Graph** to define:
- Nodes (each agent stage)
- Edges (data flow and control flow)
- Loop bounds (max iterations from config)
- Conditional branches (e.g. "if existing scale found, branch to recommendation")

**AND-join semantics:** A node executes only when **all** incoming edges have completed. Design the graph carefully to avoid unintended blocking.

### 2. Decision models (closed-choice judgements)

For every boolean or closed-choice decision (interview checklist, language flags, panel ratings, persona responses), use **`LLMDecisionModel.ask`**.

```typescript
import { LLMDecisionModel } from '@strands-agents/sdk';

const decision = await LLMDecisionModel.ask({
  model: modelConfig.panelJudge, // Always pass explicit model
  prompt: "Is this item relevant to the indicator 'anticipatory dread'?",
  options: ['Relevant', 'Somewhat relevant', 'Not relevant', 'Uncertain'],
  context: { item: itemText, indicator: indicatorDefinition }
});

// decision.choice: one of the options
// No confidence scores or probabilities (SDK limitation as of v1.25.0)
```

**Rules:**
- Always pass an explicit `model` parameter (never rely on defaults)
- One criterion per decision call (never "rate all 15 flags in one prompt")
- Handle `'Uncertain'` explicitly in downstream logic
- Log the decision for traceability (NFR-1)

**Known limitation:** As of v1.25.0, `LLMDecisionModel` returns no confidence scores or probabilities. The choice is categorical only.

### 3. Interrupts (mid-pipeline questions)

When the pipeline needs a human decision (Scientist theory choice, Business key decision), use **Strands interrupts**:

```typescript
import { interrupt } from '@strands-agents/sdk';

const userChoice = await interrupt({
  type: 'question',
  role: creatorRole, // 'scientist' | 'business'
  prompt: adaptPromptToRole(question, role),
  options: ['Option A', 'Option B', 'Skip and let the committee decide']
});

// Pipeline pauses, user sees question in UI
// Resumes when user responds
```

**Role adaptation (FR-ASK):**
- **Scientist:** theoretical language, full context, frequent asks
- **Business:** plain language, job-related framing, key decisions only

Log every interrupt and the user's response for traceability.

### 4. Structured outputs (Zod schemas)

For complex agent outputs (construct framework, item pool, report), use **Zod schemas**:

```typescript
import { z } from 'zod';

const ConstructFrameworkSchema = z.object({
  definition: z.string(),
  dimensions: z.array(z.object({
    name: z.string(),
    definition: z.string(),
    indicators: z.array(z.string()),
    citations: z.array(z.string())
  })),
  orbitingConstructs: z.array(z.object({
    name: z.string(),
    definition: z.string(),
    citations: z.array(z.string())
  }))
});

type ConstructFramework = z.infer<typeof ConstructFrameworkSchema>;
```

Pass schema to agent calls to enforce structure. Validate outputs before passing to next stage.

## Known risks and mitigations

### Risk 1: Non-Bedrock provider support for Decision models

**Status (v1.25.0):** Decision model support for providers other than AWS Bedrock is undocumented.

**Mitigation:**
- Smoke-test decision models early in Spec 4 (Interviewer)
- If unsupported, fall back to structured outputs with explicit "choose one" prompts
- Document the workaround in implementation notes

### Risk 2: Structured-output nodes forwarding tool-use blocks

**Issue:** An open GitHub issue reports that Graph nodes using structured outputs may forward raw tool-use blocks to the next node instead of only the structured data.

**Mitigation:**
- Test Graph behavior in Spec 12 with a simple two-node pipeline
- If confirmed, add explicit filtering: each node extracts only the structured data and discards tool metadata before passing to the next edge
- Report issue to Strands if not already tracked

### Risk 3: AND-join blocking

**Behavior:** A node waits for **all** incoming edges to complete before executing.

**Mitigation:**
- Design the graph with this in mind: parallel branches must converge at a node that expects multiple inputs
- Use explicit "merge" nodes where needed
- Document join semantics in graph diagrams

## Multi-vendor panel pattern

For the content panel (FR-PANEL), judges must use **different vendors**. Example config:

```yaml
panel:
  judges:
    - vendor: openai
      model: gpt-4o
    - vendor: openai
      model: o1
    - vendor: anthropic
      model: claude-3-5-sonnet-20241022
    - vendor: anthropic
      model: claude-3-opus-20240229
```

Instantiate one `LLMDecisionModel` per judge and aggregate results:

```typescript
const ratings = await Promise.all(
  judges.map(judge => 
    LLMDecisionModel.ask({
      model: judge,
      prompt: relevancePrompt,
      options: ['Relevant', 'Somewhat relevant', 'Not relevant', 'Uncertain']
    })
  )
);

// Compute I-CVI, S-CVI/Ave, k* from ratings
```

## Agent loop pattern

Only two agents use loops (FR-INT, FR-LIT):

1. **Interviewer:** loop until checklist complete (all items true)
2. **Literature research:** loop until all required outputs found or max iterations reached

```typescript
let checklistComplete = false;
let iteration = 0;
const maxIterations = config.interviewer.max_iterations;

while (!checklistComplete && iteration < maxIterations) {
  const question = generateNextQuestion(checklist);
  const answer = await interrupt({ type: 'question', prompt: question });
  
  updateChecklist(answer);
  checklistComplete = await LLMDecisionModel.ask({
    model: config.interviewer.model,
    prompt: 'Is the checklist complete?',
    options: ['Complete', 'Incomplete'],
    context: { checklist }
  });
  
  iteration++;
}

if (!checklistComplete) {
  throw new Error('Interview did not converge. Human review required.');
}
```

## Traceability logging

Every agent call must log:

```typescript
const logEntry = {
  timestamp: new Date().toISOString(),
  stage: 'content_panel',
  model_id: judge.model,
  model_version: judge.version,
  temperature: judge.temperature,
  prompt_version: 'panel-relevance-v1.2',
  decision: rating.choice,
  rationale: rating.rationale, // if available
  execution_context: { item_id, indicator_id }
};

await saveToTraceabilityLog(logEntry);
```

This supports NFR-1 and validity ladder reporting.

## Development workflow

1. **Spec 1–3:** Set up foundations (R service, Supabase, config structure)
2. **Spec 4:** Smoke-test Strands decision models with Interviewer
3. **Spec 5–11:** Build agent stages sequentially, testing each in isolation
4. **Spec 12:** Integrate into Graph, test end-to-end pipeline with bounded loops and interrupts
5. **Spec 13–15:** UI layers (creator review, respondent flow, catalog)

Each agent stage should be testable independently before graph integration.

## Resources

- Strands TS SDK docs: (check official documentation for latest patterns)
- Example repo: (if available from Strands)
- GitHub issues: (track known issues with Graph and Decision models)

When in doubt, smoke-test early and fail explicitly with actionable error messages.
