# tests/test_cfa.R
# /cfa pipeline against the recorded fixture (Requirements 4.13, 6.2, 6.5,
# 6.6, 6.11, 8.11). Fixture values are TEST ONLY.
#
# This test checks that the CFA code path recovers the planted structure
# (loadings and factor correlation) on simulated data. It is a technical
# rehearsal (smoke test), not validation and not a verdict on any scale.
# Fit indices are printed for reporting only and are never asserted on.
#
# Run via `Rscript tests/run_all.R` (helpers.R is sourced by the runner), or
# source helpers.R first when running this file directly from r-service/.

if (!exists("assert_true", mode = "function")) {
  source(file.path(if (dir.exists("tests")) "tests" else "r-service/tests", "helpers.R"))
  reset_test_state()
}

local({
  service_dir <- if (file.exists(file.path("cfa", "pipeline.R"))) "." else "r-service"
  if (!file.exists(file.path(service_dir, "cfa", "pipeline.R"))) {
    stop("test_cfa.R: run from r-service/ (or the repo root)", call. = FALSE)
  }
  fixture_dir <- file.path(service_dir, "tests", "fixtures")

  for (f in c("utils/conditions.R", "logging/logger.R", "config/loader.R",
              "validation/request_validator.R", "cfa/model_builder.R",
              "cfa/estimator.R", "cfa/extractor.R", "cfa/pipeline.R")) {
    source(file.path(service_dir, f), local = FALSE)
  }

  input_text <- paste(readLines(file.path(fixture_dir, "cfa_input.json"), warn = FALSE),
                      collapse = "\n")
  expected <- jsonlite::fromJSON(file.path(fixture_dir, "cfa_expected.json"),
                                 simplifyVector = FALSE)

  result <- execute_cfa_pipeline(parse_json_body(input_text))

  # Reporting only: no assertion on any fit index.
  fi <- result$fit_indices
  show <- function(x) if (is.null(x) || is.na(x)) "NA" else format(x, digits = 6)
  cat("Technical rehearsal (smoke test), not validation. Fit values reported only:\n")
  cat(sprintf("  chisq (scaled): %s\n", show(fi$chisq)))
  cat(sprintf("  df (scaled):    %s\n", show(fi$df)))
  cat(sprintf("  CFI (robust):   %s\n", show(fi$cfi)))
  cat(sprintf("  RMSEA (robust): %s\n", show(fi$rmsea)))
  cat(sprintf("  SRMR:           %s\n", show(fi$srmr)))

  assert_equal("success", result$status, "status is success")
  assert_equal("scaled_robust", result$fit_variant, "fit_variant is scaled_robust")

  # Loadings within the fixture tolerance of the planted values.
  load_tol <- expected$planted_loadings$tolerance
  for (factor_name in names(expected$planted_loadings$values)) {
    planted <- expected$planted_loadings$values[[factor_name]]
    for (item in names(planted)) {
      planted_value <- planted[[item]]
      actual <- result$loadings[[factor_name]][[item]]
      cat(sprintf("  loading %s/%s: planted %.2f, estimated %s\n",
                  factor_name, item, planted_value, show(actual)))
      assert_near(planted_value, if (is.null(actual)) NA_real_ else actual, load_tol,
                  paste("loading", factor_name, item))
    }
  }

  # Factor correlation within the fixture tolerance.
  corr <- expected$planted_factor_correlation
  actual_corr <- result$factor_correlations[[corr$pair]]
  cat(sprintf("  factor correlation %s: planted %.2f, estimated %s\n",
              corr$pair, corr$value, show(actual_corr)))
  assert_near(corr$value, if (is.null(actual_corr)) NA_real_ else actual_corr,
              corr$tolerance, paste("factor correlation", corr$pair))
})
