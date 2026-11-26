# Spec 04 — Interviewer Agent

**Status:** Draft  
**Priority:** P0 (first agent, Strands SDK smoke test)  
**Requirements:** FR-INT  
**Dependencies:** Spec 03 (config structure)

---

## Goal

Build the Interviewer agent using Strands TypeScript SDK:
1. Agent loop until checklist complete (FR-INT-2)
2. Role-adaptive questions (Scientist vs Business, FR-INT-1)
3. Closed-choice checklist completeness decisions (Strands Decision models smoke test)
4. Clinical construct detection and handling (FR-INT-5)
5. Structured brief output for downstream agents

This spec is the **first Strands SDK implementation** and serves as a smoke test for Decision models (Risk 1 from `02-strands-agents-guide.md`).

---

## Success criteria

- [ ] Interviewer agent runs end-to-end for Scientist role
- [ ] Interviewer agent runs end-to-end for Business role
- [ ] Checklist completeness judged with Decision models (not simple boolean logic)
- [ ] Clinical construct detection triggers appropriate response (redirect Business, warn Scientist)
- [ ] Structured brief output validated with Zod schema
- [ ] Agent loop bounded by config (`max_iterations`)
- [ ] Traceability log captures all decisions
- [ ] Manual test with "Sunday scaries" construct (demo construct)
- [ ] If Decision models fail, fallback implemented and documented

---

## Non-goals (for this spec)

- Full Graph integration (that's Spec 12)
- Production UI integration (manual test via CLI/script sufficient)
- Multi-language support (English only for hackathon)
- Crisis detection (Open Question #7, deferred)

---

## Technical approach

### Architecture

```
interviewer-agent/
├── agent.ts              # Main agent loop
├── checklist.ts          # Checklist items and completeness logic
├── questions.ts          # Question generation (role-adaptive)
├── clinical-detector.ts  # Clinical construct detection
├── schemas.ts            # Zod schemas for structured brief
├── traceability.ts       # Logging helpers
└── __tests__/
    ├── agent.test.ts
    ├── checklist.test.ts
    └── clinical-detector.test.ts
```

### Checklist items (FR-INT-2)

From `app-config/psychometric-procedure.yaml`:

```typescript
// From config
const CHECKLIST_ITEMS = [
  'construct_definition',
  'target_population',
  'intended_dimensions',
  'response_format',
  'context_of_use'
];
```

Each item has:
- **Question prompt** (role-specific)
- **Completeness criteria** (judged by Decision model)
- **Follow-up prompts** if incomplete

### Decision model usage (Strands SDK)

**Smoke test for Risk 1:** Decision model support for non-Bedrock providers.

```typescript
import { LLMDecisionModel } from '@strands-agents/sdk';
import { modelConfig } from '@/lib/config';

async function isChecklistComplete(
  checklistState: ChecklistState,
  conversationHistory: Message[]
): Promise<boolean> {
  
  const model = modelConfig.getStageModel('interviewer');
  
  try {
    const decision = await LLMDecisionModel.ask({
      model: `${model.vendor}/${model.model}`, // e.g., "openai/gpt-4o"
      prompt: `
Based on the conversation so far, determine if the checklist item "${item}" 
has been sufficiently answered.

Checklist item: ${item}
Conversation: ${JSON.stringify(conversationHistory)}

Has this information been provided clearly and completely?
      `,
      options: ['Complete', 'Incomplete', 'Needs clarification'],
      context: {
        checklist: checklistState,
        item: item
      }
    });
    
    return decision.choice === 'Complete';
    
  } catch (error) {
    // Fallback if Decision models don't work
    console.warn('Decision model failed, falling back to keyword matching', error);
    return fallbackCompleteness(checklistState, item);
  }
}
```

**If Decision models fail:** Implement fallback with structured output + explicit "choose one" prompt.

### Role-adaptive questions (FR-INT-1, FR-ASK)

**Scientist questions:** Theoretical language, citations encouraged

```typescript
const scientistPrompts = {
  construct_definition: `
What construct do you want to measure?

Please provide:
- A working definition of the construct
- Theoretical framework or model (if applicable)
- Key sources or citations that inform your understanding
- How this construct differs from related constructs
  `,
  
  intended_dimensions: `
Is this construct unidimensional or multidimensional?

If multidimensional:
- What are the dimensions or facets?
- How are they theoretically related?
- Are there established models you're following?
  `,
  
  target_population: `
Who will be taking this scale?

Consider:
- Demographic characteristics
- Developmental stage (if relevant)
- Cultural context
- Any population-specific considerations
  `
};
```

**Business questions:** Plain language, job-focused

```typescript
const businessPrompts = {
  construct_definition: `
What do you want to measure about people in your organization?

Describe in your own words:
- What quality, skill, or characteristic matters for this role
- Why it's important for job performance
- What it looks like when someone has more or less of it
  `,
  
  intended_dimensions: `
Is this a single quality, or does it have multiple parts?

For example, "customer service excellence" might include:
- Responsiveness to requests
- Empathy and rapport-building
- Problem-solving under pressure

What are the key parts of what you're measuring?
  `,
  
  target_population: `
Who will be taking this assessment?

Consider:
- Job role or level
- Industry or work context
- Any specific requirements or constraints
  `
};
```

### Clinical construct detection (FR-INT-5)

Use Decision model or structured output to classify construct as clinical/non-clinical.

**Clinical indicators:**
- Diagnostic terms (depression, anxiety disorder, PTSD, schizophrenia, etc.)
- Symptom language (hallucinations, suicidal ideation, etc.)
- Clinical severity language (pathological, disorder, illness, etc.)

**Handler:**

```typescript
async function detectClinical(
  constructDefinition: string,
  role: 'scientist' | 'business'
): Promise<{ isClinical: boolean; alternativeConstruct?: string }> {
  
  const decision = await LLMDecisionModel.ask({
    model: modelConfig.getStageModel('interviewer'),
    prompt: `
Determine if this construct is clinical in nature (diagnostic, symptom-based, 
pathological) or non-clinical (personality, skills, attitudes, everyday experiences).

Construct definition: "${constructDefinition}"

Classification:
    `,
    options: ['Clinical', 'Non-clinical', 'Ambiguous'],
    context: { role }
  });
  
  if (decision.choice === 'Clinical') {
    if (role === 'business') {
      // Find alternative
      const alternative = await suggestNonClinicalAlternative(constructDefinition);
      return { isClinical: true, alternativeConstruct: alternative };
    } else {
      // Warn scientist
      return { isClinical: true };
    }
  }
  
  return { isClinical: false };
}
```

**Business redirect:**

```typescript
// Use copy-text.yaml
const redirectMessage = copyTextConfig.interpolate(
  'clinical_warning.business.redirect_message',
  { 
    construct_name: originalConstruct,
    alternative_construct: alternativeConstruct
  }
);

// Pause for user decision (future: Strands interrupt)
// For this spec: return in structured brief with flag
```

**Scientist warning:**

```typescript
const warningMessage = copyTextConfig.interpolate(
  'clinical_warning.scientist.body',
  { construct_name: originalConstruct }
);

// Show warning, ask to proceed or cancel
// For this spec: return in structured brief with flag
```

### Agent loop

```typescript
export async function runInterviewer(
  initialRequest: string,
  role: 'scientist' | 'business'
): Promise<StructuredBrief> {
  
  const config = psychometricConfig;
  const maxIterations = config.get('interview.max_iterations');
  const checklistItems = config.get('interview.checklist_items');
  
  let iteration = 0;
  let conversationHistory: Message[] = [{ role: 'user', content: initialRequest }];
  let checklistState: ChecklistState = initializeChecklist(checklistItems);
  
  // Traceability
  const traceLog: TraceEntry[] = [];
  
  while (iteration < maxIterations) {
    // Check completeness
    const allComplete = await isAllChecklistComplete(checklistState, conversationHistory);
    
    if (allComplete) {
      // Clinical detection
      const clinicalCheck = await detectClinical(
        checklistState.construct_definition.answer,
        role
      );
      
      // Build structured brief
      const brief = buildStructuredBrief(checklistState, clinicalCheck);
      
      // Log and return
      traceLog.push({ stage: 'interview_complete', iteration, brief });
      await saveTraceabilityLog('interviewer', traceLog);
      
      return brief;
    }
    
    // Find next incomplete item
    const nextItem = findNextIncompleteItem(checklistState);
    
    // Generate question
    const question = generateQuestion(nextItem, role, conversationHistory);
    conversationHistory.push({ role: 'assistant', content: question });
    
    // Get user answer (manual for this spec; future: UI integration)
    const answer = await getUserInput(question);
    conversationHistory.push({ role: 'user', content: answer });
    
    // Update checklist
    checklistState[nextItem].answer = answer;
    checklistState[nextItem].complete = await isItemComplete(nextItem, answer, conversationHistory);
    
    // Log
    traceLog.push({
      iteration,
      item: nextItem,
      question,
      answer,
      complete: checklistState[nextItem].complete,
      model: modelConfig.getStageModel('interviewer'),
      prompt_version: modelConfig.getPromptVersion('interviewer')
    });
    
    iteration++;
  }
  
  // Max iterations reached without completion
  throw new Error(
    `Interview did not converge after ${maxIterations} iterations. Human review required.`
  );
}
```

### Structured brief schema (Zod)

```typescript
import { z } from 'zod';

export const StructuredBriefSchema = z.object({
  construct_name: z.string(),
  construct_definition: z.string(),
  
  target_population: z.object({
    description: z.string(),
    demographics: z.array(z.string()).optional(),
    cultural_context: z.string().optional()
  }),
  
  intended_dimensions: z.array(z.object({
    name: z.string(),
    description: z.string()
  })).min(1),
  
  response_format: z.object({
    type: z.enum(['likert_5', 'likert_7', 'likert_other']),
    labels: z.array(z.string()).optional()
  }),
  
  context_of_use: z.string(),
  
  creator_role: z.enum(['scientist', 'business']),
  
  clinical_flag: z.object({
    is_clinical: z.boolean(),
    alternative_construct: z.string().optional(),
    user_decision: z.enum(['proceed', 'use_alternative', 'cancel']).optional()
  }).optional(),
  
  interview_metadata: z.object({
    iterations: z.number(),
    model_used: z.string(),
    prompt_version: z.string(),
    timestamp: z.string()
  })
});

export type StructuredBrief = z.infer<typeof StructuredBriefSchema>;
```

### Fallback for Decision models

If Decision models fail (vendor not supported, API error):

```typescript
function fallbackCompleteness(
  checklistState: ChecklistState,
  item: string
): boolean {
  const answer = checklistState[item].answer;
  
  // Simple heuristics
  switch (item) {
    case 'construct_definition':
      return answer.length > 50 && answer.includes('measure');
    
    case 'intended_dimensions':
      return answer.length > 20 && (
        answer.toLowerCase().includes('dimension') ||
        answer.toLowerCase().includes('factor') ||
        answer.toLowerCase().includes('unidimensional')
      );
    
    // ... other items
    
    default:
      return answer.length > 20;
  }
}
```

**Document fallback usage** in traceability log.

---

## Testing strategy

### Unit tests

```typescript
// __tests__/checklist.test.ts
describe('Checklist', () => {
  test('initializes with all items incomplete', () => {
    const checklist = initializeChecklist(CHECKLIST_ITEMS);
    expect(Object.values(checklist).every(item => !item.complete)).toBe(true);
  });
  
  test('marks item complete when criteria met', async () => {
    // Mock Decision model response
    const checklist = { construct_definition: { answer: 'Sunday scaries...', complete: false } };
    const isComplete = await isItemComplete('construct_definition', 'Sunday scaries...', []);
    expect(isComplete).toBe(true);
  });
});

// __tests__/clinical-detector.test.ts
describe('Clinical detection', () => {
  test('detects clinical construct (depression)', async () => {
    const result = await detectClinical('Major depressive disorder symptoms', 'scientist');
    expect(result.isClinical).toBe(true);
  });
  
  test('allows non-clinical construct (Sunday scaries)', async () => {
    const result = await detectClinical('Anticipatory dread about the work week', 'scientist');
    expect(result.isClinical).toBe(false);
  });
  
  test('suggests alternative for Business clinical request', async () => {
    const result = await detectClinical('Employee anxiety', 'business');
    expect(result.isClinical).toBe(true);
    expect(result.alternativeConstruct).toBeTruthy();
  });
});
```

### Integration test (manual for this spec)

**Test script:** `scripts/test-interviewer.ts`

```typescript
import { runInterviewer } from '@/agents/interviewer-agent/agent';

async function testSundayScaries() {
  console.log('Testing Interviewer with "Sunday scaries" construct...\n');
  
  const brief = await runInterviewer(
    'I want to measure Sunday scaries - the anticipatory dread people feel about the coming work week',
    'scientist'
  );
  
  console.log('Structured Brief:', JSON.stringify(brief, null, 2));
  
  // Verify
  console.assert(brief.construct_name.toLowerCase().includes('sunday'), 'Construct name mismatch');
  console.assert(brief.clinical_flag?.is_clinical === false, 'Should not be clinical');
  console.assert(brief.intended_dimensions.length > 0, 'Should have dimensions');
  
  console.log('\n✅ Test passed');
}

testSundayScaries().catch(console.error);
```

Run: `npm run test:interviewer`

---

## Risks and mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Decision models fail on non-Bedrock provider | **High** | Implement fallback with structured output; document workaround |
| Loop does not converge (user gives vague answers) | Medium | Bounded iterations; explicit error message for human review |
| Clinical detection too sensitive/not sensitive | Medium | Test with known clinical and non-clinical constructs; tune prompt |
| Scientist vs Business questions not differentiated enough | Low | Review with owner; refine prompts based on demo feedback |

---

## Tasks

### Setup

- [ ] Install Strands SDK: `npm install @strands-agents/sdk`
- [ ] Create `src/agents/interviewer-agent/` directory structure

### Implementation

- [ ] `schemas.ts`: Zod schema for StructuredBrief
- [ ] `checklist.ts`: Checklist initialization and completeness logic
- [ ] `questions.ts`: Role-adaptive question generation (Scientist vs Business)
- [ ] `clinical-detector.ts`: Clinical construct detection with Decision model
- [ ] `traceability.ts`: Logging helpers for NFR-1
- [ ] `agent.ts`: Main agent loop with bounded iterations

### Decision model smoke test

- [ ] Try Decision model with configured provider
- [ ] If fails: implement and test fallback
- [ ] Document outcome in journal (Risk 1 mitigation)

### Testing

- [ ] Unit tests: checklist, clinical detection
- [ ] Integration test script: `scripts/test-interviewer.ts`
- [ ] Manual test: "Sunday scaries" construct (Scientist role)
- [ ] Manual test: "Hobby hustle" construct (Scientist role)
- [ ] Manual test: Clinical construct with Business role (verify redirect)

### Documentation

- [ ] Update journal with Decision model outcome
- [ ] Document any prompts or heuristics that work well
- [ ] Note any items for owner review (e.g., clinical detection tuning)

---

## Acceptance

This spec is complete when:

1. Interviewer agent runs end-to-end for both roles
2. Decision models tested (success or fallback documented)
3. Clinical detection works for test cases
4. Structured brief validates against Zod schema
5. Manual tests with demo constructs pass
6. Code committed with tests
7. Journal entry documents Decision model outcome and any discoveries

---

## References

- PRD: FR-INT (Interviewer requirements)
- Steering: `02-strands-agents-guide.md` (Decision models, Risk 1)
- Steering: `00-project-rules.md` (traceability)
- Spec 03: Config structure for model and copy text

---

**Next spec:** `05-literature-research-agent.md` (agent loop with literature tools)
