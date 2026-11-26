# Spec 01 — Spike: R Statistics Service

**Status:** Draft  
**Priority:** P0 (foundation for FR-STRUCT, FR-SIM)  
**Requirements:** FR-STRUCT, FR-SIM, NFR-7  
**Dependencies:** None

---

## Goal

Build and test the R statistics service (plumber JSON API) with two endpoints:
1. `/ega` — EGAnet structural screening (UVA + bootEGA + NMI)
2. `/cfa` — lavaan confirmatory factor analysis (WLSMV for ordinal data)

Verify the service works end-to-end with sample data and that tests check **numeric output**, not just "does not crash" (NFR-7).

---

## Success criteria

- [ ] R service runs on `localhost:8000` (configurable via env var)
- [ ] `/health` endpoint returns `{"status": "ok"}`
- [ ] `/ega` endpoint accepts embedding matrix, returns UVA + bootEGA + NMI results
- [ ] `/cfa` endpoint accepts ordinal response matrix, returns fit indices + loadings
- [ ] Test suite verifies numeric output against known values
- [ ] Error handling returns HTTP 400 for null config, HTTP 500 for R errors
- [ ] Service can be started with `Rscript r-service/api.R`

---

## Non-goals (for this spike)

- Containerizing the R service (future, if needed)
- Performance optimization or caching
- Authentication (service is internal, not public-facing)
- Full production logging (stdout is sufficient for spike)

---

## Technical approach

### Directory structure

```
r-service/
├── api.R                 # plumber API definition
├── ega.R                 # EGAnet logic (UVA, bootEGA, NMI)
├── cfa.R                 # lavaan CFA logic
├── utils.R               # Shared utilities (error handling, validation)
├── tests/
│   ├── run_all.R         # Test runner
│   ├── test_ega.R        # EGA endpoint tests with known data
│   ├── test_cfa.R        # CFA endpoint tests with known data
│   └── fixtures/
│       ├── ega_input.json      # 18-item 3-factor embedding matrix
│       ├── ega_expected.json   # Expected UVA/bootEGA results
│       ├── cfa_input.json      # 300×12 simulated ordinal responses
│       └── cfa_expected.json   # Expected fit indices
└── README.md
```

### R packages required

Install before running:

```r
install.packages(c(
  "plumber",    # JSON HTTP API
  "EGAnet",     # UVA, bootEGA, NMI
  "lavaan",     # CFA
  "igraph",     # NMI computation
  "jsonlite"    # JSON parsing
))
```

### Endpoint 1: `/ega`

**Contract:** See `03-statistics-contract.md` steering file

**Implementation steps:**

1. Parse JSON request, validate structure
2. Check for null config values → HTTP 400 if found
3. Convert embeddings to matrix
4. Run `EGAnet::UVA()` with `wto` threshold
5. Run `EGAnet::bootEGA()` on retained items with stability threshold
6. Compute NMI (initial vs final) with `igraph::compare()`
7. Return JSON response with removed items, retained items, stability per item, NMI

**Test fixture:**

- **Input:** 18 items, 3 dimensions (6 items each), embeddings generated with known redundancies
  - Items 3, 7 planted as near-duplicates (high wTO)
  - Item 12 planted with cross-loading (low stability)
- **Expected output:** Items 3, 7 flagged by UVA; item 12 flagged by bootEGA; NMI improves from ~0.68 to ~0.84

**Test verification:** Assert removed item IDs match expected; NMI values within ±0.05 of expected.

### Endpoint 2: `/cfa`

**Contract:** See `03-statistics-contract.md` steering file

**Implementation steps:**

1. Parse JSON request, validate structure
2. Check ordinal flag, set estimator (WLSMV if true, ML if false)
3. Build lavaan model syntax from `model_specification.factors`
4. Run `lavaan::cfa()` with specified estimator
5. Extract fit indices with `lavaan::fitMeasures()`
6. Extract standardized loadings with `lavaan::standardizedSolution()`
7. Handle non-convergence → return HTTP 200 with `"status": "warning"`
8. Return JSON response

**Test fixture:**

- **Input:** 300 personas × 12 items, 2 factors (6 items each), responses generated from known structure
  - Factor 1 loadings: 0.75–0.85
  - Factor 2 loadings: 0.70–0.80
  - Factor correlation: r = 0.5
  - Likert scale: 1–5
- **Expected output:** 
  - Loadings within ±0.10 of planted values
  - CFI > 0.95
  - RMSEA < 0.06
  - Factor correlation ≈ 0.5 ±0.1

**Test verification:** Assert fit indices in expected ranges; loadings within tolerance.

### Error handling

All endpoints must:

1. Catch R errors with `tryCatch()`
2. Return structured JSON error response
3. Use appropriate HTTP status codes:
   - 200: Success or warning (check `status` field)
   - 400: Bad request (malformed JSON, null config, dimension mismatch)
   - 500: Internal R error (with stack trace in `message`)

Example error response:

```json
{
  "status": "error",
  "message": "config.wto_threshold is null; owner decision required",
  "request_id": "uuid"
}
```

### Health check

```r
#* Health check
#* @get /health
function() {
  list(status = "ok", timestamp = Sys.time())
}
```

---

## Test strategy (NFR-7)

**Principle:** Tests must verify **numeric correctness**, not just exit codes.

### Test execution

```bash
cd r-service
Rscript tests/run_all.R
```

Expected output:

```
Running EGA tests...
✓ UVA identifies planted redundancies
✓ bootEGA identifies planted instability
✓ NMI improves as expected
✓ Error handling: null config rejected

Running CFA tests...
✓ Planted loadings recovered within tolerance
✓ Fit indices in expected range
✓ Non-convergence handled gracefully
✓ Error handling: dimension mismatch rejected

All tests passed.
```

### Fixture generation

Test fixtures are **committed to git** (not generated dynamically) so tests are deterministic.

Generate fixtures with:

```r
# r-service/tests/generate_fixtures.R
# (Run once, commit output)
```

Document planted values in fixture JSON comments or README.

---

## Integration with Next.js

This spike focuses on the R service in isolation. Integration with Next.js happens in Spec 9 (structural screening) and Spec 10 (simulation).

Sketch of client call (not implemented in this spec):

```typescript
// Future: src/lib/r-service-client.ts
const response = await fetch(`${process.env.R_SERVICE_URL}/ega`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    embeddings: embeddingMatrix,
    item_ids: itemIds,
    intended_dimensions: dimensionAssignment,
    config: {
      wto_threshold: procedure.structural.wto_threshold,
      stability_threshold: procedure.structural.stability_threshold,
      boot_iterations: procedure.structural.boot_iterations
    }
  })
});

if (!response.ok) {
  throw new Error(`R service error: ${response.status}`);
}

const result = await response.json();
if (result.status === 'error') {
  throw new Error(result.message);
}
```

---

## Risks and mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| EGAnet/lavaan not behaving as expected | Medium | Use well-documented functions; verify against package vignettes |
| Test fixtures don't match planted structure | Medium | Generate with known code, validate visually before committing |
| R service crashes under malformed input | Low | Extensive validation and error handling |
| Non-reproducible results (random seed) | Medium | Set seed explicitly in bootEGA; document in test fixtures |

---

## Tasks

### Setup

- [ ] Create `r-service/` directory structure
- [ ] Write `r-service/README.md` with installation and run instructions
- [ ] Install R packages (document versions in README)

### Implementation

- [ ] `r-service/api.R`: plumber app with `/health`, `/ega`, `/cfa` routes
- [ ] `r-service/ega.R`: UVA + bootEGA + NMI logic
- [ ] `r-service/cfa.R`: lavaan CFA with WLSMV
- [ ] `r-service/utils.R`: JSON validation, error handling helpers

### Testing

- [ ] Generate test fixtures: `tests/fixtures/*.json`
- [ ] `tests/test_ega.R`: EGA endpoint tests with numeric assertions
- [ ] `tests/test_cfa.R`: CFA endpoint tests with numeric assertions
- [ ] `tests/run_all.R`: Test runner with summary output
- [ ] Verify all tests pass

### Verification

- [ ] Start service: `Rscript r-service/api.R`
- [ ] Manual smoke test: `curl http://localhost:8000/health`
- [ ] Manual smoke test: POST sample data to `/ega` and `/cfa` with `curl` or Postman
- [ ] Document any deviations from expected behavior in journal

---

## Acceptance

This spec is complete when:

1. R service starts without errors
2. All test suite tests pass with numeric assertions
3. Manual smoke tests confirm endpoints respond correctly
4. Code is committed with test fixtures and README
5. Journal entry documents any discoveries or owner decisions

---

## References

- PRD: FR-STRUCT (structural screening), FR-SIM (simulation), NFR-7 (correctness of statistics)
- Steering: `03-statistics-contract.md` (endpoint contracts)
- Literature: Russell-Lasalandra, Christensen & Golino (2024/2026) for AI-GENIE approach
- R packages: EGAnet, lavaan, igraph documentation

---

**Next spec:** `02-setup-supabase-schema.md` (database foundation)
