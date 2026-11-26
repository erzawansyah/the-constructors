# logging/logger.R
#
# JSON-line logging for the R Statistics Service (Requirement 10, 5.5, 2.4).
# One JSON object per line. stdout for successful operations, stderr for errors.
#
# Public API (keep stable; api.R and the pipelines depend on it):
#
#   JSON_SERIALIZER_ARGS
#     list(auto_unbox = TRUE, na = "null", digits = NA). The single definition of
#     the serialization used for HTTP responses AND log lines (Requirement 12.6),
#     so numbers in logs equal numbers in responses. api.R should build its
#     plumber serializer from it:
#       do.call(plumber::serializer_json, JSON_SERIALIZER_ARGS)
#
#   to_json(x)
#     Serialize x with JSON_SERIALIZER_ARGS after sanitize_for_json(). Returns a
#     single-line character string.
#
#   sanitize_for_json(x)
#     Recursively drops ggplot objects (class "gg"/"ggplot", e.g. the $plot
#     element of an itemStability result), unclasses classed atomic vectors such
#     as EGA.community, turns NULL list elements into NA (so they serialize as
#     null instead of {}), and turns named atomic vectors into named lists (so
#     they serialize as JSON objects instead of losing their names).
#
#   iso_timestamp()
#     Current UTC time, ISO 8601 with milliseconds, e.g. "2026-01-15T10:30:00.123Z".
#
#   log_ega_execution(body, result, request_id, duration_ms, warnings = character(0))
#     body: parsed /ega request (list with item_ids, config, ...).
#     result: the /ega success response list (uva, bootega, retained_items, nmi).
#     warnings: character vector of pipeline warning messages collected by
#     make_handler() (e.g. from run_uva_loop() / compute_nmi()). Written as a
#     `warnings` JSON array: [] when none, and still an array for one message.
#     Writes to stdout.
#
#   log_cfa_execution(body, result, request_id, duration_ms, warnings = character(0))
#     body: parsed /cfa request. result: the /cfa response list (success or
#     warning). The estimator label is derived from body$ordinal with
#     cfa_estimator_label() ("WLSMV" / "ML"), the same rule run_cfa() uses; it is
#     never read from lavInspect(fit, "options")$estimator, which reports "DWLS".
#     warnings: as for log_ega_execution(). These are pipeline warnings seen by
#     make_handler(); lavaan warnings captured by run_cfa() are muffled there
#     and appear only in the response.
#     Writes to stdout.
#
#   log_error(endpoint, error, request_body, request_id, warnings = character(0))
#     endpoint: "ega" / "cfa" / ... ; error: a condition; request_body: the raw
#     body string (req$postBody), a raw vector, or an already parsed list.
#     warnings: pipeline warnings collected before the failure (same `warnings`
#     array as the success entries).
#     Writes to stderr with level "error". The embeddings / responses matrices
#     are never written; only their dimensions are recorded.
#
#   cfa_estimator_label(ordinal)
#     "WLSMV" if isTRUE(ordinal), otherwise "ML".

JSON_SERIALIZER_ARGS <- list(auto_unbox = TRUE, na = "null", digits = NA)

# Fields of a request that are never logged (Requirement 5.5).
.LOG_EXCLUDED_FIELDS <- c("embeddings", "responses")

# Maximum characters of an unparseable request body kept in an error log entry.
# Logging limit only, not a psychometric parameter.
.LOG_MAX_RAW_BODY_CHARS <- 2000L

# The eight /ega config fields logged with every /ega execution.
.EGA_CONFIG_FIELDS <- c(
  "wto_threshold", "stability_threshold", "boot_iterations", "network_method",
  "community_algorithm", "random_seed", "uva_method", "bootstrap_type"
)

iso_timestamp <- function() {
  format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")
}

cfa_estimator_label <- function(ordinal) {
  if (isTRUE(ordinal)) "WLSMV" else "ML"
}

sanitize_for_json <- function(x) {
  if (is.null(x)) return(NA)
  if (inherits(x, c("gg", "ggplot"))) return(NULL)
  if (is.data.frame(x)) {
    x <- as.data.frame(lapply(x, function(col) {
      if (is.atomic(col) && !is.null(oldClass(col)) && !inherits(col, "factor")) unclass(col) else col
    }), stringsAsFactors = FALSE, check.names = FALSE)
    return(x)
  }
  if (is.factor(x)) x <- as.character(x)
  if (is.atomic(x)) {
    if (!is.matrix(x)) {
      nms <- names(x)
      x <- as.vector(unclass(x))
      if (!is.null(nms)) {
        names(x) <- nms
        return(as.list(x))
      }
    }
    return(x)
  }
  if (is.list(x)) {
    nms <- names(x)
    out <- vector("list", length(x))
    keep <- rep(TRUE, length(x))
    for (i in seq_along(x)) {
      el <- x[[i]]
      if (inherits(el, c("gg", "ggplot"))) {
        keep[i] <- FALSE
      } else {
        val <- sanitize_for_json(el)
        out[i] <- list(val)
      }
    }
    names(out) <- nms
    out <- out[keep]
    if (is.null(nms) && length(out) == 0L) return(list())
    return(out)
  }
  # Functions, environments and other non-data objects are not serializable.
  paste0("<", class(x)[1L], ">")
}

to_json <- function(x) {
  as.character(do.call(jsonlite::toJSON, c(list(sanitize_for_json(x)), JSON_SERIALIZER_ARGS)))
}

.write_log_line <- function(entry, con) {
  cat(to_json(entry), "\n", sep = "", file = con)
  invisible(NULL)
}

.n_rows <- function(m) {
  if (is.null(m)) return(NA_integer_)
  if (is.matrix(m) || is.data.frame(m)) return(nrow(m))
  if (is.list(m)) return(length(m))
  NA_integer_
}

.n_cols <- function(m) {
  if (is.null(m)) return(NA_integer_)
  if (is.matrix(m) || is.data.frame(m)) return(ncol(m))
  if (is.list(m) && length(m) > 0L) return(length(m[[1L]]))
  NA_integer_
}

.scalar_or_na <- function(x) {
  if (is.null(x) || length(x) == 0L) NA else unname(x[[1L]])
}

.common_fields <- function(endpoint, request_id, duration_ms) {
  list(
    timestamp = iso_timestamp(),
    level = "info",
    request_id = request_id,
    endpoint = endpoint,
    execution_duration_ms = if (is.null(duration_ms)) NA_real_ else as.numeric(duration_ms)
  )
}

# `warnings` log field: always a JSON array. as.list() keeps a single message
# from being unboxed to a string by auto_unbox = TRUE; an empty vector gives [].
.warnings_field <- function(warnings) {
  if (is.null(warnings)) warnings <- character(0)
  as.list(as.character(warnings))
}

log_ega_execution <- function(body, result, request_id, duration_ms, warnings = character(0)) {
  config <- body$config
  config_values <- stats::setNames(
    lapply(.EGA_CONFIG_FIELDS, function(f) .scalar_or_na(config[[f]])),
    .EGA_CONFIG_FIELDS
  )

  uva_removed <- as.character(unlist(result$uva$removed_items))
  wto_scores <- result$uva$removed_wto_scores
  removed_uva_items <- lapply(uva_removed, function(id) {
    entry <- wto_scores[[id]]
    list(
      item_id = id,
      redundant_with = if (is.null(entry$redundant_with)) NA_character_ else .scalar_or_na(entry$redundant_with),
      wto = if (is.null(entry$wto)) NA_real_ else .scalar_or_na(entry$wto)
    )
  })

  boot_removed <- as.character(unlist(result$bootega$removed_items))
  stab_scores <- result$bootega$removed_stability_scores
  removed_bootega_items <- lapply(boot_removed, function(id) {
    list(
      item_id = id,
      stability = if (is.null(stab_scores[[id]])) NA_real_ else .scalar_or_na(stab_scores[[id]])
    )
  })

  entry <- c(
    .common_fields("ega", request_id, duration_ms),
    list(
      item_count = length(body$item_ids),
      config = config_values,
      removed_uva_items = removed_uva_items,
      removed_bootega_items = removed_bootega_items,
      retained_count = length(unlist(result$retained_items)),
      nmi_initial = if (is.null(result$nmi$initial)) NA_real_ else .scalar_or_na(result$nmi$initial),
      nmi_final = if (is.null(result$nmi$final)) NA_real_ else .scalar_or_na(result$nmi$final),
      warnings = .warnings_field(warnings)
    )
  )
  .write_log_line(entry, stdout())
}

log_cfa_execution <- function(body, result, request_id, duration_ms, warnings = character(0)) {
  factors <- body$model_specification$factors
  factor_count <- if (is.data.frame(factors)) nrow(factors) else length(factors)

  fit <- result$fit_indices
  if (is.null(fit)) fit <- result$partial_fit_indices

  entry <- c(
    .common_fields("cfa", request_id, duration_ms),
    list(
      status = if (is.null(result$status)) NA_character_ else .scalar_or_na(result$status),
      persona_count = .n_rows(body$responses),
      item_count = length(body$item_ids),
      estimator = cfa_estimator_label(body$ordinal),
      fit_variant = if (is.null(result$fit_variant)) NA_character_ else .scalar_or_na(result$fit_variant),
      factor_count = factor_count,
      cfi = if (is.null(fit$cfi)) NA_real_ else .scalar_or_na(fit$cfi),
      rmsea = if (is.null(fit$rmsea)) NA_real_ else .scalar_or_na(fit$rmsea),
      warnings = .warnings_field(warnings)
    )
  )
  .write_log_line(entry, stdout())
}

# Builds the request context for an error log entry without the large matrices.
.error_request_context <- function(request_body) {
  if (is.raw(request_body)) request_body <- rawToChar(request_body)

  parsed <- request_body
  if (is.character(request_body)) {
    text <- paste(request_body, collapse = "\n")
    parsed <- tryCatch(
      jsonlite::parse_json(text, simplifyVector = TRUE),
      error = function(e) NULL
    )
    if (is.null(parsed) || !is.list(parsed)) {
      # Unparseable body: keep a truncated copy so the parse failure can be
      # diagnosed, without risking a full embeddings matrix in the log.
      return(list(
        body_parsed = FALSE,
        body_chars = nchar(text, type = "chars"),
        body_excerpt = substr(text, 1L, .LOG_MAX_RAW_BODY_CHARS)
      ))
    }
  }
  if (is.null(parsed)) return(list(body_parsed = FALSE))
  if (!is.list(parsed)) return(list(body_parsed = FALSE))

  context <- parsed[setdiff(names(parsed), .LOG_EXCLUDED_FIELDS)]
  for (f in intersect(.LOG_EXCLUDED_FIELDS, names(parsed))) {
    context[[paste0(f, "_rows")]] <- .n_rows(parsed[[f]])
    context[[paste0(f, "_cols")]] <- .n_cols(parsed[[f]])
  }
  context
}

log_error <- function(endpoint, error, request_body, request_id, warnings = character(0)) {
  entry <- list(
    timestamp = iso_timestamp(),
    level = "error",
    request_id = request_id,
    endpoint = endpoint,
    error_class = if (inherits(error, "validation_error")) "validation_error" else "computation_error",
    error_message = if (inherits(error, "condition")) conditionMessage(error) else as.character(error),
    warnings = .warnings_field(warnings),
    request_context = .error_request_context(request_body)
  )
  .write_log_line(entry, stderr())
}
