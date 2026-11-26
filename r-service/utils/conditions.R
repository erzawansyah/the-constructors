# utils/conditions.R
#
# Shared condition and request helpers for the R Statistics Service.
# Sourced by api.R before config/, validation/, ega/ and cfa/.
#
# Public API (keep stable; later modules depend on it):
#
#   validation_error(msg)
#     Returns (does not signal) a condition object of class
#     c("validation_error", "error", "condition") with call = NULL.
#     Signal it with stop():   stop(validation_error("config.x is missing"))
#     Route handlers choose HTTP 400 vs 500 with inherits(e, "validation_error"),
#     never by matching message text.
#
#   new_request_id()
#     Returns a new UUID string (uuid::UUIDgenerate()) for log correlation.
#
#   parse_json_body(post_body, ...)
#     Parses a request body (character string or raw vector) as JSON text with
#     jsonlite::parse_json(simplifyVector = TRUE), so the result has the same
#     shape as jsonlite::fromJSON(): a list of numeric rows becomes a matrix and
#     whole numbers become integer (see PROBE_NOTES.md 3.7). parse_json() is used
#     instead of fromJSON() because fromJSON() treats a string that looks like a
#     file path or URL as a location to read, which must not happen for
#     untrusted request bodies. Extra arguments are passed to parse_json().
#     An empty body or any parse failure signals
#     validation_error("Invalid JSON: <parser message>").

validation_error <- function(msg) {
  structure(
    class = c("validation_error", "error", "condition"),
    list(message = as.character(msg), call = NULL)
  )
}

new_request_id <- function() {
  uuid::UUIDgenerate()
}

parse_json_body <- function(post_body, ...) {
  if (is.raw(post_body)) {
    post_body <- rawToChar(post_body)
  }
  if (is.null(post_body) || length(post_body) == 0L ||
      !is.character(post_body) || all(!nzchar(trimws(post_body)))) {
    stop(validation_error("Invalid JSON: request body is empty"))
  }
  text <- paste(post_body, collapse = "\n")

  tryCatch(
    jsonlite::parse_json(text, simplifyVector = TRUE, ...),
    error = function(e) {
      stop(validation_error(paste0("Invalid JSON: ", conditionMessage(e))))
    }
  )
}
