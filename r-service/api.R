# api.R
#
# R Statistics Service: plumber JSON HTTP API (design.md "Service
# initialization"; Requirements 1.1-1.7, 5.1, 5.3, 5.4, 5.6, 12.2-12.6).
#
# Start (from the repo root):   Rscript r-service/api.R
# Health check:                 curl http://localhost:8000/health
#
# Environment variables:
#   R_SERVICE_HOST  host to bind              (default 127.0.0.1)
#   R_SERVICE_PORT  port to bind              (default 8000)
#   R_SERVICE_CORS  "true" adds CORS headers  (default unset = off)
#
# Routes:
#   GET  /health -> {"status": "ok", "timestamp": "<ISO 8601>"}
#   POST /ega    -> structural semantic screening (UVA, bootEGA, NMI)
#   POST /cfa    -> CFA for the technical rehearsal (smoke test), not validation
#
# Contract: .kiro/steering/03-statistics-contract.md. The service holds no
# psychometric thresholds; every value arrives in the request `config`.
#
# HTTP status:
#   200  success or warning (client checks the `status` field)
#   400  condition of class validation_error (malformed JSON, missing / null
#        config, unsupported uva_method, dimension mismatch)
#   500  any other R error during computation
# Error body: {"status": "error", "message": "<R error text>", "request_id": "<uuid>"}
# with no stack trace. The status is chosen by condition class, never by
# matching message text.
#
# Pipeline warnings (R warning() calls from the EGA / CFA pipelines) are
# collected by make_handler(), muffled, and written to the `warnings` array of
# the request's JSON log entry (success and error entries). They are not added
# to the HTTP response.
#
# Expected Next.js client call (TypeScript, server side):
#
#   const baseUrl = process.env.R_SERVICE_URL ?? "http://localhost:8000";
#   const res = await fetch(`${baseUrl}/ega`, {         // or `${baseUrl}/cfa`
#     method: "POST",
#     headers: { "Content-Type": "application/json" },
#     body: JSON.stringify({ embeddings, item_ids, intended_dimensions, config }),
#   });
#   const payload = await res.json();                   // every response is JSON
#   if (!res.ok) {
#     // 400: fix the request (e.g. a null config value: owner decision required)
#     // 500: R computation error. Log payload.request_id for correlation.
#     throw new Error(`R service ${res.status}: ${payload.message} (request_id ${payload.request_id})`);
#   }
#   if (payload.status === "warning") { /* e.g. CFA did not converge */ }
#   else if (payload.status !== "success") { throw new Error(payload.message); }
#
# Sourcing for tests: when this file is sourced (sys.nframe() > 0), routes and
# handlers are defined but the server is not started. `make_handler()`,
# `build_router()` and the module functions become available to the caller.

# ---- 1. Required packages (Requirements 1.6, 1.7) ---------------------------

.REQUIRED_PACKAGES <- c("plumber", "EGAnet", "lavaan", "igraph", "jsonlite", "uuid")

.missing_packages <- .REQUIRED_PACKAGES[
  !vapply(.REQUIRED_PACKAGES, requireNamespace, logical(1), quietly = TRUE)
]
if (length(.missing_packages) > 0L) {
  cat(
    "R Statistics Service cannot start. Missing required R package(s): ",
    paste(.missing_packages, collapse = ", "), "\n",
    "Install them with: Rscript r-service/install_packages.R\n",
    sep = "", file = stderr()
  )
  quit(save = "no", status = 1)
}

# ---- 2. Locate r-service/ and source modules --------------------------------

# Works for `Rscript r-service/api.R` (any working directory), for
# source("api.R") from r-service/ and for source("r-service/api.R") from the
# repo root.
.find_service_dir <- function() {
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  candidates <- character(0)
  if (length(file_arg) > 0L) {
    candidates <- c(candidates, dirname(sub("^--file=", "", file_arg[1L])))
  }
  for (i in rev(seq_len(sys.nframe()))) {
    ofile <- sys.frame(i)$ofile
    if (!is.null(ofile)) candidates <- c(candidates, dirname(ofile))
  }
  candidates <- c(candidates, ".", "r-service", "..")
  for (d in candidates) {
    if (file.exists(file.path(d, "utils", "conditions.R")) &&
        file.exists(file.path(d, "ega", "pipeline.R"))) {
      return(normalizePath(d, winslash = "/"))
    }
  }
  stop("api.R: cannot locate the r-service directory (utils/conditions.R not found). ",
       "Run `Rscript r-service/api.R` from the repo root or source api.R from r-service/.",
       call. = FALSE)
}

SERVICE_DIR <- .find_service_dir()

# Explicit order: each module depends only on modules listed before it.
.MODULE_FILES <- c(
  "utils/conditions.R",
  "logging/logger.R",
  "config/loader.R",
  "validation/request_validator.R",
  "ega/nmi.R",
  "ega/uva.R",
  "ega/bootega.R",
  "ega/pipeline.R",
  "cfa/model_builder.R",
  "cfa/estimator.R",
  "cfa/extractor.R",
  "cfa/pipeline.R"
)
for (.f in .MODULE_FILES) {
  source(file.path(SERVICE_DIR, .f), local = FALSE)
}
rm(.f)

# ---- 3. Handlers ------------------------------------------------------------

# Success loggers per endpoint. Endpoints without an entry are not logged on
# success.
.SUCCESS_LOGGERS <- list(ega = log_ega_execution, cfa = log_cfa_execution)

# Raw body text of a plumber request (postBody in plumber >= 1.0; bodyRaw as a
# fallback).
.request_body_text <- function(req) {
  body <- req$postBody
  if (is.null(body) && !is.null(req$bodyRaw)) body <- rawToChar(req$bodyRaw)
  body
}

# Logging must never change the HTTP response; a failure in a logger is
# reported to stderr and otherwise ignored.
.safe_log <- function(expr) {
  tryCatch(expr, error = function(e) {
    cat("log write failed: ", conditionMessage(e), "\n", sep = "", file = stderr())
  })
  invisible(NULL)
}

# True when `fn` can be called with a named `warnings` argument (it declares
# `warnings` or `...`). Lets a custom log_fn that only takes the original four
# arguments keep working.
.accepts_warnings <- function(fn) {
  is.function(fn) && any(c("warnings", "...") %in% names(formals(fn)))
}

# make_handler(endpoint, pipeline_fn, log_fn)
#   endpoint:    label used in logs ("ega", "cfa").
#   pipeline_fn: function(body) taking the parsed request and returning the
#                response list (execute_ega_pipeline / execute_cfa_pipeline).
#   log_fn:      success logger function(body, result, request_id, duration_ms,
#                warnings); defaults to the logger registered for `endpoint`.
#                `warnings` is passed as a named 5th argument. A log_fn that
#                declares neither `warnings` nor `...` is called with the
#                original four arguments only.
# Returns function(req, res). Only req$postBody (or req$bodyRaw) is read, and
# only res$status is set, so tests can call it with mock list / environment
# objects. HTTP status: 400 for validation_error, 500 for any other error,
# chosen by condition class.
#
# Pipeline warnings: every warning raised while pipeline_fn(body) runs (for
# example from run_uva_loop() or compute_nmi()) is collected as its message
# text and muffled, so it is no longer printed to stderr as plain text. The
# messages go to the `warnings` array of the request's JSON log entry, in both
# the success entry and the error entry (warnings raised before a failure).
# They are never added to the HTTP response; the response contract is
# unchanged (run_cfa() puts lavaan warnings in the /cfa response itself).
make_handler <- function(endpoint, pipeline_fn, log_fn = .SUCCESS_LOGGERS[[endpoint]]) {
  force(endpoint)
  force(pipeline_fn)
  force(log_fn)
  function(req, res) {
    request_id <- new_request_id()
    started <- Sys.time()
    raw_body <- .request_body_text(req)
    body <- NULL
    # Defined outside tryCatch() so the error handler sees warnings collected
    # before the failure.
    pipeline_warnings <- character(0)

    tryCatch(
      {
        body <- parse_json_body(raw_body)
        result <- withCallingHandlers(
          pipeline_fn(body),
          warning = function(w) {
            pipeline_warnings <<- c(pipeline_warnings, conditionMessage(w))
            invokeRestart("muffleWarning")
          }
        )
        duration_ms <- as.numeric(difftime(Sys.time(), started, units = "secs")) * 1000
        if (is.function(log_fn)) {
          if (.accepts_warnings(log_fn)) {
            .safe_log(log_fn(body, result, request_id, duration_ms, warnings = pipeline_warnings))
          } else {
            .safe_log(log_fn(body, result, request_id, duration_ms))
          }
        }
        res$status <- 200L
        result
      },
      error = function(e) {
        res$status <- if (inherits(e, "validation_error")) 400L else 500L
        # Parsed body when available, so the logger can drop the matrices
        # field by field; otherwise the raw text (truncated by the logger).
        .safe_log(log_error(endpoint, e, if (is.null(body)) raw_body else body, request_id,
                            warnings = pipeline_warnings))
        list(
          status = "error",
          message = conditionMessage(e),
          request_id = request_id
        )
      }
    )
  }
}

health_handler <- function(req, res) {
  list(status = "ok", timestamp = iso_timestamp())
}

ega_handler <- make_handler("ega", execute_ega_pipeline)
cfa_handler <- make_handler("cfa", execute_cfa_pipeline)

# ---- 4. Router --------------------------------------------------------------

# One serializer for every route and for error bodies (Requirement 12.6):
# auto_unbox = TRUE, na = "null" (NA -> null, never "NA"), digits = NA (full
# precision). Content-Type: application/json.
json_serializer <- function() {
  do.call(plumber::serializer_json, JSON_SERIALIZER_ARGS)
}

# CORS filter, added only when R_SERVICE_CORS == "true" (Requirement 12.4).
cors_filter <- function(req, res) {
  res$setHeader("Access-Control-Allow-Origin", "*")
  res$setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
  res$setHeader("Access-Control-Allow-Headers", "Content-Type")
  if (identical(req$REQUEST_METHOD, "OPTIONS")) {
    res$status <- 204L
    return(list())
  }
  plumber::forward()
}

# Errors raised outside the handlers' tryCatch (e.g. inside plumber itself):
# JSON body, no stack trace.
.router_error_handler <- function(req, res, err) {
  request_id <- new_request_id()
  res$status <- 500L
  .safe_log(log_error("router", err, list(path = req$PATH_INFO), request_id))
  list(status = "error", message = conditionMessage(err), request_id = request_id)
}

.router_404_handler <- function(req, res) {
  res$status <- 404L
  list(status = "error", message = paste0("Not found: ", req$REQUEST_METHOD, " ", req$PATH_INFO),
       request_id = new_request_id())
}

# Parser for application/json that returns the raw body unchanged (no
# parsing), so JSON parsing and its errors stay in parse_json_body().
.PASSTHROUGH_PARSER <- "json_passthrough"
.register_passthrough_parser <- function() {
  if (!(.PASSTHROUGH_PARSER %in% plumber::registered_parsers())) {
    plumber::register_parser(
      .PASSTHROUGH_PARSER,
      function(...) function(value, ...) value,
      fixed = "application/json",
      verbose = FALSE
    )
  }
  invisible(NULL)
}

build_router <- function(cors = identical(Sys.getenv("R_SERVICE_CORS"), "true")) {
  serializer <- json_serializer()
  pr <- plumber::pr()
  if (isTRUE(cors)) {
    pr <- plumber::pr_filter(pr, "cors", cors_filter)
  }
  # Body parsing: the POST routes use the pass-through parser registered
  # below, so plumber never parses JSON itself. The handlers parse
  # req$postBody with parse_json_body(), and malformed JSON becomes a
  # validation_error (HTTP 400, "Invalid JSON: ..."). With plumber's built-in
  # "json" parser a malformed body fails before the handler runs (HTTP 500),
  # and the built-in "none" parser fails on Windows with a regex error.
  .register_passthrough_parser()
  pr <- plumber::pr_get(pr, "/health", health_handler, serializer = serializer)
  pr <- plumber::pr_post(pr, "/ega", ega_handler, serializer = serializer,
                         parsers = .PASSTHROUGH_PARSER)
  pr <- plumber::pr_post(pr, "/cfa", cfa_handler, serializer = serializer,
                         parsers = .PASSTHROUGH_PARSER)
  pr <- plumber::pr_set_serializer(pr, serializer)
  pr <- plumber::pr_set_debug(pr, FALSE)
  pr <- plumber::pr_set_error(pr, .router_error_handler)
  pr <- plumber::pr_set_404(pr, .router_404_handler)
  pr
}

# ---- 5. Bind and run (Requirements 1.1-1.4) ---------------------------------

service_host <- function() {
  host <- Sys.getenv("R_SERVICE_HOST", unset = "")
  if (nzchar(host)) host else "127.0.0.1"
}

service_port <- function() {
  raw <- Sys.getenv("R_SERVICE_PORT", unset = "")
  if (!nzchar(raw)) return(8000L)
  port <- suppressWarnings(as.integer(raw))
  if (is.na(port) || port < 1L || port > 65535L || as.character(port) != trimws(raw)) {
    stop("R_SERVICE_PORT must be an integer between 1 and 65535; got \"", raw, "\"", call. = FALSE)
  }
  port
}

# Guard: start the server only when run as a script (Rscript r-service/api.R).
# source() from tests runs with sys.nframe() > 0, so the server does not start.
if (sys.nframe() == 0L) {
  .host <- service_host()
  .port <- service_port()
  cat(to_json(list(
    timestamp = iso_timestamp(), level = "info", event = "startup",
    host = .host, port = .port,
    cors = identical(Sys.getenv("R_SERVICE_CORS"), "true")
  )), "\n", sep = "")
  plumber::pr_run(build_router(), host = .host, port = .port, docs = FALSE, quiet = TRUE)
}
