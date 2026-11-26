---
inclusion: fileMatch
fileMatchPattern: ["r-service/**"]
---

# Statistics Service Contract — R (plumber) JSON API

The R statistics service provides EGAnet and lavaan endpoints for structural screening and CFA.

## Service configuration

- **Default URL:** `http://localhost:8000`
- **Environment variable:** `R_SERVICE_URL`
- **Process:** Separate from Next.js app (not containerized by default, runs on same host)
- **API framework:** plumber (R package for JSON HTTP APIs)

## Endpoint 1: `/ega` — Structural screening (AI-GENIE)

**Method:** POST

**Purpose:** Remove redundant items (UVA) and unstable items (bootEGA), compute NMI against intended structure.

### Request schema

```json
{
  "embeddings": [
    [0.123, -0.456, 0.789, ...],  // item 1 embedding (vector length = embedding_dim)
    [0.234, -0.567, 0.890, ...],  // item 2
    ...
  ],
  "item_ids": ["item_001", "item_002", ...],
  "intended_dimensions": [0, 0, 1, 1, 2, 2, ...],  // dimension assignment per item
  "config": {
    "wto_threshold": null,          // null triggers error
    "stability_threshold": null,    // null triggers error
    "boot_iterations": null          // null triggers error
  }
}
```

**Notes:**

- `embeddings`: numeric matrix, one row per item, columns = embedding dimensions
- `item_ids`: string array, same length as embeddings
- `intended_dimensions`: integer array (0-indexed), same length as embeddings
- All `config` values must be non-null; R service returns HTTP 400 if null

### Response schema (success)

```json
{
  "status": "success",
  "uva": {
    "removed_items": ["item_003", "item_007"],
    "reason": "weighted topological overlap >= 0.25"
  },
  "bootega": {
    "removed_items": ["item_012"],
    "reason": "stability < 0.75 over 500 iterations",
    "stability_per_item": {
      "item_001": 0.92,
      "item_002": 0.88,
      ...
    }
  },
  "retained_items": ["item_001", "item_002", "item_004", ...],
  "nmi": {
    "initial": 0.68,
    "final": 0.84
  }
}
```

### Response schema (error)

```json
{
  "status": "error",
  "message": "config.wto_threshold is null; owner decision required"
}
```

**R packages used:**

- `EGAnet::UVA()` — redundancy removal
- `EGAnet::bootEGA()` — stability analysis
- `igraph::compare()` — NMI computation

---

## Endpoint 2: `/cfa` — Confirmatory factor analysis (smoke test)

**Method:** POST

**Purpose:** Run CFA (WLSMV estimator for ordinal data) on simulated persona responses, verify planted structure is recovered.

### Request schema

```json
{
  "responses": [
    [4, 5, 3, 4, 2, ...],  // persona 1 responses (integers, Likert scale)
    [3, 4, 4, 5, 3, ...],  // persona 2
    ...
  ],
  "item_ids": ["item_001", "item_002", ...],
  "model_specification": {
    "factors": [
      {
        "name": "AnticDread",
        "items": ["item_001", "item_002", "item_003"]
      },
      {
        "name": "WorkRumination",
        "items": ["item_004", "item_005", "item_006"]
      }
    ]
  },
  "ordinal": true  // use WLSMV estimator
}
```

**Notes:**

- `responses`: integer matrix, rows = personas, columns = items
- `item_ids`: string array, same length as number of columns
- `model_specification.factors`: list of factor definitions (item → factor mapping)
- `ordinal`: boolean; if true, use WLSMV; if false, use ML

### Response schema (success)

```json
{
  "status": "success",
  "fit_indices": {
    "chisq": 42.3,
    "df": 24,
    "pvalue": 0.012,
    "cfi": 0.976,
    "tli": 0.968,
    "rmsea": 0.048,
    "rmsea_ci_lower": 0.021,
    "rmsea_ci_upper": 0.072,
    "srmr": 0.035
  },
  "loadings": {
    "AnticDread": {
      "item_001": 0.78,
      "item_002": 0.82,
      "item_003": 0.71
    },
    "WorkRumination": {
      "item_004": 0.85,
      "item_005": 0.79,
      "item_006": 0.73
    }
  },
  "factor_correlations": {
    "AnticDread_WorkRumination": 0.54
  },
  "warnings": []
}
```

### Response schema (non-convergence)

```json
{
  "status": "warning",
  "message": "Model did not converge after 1000 iterations",
  "partial_fit_indices": { ... },
  "lavaan_warnings": ["..."]
}
```

**R packages used:**

- `lavaan::cfa()` — CFA with WLSMV estimator
- `lavaan::fitMeasures()` — extract fit indices

---

## Error handling

All endpoints return:

- **HTTP 200** for success or warning (check `status` field in JSON)
- **HTTP 400** for bad request (malformed JSON, null config values, dimension mismatch)
- **HTTP 500** for internal R errors (include stack trace in `message`)

Client (Next.js) must:

1. Check HTTP status
2. Parse JSON
3. Check `status` field (`"success"` | `"warning"` | `"error"`)
4. Handle null config values before calling (never send null to R service)

---

## Testing strategy (NFR-7)

The R service must be tested against **known results**, not just "does not crash":

### EGA test fixture

- Input: 18-item embedding matrix from a 3-factor structure (6 items per factor, known redundancies planted)
- Expected output: specific items flagged as redundant, NMI values in expected range

### CFA test fixture

- Input: 300 personas × 12 items, responses generated from known factor structure (2 factors, correlation r=0.5)
- Expected output: loadings within ±0.1 of planted values, CFI > 0.95, RMSEA < 0.06

**Test files:** `r-service/tests/test_ega.R`, `r-service/tests/test_cfa.R`

Run with: `Rscript r-service/tests/run_all.R`

Verify numeric output, not just exit code.

---

## Deployment notes

The R service runs as a **separate process** (not containerized by default):

```bash
# Install dependencies
Rscript -e "install.packages(c('plumber', 'EGAnet', 'lavaan', 'igraph'))"

# Start service
Rscript r-service/api.R
```

**Docker option (future):** If needed, add `r-service/Dockerfile` and include in `docker-compose.yml`.

**Health check endpoint:** `/health` (returns `{"status": "ok"}`)

**Logging:** R service logs to stdout; Next.js app logs R service calls for traceability.
