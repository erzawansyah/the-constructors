# R Statistics Service

A plumber JSON API that wraps EGAnet and lavaan for The Constructors. It runs as a separate process from the Next.js app.

- `POST /ega`: structural semantic screening of item embeddings (UVA redundancy removal, bootEGA stability removal, NMI against the intended structure).
- `POST /cfa`: confirmatory factor analysis on simulated persona responses.
- `GET /health`: liveness check.

Request and response schemas are in the statistics contract (`.kiro/steering/03-statistics-contract.md`).

## Required packages

Minimum versions are the versions installed and tested (recorded in `PACKAGE_VERSIONS.md`; R 4.6.1).

| Package  | Minimum version | Used for                                              |
| -------- | --------------- | ----------------------------------------------------- |
| plumber  | 1.3.3           | HTTP JSON API                                         |
| EGAnet   | 2.4.1           | `EGA`, `UVA`, `bootEGA`, `itemStability`              |
| lavaan   | 0.6.21          | `cfa`, `fitMeasures`, `standardizedSolution`          |
| igraph   | 2.3.3           | `compare(method = "nmi")`                             |
| jsonlite | 2.0.0           | JSON parsing and serialization                        |
| uuid     | 1.2.2           | request IDs                                           |
| MASS     | 7.3.65          | `mvrnorm`, only in `tests/generate_fixtures.R`        |
| testthat | 3.3.2           | test-only, `tests/test_properties.R`                  |
| hedgehog | 0.2             | test-only, property-based tests                       |

`testthat` and `hedgehog` are never loaded by `api.R`. MASS ships with R as a recommended package.

### Install

```bash
Rscript r-service/install_packages.R
```

Already-installed packages are skipped. The script exits with status 1 if a package still cannot be loaded, and prints each installed version. Set `R_SERVICE_CRAN_MIRROR` to use a mirror other than `https://cloud.r-project.org`.

## Start the service

```bash
Rscript r-service/api.R
```

If a required package is missing, the service writes the list to stderr and exits with status 1.

| Variable           | Default     | Meaning                                                              |
| ------------------ | ----------- | -------------------------------------------------------------------- |
| `R_SERVICE_HOST`   | `127.0.0.1` | Interface to bind                                                    |
| `R_SERVICE_PORT`   | `8000`      | Port to listen on                                                    |
| `R_SERVICE_CORS`   | unset       | CORS headers are added only when set to `true`                       |

The Next.js app reads the service address from `R_SERVICE_URL` (default `http://localhost:8000`).

## Health check

```bash
curl http://localhost:8000/health
```

Returns `{"status":"ok","timestamp":"<ISO 8601>"}`.

## Tests

Run from `r-service/`:

```bash
cd r-service
Rscript tests/run_all.R
```

The runner exits 0 and prints `All tests passed`, or exits 1 and prints the failed assertion count. Read the printed numeric values (removed items, NMI, loadings, fit indices, Holzinger differences), not only the exit code.

Regenerate the fixtures (also from `r-service/`):

```bash
cd r-service
Rscript tests/generate_fixtures.R
```

This rewrites `tests/fixtures/ega_input.json`, `ega_expected.json`, `cfa_input.json` and `cfa_expected.json`. The EGA expected values are recorded from a real pipeline run, not set by hand. Review the diff before committing regenerated fixtures.

## Behavior to know

- **No default thresholds.** The service has no default psychometric thresholds. Every `config` field in a `/ega` request (`wto_threshold`, `stability_threshold`, `boot_iterations`, `network_method`, `community_algorithm`, `random_seed`, `uva_method`, `bootstrap_type`) must be non-null. A null or missing field returns HTTP 400, for example `config.wto_threshold is null; owner decision required`. Values come from `app-config/psychometric-procedure.yaml` via the caller. Config values inside `tests/` and the fixtures are **TEST ONLY** and are not production values.
- **`config.uva_method` accepts only `"mbr"`** (any letter case). `"ejp"` is rejected with HTTP 400 before any computation, because UVA with `"ejp"`, `reduce.method = "remove"` and `auto = TRUE` waits for interactive input and would hang the process. Any other value is also rejected with HTTP 400.
- **Seeding.** `config.random_seed` is passed to `bootEGA` as a double and used in `set.seed()` before every `EGAnet::EGA` call, because `EGA` has no seed argument.
- **Ordinal `/cfa` fit indices.** When `ordinal` is true (WLSMV), the response has `"fit_variant": "scaled_robust"`: `chisq`, `df`, `pvalue` come from lavaan's `.scaled` values, and `cfi`, `tli`, `rmsea` and its CI from the `.robust` values. `srmr` is unchanged. When `ordinal` is false (ML), `fit_variant` is `"standard"` with the unsuffixed lavaan values. Values that R reports as `NA` are returned as JSON `null`.
- **Labeling.** CFA output is a technical rehearsal (smoke test), not validation. The service applies no fit cut-offs; fit indices are reported for inspection only. `/ega` results are structural semantic screening of embeddings, not factor analysis of human responses. Simulated data is never shown to respondents or used for norms.
- **Errors.** HTTP 200 for `success` and `warning`, 400 for bad requests (malformed JSON, null or missing config, dimension mismatch), 500 for internal errors. Error bodies contain `status`, `message` and `request_id`, without stack traces.
- **Logging.** One JSON object per line: stdout for success, stderr for errors. Each entry has `timestamp`, `request_id`, `endpoint` and `execution_duration_ms`, plus the endpoint-specific fields used for traceability.

## Probe notes

`probe.R` calls EGAnet and lavaan on small sample data and prints argument names, result structures and field paths. The wrappers follow what the probe showed; where the probe and package documentation disagree, the probe wins.

- `PROBE_NOTES.md`: findings, the table comparing design names with probe results, and the owner decisions that followed.
- `probe_output.txt`: raw probe output (about 3,250 lines, mostly a `ggplot` object dump; search for the numbered section headers).

Rerun the probe after any EGAnet or lavaan upgrade, or when a wrapper reports an unexpected missing field. Run it from the repository root, with stdin closed so an unexpected interactive prompt cannot block it:

```bash
Rscript r-service/probe.R > r-service/probe_output.txt 2>&1 < /dev/null
```

Then update `PROBE_NOTES.md` and its comparison table, and re-run the tests.

## Directory layout

```
r-service/
├── api.R                      plumber entry point: package check, routes, error handler, CORS, host/port
├── install_packages.R         installs required and test-only packages, prints versions
├── probe.R                    development probe of EGAnet and lavaan (sample values are probe-only)
├── probe_output.txt           raw output of the last probe run
├── PROBE_NOTES.md             probe findings and design.md comparison
├── PACKAGE_VERSIONS.md        installed package versions (source of the minimums above)
├── README.md                  this file
├── config/
│   └── loader.R               validate_config(): null/missing fields, uva_method check; no defaults
├── validation/
│   └── request_validator.R    validate_ega_request(), validate_cfa_request()
├── utils/
│   └── conditions.R           validation_error(), new_request_id(), parse_json_body()
├── logging/
│   └── logger.R               JSON-line logging for /ega, /cfa and errors
├── ega/
│   ├── pipeline.R             execute_ega_pipeline(), run_ega() (only caller of EGAnet::EGA)
│   ├── uva.R                  run_uva_loop(): UVA until a pass removes nothing
│   ├── bootega.R              run_bootega_loop(): bootEGA and item stability until all items are stable
│   └── nmi.R                  compute_nmi() via igraph::compare
├── cfa/
│   ├── pipeline.R             execute_cfa_pipeline()
│   ├── model_builder.R        build_lavaan_model()
│   ├── estimator.R            run_cfa(): WLSMV (ordinal) or ML
│   └── extractor.R            fit indices (fit_variant), loadings, factor correlations
└── tests/
    ├── run_all.R              test runner (custom tests plus testthat property tests)
    ├── helpers.R              assert_true, assert_equal, assert_near, assert_in_range, assert_set_equal
    ├── generate_fixtures.R    generates fixtures and records expected values (TEST ONLY config)
    ├── test_ega.R             EGA fixture test: planted redundancy, NMI, reproducibility
    ├── test_cfa.R             CFA fixture test: planted loadings and factor correlation
    ├── test_holzinger.R       /cfa vs direct lavaan on HolzingerSwineford1939
    ├── test_errors.R          HTTP 400/500 handling, uva_method rejection, NA serialization
    ├── test_units.R           unit tests for helpers and extractors
    ├── test_properties.R      property-based tests (hedgehog) for three pure helpers
    └── fixtures/
        ├── ega_input.json, ega_expected.json
        └── cfa_input.json, cfa_expected.json
```
