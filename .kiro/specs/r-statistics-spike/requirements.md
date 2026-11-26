# Requirements Document

## Introduction

The R Statistics Service is a plumber-based JSON HTTP API that provides statistical analysis endpoints for psychometric scale development. The service performs structural screening using EGAnet (Exploratory Graph Analysis network methods) and confirmatory factor analysis using lavaan. This spike establishes the foundation for the structural screening agent (FR-STRUCT) and simulation agent (FR-SIM) in the multi-agent psychometric pipeline.

The service runs as a separate process from the main Next.js application and communicates via HTTP JSON requests. All statistical thresholds and parameters are externalized to configuration files, never hardcoded, to maintain flexibility for psychometric procedure refinement.

## Glossary

- **R_Service**: The plumber-based HTTP API server providing statistical analysis endpoints
- **EGAnet**: R package implementing Exploratory Graph Analysis network methods for dimensionality assessment
- **UVA**: Unique Variable Analysis - detects redundant items via weighted topological overlap
- **bootEGA**: Bootstrap EGA - assesses item stability across bootstrap samples
- **NMI**: Normalized Mutual Information - measures alignment between detected and intended factor structures
- **lavaan**: R package for latent variable analysis and structural equation modeling
- **CFA**: Confirmatory Factor Analysis - tests whether data fits a hypothesized factor structure
- **WLSMV**: Weighted Least Squares Mean and Variance adjusted - robust estimator for ordinal data
- **Plumber**: R package for creating HTTP APIs from R functions
- **Config_Loader**: Component that reads psychometric procedure configuration from YAML files
- **Test_Runner**: Component that executes test suites with numeric assertions
- **Fixture**: Known test data with documented expected outputs for verification

## Requirements

### Requirement 1: Service Initialization and Health

**User Story:** As a system operator, I want the R service to start reliably and report its health status, so that I can verify the service is operational before pipeline execution.

#### Acceptance Criteria

1. WHEN the R service is started with `Rscript r-service/api.R`, THE R_Service SHALL bind to the port specified in the R_SERVICE_PORT environment variable
2. WHERE R_SERVICE_PORT is not set, THE R_Service SHALL bind to port 8000
3. WHERE R_SERVICE_HOST is set, THE R_Service SHALL bind to the host specified in R_SERVICE_HOST
4. WHERE R_SERVICE_HOST is not set, THE R_Service SHALL bind to 127.0.0.1
5. THE R_Service SHALL expose a `/health` endpoint that returns HTTP 200 with JSON payload `{"status": "ok", "timestamp": "<ISO8601>"}`
6. WHEN the R service starts, THE R_Service SHALL load required packages (plumber, EGAnet, lavaan, igraph, jsonlite) and report any missing dependencies to stderr
7. IF a required package is not installed, THEN THE R_Service SHALL terminate with exit code 1 and an error message listing the missing package

### Requirement 2: Configuration Validation

**User Story:** As a pipeline developer, I want the R service to reject null configuration values explicitly, so that missing psychometric decisions are caught early rather than causing silent failures.

#### Acceptance Criteria

1. WHEN a request includes a `config` object with any null values, THE R_Service SHALL return HTTP 400 with JSON payload `{"status": "error", "message": "config.<field_name> is null; owner decision required"}`
2. THE R_Service SHALL validate that all required config fields are present before executing statistical computations
3. THE R_Service SHALL NOT use hardcoded default values for any psychometric threshold parameters
4. WHEN configuration validation fails, THE R_Service SHALL log the validation error with the full request context

### Requirement 3: EGA Endpoint - Structural Screening

**User Story:** As a structural screening agent, I want to identify redundant and unstable items using EGAnet methods, so that the item pool contains only distinct, reliable indicators.

#### Acceptance Criteria

1. THE R_Service SHALL expose a `/ega` endpoint that accepts POST requests with JSON payload containing embeddings matrix, item IDs, intended dimensions, and configuration parameters
2. IF config.wto_threshold, config.uva_method, config.bootstrap_type, config.network_method, config.community_algorithm, config.stability_threshold, config.boot_iterations, or config.random_seed is null, THEN THE R_Service SHALL return HTTP 400 with error message "config.<field_name> is null; owner decision required"
3. WHEN the `/ega` endpoint receives a valid request, THE R_Service SHALL transpose the embeddings matrix so that embedding dimensions become observations and items become variables, following the AI-GENIE methodology
4. WHEN the transposed embeddings are prepared, THE R_Service SHALL execute UVA (Unique Variable Analysis) with the weighted topological overlap threshold from config.wto_threshold
5. WHEN UVA identifies redundant items, THE R_Service SHALL repeat UVA on the retained item set until no redundant items remain
6. THE R_Service SHALL include all removed item IDs in the response under `uva.removed_items` with reason "weighted topological overlap >= <threshold>"
7. WHEN UVA completes with no further redundant items, THE R_Service SHALL execute bootEGA on retained items using config.stability_threshold, config.boot_iterations, config.network_method, config.community_algorithm, and config.random_seed
8. WHEN bootEGA identifies unstable items, THE R_Service SHALL repeat bootEGA on the retained item set until all items are stable
9. THE R_Service SHALL include all removed item IDs in the response under `bootega.removed_items` with reason "stability < <threshold> over <iterations> iterations"
10. THE R_Service SHALL compute stability scores for all retained items and include them in `bootega.stability_per_item` as a key-value map
11. THE R_Service SHALL compute Normalized Mutual Information (NMI) between the intended dimension assignment and the initial detected structure, returning the value as `nmi.initial`
12. THE R_Service SHALL compute NMI between the intended dimension assignment and the final retained structure, returning the value as `nmi.final`
13. THE R_Service SHALL return HTTP 200 with JSON response containing UVA results, bootEGA results, retained item IDs, and NMI scores

### Requirement 4: CFA Endpoint - Confirmatory Factor Analysis

**User Story:** As a simulation agent, I want to verify that planted factor structures can be recovered through CFA, so that I can validate the statistical pipeline before deploying scales to real respondents.

#### Acceptance Criteria

1. THE R_Service SHALL expose a `/cfa` endpoint that accepts POST requests with JSON payload containing response matrix, item IDs, model specification, and ordinal flag
2. WHEN the `ordinal` flag is true, THE R_Service SHALL use the WLSMV estimator in lavaan CFA
3. WHEN the `ordinal` flag is false, THE R_Service SHALL use the ML (Maximum Likelihood) estimator in lavaan CFA
4. THE R_Service SHALL construct a lavaan model syntax from the factors and items specified in `model_specification.factors`
5. WHEN CFA completes successfully, THE R_Service SHALL extract fit indices (chisq, df, pvalue, CFI, TLI, RMSEA with confidence interval, SRMR) and return them in the response
6. THE R_Service SHALL extract standardized factor loadings for each item and return them organized by factor name
7. WHEN the model includes multiple factors, THE R_Service SHALL extract factor correlations and return them as `factor_correlations`
8. IF the lavaan model does not converge, THEN THE R_Service SHALL return HTTP 200 with status "warning" and include partial fit indices and lavaan warning messages
9. WHEN CFA completes, THE R_Service SHALL return HTTP 200 with JSON response containing fit indices, loadings, factor correlations, and any warnings

### Requirement 5: Error Handling and Diagnostics

**User Story:** As a pipeline developer, I want clear, actionable error messages when requests fail, so that I can quickly diagnose configuration issues or data problems.

#### Acceptance Criteria

1. WHEN the R service receives malformed JSON, THE R_Service SHALL return HTTP 400 with error message describing the JSON parsing failure
2. WHEN request data has dimension mismatches (e.g., item_ids length differs from embeddings row count), THE R_Service SHALL return HTTP 400 with error message specifying the mismatch
3. IF an R computation throws an exception, THEN THE R_Service SHALL catch the exception with tryCatch and return HTTP 500 with error message including the R error text
4. THE R_Service SHALL include a unique request_id in all error responses for log correlation
5. WHEN an error occurs, THE R_Service SHALL log the full request payload (excluding embeddings/responses to reduce log size) and error details to stderr
6. THE R_Service SHALL NOT expose R stack traces to external clients in production mode

### Requirement 6: Test Suite with Numeric Verification

**User Story:** As a quality assurance engineer, I want tests that verify numeric correctness of statistical outputs, so that I can trust the R service produces valid results, not just non-crashing outputs.

#### Acceptance Criteria

1. THE Test_Runner SHALL execute all test files in `r-service/tests/` when invoked with `Rscript tests/run_all.R`
2. THE Test_Runner SHALL load test fixtures from `r-service/tests/fixtures/` containing known input data and expected outputs
3. WHEN testing the `/ega` endpoint, THE Test_Runner SHALL verify that exactly one item of the planted duplicate pair is present in `uva.removed_items`, and that the removed item IDs (`uva.removed_items` and `bootega.removed_items`) equal the sets recorded in the fixture by the `generate_fixtures.R` run, so that results are reproducible
4. WHEN testing the `/ega` endpoint, THE Test_Runner SHALL verify that `nmi.initial` and `nmi.final` are each within 0.001 of the values recorded in the fixture by the `generate_fixtures.R` run
5. WHEN testing the `/cfa` endpoint with planted structure, THE Test_Runner SHALL verify that recovered factor loadings are within ±0.10 of planted values documented in the fixture
6. WHEN testing the `/cfa` endpoint with planted structure, THE Test_Runner SHALL verify that the recovered factor correlation is within ±0.10 of the planted factor correlation documented in the fixture, and SHALL print CFI, RMSEA, and SRMR for reporting without asserting on them
7. WHEN testing the `/cfa` endpoint with the HolzingerSwineford1939 reference model, THE Test_Runner SHALL verify that chisq, df, CFI, and RMSEA are identical to direct lavaan::cfa() output for the same model
8. IF any numeric assertion fails, THEN THE Test_Runner SHALL report the expected value, actual value, and tolerance to stdout
9. WHEN all tests pass, THE Test_Runner SHALL exit with code 0 and print "All tests passed"
10. IF any test fails, THEN THE Test_Runner SHALL exit with code 1 and print the count of failed assertions

### Requirement 7: EGA Test Fixtures

**User Story:** As a test developer, I want reproducible EGA test fixtures with documented planted structure, so that tests remain deterministic and verifiable across runs.

#### Acceptance Criteria

1. THE Fixture SHALL contain an embedding matrix representing a multi-factor structure
2. THE Fixture SHALL be generated using cluster centers with additive noise and embedded duplicates, using a fixed random seed for reproducibility
3. THE Fixture SHALL document the generation method: cluster center positions, noise distribution parameters, duplicate item indices, and random seed
4. THE Fixture SHALL plant exactly one pair of near-duplicate items with high weighted topological overlap intended for UVA removal
5. THE Fixture SHALL plant unstable items with cross-loading behavior intended for bootEGA removal
6. THE Fixture SHALL document the intended dimension assignment for all items
7. THE Fixture SHALL record expected NMI values (initial and final) from the generation result, not from arbitrary targets
8. THE Fixture SHALL be saved as `r-service/tests/fixtures/ega_input.json` and `ega_expected.json`
9. THE Fixture SHALL include a generation script or inline documentation explaining how to regenerate the fixture
10. WHEN test assertions run, THE Test_Runner SHALL verify that exactly one item of the planted duplicate pair is present in `uva.removed_items`
11. WHEN test assertions run, THE Test_Runner SHALL verify that nmi.final >= nmi.initial

### Requirement 8: CFA Test Fixtures

**User Story:** As a test developer, I want reproducible CFA test fixtures with known factor structure, so that tests can verify the service correctly recovers planted loadings and fit statistics.

#### Acceptance Criteria

1. THE Fixture SHALL contain a response matrix with simulated personas responding to items
2. THE Fixture SHALL represent a multi-factor structure
3. THE Fixture SHALL plant factor loadings with documented values for each factor
4. THE Fixture SHALL plant a documented factor correlation
5. THE Fixture SHALL use a 5-point Likert scale (1–5) for all item responses
6. THE Fixture SHALL NOT define pass/fail ranges for CFI, RMSEA, or SRMR; these fit indices are reported by the test run only
7. THE Fixture SHALL be saved as `r-service/tests/fixtures/cfa_input.json` and `cfa_expected.json`
8. THE Fixture SHALL include documentation of the data generation code and random seed used for reproducibility
9. THE Test_Runner SHALL include a reference test using the 3-factor HolzingerSwineford1939 dataset from lavaan
10. WHEN testing with HolzingerSwineford1939, THE Test_Runner SHALL verify that the `/cfa` endpoint output is identical to direct lavaan::cfa() output for chisq, df, CFI, and RMSEA

### Requirement 9: Request Validation

**User Story:** As a security-conscious developer, I want all incoming requests validated before processing, so that malformed or malicious inputs cannot cause crashes or incorrect computations.

#### Acceptance Criteria

1. WHEN the `/ega` endpoint receives a request, THE R_Service SHALL verify that `embeddings` is a numeric matrix with at least 2 rows
2. WHEN the `/ega` endpoint receives a request, THE R_Service SHALL verify that `item_ids` length equals the number of rows in `embeddings`
3. WHEN the `/ega` endpoint receives a request, THE R_Service SHALL verify that `intended_dimensions` length equals the number of rows in `embeddings`
4. WHEN the `/cfa` endpoint receives a request, THE R_Service SHALL verify that `responses` is an integer matrix
5. WHEN the `/cfa` endpoint receives a request, THE R_Service SHALL verify that `item_ids` length equals the number of columns in `responses`
6. WHEN the `/cfa` endpoint receives a request, THE R_Service SHALL verify that all items in `model_specification.factors` are present in `item_ids`
7. IF validation fails, THEN THE R_Service SHALL return HTTP 400 with a specific error message indicating which validation rule was violated

### Requirement 10: Logging for Traceability

**User Story:** As a pipeline auditor, I want detailed logs of R service operations, so that I can trace psychometric decisions and debug issues in production.

#### Acceptance Criteria

1. WHEN the `/ega` endpoint processes a request, THE R_Service SHALL log to stdout: timestamp, endpoint, item count, config values (thresholds, iterations), and execution duration
2. WHEN the `/cfa` endpoint processes a request, THE R_Service SHALL log to stdout: timestamp, endpoint, persona count, item count, estimator type, and execution duration
3. WHEN UVA removes items, THE R_Service SHALL log the removed item IDs and their wTO scores
4. WHEN bootEGA removes items, THE R_Service SHALL log the removed item IDs and their stability scores
5. IF an error occurs, THEN THE R_Service SHALL log the error message, request_id, and timestamp to stderr
6. THE R_Service SHALL format all log entries as JSON for structured log parsing

### Requirement 11: Service Startup Documentation

**User Story:** As a system operator, I want clear instructions for starting the R service and installing dependencies, so that I can deploy the service without trial-and-error.

#### Acceptance Criteria

1. THE R_Service SHALL include a README.md file documenting required R packages with minimum version numbers
2. THE README SHALL include an installation script or commands for installing all dependencies
3. THE README SHALL document the command to start the service: `Rscript r-service/api.R`
4. THE README SHALL document the R_SERVICE_PORT environment variable and its default value
5. THE README SHALL document the command to run the test suite: `Rscript tests/run_all.R`
6. THE README SHALL include a health check example using curl: `curl http://localhost:8000/health`
7. THE README SHALL document the directory structure and purpose of each file

### Requirement 12: Integration Readiness

**User Story:** As a Next.js developer, I want the R service contract defined and stable, so that I can build the TypeScript client without rework when integration time comes.

#### Acceptance Criteria

1. THE R_Service SHALL implement the exact request and response schemas documented in `.kiro/steering/03-statistics-contract.md`
2. THE R_Service SHALL return Content-Type header `application/json` for all responses
3. THE R_Service SHALL accept requests with Content-Type `application/json`
4. THE R_Service SHALL enable CORS headers if the R_SERVICE_CORS environment variable is set to "true"
5. THE R_Service SHALL document the expected format for Next.js client calls in a code comment or example file
