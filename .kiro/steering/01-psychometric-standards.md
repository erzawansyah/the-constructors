---
inclusion: always
---

# Psychometric Standards — The Constructors

This steering file documents the psychometric practice standards that The Constructors follows. These are grounded in the literature listed in PRD §15.

## Item-writing rules (FR-ITEM-6)

When generating or reviewing items:

1. **One idea per item** — no double-barreled statements
2. **Short, plain, first-person declarative sentences** — "I feel anxious about Monday mornings" not "One might experience a sense of trepidation"
3. **No jargon or slang** — accessible to the target population
4. **No absolute terms** — avoid "always", "never", "all", "none"
5. **No double negatives** — "I don't avoid..." becomes "I engage with..."
6. **Avoid extreme endorsement** — items nearly everyone or no one would endorse are uninformative
7. **Feelings must have an object or situation** — "I feel dread" → "I feel dread about the coming work week"
8. **Reduce evaluative loading** — minimize social desirability bias
9. **Consistent time frame** — present tense for current states, past week for recent experiences
10. **No identity bias** — avoid assumptions about gender, culture, occupation unless part of the construct
11. **No negative-affect terms unless the construct is negative affect** — don't conflate measurement
12. **Do not copy or closely paraphrase published items** — especially from closed-license scales

**All items keyed in one direction.** No reverse-worded items (see García-Fernández et al. 2022; Zeng et al. 2020, 2024; Widhiarso et al. 2025).

## Content screening labeling

LLM judges (FR-PANEL) are **not independent** the way human expert panels are. They share training data and may exhibit correlated biases.

**Always label results as:**
- ✅ "LLM content screening"
- ❌ NOT "content validity" or "expert panel validation"

Report the limitation explicitly: "LLM judges were used for relevance and distinctiveness screening. These are not independent human experts."

## Structural screening labeling (AI-GENIE)

Structural screening (FR-STRUCT) uses semantic similarity of item embeddings, not response covariance from real people.

**Always label as:**
- ✅ "Structural semantic screening"
- ❌ NOT "factor structure" or "dimensionality from respondent data"

Report explicitly: "Items were screened for semantic redundancy and instability using embedding-based network analysis. This is not equivalent to factor analysis of human responses."

## Simulation is not validation

The smoke test (FR-SIM) rehearses the CFA code path with known-structure data to verify the pipeline works. It does **not** validate the scale.

**Always label as:**
- ✅ "Technical rehearsal (smoke test)"
- ❌ NOT "validation", "pilot study", or "preliminary evidence"

Never use rigid fit cut-offs (CFI > .95, RMSEA < .06) as a pass/fail verdict on simulated data. Report whether planted structure was recovered and flag anomalies.

**Simulated data is never shown to respondents and never used for norms or comparisons.**

## Validity ladder

Every scale report shows its evidence tier:

1. ✅ Passed LLM content screening (I-CVI, k*, Hinkin-Tracey c/d)
2. ✅ Passed structural semantic screening (AI-GENIE: UVA + bootEGA)
3. ✅ Passed technical rehearsal (smoke test: simulated CFA)
4. ⬜ Human data
5. ⬜ Norms (≥ 1,000 respondents, configurable)

New scales sit at rung 3. Only real human responses move a scale past it.

## No diagnostic language

This is a tool for **non-clinical self-insight and research**, not diagnosis.

**For respondents:**
- ✅ "Your score on this dimension is higher than 68% of respondents so far"
- ❌ NOT "You have high anxiety" or "You are at risk for..."

**For creators:**
- Business output is a **draft for review by a qualified professional**, not a selection-ready hiring test.

**Clinical constructs:**
- Business users: automatically redirect to a nearby non-clinical construct (e.g. "workplace stress" instead of "depression")
- Scientists: show explicit warning before proceeding, never block

## Content validity indices (FR-PANEL-2)

The exact formulas for Hinkin-Tracey **definitional correspondence (c)** and **distinctiveness (d)** must be verified against **Colquitt et al. (2019)** before implementation.

Do not use approximate or "similar" formulas from other sources. This is an open question (PRD §14 #3) and requires owner verification.

## Reference literature

Owner's library (PRD §15) includes:

- **AI-GENIE approach:** Russell-Lasalandra, Christensen & Golino (2024/2026)
- **LLM-based AIG:** Lee, Son & Jia (2025); Zhang, Suzuki & Zhou (preprint); Götz et al. (2023); and others
- **Content validity:** Polit & Beck (2006); Almanasreh et al. (2019); Haynes et al. (1995)
- **Scale development:** Clark & Watson (2019); Boateng et al. (2018); DeVellis & Thorpe (2022); and others
- **Factor analysis:** Brown (2015); Kline (2023); Alamer (2022)
- **Reverse items issues:** García-Fernández et al. (2022); Zeng et al. (2020, 2024)
- **Method effects:** Widhiarso et al. (2025); Widhiarso & Hanifa (2022); Widhiarso (2016)
- **Testing standards:** AERA, APA & NCME (2014)

When making psychometric decisions, cite relevant sources from this list or from literature research output.

## Thresholds are config, not code

All numeric cut-offs (I-CVI ≥ .78, S-CVI/Ave ≥ .90, k* > .74, c > .88, d > .35, wTO, stability, etc.) live in `app-config/psychometric-procedure.yaml`.

Literature reference points are documented in comments but **never hardcoded as defaults**. If the owner has not set a value, the system stops and asks.
