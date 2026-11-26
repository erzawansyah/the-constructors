# tests/test_errors.R
# Error handling of the route handlers (Requirements 2.1, 2.5, 3.2, 5.1-5.4,
# 5.6, 9.7-9.10, 12.6). Handlers from make_handler() are called with mock
# req / res objects; no HTTP server is started. Config values below are
# # TEST ONLY and are not psychometric thresholds.
# Run via `Rscript tests/run_all.R` (helpers.R is sourced by the runner), or
# source helpers.R first when running this file directly from r-service/.

if (!exists("assert_true", mode = "function")) {
  source(file.path(if (dir.exists("tests")) "tests" else "r-service/tests", "helpers.R"))
  reset_test_state()
}

local({
  service_dir <- if (file.exists(file.path("ega", "pipeline.R"))) "." else "r-service"
  if (!file.exists(file.path(service_dir, "ega", "pipeline.R"))) {
    stop("test_errors.R: run from r-service/ (or the repo root)", call. = FALSE)
  }
  # api.R defines make_handler() and sources every module; it does not start
  # the server when sourced.
  if (!exists("make_handler", mode = "function")) {
    source(file.path(service_dir, "api.R"), local = FALSE)
  }

  uuid_re <- "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"

  call_handler <- function(handler, body_text) {
    res <- new.env()
    res$status <- NA_integer_
    out <- handler(list(postBody = body_text), res)
    list(status = res$status, body = out)
  }

  # A response must be an error body with a UUID request_id and no stack trace.
  check_error_shape <- function(r, label) {
    assert_equal("error", r$body$status, paste(label, "- status field is error"))
    assert_true(is.character(r$body$request_id) && length(r$body$request_id) == 1L &&
                  nzchar(r$body$request_id) && grepl(uuid_re, r$body$request_id),
                paste(label, "- request_id is a non-empty UUID"))
    assert_set_equal(c("status", "message", "request_id"), names(r$body),
                     paste(label, "- only status, message, request_id"))
    msg <- r$body$message
    assert_true(is.character(msg) && length(msg) == 1L && nzchar(msg) &&
                  !grepl("Traceback|traceback|Error in |\\.R#\\d+|\\bcall:", msg),
                paste(label, "- message has no stack trace"))
  }

  # ---- request builders (TEST ONLY values) ---------------------------------

  # JSON literals so that null can be placed exactly.
  base_config <- list(
    wto_threshold = "0.25",          # TEST ONLY
    stability_threshold = "0.75",    # TEST ONLY
    boot_iterations = "10",          # TEST ONLY
    network_method = "\"glasso\"",   # TEST ONLY
    community_algorithm = "\"walktrap\"",  # TEST ONLY
    random_seed = "1",               # TEST ONLY
    uva_method = "\"mbr\"",          # TEST ONLY
    bootstrap_type = "\"resampling\""  # TEST ONLY
  )

  config_json <- function(overrides = list(), drop = character(0)) {
    cfg <- utils::modifyList(base_config, overrides)
    cfg <- cfg[setdiff(names(cfg), drop)]
    paste0("{", paste0("\"", names(cfg), "\":", unlist(cfg), collapse = ","), "}")
  }

  ega_json <- function(config = config_json(),
                       item_ids = "[\"a\",\"b\",\"c\"]",
                       dims = "[0,0,1]",
                       embeddings = "[[0.1,0.2],[0.3,0.4],[0.5,0.7]]") {
    sprintf("{\"embeddings\":%s,\"item_ids\":%s,\"intended_dimensions\":%s,\"config\":%s}",
            embeddings, item_ids, dims, config)
  }

  cfa_json <- function(item_ids = "[\"a\",\"b\",\"c\"]",
                       responses = "[[1,2,3],[2,3,4],[3,4,5]]",
                       factors = "[{\"name\":\"F1\",\"items\":[\"a\",\"b\",\"c\"]}]") {
    sprintf("{\"responses\":%s,\"item_ids\":%s,\"model_specification\":{\"factors\":%s},\"ordinal\":true}",
            responses, item_ids, factors)
  }

  ega <- make_handler("ega", execute_ega_pipeline)
  cfa <- make_handler("cfa", execute_cfa_pipeline)

  # ---- null / missing config fields (Req 2.1, 2.5) -------------------------

  for (field in EGA_REQUIRED_CONFIG_FIELDS) {
    r <- call_handler(ega, ega_json(config_json(overrides = stats::setNames(list("null"), field))))
    assert_equal(400L, r$status, paste0("null ", field, " -> 400"))
    assert_equal(paste0("config.", field, " is null; owner decision required"),
                 r$body$message, paste0("null ", field, " message"))
    check_error_shape(r, paste0("null ", field))

    r <- call_handler(ega, ega_json(config_json(drop = field)))
    assert_equal(400L, r$status, paste0("missing ", field, " -> 400"))
    assert_equal(paste0("config.", field, " is missing"), r$body$message,
                 paste0("missing ", field, " message"))
    check_error_shape(r, paste0("missing ", field))
  }

  # ---- uva_method (Req 3.2) -------------------------------------------------

  cfg_for <- function(method) {
    config_json(overrides = list(uva_method = paste0("\"", method, "\"")))
  }

  # Stub EGAnet::UVA so that any call fails the test; restored afterwards.
  ns <- asNamespace("EGAnet")
  original_uva <- get("UVA", envir = ns)
  uva_called <- FALSE
  unlockBinding("UVA", ns)
  assign("UVA", function(...) {
    uva_called <<- TRUE
    stop("UVA stub must not be called for a rejected request")
  }, envir = ns)
  on.exit({
    assign("UVA", original_uva, envir = ns)
    lockBinding("UVA", ns)
  }, add = TRUE)

  for (m in c("ejp", "EJP")) {
    r <- call_handler(ega, ega_json(cfg_for(m)))
    assert_equal(400L, r$status, paste0("uva_method ", m, " -> 400"))
    assert_true(grepl("\"mbr\"", r$body$message, fixed = TRUE) &&
                  grepl("\"ejp\"", r$body$message, fixed = TRUE) &&
                  grepl("reduce.method \"remove\"", r$body$message, fixed = TRUE) &&
                  grepl("auto TRUE", r$body$message, fixed = TRUE) &&
                  grepl("interactive input", r$body$message, fixed = TRUE),
                paste0("uva_method ", m, " message explains interactive input"))
    check_error_shape(r, paste0("uva_method ", m))
  }
  assert_true(!uva_called, "UVA stub was not called: ejp rejected before UVA runs")

  r <- call_handler(ega, ega_json(cfg_for("wto")))
  assert_equal(400L, r$status, "uva_method wto -> 400")
  assert_true(grepl("wto", r$body$message, fixed = TRUE), "uva_method wto message names the value")
  check_error_shape(r, "uva_method wto")
  assert_true(!uva_called, "UVA stub was not called for wto")

  # validate_config() accepts mbr in any case.
  for (m in c("mbr", "MBR", "Mbr")) {
    cfg <- jsonlite::parse_json(cfg_for(m), simplifyVector = TRUE)
    ok <- tryCatch({ validate_config(cfg); TRUE }, error = function(e) FALSE)
    assert_true(ok, paste0("validate_config accepts uva_method ", m))
  }

  # ---- NA serialization (Req 12.6) -----------------------------------------

  serialized <- as.character(do.call(
    jsonlite::toJSON,
    c(list(list(status = "success", value = NA_real_, precise = 0.123456789)),
      list(auto_unbox = TRUE, na = "null", digits = NA))
  ))
  assert_true(grepl("\"value\":null", serialized, fixed = TRUE), "NA serializes as null")
  assert_true(!grepl("NA", serialized, fixed = TRUE), "serialized output has no \"NA\"")
  assert_true(grepl("0.123456789", serialized, fixed = TRUE), "0.123456789 is not rounded to 4 digits")

  # ---- malformed JSON (Req 5.1) --------------------------------------------

  for (bad in c("{not json", "", "{\"a\":")) {
    for (h in list(ega, cfa)) {
      r <- call_handler(h, bad)
      assert_equal(400L, r$status, paste0("malformed JSON '", bad, "' -> 400"))
      assert_true(startsWith(r$body$message, "Invalid JSON:"),
                  paste0("malformed JSON '", bad, "' message prefix"))
      check_error_shape(r, paste0("malformed JSON '", bad, "'"))
    }
  }

  # ---- dimension mismatches (Req 5.2, 9.7-9.10) ----------------------------

  r <- call_handler(ega, ega_json(item_ids = "[\"a\",\"b\"]"))
  assert_equal(400L, r$status, "item_ids vs embeddings rows -> 400")
  assert_equal("item_ids length (2) does not match embeddings rows (3)", r$body$message,
               "item_ids vs embeddings rows message")
  check_error_shape(r, "item_ids vs embeddings rows")

  r <- call_handler(ega, ega_json(dims = "[0,1]"))
  assert_equal(400L, r$status, "intended_dimensions vs rows -> 400")
  assert_equal("intended_dimensions length (2) does not match embeddings rows (3)",
               r$body$message, "intended_dimensions vs rows message")
  check_error_shape(r, "intended_dimensions vs rows")

  r <- call_handler(cfa, cfa_json(item_ids = "[\"a\",\"b\"]"))
  assert_equal(400L, r$status, "item_ids vs responses columns -> 400")
  assert_equal("item_ids length (2) does not match responses columns (3)", r$body$message,
               "item_ids vs responses columns message")
  check_error_shape(r, "item_ids vs responses columns")

  r <- call_handler(cfa, cfa_json(
    factors = "[{\"name\":\"F1\",\"items\":[\"a\",\"zzz\"]}]"))
  assert_equal(400L, r$status, "unknown model item -> 400")
  assert_equal("Items in model_specification not found in item_ids: zzz", r$body$message,
               "unknown model item message")
  check_error_shape(r, "unknown model item")

  # ---- internal errors (Req 5.3, 5.4, 5.6) ---------------------------------

  boom <- make_handler("ega", function(body) stop("simulated computation failure"),
                       log_fn = NULL)
  r <- call_handler(boom, ega_json())
  assert_equal(500L, r$status, "stubbed pipeline stop() -> 500")
  assert_equal("simulated computation failure", r$body$message, "500 message is the R error text")
  check_error_shape(r, "stubbed pipeline error")

  # Distinct request ids across calls.
  r2 <- call_handler(boom, ega_json())
  assert_true(!identical(r$body$request_id, r2$body$request_id), "request_id differs per request")
})
