# Implementation Plan: R Statistics Spike

## Overview

Build the plumber R service in `r-service/` in this order: install packages and create the skeleton, run `probe.R` and record what EGAnet and lavaan actually return, write the wrappers to match the probe output, generate fixtures and record expected values from a real run, write and run the numeric tests, then document the service.

Hard rules for every task:

- No task sets production threshold values. `app-config/psychometric-procedure.yaml` values stay null and are not created or filled by this spec. Config values appear only inside test fixtures and test code, and each place is labeled `"TEST ONLY"`.
- No task writes to `notes/`. Probe findings go in `r-service/`.
- Property-based tests only for three pure helpers (`compute_nmi`, `validate_config`, `build_lavaan_model`) in `tests/test_properties.R` (task 9.8). No property tests for EGA, UVA, bootEGA or CFA, which are covered by fixture tests, the lavaan reference test and example-based tests.
- Tolerances come from design.md as written. Where design.md delegates a tolerance to the fixture and neither design.md nor requirements.md gives a number, the task stops and asks the owner.

## Tasks

- [x] 1. Set up packages, skeleton and the development probe
  - [x] 1.1 Create the `r-service/` skeleton and package install script
    - Create the directories from design.md File structure: `config/`, `validation/`, `ega/`, `cfa/`, `logging/`, `utils/`, `tests/`, `tests/fixtures/`
    - Write `r-service/install_packages.R` installing plumber, EGAnet, lavaan, igraph, jsonlite, uuid, and MASS (MASS is used only by `tests/generate_fixtures.R`)
    - Run the script and record the installed `packageVersion()` of each package for the README minimum versions
    - _Requirements: 1.6, 11.1, 11.2_

  - [x] 1.2 Write `r-service/probe.R`
    - Print `packageVersion()` for plumber, EGAnet, lavaan, igraph, jsonlite, uuid
    - Generate small sample data with a fixed seed: an item × embedding-dimension matrix (transposed before EGA, as in design.md step 4) and a small ordinal response data frame
    - Run `EGAnet::UVA`, `EGAnet::EGA`, `EGAnet::bootEGA`, `EGAnet::itemStability` (on the bootEGA result) and `lavaan::cfa` (ordinal, `estimator = "WLSMV"`, `std.lv = TRUE`)
    - Print `str()` and `names()` of each result, including `ega$wc`, the UVA reduced-data and wTO fields, the itemStability per-item output, `fitMeasures()` and `str(standardizedSolution())`
    - Print `args()` / `formals()` of `UVA`, `EGA`, `bootEGA`, `itemStability` so argument names are recorded
    - Label every sample parameter value in the script with a `# PROBE ONLY - not a production value` comment
    - _Requirements: 1.6, 3.3, 3.4, 3.7, 3.10, 4.2, 4.5, 4.6_

  - [x] 1.3 Run the probe and record findings in `r-service/`
    - Run `Rscript r-service/probe.R > r-service/probe_output.txt 2>&1`
    - Write `r-service/PROBE_NOTES.md` summarizing: package versions, exact argument names for `UVA` (`cut.off`, `uva.method`, `reduce`, `reduce.method`, `auto`), `EGA` / `bootEGA` (`model`, `algorithm`, `iter`, `type`, `seed`), `itemStability`, and the result field paths for UVA reduced data, wTO scores, `wc`, and per-item stability
    - Cross-check each name against official package documentation (Context7 or CRAN reference manual) for the installed version, and record any disagreement. Where probe and documentation disagree, the probe wins (design.md Development probe rule 4)
    - Add a table comparing each design.md argument/field name with the probe result: match or differs
    - Do not write anything to `notes/`
    - _Requirements: 3.4, 3.7, 3.10, 11.7_

- [x] 2. Checkpoint: probe findings review (complete, owner decisions recorded)
  - Owner decisions made: `uva_method` accepts only `"mbr"`; ordinal CFA reports scaled/robust fit variants (`fit_variant`); `removed_wto_scores` entries are `{redundant_with, wto}`; `set.seed(as.numeric(random_seed))` before every `EGAnet::EGA` call. These are now in requirements.md and design.md, which are the source of truth for the wrapper tasks.

- [x] 3. Implement shared utilities and validation
  - [x] 3.1 Implement `r-service/utils/conditions.R` and `r-service/logging/logger.R`
    - `utils/conditions.R`: `validation_error(msg)` condition constructor with class `c("validation_error", "error", "condition")` and `call = NULL`; `new_request_id()` wrapping `uuid::UUIDgenerate()`; `parse_json_body(post_body)` that re-throws parse failures as `validation_error("Invalid JSON: <parser message>")`
    - `logging/logger.R`: `log_ega_execution()`, `log_cfa_execution()`, `log_error()` writing one JSON object per line with `jsonlite::toJSON(auto_unbox = TRUE, na = "null", digits = NA)`, the same serialization as the HTTP responses so numbers in logs equal numbers in responses; stdout for success, stderr for errors; common fields `timestamp` (ISO 8601), `request_id`, `endpoint`, `execution_duration_ms`; `/ega` and `/cfa` fields as listed in design.md Logging; each of the three functions takes an optional `warnings` argument (default `character(0)`) written as a `warnings` JSON array (`[]` when empty, still an array for one message); error context excludes `embeddings` and `responses`
    - `/ega` log fields include `removed_uva_items` with, for each, its `redundant_with` partner and `wto` score, and `removed_bootega_items` with each stability score
    - `/cfa` log field `estimator` is the wrapper's own choice (`"WLSMV"` when `ordinal` is true, `"ML"` when false), never `lavInspect(fit, "options")$estimator` (which reports `"DWLS"`)
    - Never log or serialize a ggplot object (the `plot` element of `itemStability` results)
    - `utils/` is a small addition to the design.md layout to hold the shared condition and request_id helpers used by `config/` and `validation/`
    - _Requirements: 2.4, 5.1, 5.4, 5.5, 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 12.6_

  - [x] 3.2 Implement `r-service/config/loader.R`
    - `validate_config(config, required_fields)`: missing field → `validation_error("config.<field> is missing")`; null field → `validation_error("config.<field> is null; owner decision required")`
    - Define the `/ega` required field list: `wto_threshold`, `stability_threshold`, `boot_iterations`, `network_method`, `community_algorithm`, `random_seed`, `uva_method`, `bootstrap_type`
    - No default value for any field. `config.uva_method` stays null until the owner sets it; a null value returns `"config.uva_method is null; owner decision required"` and no default is substituted
    - After all eight fields pass the null/missing check, check `uva_method`: `tolower(uva_method) == "mbr"` is accepted in any letter case; any other value throws `validation_error` before any computation. Check by value and condition class, never by message text
    - For `"ejp"` (case-insensitive) the message is the one in design.md Error Handling: UVA with `"ejp"`, `reduce.method "remove"` and `auto TRUE` requires interactive input and would hang a non-interactive process. Any other non-`"mbr"` value gets the `got "<value>"` message from design.md
    - _Requirements: 2.1, 2.2, 2.3, 2.5, 3.2, 9.8, 9.9, 9.10_

  - [x] 3.3 Implement `r-service/validation/request_validator.R`
    - `validate_ega_request(body)`: required fields present; `embeddings` bound with `rbind` if a list of rows; numeric matrix with ≥ 2 rows; `item_ids` and `intended_dimensions` lengths equal the row count, with messages such as `"item_ids length (10) does not match embeddings rows (12)"`
    - `validate_cfa_request(body)`: required fields `responses`, `item_ids`, `model_specification`, `ordinal`; `ordinal` is validated first; `responses` bound with `rbind`, finite numeric, and integer-valued only when `ordinal` is true (kept as double when false); `item_ids` length equals the column count; every item in `model_specification.factors[*].items` is in `item_ids`, else `"Items in model_specification not found in item_ids: <ids>"`
    - All failures throw `validation_error`
    - The `uva_method` check lives in `validate_config()` (task 3.2), which the `/ega` pipeline calls right after `validate_ega_request()`, so an `"ejp"` request is rejected with HTTP 400 before `EGAnet::UVA` can be reached
    - _Requirements: 5.2, 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 9.7, 9.8_

- [x] 4. Implement EGA wrappers following the probe output
  - [x] 4.1 Implement `r-service/ega/nmi.R`
    - `compute_nmi(detected, intended)`: error on unequal lengths; drop positions where either vector is NA (NA can occur in `wc`), warn with the dropped count; error if nothing remains; return `igraph::compare(detected, intended, method = "nmi")`
    - _Requirements: 3.11, 3.12_

  - [x] 4.2 Implement `r-service/ega/uva.R`
    - `run_uva_loop(data, config)`: call `EGAnet::UVA` with `cut.off = config$wto_threshold`, `uva.method = config$uva_method`, `reduce = TRUE`, `reduce.method = "remove"`, `auto = TRUE`, `verbose = FALSE`, using argument names and result fields recorded in `r-service/PROBE_NOTES.md`
    - Removed items per pass: `setdiff(colnames(data), colnames(result$reduced_data))`. If `result$reduced_data` is `NULL` (nothing redundant), stop the loop and treat all items of that pass's input as retained (otherwise `colnames(NULL)` makes `setdiff()` return every item). Never read `$keep_remove` (inconsistent with `reduced_data` in the probe)
    - Pass `result$reduced_data` to the next pass with `colnames` intact; repeat until a pass removes nothing
    - `removed_wto_scores`: for each removed item `r`, partners are the `result$redundant[[r]]` entries plus names of entries whose vector contains `r`; read their wTO from that pass's `result$wto$pairwise` (`node_i`, `node_j`, `wto`); skip partners with no row (not all pairs are present); report the highest-wTO partner as `redundant_with` and its value as `wto`; if no partner has a row, both are `null` and a `warning()` is raised (`make_handler()` collects it into the log entry's `warnings` array). Entry form `{redundant_with, wto}`
    - Return `removed_items`, `removed_wto_scores`, `retained_data`
    - _Requirements: 3.4, 3.5, 3.6, 3.14, 3.15, 3.16, 10.3_

  - [x] 4.3 Implement `r-service/ega/bootega.R`
    - `run_bootega_loop(data, config)`: call `EGAnet::bootEGA` with `model = config$network_method`, `algorithm = config$community_algorithm`, `iter = config$boot_iterations`, `type = config$bootstrap_type`, `seed = as.numeric(config$random_seed)` (bootEGA rejects integer seeds and `fromJSON` returns whole numbers as integer), plus the fixed arguments `ncores = 1`, `plot.itemStability = FALSE`, `verbose = FALSE`
    - Per-item stability: `EGAnet::itemStability(boot, IS.plot = FALSE)$item.stability$empirical.dimensions` (named numeric vector, names = item IDs). Keep only this vector; drop the `plot` element, never store, log or serialize it
    - Remove every item with stability < `config$stability_threshold`, record its score in `removed_stability_scores` (the pass that removed it), repeat until all remaining items are stable
    - Return `removed_items`, `removed_stability_scores`, `retained_data`, and `stability_per_item` from the last pass
    - _Requirements: 3.7, 3.8, 3.9, 3.10, 3.17, 3.19, 10.4_

  - [x] 4.4 Implement `r-service/ega/pipeline.R`
    - `run_ega(data, config)`: the only caller of `EGAnet::EGA`. It calls `set.seed(as.numeric(config$random_seed))` immediately before every `EGAnet::EGA(..., model, algorithm, plot.EGA = FALSE, verbose = FALSE)` call, because `EGA` has no seed argument. Both the initial and the final structure go through it
    - `execute_ega_pipeline(body)`: `validate_ega_request` → `validate_config` → `t(embeddings)` with column names = `item_ids` → `run_ega` on the full data and `nmi.initial` against `intended_dimensions + 1` → `run_uva_loop` → `run_bootega_loop` → `run_ega` on retained data and `nmi.final` against intended dimensions subset by retained item IDs, `+ 1`
    - Use `ega$wc` directly with `igraph::compare()` (via `compute_nmi()`); no conversion needed
    - Build the success response from design.md Data Models, including `uva.removed_wto_scores` and `bootega.removed_stability_scores`, with `uva.reason = "weighted topological overlap >= <wto_threshold>"` and `bootega.reason = "stability < <stability_threshold> over <boot_iterations> iterations"`, both interpolated from the request config
    - Identical requests return identical `uva`, `bootega`, `retained_items` and `nmi` values
    - _Requirements: 3.1, 3.3, 3.6, 3.9, 3.11, 3.12, 3.13, 3.14, 3.17, 3.18, 3.20, 12.1, 12.8_

- [x] 5. Implement CFA wrappers following the probe output
  - [x] 5.1 Implement `r-service/cfa/model_builder.R`
    - `build_lavaan_model(model_specification)`: one `<name> =~ item_a + item_b + ...` line per factor, joined by newlines
    - _Requirements: 4.4_

  - [x] 5.2 Implement `r-service/cfa/estimator.R`
    - `run_cfa(model_syntax, response_df, item_ids, ordinal)`: `ordinal = TRUE` → `lavaan::cfa(..., ordered = item_ids, estimator = "WLSMV", std.lv = TRUE)`; `ordinal = FALSE` → `lavaan::cfa(..., estimator = "ML", std.lv = TRUE)`. The estimator is always set explicitly
    - Capture warnings with `withCallingHandlers` and muffle them into a list; read convergence with `lavaan::lavInspect(fit, "converged")`
    - Return `fit`, `converged`, `warnings`, `estimator`. The returned `estimator` is the wrapper's own choice (`"WLSMV"` when `ordinal` is true, `"ML"` when false), not `lavInspect(fit, "options")$estimator`, which reports `"DWLS"` for a WLSMV fit
    - _Requirements: 4.2, 4.3, 4.8, 10.2_

  - [x] 5.3 Implement `r-service/cfa/extractor.R`
    - `extract_fit_indices(fit, ordinal)`: `fitMeasures()` with the names chosen by the `ordinal` flag, each `unname()`d and stored under the fixed response key (design.md `/cfa` flow, step 6):
      - `ordinal = TRUE` (`fit_variant = "scaled_robust"`): `chisq` ← `chisq.scaled`, `df` ← `df.scaled`, `pvalue` ← `pvalue.scaled`, `cfi` ← `cfi.robust`, `tli` ← `tli.robust`, `rmsea` ← `rmsea.robust`, `rmsea_ci_lower` ← `rmsea.ci.lower.robust`, `rmsea_ci_upper` ← `rmsea.ci.upper.robust`, `srmr` ← unsuffixed `srmr`
      - `ordinal = FALSE` (`fit_variant = "standard"`): all keys from the unsuffixed lavaan names (`rmsea.ci.lower` / `rmsea.ci.upper` for the CI keys)
      - Return `fit_variant` (`"scaled_robust"` or `"standard"`) with the indices. Leave `NA` as `NA` so the serializer writes JSON `null`. Apply no fit cut-off
    - `extract_loadings(fit, model_specification)`: `standardizedSolution()` rows with `op == "=~"` as `loadings[factor][item] = est.std`
    - `extract_factor_correlations(fit, model_specification)`: rows with `op == "~~"`, `lhs != rhs`, both sides factor names, keyed `"<lhs>_<rhs>"`; empty object for one factor. Ordinal fits also contain `"|"`, `"~*~"` and `"~1"` rows; filtering by `op` excludes them
    - Use the field names recorded in `PROBE_NOTES.md`
    - _Requirements: 4.5, 4.6, 4.7, 4.10, 4.11, 4.12, 4.13, 4.14, 4.15_

  - [x] 5.4 Implement `r-service/cfa/pipeline.R`
    - `execute_cfa_pipeline(body)`: `validate_cfa_request` → `build_lavaan_model` → data frame with column names `item_ids` → `run_cfa` → extraction
    - Non-convergence: return `status: "warning"`, `message: "Model did not converge"`, `partial_fit_indices` (empty object if extraction fails), `lavaan_warnings`
    - Success: `status: "success"`, `fit_variant`, `fit_indices`, `loadings`, `factor_correlations`, `warnings`
    - Pass `ordinal` to `extract_fit_indices()`; the response `fit_variant` is `"scaled_robust"` when `ordinal` is true and `"standard"` when false
    - _Requirements: 4.1, 4.8, 4.9, 4.13, 12.1, 12.7_

- [x] 6. Implement `r-service/api.R`
  - Check that plumber, EGAnet, lavaan, igraph, jsonlite and uuid are installed; if any are missing, write the list to stderr and `quit(status = 1)`
  - Source `utils/`, `logging/`, `config/`, `validation/`, `ega/`, `cfa/`
  - Define `make_handler(endpoint, pipeline_fn)` returning a `function(req, res)` that creates a `request_id`, records the start time, parses the body with `parse_json_body`, runs `pipeline_fn` in `tryCatch`, with the `pipeline_fn(body)` call wrapped in `withCallingHandlers` that collects each warning message and muffles it (the messages are passed to the logger as `warnings` in both the success and the error entry and are not added to the HTTP response), sets `res$status` to 400 for `validation_error` and 500 otherwise (by condition class, never by message text), logs, and returns `{status: "error", message, request_id}` without a stack trace
  - Routes: `GET /health` → `{"status": "ok", "timestamp": "<ISO8601>"}`; `POST /ega`; `POST /cfa`; `plumber::serializer_json(auto_unbox = TRUE, na = "null", digits = NA)` on all routes (including error bodies) so `Content-Type: application/json` and numeric `NA` is written as JSON `null`, never the string `"NA"`; `digits = NA` keeps full numeric precision instead of the jsonlite default of 4 digits
  - CORS filter only when `R_SERVICE_CORS == "true"`
  - Bind to `R_SERVICE_HOST` (default `127.0.0.1`) and `R_SERVICE_PORT` (default `8000`)
  - Guard `pr_run()` so tests can source handler definitions without starting the server
  - Add a header comment showing the expected Next.js `fetch` call format (URL from `R_SERVICE_URL`, JSON body, checking HTTP status then the `status` field)
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 5.1, 5.3, 5.4, 5.6, 12.2, 12.3, 12.4, 12.5, 12.6_

- [x] 7. Checkpoint: wrappers load
  - Confirm `api.R` sources without errors and that wrapper argument names and result fields match `r-service/PROBE_NOTES.md`. Ensure all tests pass, ask the user if questions arise.

- [x] 8. Generate fixtures and record expected values from a real run
  - [x] 8.1 Write `r-service/tests/generate_fixtures.R`
    - EGA input: fixed seed; 3 cluster centers in a 128-dimension space; 6 items per factor (18 items) as center + Gaussian noise; `item_004` = `item_003` + small noise (UVA target); `item_010` = equal mix of the factor 2 and factor 3 centers + noise (bootEGA target); 0-indexed `intended_dimensions`
    - EGA config in the fixture: every value labeled `"TEST ONLY"` in the script and in the JSON (for example a `"_label": "TEST ONLY - not production values"` field); none read from or written to `app-config/psychometric-procedure.yaml`. `uva_method` is `"mbr"` (TEST ONLY), the only value the service accepts
    - CFA input: documented seed; 1000 personas; 12 items; 2 correlated factors `AnticDread` and `WorkRumination` (6 items each); latent scores from `MASS::mvrnorm`; continuous responses discretized to 1–5; `ordinal = true`; planted loadings and planted factor correlation written to `cfa_expected.json`
    - `cfa_expected.json` contains only the planted loadings with loading tolerance ±0.10 (Requirement 6.5) and the planted factor correlation with tolerance ±0.10, all labeled `"TEST ONLY"`. It defines NO pass/fail ranges for CFI, RMSEA, or SRMR (Requirement 8.6)
    - Document seed, cluster centers, noise parameters, planted indices, and the regeneration command in the script header and in each JSON file
    - EGA expected values are not set by hand: the script sources the pipeline, runs `execute_ega_pipeline()` once on the generated input, and writes the actual `removed_uva`, `removed_bootega`, `nmi_initial`, `nmi_final` to `ega_expected.json`
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6, 7.7, 7.8, 7.9, 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7, 8.8_

  - [x] 8.2 Run the fixture generator
    - Run `Rscript tests/generate_fixtures.R` from `r-service/`
    - Confirm `tests/fixtures/ega_input.json`, `ega_expected.json`, `cfa_input.json`, `cfa_expected.json` exist and the expected values came from the run
    - If the run does not remove exactly one of `item_003` / `item_004`, or `nmi_final < nmi_initial`, report it to the owner instead of editing expected values by hand
    - Do not run `git add`, `git commit` or `git push`. Leave the generated fixture files uncommitted and tell the owner which files to commit (`r-service/tests/fixtures/ega_input.json`, `ega_expected.json`, `cfa_input.json`, `cfa_expected.json`)
    - _Requirements: 7.7, 7.8, 8.7_

- [x] 9. Write the test suite
  - [x] 9.1 Write `r-service/tests/helpers.R`
    - `assert_true`, `assert_equal`, `assert_near(expected, actual, tolerance, label)`, `assert_in_range`, `assert_set_equal`
    - Failed numeric assertions print expected value, actual value and tolerance to stdout and increment a shared failure counter
    - _Requirements: 6.8_

  - [x] 9.2 Write `r-service/tests/run_all.R`
    - Source `helpers.R` and every `test_*.R` file in `tests/`, run each test in `tryCatch`, print a summary
    - Exit 0 with `"All tests passed"`, or exit 1 and print the failed assertion count
    - _Requirements: 6.1, 6.9, 6.10_

  - [x] 9.3 Write `r-service/tests/test_ega.R`
    - Load `ega_input.json` and `ega_expected.json` from `tests/fixtures/`, run `execute_ega_pipeline()`
    - `removed_from_pair <- intersect(result$uva$removed_items, c("item_003", "item_004"))`; `assert_true(length(removed_from_pair) == 1, ...)`
    - `assert_true(result$nmi$final >= result$nmi$initial, ...)`
    - Score entries: every item in `uva$removed_items` has an entry in `uva$removed_wto_scores` whose `redundant_with` is an ID in `item_ids` and differs from the removed item, and a numeric `wto`; every item in `bootega$removed_items` has an entry in `bootega$removed_stability_scores`
    - Reproducibility: `assert_set_equal` on removed UVA and bootEGA sets against the recorded file; `assert_near` on NMI initial and final at tolerance 0.001 (design.md)
    - Repeat-request: run the same request twice; `uva$removed_items` and `bootega$removed_items` equal as sets (`assert_set_equal`), `nmi$initial` and `nmi$final` equal within 0.001 (`assert_near`)
    - _Requirements: 3.14, 3.17, 3.20, 6.2, 6.3, 6.4, 6.13, 7.10, 7.11_

  - [x] 9.4 Write `r-service/tests/test_cfa.R`
    - Load `cfa_input.json` and `cfa_expected.json`, run `execute_cfa_pipeline()`
    - Assert `status == "success"`; `fit_variant == "scaled_robust"`; every loading within the fixture's loading tolerance (±0.10) of its planted value; factor correlation within the fixture's correlation tolerance (±0.10). Assert nothing else
    - Do NOT assert on CFI, RMSEA, or SRMR. Print them, together with chisq and df (the scaled/robust values), to stdout for reporting only
    - Comment in the test that it checks the code path recovers planted structure, and that it is a technical rehearsal, not validation and not a verdict on any scale
    - _Requirements: 4.13, 6.2, 6.5, 6.6, 6.11, 8.11_

  - [x] 9.5 Write `r-service/tests/test_holzinger.R`
    - Model `visual =~ x1 + x2 + x3`, `textual =~ x4 + x5 + x6`, `speed =~ x7 + x8 + x9` on `lavaan::HolzingerSwineford1939`, `ordinal = false`
    - Reference: direct `lavaan::cfa(model, data, estimator = "ML", std.lv = TRUE)` and `fitMeasures()`
    - Compare `/cfa` pipeline output with `assert_near` at tolerance 1e-6 on `unname()`'d chisq, CFI, RMSEA, and df at tolerance 0.5. Never use `identical()`
    - Assert `fit_variant == "standard"` (ML uses the unsuffixed lavaan values)
    - _Requirements: 4.12, 4.13, 6.7, 6.12, 8.9, 8.10, 8.12_

  - [x] 9.6 Write `r-service/tests/test_errors.R`
    - Call handlers from `make_handler()` with mock `req` (`postBody`) and `res` objects
    - Each of the eight config fields set to null → `res$status == 400`, message `"config.<field> is null; owner decision required"`; a missing field → 400 with `"config.<field> is missing"`
    - `uva_method` `"ejp"` and `"EJP"` → `validation_error`, `res$status == 400`, message states that `"ejp"` with `reduce.method "remove"` and `auto TRUE` requires interactive input. Another non-`"mbr"` value (for example `"wto"`) → 400. `"mbr"`, `"MBR"` and `"Mbr"` are accepted by `validate_config()`. For `"ejp"`, a stub replacing `EGAnet::UVA` that fails if called proves the request is rejected before UVA runs
    - NA serialization: a response list containing a numeric `NA` serialized with `jsonlite::toJSON(auto_unbox = TRUE, na = "null", digits = NA)` yields `null`, and the output does not contain the string `"NA"`. A numeric such as 0.123456789 is not rounded to 4 digits
    - Malformed JSON → 400 with message starting `"Invalid JSON:"`
    - Dimension mismatches (`item_ids` vs embeddings rows, `intended_dimensions` vs rows, `item_ids` vs responses columns, unknown model items) → 400 with the specific message
    - Stubbed pipeline calling `stop()` → 500
    - Every error response has a non-empty UUID `request_id`; no response contains a stack trace
    - Config values in this file are labeled `# TEST ONLY`
    - _Requirements: 2.1, 2.5, 3.2, 5.1, 5.2, 5.3, 5.4, 5.6, 9.7, 9.8, 9.9, 9.10, 12.6_

  - [x] 9.7 Write `r-service/tests/test_units.R`
    - `build_lavaan_model()`: exact syntax string for 1-factor and 2-factor specifications
    - `compute_nmi()`: identical partitions → 1; NA in `detected` is dropped with a warning; length mismatch → error; all-NA → error
    - `validate_config()`: null and missing fields raise `validation_error` with the documented messages; a complete config passes. `uva_method` examples: `"mbr"`, `"MBR"`, `"Mbr"` accepted; `"ejp"`, `"EJP"` and `"wto"` raise `validation_error` (the `"ejp"` message mentions interactive input); a null `uva_method` raises `"config.uva_method is null; owner decision required"`
    - `extract_fit_indices()`: on a small WLSMV fit, the returned `chisq`, `df`, `pvalue` equal the `fitMeasures()` entries `chisq.scaled`, `df.scaled`, `pvalue.scaled`; `cfi`, `tli`, `rmsea`, `rmsea_ci_lower`, `rmsea_ci_upper` equal `cfi.robust`, `tli.robust`, `rmsea.robust`, `rmsea.ci.lower.robust`, `rmsea.ci.upper.robust`; `srmr` equals unsuffixed `srmr`; `fit_variant == "scaled_robust"`. On a small ML fit, every value equals the unsuffixed entry and `fit_variant == "standard"`. Compare with `assert_near` at 1e-6. A value lavaan reports as `NA` stays `NA`
    - `validate_ega_request()` / `validate_cfa_request()`: fewer than 2 embedding rows; non-integer responses rejected when `ordinal` is true ("responses must contain only integer values") and accepted, kept as double, when `ordinal` is false
    - _Requirements: 2.1, 2.2, 2.5, 3.11, 3.12, 4.4, 4.10, 4.11, 4.12, 4.13, 4.14, 9.1, 9.4, 9.8, 9.9, 9.10_

  - [x] 9.8 Write `r-service/tests/test_properties.R` (property-based tests)
    - Add `testthat` and `hedgehog` to `r-service/install_packages.R` as test-only dependencies (never loaded by `api.R`), install them, and record their `packageVersion()` for the README
    - Verify generator names against the installed package before use (`ls("package:hedgehog")`, the package manual, or the CRAN vignette). The vignette documents `gen.c`, `gen.element`, `gen.unif`, `gen.sample`, `gen.with`, `gen.and_then` and `generate(for (x in gen) ...)`. Record the verified names in a comment at the top of the file. Context7 does not index the R `hedgehog` package, so verification is done against the CRAN vignette/manual and the installed package
    - Put `set.seed()` with a documented value at the top of the file for reproducibility
    - Each property is its own `test_that()` block containing a `forall()` call, and carries the comments `# Feature: r-statistics-spike, Property N: <title>` and `# Validates: Requirements ...`
    - Property 1 (`compute_nmi()` is invariant under relabeling): generate `detected` and `intended` label vectors of equal length with no NA and at least two distinct labels each; apply a permutation of the label set to `detected`, to `intended`, or to both; the NMI equals the unrelabeled value within an absolute tolerance of 1e-9 (`abs(relabeled - original) <= 1e-9`; TEST ONLY, floating-point error only). Do not rely on the default `expect_equal` tolerance, which is relative. Validates: Requirements 3.11, 3.12
    - Property 2 (`validate_config()` rejects any config with a null or missing field): start from the eight required fields, set a non-empty subset to `NULL` or remove it, fill the remaining fields with arbitrary non-null generator values labeled `# TEST ONLY` (not psychometric values, never read from or written to `app-config/psychometric-procedure.yaml`); the call always throws a condition with class `validation_error`. Because `validate_config()` also rejects any `uva_method` other than `"mbr"`, a generated `uva_method` may be rejected for that reason too; the property asserts only the condition class. Validates: Requirements 2.1, 2.2, 3.2
    - Property 3 (`build_lavaan_model()` contains every item exactly once): one or more factors with distinct names, non-empty item lists, item IDs globally distinct, identifier-safe and distinct from factor names; split the syntax on `=~`, `+`, whitespace and newlines; each item ID appears exactly once as a whole token and no other item IDs appear. Validates: Requirements 4.4
    - Do NOT write property tests for EGA, UVA, bootEGA, or CFA
    - Update `r-service/tests/run_all.R` so `test_properties.R` is run through testthat (not sourced like the custom-helper tests) and its failed and errored expectations are added to the shared failure counter. Verify the mechanism once with a deliberately failing property, then revert it: the runner must exit 1 and print the failed count
    - If hedgehog finds a counterexample, report it to the owner with the shrunk example instead of weakening the property
    - _Requirements: 2.1, 2.2, 3.2, 3.11, 3.12, 4.4_

- [x] 10. Checkpoint: run all tests and verify numeric output
  - Run `Rscript tests/run_all.R` from `r-service/`. Confirm exit code 0, `"All tests passed"`, and read the printed numeric values (removed items, NMI, loadings, fit indices, Holzinger differences), not only the exit code. Ensure all tests pass, ask the user if questions arise.

- [x] 11. Write `r-service/README.md`
  - Required packages with minimum versions (from task 1.1), install command (`Rscript r-service/install_packages.R`)
  - Start command `Rscript r-service/api.R`; env vars `R_SERVICE_HOST` (default `127.0.0.1`), `R_SERVICE_PORT` (default `8000`), `R_SERVICE_CORS`
  - Test command `Rscript tests/run_all.R` and fixture regeneration command
  - Health check: `curl http://localhost:8000/health`
  - Directory layout with each file's purpose
  - Reference to `PROBE_NOTES.md` and `probe_output.txt` and when to rerun the probe
  - State that the service has no default psychometric thresholds, and that fixture config values are TEST ONLY
  - State that `config.uva_method` accepts only `"mbr"` (`"ejp"` is rejected with HTTP 400 because it needs interactive input), and that ordinal `/cfa` responses report scaled/robust fit indices (`fit_variant`)
  - _Requirements: 9.8, 9.9, 11.1, 11.2, 11.3, 11.4, 11.5, 11.6, 11.7_

## Notes

- Test sub-tasks are not marked optional: Requirements 6, 7 and 8 make the fixture, reference and error tests deliverables of this spike.
- Property-based tests cover only `compute_nmi`, `validate_config` and `build_lavaan_model`; `hedgehog` and `testthat` are test-only dependencies.
- Task 2 is complete. Owner decisions it recorded: `uva_method` only `"mbr"`; scaled/robust fit variants for ordinal CFA; `removed_wto_scores` as `{redundant_with, wto}`; `set.seed` before every `EGAnet::EGA` call. Wrapper tasks follow requirements.md, design.md and `r-service/PROBE_NOTES.md`; where the probe and documentation disagree, the probe wins.
- `config.uva_method` stays null in the owner's config until the owner sets it; the service never substitutes a default.
- All JSON responses and log lines use `na = "null"` and `digits = NA` (full numeric precision), so numeric `NA` (for example an unscaled WLSMV `pvalue`) is written as `null`, not `"NA"`.
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
