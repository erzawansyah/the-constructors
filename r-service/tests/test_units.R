# tests/test_units.R
# Unit tests for model building, NMI, config and request validation, and fit
# index extraction (Requirements 2.1, 2.2, 2.5, 3.11, 3.12, 4.4, 4.10 to 4.14,
# 9.1, 9.4, 9.8, 9.9, 9.10).
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
    stop("test_units.R: run from r-service/ (or the repo root)", call. = FALSE)
  }
  for (f in c("utils/conditions.R", "config/loader.R",
              "validation/request_validator.R", "ega/nmi.R",
              "cfa/model_builder.R", "cfa/extractor.R")) {
    source(file.path(service_dir, f), local = FALSE)
  }

  # Returns list(error = <condition or NULL>, warnings = <character>).
  capture <- function(expr) {
    warns <- character(0)
    err <- NULL
    tryCatch(
      withCallingHandlers(expr, warning = function(w) {
        warns <<- c(warns, conditionMessage(w))
        invokeRestart("muffleWarning")
      }),
      error = function(e) err <<- e
    )
    list(error = err, warnings = warns)
  }
  expect_validation_error <- function(expr, pattern, label) {
    r <- capture(expr)
    assert_true(inherits(r$error, "validation_error"), paste(label, "- class"))
    assert_true(!is.null(r$error) && grepl(pattern, conditionMessage(r$error), fixed = TRUE),
                paste(label, "- message"))
  }

  # ---- build_lavaan_model (4.4) ---------------------------------------------
  assert_equal(
    "F1 =~ a + b + c",
    build_lavaan_model(list(factors = list(list(name = "F1", items = c("a", "b", "c"))))),
    "build_lavaan_model 1 factor"
  )
  assert_equal(
    "F1 =~ a + b\nF2 =~ c + d + e",
    build_lavaan_model(list(factors = list(
      list(name = "F1", items = c("a", "b")),
      list(name = "F2", items = c("c", "d", "e"))))),
    "build_lavaan_model 2 factors"
  )

  # ---- compute_nmi (3.11, 3.12) ---------------------------------------------
  assert_near(1, compute_nmi(c(1, 1, 2, 2, 3, 3), c(1, 1, 2, 2, 3, 3)), 1e-12,
              "compute_nmi identical partitions")
  assert_near(1, compute_nmi(c(2, 2, 1, 1), c(1, 1, 2, 2)), 1e-12,
              "compute_nmi relabelled partitions")
  r <- capture(res <- compute_nmi(c(1, 1, NA, 2, 2), c(1, 1, 1, 2, 2)))
  assert_true(is.null(r$error), "compute_nmi NA: no error")
  assert_true(length(r$warnings) == 1L && grepl("dropped 1", r$warnings), "compute_nmi NA: warning")
  assert_near(1, res, 1e-12, "compute_nmi NA dropped value")
  r <- capture(compute_nmi(c(1, 2), c(1, 2, 3)))
  assert_true(!is.null(r$error) && grepl("equal length", conditionMessage(r$error)),
              "compute_nmi length mismatch errors")
  r <- capture(compute_nmi(c(NA_real_, NA_real_), c(1, 2)))
  assert_true(!is.null(r$error) && grepl("no positions remain", conditionMessage(r$error)),
              "compute_nmi all-NA errors")

  # ---- validate_config (2.1, 2.2, 2.5) --------------------------------------
  complete <- list(wto_threshold = 0.2, stability_threshold = 0.7, boot_iterations = 10L,
                   network_method = "glasso", community_algorithm = "walktrap",
                   random_seed = 1L, uva_method = "mbr", bootstrap_type = "resampling")
  assert_true(is.list(validate_config(complete)), "validate_config complete passes")

  for (field in EGA_REQUIRED_CONFIG_FIELDS) {
    cfg <- complete
    cfg[field] <- list(NULL)
    expect_validation_error(validate_config(cfg),
                            paste0("config.", field, " is null; owner decision required"),
                            paste("null", field))
    cfg <- complete
    cfg[[field]] <- NULL
    expect_validation_error(validate_config(cfg),
                            paste0("config.", field, " is missing"),
                            paste("missing", field))
  }
  expect_validation_error(validate_config(NULL), "config is missing", "NULL config")

  for (m in c("mbr", "MBR", "Mbr")) {
    cfg <- complete
    cfg$uva_method <- m
    assert_true(is.list(validate_config(cfg)), paste("uva_method accepted:", m))
  }
  for (m in c("ejp", "EJP")) {
    cfg <- complete
    cfg$uva_method <- m
    expect_validation_error(validate_config(cfg), "interactive input", paste("uva_method", m))
  }
  cfg <- complete
  cfg$uva_method <- "wto"
  expect_validation_error(validate_config(cfg), "config.uva_method must be", "uva_method wto")

  # ---- extract_fit_indices (4.10 to 4.14) -----------------------------------
  set.seed(42)
  n <- 300
  f <- rnorm(n)
  cont <- sapply(1:6, function(i) 0.7 * f + rnorm(n, sd = 0.7))
  colnames(cont) <- paste0("x", 1:6)
  ord <- as.data.frame(apply(cont, 2, function(v) as.integer(cut(v, c(-Inf, -0.5, 0.5, Inf)))))
  model <- "F =~ x1 + x2 + x3 + x4 + x5 + x6"

  fit_w <- suppressWarnings(lavaan::cfa(model, data = ord, ordered = names(ord),
                                        estimator = "WLSMV"))
  fm_w <- lavaan::fitMeasures(fit_w)
  out_w <- extract_fit_indices(fit_w, TRUE)
  assert_equal("scaled_robust", out_w$fit_variant, "WLSMV fit_variant")
  expected_w <- c(chisq = "chisq.scaled", df = "df.scaled", pvalue = "pvalue.scaled",
                  cfi = "cfi.robust", tli = "tli.robust", rmsea = "rmsea.robust",
                  rmsea_ci_lower = "rmsea.ci.lower.robust",
                  rmsea_ci_upper = "rmsea.ci.upper.robust", srmr = "srmr")
  for (key in names(expected_w)) {
    assert_near(unname(fm_w[[expected_w[[key]]]]), out_w$fit_indices[[key]], 1e-6,
                paste("WLSMV", key))
  }

  fit_m <- suppressWarnings(lavaan::cfa(model, data = as.data.frame(cont), estimator = "ML"))
  fm_m <- lavaan::fitMeasures(fit_m)
  out_m <- extract_fit_indices(fit_m, FALSE)
  assert_equal("standard", out_m$fit_variant, "ML fit_variant")
  expected_m <- c(chisq = "chisq", df = "df", pvalue = "pvalue", cfi = "cfi", tli = "tli",
                  rmsea = "rmsea", rmsea_ci_lower = "rmsea.ci.lower",
                  rmsea_ci_upper = "rmsea.ci.upper", srmr = "srmr")
  for (key in names(expected_m)) {
    assert_near(unname(fm_m[[expected_m[[key]]]]), out_m$fit_indices[[key]], 1e-6,
                paste("ML", key))
  }

  # Saturated model (df = 0): lavaan reports NA for some indices; NA stays NA.
  fit_sat <- suppressWarnings(lavaan::cfa("F =~ x1 + x2 + x3",
                                          data = as.data.frame(cont), estimator = "ML"))
  fm_s <- lavaan::fitMeasures(fit_sat)
  out_s <- extract_fit_indices(fit_sat, FALSE)
  for (key in names(expected_m)) {
    assert_near(unname(fm_s[[expected_m[[key]]]]), out_s$fit_indices[[key]], 1e-6,
                paste("saturated", key))
  }
  n_na <- sum(is.na(unlist(out_s$fit_indices)))
  assert_equal(sum(is.na(fm_s[unname(expected_m)])), n_na, "saturated NA count preserved")

  # ---- validate_ega_request / validate_cfa_request (9.1, 9.4, 9.8 to 9.10) --
  ega_body <- list(embeddings = matrix(c(0.1, 0.2, 0.3, 0.4), nrow = 1),
                   item_ids = "a", intended_dimensions = 0L, config = complete)
  expect_validation_error(validate_ega_request(ega_body), "at least 2 rows",
                          "ega fewer than 2 rows")
  ega_body <- list(embeddings = matrix(c(0.1, 0.2, 0.3, 0.4), nrow = 2),
                   item_ids = c("a", "b"), intended_dimensions = c(0L, 1L), config = complete)
  assert_true(is.list(validate_ega_request(ega_body)), "ega valid request passes")

  cfa_body <- list(responses = matrix(c(1, 2, 3, 4, 5, 1), nrow = 2),
                   item_ids = c("a", "b", "c"),
                   model_specification = list(factors = list(list(name = "F", items = c("a", "b", "c")))),
                   ordinal = TRUE)
  assert_true(is.list(validate_cfa_request(cfa_body)), "cfa valid request passes")
  bad <- cfa_body
  bad$responses <- matrix(c(1, 2.5, 3, 4, 5, 1), nrow = 2)
  expect_validation_error(validate_cfa_request(bad), "integer values", "cfa non-integer ordinal")
  bad$ordinal <- FALSE
  assert_true(is.list(validate_cfa_request(bad)), "cfa non-integer accepted when not ordinal")
  bad <- cfa_body
  bad$responses <- matrix(c(1, 2, 3), nrow = 1)
  expect_validation_error(validate_cfa_request(bad), "at least 2 rows", "cfa fewer than 2 rows")
})
