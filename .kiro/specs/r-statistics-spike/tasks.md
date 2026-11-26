# Implementation Plan: R Statistics Spike

## Overview

Build the plumber R service in `r-service/` in this order: install packages and create the skeleton, run `probe.R` and record what EGAnet and lavaan actually return, write the wrappers to match the probe output, generate fixtures and record expected values from a real run, write and run the numeric tests, then document the service.

Hard rules for every task:

- No task sets production threshold values. `app-config/psychometric-procedure.yaml` values stay null and are not created or filled by this spec. Config values appear only inside test fixtures and test code, and each place is labeled `"TEST ONLY"`.
- No task writes to `notes/`. Probe findings go in `r-service/`.
- No property-based tests (design.md, Testing Strategy). Correctness is checked with fixture tests, a lavaan reference test and example-based tests.
- Tolerances come from design.md as written. Where design.md delegates a tolerance to the fixture and neither design.md nor requirements.md gives a number, the task stops and asks the owner.

## Tasks

- [ ] 1. Set up packages, skeleton and the development probe
  - [ ] 1.1 Create the `r-service/` skeleton and package install script
    - Create the directories from design.md File structure: `config/`, `validation/`, `ega/`, `cfa/`, `logging/`, `utils/`, `tests/`, `tests/fixtures/`
    - Write `r-service/install_packages.R` installing plumber, EGAnet, lavaan, igraph, jsonlite, uuid, and MASS (MASS is used only by `tests/generate_fixtures.R`)
    - Run the script and record the installed `packageVersion()` of each package for the README minimum versions
    - _Requirements: 1.6, 11.1, 11.2_

  - [ ] 1.2 Write `r-service/probe.R`
    - Print `packageVersion()` for plumber, EGAnet, lavaan, igraph, jsonlite, uuid
    - Generate small sample data with a fixed seed: an item × embedding-dimension matrix (transposed before EGA, as in design.md step 4) and a small ordinal response data frame
    - Run `EGAnet::UVA`, `EGAnet::EGA`, `EGAnet::bootEGA`, `EGAnet::itemStability` (on the bootEGA result) and `lavaan::cfa` (ordinal, `estimator = "WLSMV"`, `std.lv = TRUE`)
    - Print `str()` and `names()` of each result, including `ega$wc`, the UVA reduced-data and wTO fields, the itemStability per-item output, `fitMeasures()` and `str(standardizedSolution())`
    - Print `args()` / `formals()` of `UVA`, `EGA`, `bootEGA`, `itemStability` so argument names are recorded
    - Label every sample parameter value in the script with a `# PROBE ONLY - not a production value` comment
    - _Requirements: 1.6, 3.3, 3.4, 3.7, 3.10, 4.2, 4.5, 4.6_

  - [ ] 1.3 Run the probe and record findings in `r-service/`
    - Run `Rscript r-service/probe.R > r-service/probe_output.txt 2>&1`
    - Write `r-service/PROBE_NOTES.md` summarizing: package versions, exact argument names for `UVA` (`cut.off`, `uva.method`, `reduce`, `reduce.method`, `auto`), `EGA` / `bootEGA` (`model`, `algorithm`, `iter`, `type`, `seed`), `itemStability`, and the result field paths for UVA reduced data, wTO scores, `wc`, and per-item stability
    - Cross-check each name against official package documentation (Context7 or CRAN reference manual) for the installed version, and record any disagreement. Where probe and documentation disagree, the probe wins (design.md Development probe rule 4)
    - Add a table comparing each design.md argument/field name with the probe result: match or differs
    - Do not write anything to `notes/`
    - _Requirements: 3.4, 3.7, 3.10, 11.7_

- [ ] 2. Checkpoint: probe findings review
  - Show `r-service/PROBE_NOTES.md` to the owner. If any argument name or result field path differs from design.md, stop and wait for the owner's decision before writing wrappers. Ensure all tests pass, ask the user if questions arise.

- [ ] 3. Implement shared utilities and validation
  - [ ] 3.1 Implement `r-service/utils/conditions.R` and `r-service/logging/logger.R`
    - `utils/conditions.R`: `validation_error(msg)` condition constructor with class `c("validation_error", "error", "condition")` and `call = NULL`; `new_request_id()` wrapping `uuid::UUIDgenerate()`; `parse_json_body(post_body)` that re-throws parse failures as `validation_error("Invalid JSON: <parser message>")`
    - `logging/logger.R`: `log_ega_execution()`, `log_cfa_execution()`, `log_error()` writing one JSON object per line with `jsonlite::toJSON(auto_unbox = TRUE)`; stdout for success, stderr for errors; common fields `timestamp` (ISO 8601), `request_id`, `endpoint`, `execution_duration_ms`; `/ega` and `/cfa` fields as listed in design.md Logging; error context excludes `embeddings` and `responses`
    - `utils/` is a small addition to the design.md layout to hold the shared condition and request_id helpers used by `config/` and `validation/`
    - _Requirements: 2.4, 5.1, 5.4, 5.5, 10.1, 10.2, 10.3, 10.4, 10.5, 10.6_

  - [ ] 3.2 Implement `r-service/config/loader.R`
    - `validate_config(config, required_fields)`: missing field → `validation_error("config.<field> is missing")`; null field → `validation_error("config.<field> is null; owner decision required")`
    - Define the `/ega` required field list: `wto_threshold`, `stability_threshold`, `boot_iterations`, `network_method`, `community_algorithm`, `random_seed`, `uva_method`, `bootstrap_type`
    - No default value for any field
    - _Requirements: 2.1, 2.2, 2.3, 3.2_

  - [ ] 3.3 Implement `r-service/validation/request_validator.R`
    - `validate_ega_request(body)`: required fields present; `embeddings` bound with `rbind` if a list of rows; numeric matrix with ≥ 2 rows; `item_ids` and `intended_dimensions` lengths equal the row count, with messages such as `"item_ids length (10) does not match embeddings rows (12)"`
    - `validate_cfa_request(body)`: required fields `responses`, `item_ids`, `model_specification`, `ordinal`; `responses` bound with `rbind` and checked as integer-valued; `item_ids` length equals the column count; every item in `model_specification.factors[*].items` is in `item_ids`, else `"Items in model_specification not found in item_ids: <ids>"`
    - All failures throw `validation_error`
    - _Requirements: 5.2, 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 9.7_

- [ ] 4. Implement EGA wrappers following the probe output
  - [ ] 4.1 Implement `r-service/ega/nmi.R`
    - `compute_nmi(detected, intended)`: error on unequal lengths; drop positions where either vector is NA (NA can occur in `wc`), warn with the dropped count; error if nothing remains; return `igraph::compare(detected, intended, method = "nmi")`
    - _Requirements: 3.11, 3.12_

  - [ ] 4.2 Implement `r-service/ega/uva.R`
    - `run_uva_loop(data, config)`: call `EGAnet::UVA` with `cut.off = config$wto_threshold`, `uva.method = config$uva_method`, `reduce = TRUE`, `reduce.method = "remove"`, `auto = TRUE`, `verbose = FALSE`, using argument names and result fields recorded in `r-service/PROBE_NOTES.md`
    - Record items dropped in each pass and their wTO scores; repeat on the reduced data until a pass removes nothing
    - Return `removed_items`, `removed_wto_scores`, `retained_data`
    - _Requirements: 3.4, 3.5, 3.6, 10.3_

  - [ ] 4.3 Implement `r-service/ega/bootega.R`
    - `run_bootega_loop(data, config)`: call `EGAnet::bootEGA` with `model = config$network_method`, `algorithm = config$community_algorithm`, `iter = config$boot_iterations`, `type = config$bootstrap_type`, `seed = config$random_seed`, `verbose = FALSE`; get per-item stability from `EGAnet::itemStability` using the call and field path in `PROBE_NOTES.md`
    - Remove every item with stability < `config$stability_threshold`, record its score, repeat until all remaining items are stable
    - Return `removed_items`, `removed_stability_scores`, `retained_data`, and `stability_per_item` from the last pass
    - _Requirements: 3.7, 3.8, 3.9, 3.10, 10.4_

  - [ ] 4.4 Implement `r-service/ega/pipeline.R`
    - `execute_ega_pipeline(body)`: `validate_ega_request` → `validate_config` → `t(embeddings)` with column names = `item_ids` → initial `EGAnet::EGA` and `nmi.initial` against `intended_dimensions + 1` → `run_uva_loop` → `run_bootega_loop` → final `EGAnet::EGA` on retained data and `nmi.final` against intended dimensions subset by retained item IDs, `+ 1`
    - Build the success response from design.md Data Models, with `uva.reason = "weighted topological overlap >= <wto_threshold>"` and `bootega.reason = "stability < <stability_threshold> over <boot_iterations> iterations"`, both interpolated from the request config
    - _Requirements: 3.1, 3.3, 3.6, 3.9, 3.11, 3.12, 3.13, 12.1_

- [ ] 5. Implement CFA wrappers following the probe output
  - [ ] 5.1 Implement `r-service/cfa/model_builder.R`
    - `build_lavaan_model(model_specification)`: one `<name> =~ item_a + item_b + ...` line per factor, joined by newlines
    - _Requirements: 4.4_

  - [ ] 5.2 Implement `r-service/cfa/estimator.R`
    - `run_cfa(model_syntax, response_df, item_ids, ordinal)`: `ordinal = TRUE` → `lavaan::cfa(..., ordered = item_ids, estimator = "WLSMV", std.lv = TRUE)`; `ordinal = FALSE` → `lavaan::cfa(..., estimator = "ML", std.lv = TRUE)`. The estimator is always set explicitly
    - Capture warnings with `withCallingHandlers` and muffle them into a list; read convergence with `lavaan::lavInspect(fit, "converged")`
    - Return `fit`, `converged`, `warnings`, `estimator`
    - _Requirements: 4.2, 4.3, 4.8_

  - [ ] 5.3 Implement `r-service/cfa/extractor.R`
    - `extract_fit_indices(fit)`: `fitMeasures()` for chisq, df, pvalue, cfi, tli, rmsea, rmsea.ci.lower, rmsea.ci.upper, srmr, `unname()`d, renamed to `rmsea_ci_lower` / `rmsea_ci_upper`
    - `extract_loadings(fit, model_specification)`: `standardizedSolution()` rows with `op == "=~"` as `loadings[factor][item] = est.std`
    - `extract_factor_correlations(fit, model_specification)`: rows with `op == "~~"`, `lhs != rhs`, both sides factor names, keyed `"<lhs>_<rhs>"`; empty object for one factor
    - Use the field names recorded in `PROBE_NOTES.md`
    - _Requirements: 4.5, 4.6, 4.7_

  - [ ] 5.4 Implement `r-service/cfa/pipeline.R`
    - `execute_cfa_pipeline(body)`: `validate_cfa_request` → `build_lavaan_model` → data frame with column names `item_ids` → `run_cfa` → extraction
    - Non-convergence: return `status: "warning"`, `message: "Model did not converge"`, `partial_fit_indices` (empty object if extraction fails), `lavaan_warnings`
    - Success: `status: "success"`, `fit_indices`, `loadings`, `factor_correlations`, `warnings`
    - _Requirements: 4.1, 4.8, 4.9, 12.1_

- [ ] 6. Implement `r-service/api.R`
  - Check that plumber, EGAnet, lavaan, igraph, jsonlite and uuid are installed; if any are missing, write the list to stderr and `quit(status = 1)`
  - Source `utils/`, `logging/`, `config/`, `validation/`, `ega/`, `cfa/`
  - Define `make_handler(endpoint, pipeline_fn)` returning a `function(req, res)` that creates a `request_id`, records the start time, parses the body with `parse_json_body`, runs `pipeline_fn` in `tryCatch`, sets `res$status` to 400 for `validation_error` and 500 otherwise (by condition class, never by message text), logs, and returns `{status: "error", message, request_id}` without a stack trace
  - Routes: `GET /health` → `{"status": "ok", "timestamp": "<ISO8601>"}`; `POST /ega`; `POST /cfa`; JSON serializer on all routes so `Content-Type: application/json`
  - CORS filter only when `R_SERVICE_CORS == "true"`
  - Bind to `R_SERVICE_HOST` (default `127.0.0.1`) and `R_SERVICE_PORT` (default `8000`)
  - Guard `pr_run()` so tests can source handler definitions without starting the server
  - Add a header comment showing the expected Next.js `fetch` call format (URL from `R_SERVICE_URL`, JSON body, checking HTTP status then the `status` field)
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 5.1, 5.3, 5.4, 5.6, 12.2, 12.3, 12.4, 12.5_

- [ ] 7. Checkpoint: wrappers load
  - Confirm `api.R` sources without errors and that wrapper argument names and result fields match `r-service/PROBE_NOTES.md`. Ensure all tests pass, ask the user if questions arise.

- [ ] 8. Generate fixtures and record expected values from a real run
  - [ ] 8.1 Write `r-service/tests/generate_fixtures.R`
    - EGA input: fixed seed; 3 cluster centers in a 128-dimension space; 6 items per factor (18 items) as center + Gaussian noise; `item_004` = `item_003` + small noise (UVA target); `item_010` = equal mix of the factor 2 and factor 3 centers + noise (bootEGA target); 0-indexed `intended_dimensions`
    - EGA config in the fixture: every value labeled `"TEST ONLY"` in the script and in the JSON (for example a `"_label": "TEST ONLY - not production values"` field); none read from or written to `app-config/psychometric-procedure.yaml`
    - CFA input: documented seed; 300 personas; 12 items; 2 correlated factors `AnticDread` and `WorkRumination` (6 items each); latent scores from `MASS::mvrnorm`; continuous responses discretized to 1–5; `ordinal = true`; planted loadings and planted factor correlation written to `cfa_expected.json`
    - `cfa_expected.json` contains only the planted loadings with loading tolerance ±0.10 (Requirement 6.5) and the planted factor correlation with tolerance ±0.10, all labeled `"TEST ONLY"`. It defines NO pass/fail ranges for CFI, RMSEA, or SRMR (Requirement 8.6)
    - Document seed, cluster centers, noise parameters, planted indices, and the regeneration command in the script header and in each JSON file
    - EGA expected values are not set by hand: the script sources the pipeline, runs `execute_ega_pipeline()` once on the generated input, and writes the actual `removed_uva`, `removed_bootega`, `nmi_initial`, `nmi_final` to `ega_expected.json`
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9, 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7, 8.8_

  - [ ] 8.2 Run the fixture generator
    - Run `Rscript tests/generate_fixtures.R` from `r-service/`
    - Confirm `tests/fixtures/ega_input.json`, `ega_expected.json`, `cfa_input.json`, `cfa_expected.json` exist and the expected values came from the run
    - If the run does not remove exactly one of `item_003` / `item_004`, or `nmi_final < nmi_initial`, report it to the owner instead of editing expected values by hand
    - Do not run `git add`, `git commit` or `git push`. Leave the generated fixture files uncommitted and tell the owner which files to commit (`r-service/tests/fixtures/ega_input.json`, `ega_expected.json`, `cfa_input.json`, `cfa_expected.json`)
    - _Requirements: 7.7, 7.8, 8.7_

- [ ] 9. Write the test suite
  - [ ] 9.1 Write `r-service/tests/helpers.R`
    - `assert_true`, `assert_equal`, `assert_near(expected, actual, tolerance, label)`, `assert_in_range`, `assert_set_equal`
    - Failed numeric assertions print expected value, actual value and tolerance to stdout and increment a shared failure counter
    - _Requirements: 6.8_

  - [ ] 9.2 Write `r-service/tests/run_all.R`
    - Source `helpers.R` and every `test_*.R` file in `tests/`, run each test in `tryCatch`, print a summary
    - Exit 0 with `"All tests passed"`, or exit 1 and print the failed assertion count
    - _Requirements: 6.1, 6.9, 6.10_

  - [ ] 9.3 Write `r-service/tests/test_ega.R`
    - Load `ega_input.json` and `ega_expected.json` from `tests/fixtures/`, run `execute_ega_pipeline()`
    - `removed_from_pair <- intersect(result$uva$removed_items, c("item_003", "item_004"))`; `assert_true(length(removed_from_pair) == 1, ...)`
    - `assert_true(result$nmi$final >= result$nmi$initial, ...)`
    - Reproducibility: `assert_set_equal` on removed UVA and bootEGA sets against the recorded file; `assert_near` on NMI initial and final at tolerance 0.001 (design.md)
    - _Requirements: 6.2, 6.3, 6.4, 7.10, 7.11_

  - [ ] 9.4 Write `r-service/tests/test_cfa.R`
    - Load `cfa_input.json` and `cfa_expected.json`, run `execute_cfa_pipeline()`
    - Assert `status == "success"`; every loading within the fixture's loading tolerance of its planted value; factor correlation within the fixture's correlation tolerance
    - Do NOT assert on CFI, RMSEA, or SRMR. Print them, together with chisq and df, to stdout for reporting only
    - Comment in the test that it checks the code path recovers planted structure, and that it is a technical rehearsal, not validation and not a verdict on any scale
    - _Requirements: 6.2, 6.5, 6.6_

  - [ ] 9.5 Write `r-service/tests/test_holzinger.R`
    - Model `visual =~ x1 + x2 + x3`, `textual =~ x4 + x5 + x6`, `speed =~ x7 + x8 + x9` on `lavaan::HolzingerSwineford1939`, `ordinal = false`
    - Reference: direct `lavaan::cfa(model, data, estimator = "ML", std.lv = TRUE)` and `fitMeasures()`
    - Compare `/cfa` pipeline output with `assert_near` at tolerance 1e-6 on `unname()`'d chisq, CFI, RMSEA, and df at tolerance 0.5. Never use `identical()`
    - _Requirements: 6.7, 8.9, 8.10_

  - [ ] 9.6 Write `r-service/tests/test_errors.R`
    - Call handlers from `make_handler()` with mock `req` (`postBody`) and `res` objects
    - Each of the eight config fields set to null → `res$status == 400`, message `"config.<field> is null; owner decision required"`; a missing field → 400 with `"config.<field> is missing"`
    - Malformed JSON → 400 with message starting `"Invalid JSON:"`
    - Dimension mismatches (`item_ids` vs embeddings rows, `intended_dimensions` vs rows, `item_ids` vs responses columns, unknown model items) → 400 with the specific message
    - Stubbed pipeline calling `stop()` → 500
    - Every error response has a non-empty UUID `request_id`; no response contains a stack trace
    - Config values in this file are labeled `# TEST ONLY`
    - _Requirements: 2.1, 3.2, 5.1, 5.2, 5.3, 5.4, 5.6, 9.7_

  - [ ] 9.7 Write `r-service/tests/test_units.R`
    - `build_lavaan_model()`: exact syntax string for 1-factor and 2-factor specifications
    - `compute_nmi()`: identical partitions → 1; NA in `detected` is dropped with a warning; length mismatch → error; all-NA → error
    - `validate_config()`: null and missing fields raise `validation_error` with the documented messages; a complete config passes
    - `validate_ega_request()` / `validate_cfa_request()`: fewer than 2 embedding rows, non-integer responses
    - _Requirements: 2.1, 2.2, 3.11, 3.12, 4.4, 9.1, 9.4_

  - [ ] 9.8 Write `r-service/tests/test_properties.R` (property-based tests)
    - Add `testthat` and `hedgehog` to `r-service/install_packages.R` as test-only dependencies (never loaded by `api.R`), install them, and record their `packageVersion()` for the README
    - Verify generator names against the installed package before use (`ls("package:hedgehog")`, the package manual, or the CRAN vignette). The vignette documents `gen.c`, `gen.element`, `gen.unif`, `gen.sample`, `gen.with`, `gen.and_then` and `generate(for (x in gen) ...)`. Record the verified names in a comment at the top of the file. Context7 does not index the R `hedgehog` package, so verification is done against the CRAN vignette/manual and the installed package
    - Put `set.seed()` with a documented value at the top of the file for reproducibility
    - Each property is its own `test_that()` block containing a `forall()` call, and carries the comments `# Feature: r-statistics-spike, Property N: <title>` and `# Validates: Requirements ...`
    - Property 1 (`compute_nmi()` is invariant under relabeling): generate `detected` and `intended` label vectors of equal length with no NA and at least two distinct labels each; apply a permutation of the label set to `detected`, to `intended`, or to both; the NMI equals the unrelabeled value within an absolute tolerance of 1e-9 (`abs(relabeled - original) <= 1e-9`; TEST ONLY, floating-point error only). Do not rely on the default `expect_equal` tolerance, which is relative. Validates: Requirements 3.11, 3.12
    - Property 2 (`validate_config()` rejects any config with a null or missing field): start from the eight required fields, set a non-empty subset to `NULL` or remove it, fill the remaining fields with arbitrary non-null generator values labeled `# TEST ONLY` (not psychometric values, never read from or written to `app-config/psychometric-procedure.yaml`); the call always throws a condition with class `validation_error`. Validates: Requirements 2.1, 2.2, 3.2
    - Property 3 (`build_lavaan_model()` contains every item exactly once): one or more factors with distinct names, non-empty item lists, item IDs globally distinct, identifier-safe and distinct from factor names; split the syntax on `=~`, `+`, whitespace and newlines; each item ID appears exactly once as a whole token and no other item IDs appear. Validates: Requirements 4.4
    - Do NOT write property tests for EGA, UVA, bootEGA, or CFA
    - Update `r-service/tests/run_all.R` so `test_properties.R` is run through testthat (not sourced like the custom-helper tests) and its failed and errored expectations are added to the shared failure counter. Verify the mechanism once with a deliberately failing property, then revert it: the runner must exit 1 and print the failed count
    - If hedgehog finds a counterexample, report it to the owner with the shrunk example instead of weakening the property
    - _Requirements: 2.1, 2.2, 3.2, 3.11, 3.12, 4.4_

- [ ] 10. Checkpoint: run all tests and verify numeric output
  - Run `Rscript tests/run_all.R` from `r-service/`. Confirm exit code 0, `"All tests passed"`, and read the printed numeric values (removed items, NMI, loadings, fit indices, Holzinger differences), not only the exit code. Ensure all tests pass, ask the user if questions arise.

- [ ] 11. Write `r-service/README.md`
  - Required packages with minimum versions (from task 1.1), install command (`Rscript r-service/install_packages.R`)
  - Start command `Rscript r-service/api.R`; env vars `R_SERVICE_HOST` (default `127.0.0.1`), `R_SERVICE_PORT` (default `8000`), `R_SERVICE_CORS`
  - Test command `Rscript tests/run_all.R` and fixture regeneration command
  - Health check: `curl http://localhost:8000/health`
  - Directory layout with each file's purpose
  - Reference to `PROBE_NOTES.md` and `probe_output.txt` and when to rerun the probe
  - State that the service has no default psychometric thresholds, and that fixture config values are TEST ONLY
  - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6, 11.7_

## Notes

- Test sub-tasks are not marked optional: Requirements 6, 7 and 8 make the fixture, reference and error tests deliverables of this spike.
- Property-based tests cover only `compute_nmi`, `validate_config` and `build_lavaan_model`; `hedgehog` and `testthat` are test-only dependencies.
- `r-service/utils/conditions.R` is the only file added beyond the design.md layout. `r-service/install_packages.R`, `probe_output.txt` and `PROBE_NOTES.md` are setup and probe artifacts.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2"] },
    { "id": 2, "tasks": ["1.3"] },
    { "id": 3, "tasks": ["2"] },
    { "id": 4, "tasks": ["3.1"] },
    { "id": 5, "tasks": ["3.2", "3.3"] },
    { "id": 6, "tasks": ["4.1", "4.2", "4.3", "5.1", "5.2", "5.3"] },
    { "id": 7, "tasks": ["4.4", "5.4"] },
    { "id": 8, "tasks": ["6"] },
    { "id": 9, "tasks": ["7"] },
    { "id": 10, "tasks": ["8.1"] },
    { "id": 11, "tasks": ["8.2"] },
    { "id": 12, "tasks": ["9.1"] },
    { "id": 13, "tasks": ["9.2", "9.3", "9.4", "9.5", "9.6", "9.7"] },
    { "id": 14, "tasks": ["9.8"] },
    { "id": 15, "tasks": ["10"] },
    { "id": 16, "tasks": ["11"] }
  ]
}
```
