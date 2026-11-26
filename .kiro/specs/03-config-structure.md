# Spec 03 — Config Structure (app-config/)

**Status:** Draft  
**Priority:** P0 (foundation for all agents)  
**Requirements:** NFR-2, all FR-\* that reference thresholds  
**Dependencies:** None

---

## Goal

Create the `app-config/` directory structure with YAML configuration files for:

1. Psychometric procedure (thresholds, loop bounds, feedback tiers)
2. Model configuration (per-stage models, temperatures, vendors)
3. Copy text (informed consent, warnings, UI labels)

All files must be **config-driven** (no hardcoded values) and handle `null` explicitly for undecided values.

---

## Success criteria

- [ ] `app-config/` directory structure created
- [ ] `psychometric-procedure.yaml` with all threshold fields (mix of `null` and decided values)
- [ ] `model-config.yaml` with per-stage model specifications
- [ ] `copy-text.yaml` with informed consent, warnings, and labels
- [ ] TypeScript loader functions created (`src/lib/config.ts`)
- [ ] Loader throws explicit error for `null` values when accessed
- [ ] README documents config structure and owner decision process
- [ ] Example showing how agents use config

---

## Non-goals (for this spec)

- Deciding all threshold values (owner decision per PRD §14)
- Finalizing model provider choices (pending owner decision)
- Production config management (secrets, environment-specific overrides)
- Config validation beyond type checking

---

## Technical approach

### Directory structure

```
app-config/
├── psychometric-procedure.yaml
├── model-config.yaml
├── copy-text.yaml
└── README.md
```

### File 1: `psychometric-procedure.yaml`

**Purpose:** All numeric thresholds, loop bounds, and procedure parameters.

**Rule:** Values not yet decided by owner = `null`. Code must check and throw error.

```yaml
# Psychometric Procedure Configuration
# Owner decisions required for all null values before pipeline can run

# Item generation (FR-ITEM-4)
item_generation:
  target_items_per_dimension: 5 # Decided: 5 items is the target
  pool_multiplier: null # Owner decision pending (literature reference: ~3x)
  max_pool_size: null # Optional cap on absolute pool size

# Language review (FR-LANG)
language_review:
  # Defect flags (remove/revise item)
  defect_flags:
    - double_barreled
    - negation_multiple # Multiple negations
    - ambiguous_reference
    - jargon
    - identity_bias
    - format_mismatch

  # Attribute flags (record only, don't remove)
  attribute_flags:
    - negation_single
    - absolute_term
    - endorsement_extreme
    - colloquial_or_dated
    - wordy
    - reading_load
    - time_frame
    - negative_affect_term
    - evaluative_loading
    - affect_without_object
    - hypothetical
    - published_item_similarity

# Content panel (FR-PANEL-2, FR-PANEL-5)
content_panel:
  # Relevance indices (I-CVI, S-CVI/Ave, modified kappa)
  i_cvi_threshold: null # Literature ref: ≥ 0.78
  s_cvi_ave_threshold: null # Literature ref: ≥ 0.90
  kappa_star_threshold: null # Literature ref: > 0.74

  # Hinkin-Tracey distinctiveness (c/d)
  definitional_correspondence_threshold: null # Literature ref: > 0.88
  distinctiveness_threshold: null # Literature ref: > 0.35

  # Revision loop (FR-PANEL-7)
  max_revision_rounds: null
  min_items_per_dimension: 3 # Decided: FR-ITEM-9 minimum

  # Rating options (FR-PANEL-4)
  relevance_options:
    - Relevant
    - Somewhat relevant
    - Not relevant
    - Uncertain

  distinctiveness_options:
    - Clearly target construct
    - Somewhat target construct
    - Ambiguous
    - Somewhat different construct
    - Clearly different construct
    - Uncertain

# Structural screening (FR-STRUCT)
structural_screening:
  wto_threshold: null # Weighted topological overlap for UVA
  stability_threshold: null # bootEGA stability cut-off
  boot_iterations: null # Number of bootstrap resamples
  min_nmi_improvement: null # Optional: minimum NMI gain to accept screening

# Simulation (FR-SIM-2, interview decision)
simulation:
  persona_multiplier: 20 # Decided: 20 × number of items

  # Persona demographics (mandatory fields)
  demographics:
    - name # Fiktif
    - occupation
    - age_range
    - gender

  # Persona generation strategy
  sampling_strategy: stratified_random # Decided in interview

  # CFA expectations (not rigid cut-offs, see FR-SIM-5)
  cfa_reference_fit:
    cfi: 0.95
    tli: 0.95
    rmsea: 0.06
    srmr: 0.08
    note: "Reference values, not pass/fail criteria"

# Feedback tiers (FR-RESP-3)
feedback_tiers:
  tier1_max: 99 # < 100 respondents: self-reflection only
  tier2_min: 100 # Decided: ≥ 100: provisional comparison
  tier2_max: 999 # < 1000: still provisional
  tier3_min: 1000 # Decided: ≥ 1000: norms

  tier1_label: "Self-reflection (no comparison data yet)"
  tier2_label: "Provisional comparison (not a norm)"
  tier3_label: "Norm-referenced"

# Rewrite loops (FR-ITEM-9)
rewrite:
  max_rounds_business: null # Business mode: auto-rewrite up to this limit
  max_rounds_scientist: 1 # Scientist mode: ask after first attempt

# Interview (FR-INT-2)
interview:
  max_iterations: null # Interviewer loop bound
  checklist_items: # Required information before pipeline proceeds
    - construct_definition
    - target_population
    - intended_dimensions
    - response_format
    - context_of_use

# Literature research (FR-LIT)
literature:
  max_iterations: null
  min_citations_per_decision: 2 # Minimum citations to support a definitional choice
```

### File 2: `model-config.yaml`

**Purpose:** Model selection, temperatures, and vendor configuration per pipeline stage.

**Note:** Specific models pending owner decision (PRD §14 #1), but structure is defined now.

```yaml
# Model Configuration
# Provider and model selections per pipeline stage

# Default provider settings (overridden per stage if needed)
default:
  temperature: 0.7
  max_tokens: 4096
  timeout_seconds: 60

# Stage-specific models
stages:
  # Interviewer (FR-INT)
  interviewer:
    model: null # e.g., "gpt-4o", "claude-3-5-sonnet-20241022"
    vendor: null # e.g., "openai", "anthropic"
    temperature: 0.3 # Lower for structured checklist decisions
    max_tokens: 2048

  # Literature research (FR-LIT)
  literature:
    model: null
    vendor: null
    temperature: 0.5
    max_tokens: 8192 # Longer context for citations

  # Item writer (FR-ITEM)
  item_writer:
    model: null
    vendor: null
    temperature: 0.9 # Higher for creative generation
    max_tokens: 4096

  # Language reviewer (FR-LANG)
  language_reviewer:
    model: null
    vendor: null
    temperature: 0.2 # Very low for consistent judgements
    max_tokens: 2048

  # Content panel judges (FR-PANEL-3)
  # Multi-vendor, multi-model (≥2 vendors required)
  content_panel:
    judges:
      - id: judge_1
        vendor: null # e.g., "openai"
        model: null # e.g., "gpt-4o"
        temperature: 0.1
      - id: judge_2
        vendor: null # e.g., "openai"
        model: null # e.g., "o1"
        temperature: 0.1
      - id: judge_3
        vendor: null # e.g., "anthropic"
        model: null # e.g., "claude-3-5-sonnet-20241022"
        temperature: 0.1
      - id: judge_4
        vendor: null # e.g., "anthropic"
        model: null # e.g., "claude-3-opus-20240229"
        temperature: 0.1

  # Persona simulation (FR-SIM-3)
  # Cheaper model acceptable (many calls)
  persona_simulator:
    model: null # e.g., "gpt-4o-mini", "claude-3-haiku"
    vendor: null
    temperature: 0.7
    max_tokens: 1024

  # Reporter (FR-REP)
  reporter:
    model: null
    vendor: null
    temperature: 0.3
    max_tokens: 8192

# Embedding model (FR-STRUCT-1)
embedding:
  provider: null # e.g., "openai"
  model: null # e.g., "text-embedding-3-large"
  dimensions: null # e.g., 1536 for OpenAI, 768 for others

# Prompt versioning (NFR-1 traceability)
prompt_versions:
  interviewer: "v1.0"
  literature: "v1.0"
  item_writer: "v1.0"
  language_reviewer: "v1.0"
  content_panel_relevance: "v1.0"
  content_panel_distinctiveness: "v1.0"
  persona_simulator: "v1.0"
  reporter: "v1.0"
```

### File 3: `copy-text.yaml`

**Purpose:** User-facing text (informed consent, warnings, labels) that may need editing.

```yaml
# Copy Text Configuration
# User-facing strings that may need customization

# Informed consent (FR-RESP-1, Open Question #6)
informed_consent:
  title: "Informed Consent"
  body: |
    You are invited to participate in a research project by completing this psychological scale.

    **What we collect:**
    - Your responses to the scale items
    - Completion time and basic technical information (browser type)
    - Optional: demographic information if provided

    **How we use your data:**
    This scale's data policy is: {data_policy}

    - Research scales: Your anonymous responses contribute to a pooled research dataset 
      and may be used to calculate norms and validate the scale. No personally 
      identifiable information is collected.

    - Private scales: Your responses are visible only to the organization that created 
      this scale and are not included in public research datasets.

    **Your rights:**
    - Participation is voluntary
    - You may stop at any time
    - Your responses are anonymous by default

    **Contact:** [Owner to provide contact email]

    By clicking "I Agree," you consent to participate.

  agree_button: "I Agree"
  decline_button: "No Thanks"

# Clinical construct warning (FR-INT-5, Open Question #6)
clinical_warning:
  scientist:
    title: "Clinical Construct Warning"
    body: |
      The construct you described ({construct_name}) appears to be clinical in nature.

      This tool is designed for **non-clinical self-insight and research**, not diagnosis 
      or clinical assessment. Creating a scale for a clinical construct without 
      appropriate validation and safeguards may be unethical or harmful.

      **We strongly recommend:**
      - Consulting with a licensed clinical psychologist
      - Following established clinical scale development procedures
      - Obtaining IRB approval if this will be used in research

      Do you want to proceed anyway?

    proceed_button: "Proceed (I understand the risks)"
    cancel_button: "Cancel and Revise"

  business:
    # Business users are redirected, not warned
    redirect_message: |
      The construct you described ({construct_name}) appears to be clinical in nature.

      This tool is designed for workplace assessments and non-clinical attributes.
      We've identified a related non-clinical construct that may fit your needs:

      **Suggested alternative:** {alternative_construct}

      Would you like to proceed with this alternative?

    accept_button: "Use Alternative"
    revise_button: "Revise My Request"

# Validity ladder labels (PRD §8)
validity_ladder:
  tier_0: "Draft (not screened)"
  tier_1: "Passed LLM content screening"
  tier_2: "Passed structural semantic screening"
  tier_3: "Passed technical rehearsal (simulation)"
  tier_4: "Has human response data"
  tier_5: "Has norms (≥ {tier3_min} respondents)"

  disclaimer: |
    This scale is at tier {current_tier}. It is a screening draft, not a validated 
    or diagnostic instrument. Results should be interpreted with caution and are 
    intended for self-reflection or research purposes only.

# Feedback tier messaging (FR-RESP-3)
feedback:
  tier1:
    title: "Your Scores"
    intro: |
      Here are your scores on each dimension. This scale has {response_count} responses 
      so far, which is not yet enough for meaningful comparisons.

      These scores are for self-reflection only.

  tier2:
    title: "Your Scores (Provisional Comparison)"
    intro: |
      Here are your scores on each dimension, compared with {response_count} people 
      who have taken this scale so far.

      **Note:** This is a provisional comparison, not a norm. The sample size is still 
      growing and may not be representative.

  tier3:
    title: "Your Scores (Norm-Referenced)"
    intro: |
      Here are your scores on each dimension, compared with a norm group of 
      {response_count} respondents.

      Sample composition: {sample_description}

# No diagnostic language (PRD §9)
result_phrasing:
  allowed:
    - "Your score on {dimension} is higher than {percentile}% of respondents"
    - "You scored in the {range} range on {dimension}"

  forbidden:
    - "You have high/low {construct}"
    - "You are at risk for..."
    - Any condition names or diagnostic terms

# Business draft disclaimer (PRD §9)
business_disclaimer: |
  This is a draft assessment for review by a qualified professional. It is not a 
  selection-ready hiring test and should not be used for employment decisions 
  without appropriate validation and legal review.

# Hackathon roadmap (PRD §12)
roadmap_items:
  - "Business mode polish"
  - "Multilingual scales (including Indonesian)"
  - "Item Response Theory (IRT) analysis"
  - "Norm analytics and dataset tools"

# Error messages
errors:
  config_null: "Configuration value '{key}' has not been set. Owner decision required before this operation can proceed."
  config_invalid: "Configuration value '{key}' is invalid: {reason}"
  pipeline_failed: "Scale generation failed at stage '{stage}'. Review the logs for details."
```

### Config loader (`src/lib/config.ts`)

**Purpose:** Load YAML configs and enforce null-checking.

```typescript
import * as fs from "fs";
import * as yaml from "js-yaml";
import * as path from "path";

export class ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ConfigError";
  }
}

export class PsychometricConfig {
  private config: any;

  constructor(configPath: string = "app-config/psychometric-procedure.yaml") {
    const fullPath = path.resolve(process.cwd(), configPath);
    const fileContents = fs.readFileSync(fullPath, "utf8");
    this.config = yaml.load(fileContents);
  }

  /**
   * Get a config value. Throws if the value is null.
   */
  get(keyPath: string): any {
    const value = this.getPath(this.config, keyPath);

    if (value === null || value === undefined) {
      throw new ConfigError(
        `Configuration value '${keyPath}' has not been set. Owner decision required.`,
      );
    }

    return value;
  }

  /**
   * Get a config value, allowing null (for optional values).
   */
  getOptional(keyPath: string, defaultValue?: any): any {
    const value = this.getPath(this.config, keyPath);
    return value !== null && value !== undefined ? value : defaultValue;
  }

  /**
   * Check if a value is set (not null).
   */
  isSet(keyPath: string): boolean {
    const value = this.getPath(this.config, keyPath);
    return value !== null && value !== undefined;
  }

  private getPath(obj: any, path: string): any {
    return path.split(".").reduce((current, key) => current?.[key], obj);
  }
}

export class ModelConfig {
  private config: any;

  constructor(configPath: string = "app-config/model-config.yaml") {
    const fullPath = path.resolve(process.cwd(), configPath);
    const fileContents = fs.readFileSync(fullPath, "utf8");
    this.config = yaml.load(fileContents);
  }

  getStageModel(stage: string) {
    const stageConfig = this.config.stages?.[stage];

    if (!stageConfig) {
      throw new ConfigError(
        `No model configuration found for stage '${stage}'`,
      );
    }

    if (stageConfig.model === null || stageConfig.vendor === null) {
      throw new ConfigError(
        `Model provider not set for stage '${stage}'. Owner decision required.`,
      );
    }

    return stageConfig;
  }

  getJudges() {
    const judges = this.config.stages?.content_panel?.judges;

    if (!judges || judges.length === 0) {
      throw new ConfigError("No content panel judges configured");
    }

    // Verify multi-vendor requirement (FR-PANEL-3)
    const vendors = new Set(
      judges.map((j: any) => j.vendor).filter((v: any) => v !== null),
    );
    if (vendors.size < 2) {
      throw new ConfigError(
        "Content panel requires at least 2 different vendors (FR-PANEL-3)",
      );
    }

    return judges;
  }

  getPromptVersion(stage: string): string {
    return this.config.prompt_versions?.[stage] || "unknown";
  }
}

export class CopyTextConfig {
  private config: any;

  constructor(configPath: string = "app-config/copy-text.yaml") {
    const fullPath = path.resolve(process.cwd(), configPath);
    const fileContents = fs.readFileSync(fullPath, "utf8");
    this.config = yaml.load(fileContents);
  }

  get(keyPath: string): string {
    const value = this.getPath(this.config, keyPath);

    if (typeof value !== "string") {
      throw new ConfigError(
        `Copy text '${keyPath}' is not a string or not found`,
      );
    }

    return value;
  }

  /**
   * Get text with variable interpolation.
   */
  interpolate(keyPath: string, vars: Record<string, any>): string {
    let text = this.get(keyPath);

    for (const [key, value] of Object.entries(vars)) {
      text = text.replace(new RegExp(`\\{${key}\\}`, "g"), String(value));
    }

    return text;
  }

  private getPath(obj: any, path: string): any {
    return path.split(".").reduce((current, key) => current?.[key], obj);
  }
}

// Singleton instances
export const psychometricConfig = new PsychometricConfig();
export const modelConfig = new ModelConfig();
export const copyTextConfig = new CopyTextConfig();
```

### Usage example

```typescript
import { psychometricConfig, modelConfig, copyTextConfig } from "@/lib/config";

// In content panel agent
try {
  const iCviThreshold = psychometricConfig.get("content_panel.i_cvi_threshold");
  const judges = modelConfig.getJudges();

  // ... proceed with panel logic
} catch (error) {
  if (error instanceof ConfigError) {
    // Stop pipeline, ask owner for decision
    console.error(error.message);
    // ... trigger interrupt or admin notification
  }
  throw error;
}

// In respondent feedback UI
const feedbackIntro = copyTextConfig.interpolate("feedback.tier2.intro", {
  response_count: scale.response_count,
});
```

---

## Risks and mitigations

| Risk                                    | Likelihood | Mitigation                                                       |
| --------------------------------------- | ---------- | ---------------------------------------------------------------- |
| Config files get out of sync with code  | Medium     | Use TypeScript types derived from YAML schemas; validate on load |
| Owner forgets to decide critical values | High       | Explicit error messages; block pipeline progress                 |
| YAML syntax errors break loading        | Medium     | Validate YAML on commit (pre-commit hook in future spec)         |
| Sensitive data accidentally in config   | Low        | Config is committed; never put secrets here (env vars only)      |

---

## Tasks

### Setup

- [ ] Create `app-config/` directory
- [ ] Install `js-yaml`: `npm install js-yaml @types/js-yaml`

### Config files

- [ ] Create `psychometric-procedure.yaml` with all threshold fields
- [ ] Mark decided values (tier thresholds, persona multiplier, target items)
- [ ] Mark undecided values as `null` with comments referencing literature
- [ ] Create `model-config.yaml` with per-stage structure
- [ ] Leave provider/model fields as `null` (pending owner decision)
- [ ] Create `copy-text.yaml` with informed consent, warnings, labels
- [ ] Draft informed consent text (owner to review)
- [ ] Draft clinical warning text (scientist vs business)

### Loader implementation

- [ ] Create `src/lib/config.ts` with loader classes
- [ ] Implement `PsychometricConfig` with `get()` and `getOptional()`
- [ ] Implement `ModelConfig` with stage and judge getters
- [ ] Implement `CopyTextConfig` with interpolation
- [ ] Add `ConfigError` class
- [ ] Export singleton instances

### Testing

- [ ] Manual test: load each config file
- [ ] Manual test: access decided value → succeeds
- [ ] Manual test: access `null` value → throws `ConfigError`
- [ ] Manual test: interpolate copy text → variables replaced
- [ ] Verify error messages are actionable

### Documentation

- [ ] Create `app-config/README.md` explaining:
  - Purpose of each file
  - How to decide null values (owner process)
  - How agents use config (import singleton, call get())
  - What happens when null is accessed (error, pipeline stops)
  - Literature reference values (in comments, not defaults)

---

## Acceptance

This spec is complete when:

1. All three config files exist with correct structure
2. Decided values filled in; undecided values = `null` with comments
3. Config loader classes work correctly
4. `ConfigError` is thrown for `null` access
5. README documents the config system
6. Code committed
7. Journal entry documents which values are decided vs pending

---

## References

- PRD: NFR-2 (config over code), all FR-\* sections with thresholds
- Steering: `00-project-rules.md` (config-driven rule)
- Interview: Decisions on tier thresholds, persona multiplier, target items

---

**Next spec:** `04-interviewer-agent.md` (first agent, Strands SDK smoke test)
