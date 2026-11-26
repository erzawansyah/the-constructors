# tests/test_holzinger.R
# /cfa pipeline (ML, ordinal = false) against a direct lavaan fit on the
# Holzinger-Swineford 1939 data (Requirements 4.12, 4.13, 6.7, 6.12, 8.9,
# 8.10, 8.12). The data are continuous (non-integer) real-world scores, which
# the validator accepts when ordinal is false.
#
# This checks that the pipeline reproduces lavaan's own ML fit indices. It is
# a code-path check, not a validation of any scale.
# Run via `Rscript tests/run_all.R`, or source helpers.R first when running
# this file directly from r-service/.

if (!exists("assert_true", mode = "function")) {
  source(file.path(if (dir.exists("tests")) "tests" else "r-service/tests", "helpers.R"))
  reset_test_state()
}

local({
  service_dir <- if (file.exists(file.path("cfa", "pipeline.R"))) "." else "r-service"
  if (!file.exists(file.path(service_dir, "cfa", "pipeline.R"))) {
    stop("test_holzinger.R: run from r-service/ (or the repo root)", call. = FALSE)
  }

  for (f in c("utils/conditions.R", "logging/logger.R", "config/loader.R",
              "validation/request_validator.R", "cfa/model_builder.R",
              "cfa/estimator.R", "cfa/extractor.R", "cfa/pipeline.R")) {
    source(file.path(service_dir, f), local = FALSE)
  }

  item_ids <- paste0("x", 1:9)
  data <- lavaan::HolzingerSwineford1939[, item_ids]
  responses <- unname(as.matrix(data))

  model <- paste(
    "visual =~ x1 + x2 + x3",
    "textual =~ x4 + x5 + x6",
    "speed =~ x7 + x8 + x9",
    sep = "\n"
  )

  body <- list(
    responses = responses,
    item_ids = item_ids,
    model_specification = list(factors = list(
      list(name = "visual", items = c("x1", "x2", "x3")),
      list(name = "textual", items = c("x4", "x5", "x6")),
      list(name = "speed", items = c("x7", "x8", "x9"))
    )),
    ordinal = FALSE
  )

  result <- execute_cfa_pipeline(body)

  ref_fit <- lavaan::cfa(model, data = data, estimator = "ML", std.lv = TRUE)
  ref <- lavaan::fitMeasures(ref_fit, c("chisq", "df", "cfi", "rmsea"))

  fi <- result$fit_indices
  cat("Holzinger-Swineford ML: pipeline vs direct lavaan reference\n")
  for (nm in c("chisq", "df", "cfi", "rmsea")) {
    cat(sprintf("  %-6s pipeline %s  reference %s\n", nm,
                format(fi[[nm]], digits = 10), format(unname(ref[[nm]]), digits = 10)))
  }

  assert_equal("success", result$status, "Holzinger CFA status is success")
  assert_equal("standard", result$fit_variant, "Holzinger fit_variant is standard")

  assert_near(unname(ref[["chisq"]]), unname(fi$chisq), 1e-6, "Holzinger chisq matches reference")
  assert_near(unname(ref[["cfi"]]), unname(fi$cfi), 1e-6, "Holzinger CFI matches reference")
  assert_near(unname(ref[["rmsea"]]), unname(fi$rmsea), 1e-6, "Holzinger RMSEA matches reference")
  assert_near(unname(ref[["df"]]), unname(fi$df), 0.5, "Holzinger df matches reference")

  # Validator keeps non-integer responses as double when ordinal is false.
  v <- validate_cfa_request(body)
  assert_true(is.double(v$responses), "validator keeps responses as double when ordinal is false")
  assert_near(responses, v$responses, 0, "validator does not alter response values")
})
