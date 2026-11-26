# tests/generate_fixtures.R
#
# Generates the test fixtures for the R Statistics Service (Requirements
# 7.1-7.9, 8.1-8.8). Everything here is TEST ONLY: synthetic data and
# synthetic parameters. Nothing is read from or written to
# app-config/psychometric-procedure.yaml, and no value below is a production
# threshold.
#
# Regenerate (from r-service/):
#   Rscript tests/generate_fixtures.R
# (from the repo root: Rscript r-service/tests/generate_fixtures.R)
#
# Outputs, in r-service/tests/fixtures/:
#   ega_input.json     /ega request body (embeddings, item_ids,
#                      intended_dimensions, config) + documentation fields
#   ega_expected.json  ACTUAL results of one execute_ega_pipeline() run on
#                      ega_input.json: removed_uva, removed_bootega,
#                      nmi_initial, nmi_final. Not set by hand.
#   cfa_input.json     /cfa request body (responses, item_ids,
#                      model_specification, ordinal) + documentation fields
#   cfa_expected.json  planted loadings and planted factor correlation, each
#                      with tolerance 0.10. No pass/fail ranges for CFI,
#                      RMSEA or SRMR.
#
# ---- EGA input (TEST ONLY) --------------------------------------------------
# Seed:            EGA_SEED = 20260101 (set.seed() before any random draw here)
# Dimensions:      128-dimensional embedding space, 18 items, 3 factors,
#                  6 items per factor.
# Cluster centers: center_k ~ N(0, CENTER_SD^2) per coordinate, k = 1..3
#                  (CENTER_SD = 1.0), drawn once with rnorm().
# Items:           item = center of its factor + N(0, ITEM_NOISE_SD^2)
#                  (ITEM_NOISE_SD = 1.0). History: 0.5 gave within-factor
#                  correlations so high that UVA removed 6 items (incl. both
#                  item_003 and item_004); 1.5 made bootEGA also remove
#                  item_008, item_015, item_016; 1.0 gives the intended result
#                  (UVA removes item_003 only, bootEGA removes item_010 only).
#                  UVA_NOISE_SD, the item_010 mix and the seed are unchanged.
# Intended dims:   0-indexed. item_001..item_006 -> 0, item_007..item_012 -> 1,
#                  item_013..item_018 -> 2.
# Planted indices (1-based positions in the item list):
#   item_004 = item_003 + N(0, UVA_NOISE_SD^2), UVA_NOISE_SD = 0.05
#              (UVA target: near-duplicate of item_003).
#   item_010 = 0.5 * center_2 + 0.5 * center_3 + N(0, ITEM_NOISE_SD^2)
#              (bootEGA target: equal mix of the factor 2 and factor 3
#              centers; intended dimension stays 1, factor 2).
# EGA config:      every value is TEST ONLY (see EGA_TEST_CONFIG below).
#                  uva_method is "mbr", the only value the service accepts.
#
# ---- CFA input (TEST ONLY) --------------------------------------------------
# Seed:            CFA_SEED = 20260102
# Personas/items:  1000 personas x 12 items.
# Factors:         AnticDread (item_001..item_006) and WorkRumination
#                  (item_007..item_012), 6 items each.
# Latent scores:   MASS::mvrnorm(1000, c(0, 0), Sigma) with unit variances and
#                  factor correlation PLANTED_FACTOR_CORRELATION = 0.5.
# Planted loadings (standardized): 0.60, 0.65, 0.70, 0.75, 0.80, 0.70 for the
#                  six items of each factor, in item order.
# Continuous:      x = loading * latent + sqrt(1 - loading^2) * N(0, 1).
# Discretization:  cut points CUT_POINTS = -1.0, -0.3, 0.3, 1.0 on the
#                  standard-normal scale -> categories 1..5 (findInterval + 1).
# ordinal:         true.

# ---- locate r-service/ and source the pipeline (as api.R does) --------------

.find_service_dir <- function() {
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  candidates <- character(0)
  if (length(file_arg) > 0L) {
    candidates <- c(candidates, file.path(dirname(sub("^--file=", "", file_arg[1L])), ".."))
  }
  for (i in rev(seq_len(sys.nframe()))) {
    ofile <- sys.frame(i)$ofile
    if (!is.null(ofile)) candidates <- c(candidates, file.path(dirname(ofile), ".."))
  }
  candidates <- c(candidates, ".", "r-service", "..")
  for (d in candidates) {
    if (file.exists(file.path(d, "utils", "conditions.R")) &&
        file.exists(file.path(d, "ega", "pipeline.R"))) {
      return(normalizePath(d, winslash = "/"))
    }
  }
  stop("generate_fixtures.R: cannot locate the r-service directory. ",
       "Run `Rscript tests/generate_fixtures.R` from r-service/.", call. = FALSE)
}

for (pkg in c("EGAnet", "igraph", "jsonlite", "uuid", "MASS")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Missing R package: ", pkg, ". Run: Rscript r-service/install_packages.R", call. = FALSE)
  }
}

SERVICE_DIR <- .find_service_dir()
FIXTURE_DIR <- file.path(SERVICE_DIR, "tests", "fixtures")
dir.create(FIXTURE_DIR, recursive = TRUE, showWarnings = FALSE)

# Same order as api.R (EGA modules and their dependencies).
for (.f in c("utils/conditions.R", "logging/logger.R", "config/loader.R",
             "validation/request_validator.R", "ega/nmi.R", "ega/uva.R",
             "ega/bootega.R", "ega/pipeline.R")) {
  source(file.path(SERVICE_DIR, .f), local = FALSE)
}
rm(.f)

REGEN_COMMAND <- "Rscript tests/generate_fixtures.R (run from r-service/)"
TEST_ONLY_LABEL <- "TEST ONLY - not production values"

write_json_file <- function(x, name) {
  path <- file.path(FIXTURE_DIR, name)
  json <- do.call(jsonlite::toJSON, c(list(x), JSON_SERIALIZER_ARGS, list(pretty = TRUE)))
  writeLines(as.character(json), path, useBytes = TRUE)
  cat("wrote ", path, "\n", sep = "")
  invisible(path)
}

# ---- 1. EGA input -----------------------------------------------------------

EGA_SEED <- 20260101
N_DIM <- 128L
N_FACTORS <- 3L
ITEMS_PER_FACTOR <- 6L
CENTER_SD <- 1.0        # TEST ONLY
ITEM_NOISE_SD <- 1.0    # TEST ONLY
UVA_NOISE_SD <- 0.05    # TEST ONLY

set.seed(EGA_SEED)
centers <- matrix(rnorm(N_FACTORS * N_DIM, mean = 0, sd = CENTER_SD),
                  nrow = N_FACTORS, ncol = N_DIM)
n_items <- N_FACTORS * ITEMS_PER_FACTOR
factor_of_item <- rep(seq_len(N_FACTORS), each = ITEMS_PER_FACTOR)  # 1-based
item_ids <- sprintf("item_%03d", seq_len(n_items))

embeddings <- matrix(0, nrow = n_items, ncol = N_DIM)
for (i in seq_len(n_items)) {
  embeddings[i, ] <- centers[factor_of_item[i], ] + rnorm(N_DIM, 0, ITEM_NOISE_SD)
}
# UVA target: item_004 = item_003 + small noise.
embeddings[4L, ] <- embeddings[3L, ] + rnorm(N_DIM, 0, UVA_NOISE_SD)
# bootEGA target: item_010 = equal mix of factor 2 and factor 3 centers + noise.
embeddings[10L, ] <- 0.5 * centers[2L, ] + 0.5 * centers[3L, ] + rnorm(N_DIM, 0, ITEM_NOISE_SD)

intended_dimensions <- as.integer(factor_of_item - 1L)  # 0-indexed

# TEST ONLY: none of these come from app-config/psychometric-procedure.yaml.
EGA_TEST_CONFIG <- list(
  `_label` = TEST_ONLY_LABEL,
  wto_threshold = 0.25,            # TEST ONLY
  stability_threshold = 0.75,      # TEST ONLY
  boot_iterations = 100,           # TEST ONLY
  network_method = "glasso",       # TEST ONLY
  community_algorithm = "walktrap",# TEST ONLY
  random_seed = 42,                # TEST ONLY
  uva_method = "mbr",              # TEST ONLY (only value the service accepts)
  bootstrap_type = "resampling"    # TEST ONLY
)

ega_documentation <- list(
  label = TEST_ONLY_LABEL,
  regenerate = REGEN_COMMAND,
  seed = EGA_SEED,
  n_dimensions = N_DIM,
  n_factors = N_FACTORS,
  items_per_factor = ITEMS_PER_FACTOR,
  cluster_centers = paste0(
    "center_k ~ N(0, ", CENTER_SD, "^2) per coordinate, k = 1..3, drawn with rnorm() ",
    "after set.seed(", EGA_SEED, "); TEST ONLY"
  ),
  noise_parameters = list(
    item_noise_sd = ITEM_NOISE_SD,
    uva_noise_sd = UVA_NOISE_SD,
    note = "TEST ONLY. item = factor center + N(0, item_noise_sd^2)"
  ),
  planted_indices = list(
    uva_target = list(item = "item_004", index_0based = 3L, construction = "item_003 + N(0, uva_noise_sd^2)"),
    bootega_target = list(
      item = "item_010", index_0based = 9L,
      construction = "0.5 * center_2 + 0.5 * center_3 + N(0, item_noise_sd^2); intended dimension 1"
    )
  ),
  intended_dimensions_note = "0-indexed: item_001..006 = 0, item_007..012 = 1, item_013..018 = 2"
)

ega_request <- list(
  embeddings = embeddings,
  item_ids = item_ids,
  intended_dimensions = intended_dimensions,
  config = EGA_TEST_CONFIG
)
write_json_file(c(list(`_documentation` = ega_documentation), ega_request), "ega_input.json")

# ---- 2. EGA expected: ONE real run of the pipeline --------------------------

# Parse exactly as the service does (parse_json_body on the JSON text) so the
# pipeline sees the same types it sees over HTTP.
request_text <- as.character(do.call(jsonlite::toJSON, c(list(ega_request), JSON_SERIALIZER_ARGS)))
ega_result <- execute_ega_pipeline(parse_json_body(request_text))

ega_expected <- list(
  `_documentation` = c(
    ega_documentation,
    list(
      expected_source = paste(
        "Actual output of one execute_ega_pipeline() run on ega_input.json, recorded by",
        "generate_fixtures.R. Not set by hand. Regenerate after any change to EGAnet,",
        "the pipeline, or the input."
      ),
      package_versions = list(
        R = paste(R.version$major, R.version$minor, sep = "."),
        EGAnet = as.character(utils::packageVersion("EGAnet")),
        igraph = as.character(utils::packageVersion("igraph"))
      )
    )
  ),
  removed_uva = as.list(as.character(unlist(ega_result$uva$removed_items))),
  removed_bootega = as.list(as.character(unlist(ega_result$bootega$removed_items))),
  nmi_initial = ega_result$nmi$initial,
  nmi_final = ega_result$nmi$final
)
write_json_file(ega_expected, "ega_expected.json")

# ---- 3. CFA input -----------------------------------------------------------

CFA_SEED <- 20260102
N_PERSONAS <- 1000L
PLANTED_FACTOR_CORRELATION <- 0.5                      # TEST ONLY
PLANTED_LOADINGS_PER_FACTOR <- c(0.60, 0.65, 0.70, 0.75, 0.80, 0.70)  # TEST ONLY
CUT_POINTS <- c(-1.0, -0.3, 0.3, 1.0)                  # TEST ONLY
TOLERANCE <- 0.10                                      # TEST ONLY
FACTOR_NAMES <- c("AnticDread", "WorkRumination")

cfa_item_ids <- sprintf("item_%03d", 1:12)
factor_index <- rep(1:2, each = 6L)
loadings <- rep(PLANTED_LOADINGS_PER_FACTOR, times = 2L)

set.seed(CFA_SEED)
sigma <- matrix(c(1, PLANTED_FACTOR_CORRELATION, PLANTED_FACTOR_CORRELATION, 1), 2L, 2L)
latent <- MASS::mvrnorm(N_PERSONAS, mu = c(0, 0), Sigma = sigma)
continuous <- matrix(0, nrow = N_PERSONAS, ncol = 12L)
for (j in 1:12) {
  continuous[, j] <- loadings[j] * latent[, factor_index[j]] +
    sqrt(1 - loadings[j]^2) * rnorm(N_PERSONAS)
}
responses <- matrix(as.integer(findInterval(continuous, CUT_POINTS) + 1L),
                    nrow = N_PERSONAS, ncol = 12L)
stopifnot(all(responses >= 1L & responses <= 5L))

cfa_documentation <- list(
  label = TEST_ONLY_LABEL,
  regenerate = REGEN_COMMAND,
  seed = CFA_SEED,
  n_personas = N_PERSONAS,
  n_items = 12L,
  latent_scores = "MASS::mvrnorm(1000, c(0, 0), Sigma), unit variances; TEST ONLY",
  noise_parameters = list(
    residual = "x = loading * latent + sqrt(1 - loading^2) * N(0, 1)",
    cut_points = CUT_POINTS,
    categories = "findInterval(x, cut_points) + 1 -> 1..5",
    note = "TEST ONLY"
  ),
  planted_indices = list(
    AnticDread = "item_001..item_006 (indices 0..5)",
    WorkRumination = "item_007..item_012 (indices 6..11)"
  )
)

cfa_request <- list(
  responses = responses,
  item_ids = cfa_item_ids,
  model_specification = list(factors = list(
    list(name = FACTOR_NAMES[1L], items = cfa_item_ids[1:6]),
    list(name = FACTOR_NAMES[2L], items = cfa_item_ids[7:12])
  )),
  ordinal = TRUE
)
write_json_file(c(list(`_documentation` = cfa_documentation), cfa_request), "cfa_input.json")

# ---- 4. CFA expected: planted values only -----------------------------------

planted_loadings <- lapply(1:2, function(f) {
  idx <- which(factor_index == f)
  as.list(stats::setNames(loadings[idx], cfa_item_ids[idx]))
})
names(planted_loadings) <- FACTOR_NAMES

cfa_expected <- list(
  `_label` = TEST_ONLY_LABEL,
  `_documentation` = c(
    cfa_documentation,
    list(note = paste(
      "Planted values only (TEST ONLY). The CFA run is a technical rehearsal (smoke test),",
      "not validation. No pass/fail ranges for CFI, RMSEA or SRMR are defined here."
    ))
  ),
  planted_loadings = list(
    `_label` = TEST_ONLY_LABEL,
    tolerance = TOLERANCE,
    values = planted_loadings
  ),
  planted_factor_correlation = list(
    `_label` = TEST_ONLY_LABEL,
    pair = "AnticDread_WorkRumination",
    value = PLANTED_FACTOR_CORRELATION,
    tolerance = TOLERANCE
  )
)
write_json_file(cfa_expected, "cfa_expected.json")
