# validation/request_validator.R
#
# Schema and dimension checks for /ega and /cfa request bodies.
# Depends on utils/conditions.R (validation_error()), sourced first by api.R.
#
# Input: `body` is the list returned by parse_json_body() (jsonlite::parse_json
# with simplifyVector = TRUE). With that parser (verified on jsonlite 2.0.0):
#   - a list of equal-length numeric rows becomes a matrix (whole numbers are
#     integer, decimals double, JSON null becomes NA);
#   - ragged rows stay a list of vectors;
#   - an array of factor objects becomes a data.frame with a character column
#     `name` and a list column `items`.
# Both the simplified forms and the unsimplified list forms are accepted.
#
# Public API:
#
#   validate_ega_request(body)
#     Checks `embeddings`, `item_ids`, `intended_dimensions`, `config`.
#     Returns `body` with normalized fields:
#       embeddings          double matrix, one row per item, no dimnames
#       item_ids            character vector
#       intended_dimensions integer vector (0-indexed, as sent)
#       config              unchanged; validate_config() (config/loader.R) checks
#                           its fields, including uva_method, right after this
#
#   validate_cfa_request(body)
#     Checks `responses`, `item_ids`, `model_specification`, `ordinal`.
#     Returns `body` with normalized fields:
#       responses           integer matrix, rows = personas, columns = items
#       item_ids            character vector
#       model_specification list(factors = list(list(name = <chr>,
#                                                    items = <chr vector>), ...))
#       ordinal             logical scalar
#
# Every failure signals stop(validation_error(<message>)), which route handlers
# map to HTTP 400 by condition class. No psychometric values are checked here.

# ---- internal helpers -------------------------------------------------------

.require_fields <- function(body, fields) {
  if (!is.list(body) || is.data.frame(body) ||
      (length(body) > 0L && is.null(names(body)))) {
    stop(validation_error("Request body must be a JSON object"))
  }
  for (field in fields) {
    if (!(field %in% names(body))) {
      stop(validation_error(paste0(field, " is missing")))
    }
    if (is.null(body[[field]])) {
      stop(validation_error(paste0(field, " is null")))
    }
  }
  invisible(TRUE)
}

# Bind a list of rows into a matrix. Rows must be atomic, non-empty and of
# equal length; otherwise rbind() would silently recycle.
.as_row_matrix <- function(x, field) {
  if (is.matrix(x)) {
    return(x)
  }
  if (is.list(x) && !is.data.frame(x)) {
    if (length(x) == 0L) {
      stop(validation_error(paste0(field, " must be a non-empty matrix (list of rows)")))
    }
    rows <- lapply(seq_along(x), function(i) {
      row <- x[[i]]
      if (is.list(row)) {
        # rows containing JSON null are not simplified; map NULL to NA
        row <- unlist(lapply(row, function(v) if (is.null(v)) NA else v))
      }
      if (is.null(row) || !is.atomic(row) || length(row) == 0L) {
        stop(validation_error(sprintf("%s row %d is not a non-empty array of values", field, i)))
      }
      row
    })
    lens <- vapply(rows, length, integer(1))
    if (length(unique(lens)) != 1L) {
      stop(validation_error(sprintf(
        "%s rows have unequal lengths (%s)", field,
        paste(sort(unique(lens)), collapse = ", ")
      )))
    }
    return(do.call(rbind, rows))
  }
  stop(validation_error(paste0(field, " must be a matrix (list of rows)")))
}

.check_numeric_matrix <- function(m, field) {
  if (!is.numeric(m) && !(is.logical(m) && all(is.na(m)))) {
    stop(validation_error(paste0(field, " must contain only numeric values")))
  }
  if (any(!is.finite(m))) {
    stop(validation_error(paste0(field, " contains null, NA or non-finite values")))
  }
  invisible(TRUE)
}

.as_item_ids <- function(x, field = "item_ids") {
  if (is.list(x)) {
    ok <- all(vapply(x, function(v) is.character(v) && length(v) == 1L, logical(1)))
    if (!ok) stop(validation_error(paste0(field, " must be an array of strings")))
    x <- unlist(x)
  }
  if (!is.character(x) || length(x) == 0L) {
    stop(validation_error(paste0(field, " must be a non-empty array of strings")))
  }
  if (any(is.na(x)) || any(!nzchar(x))) {
    stop(validation_error(paste0(field, " contains null or empty strings")))
  }
  dup <- unique(x[duplicated(x)])
  if (length(dup) > 0L) {
    stop(validation_error(paste0(field, " contains duplicates: ", paste(dup, collapse = ", "))))
  }
  x
}

.is_whole <- function(x) {
  all(abs(x - round(x)) < sqrt(.Machine$double.eps))
}

# Normalize factors to list(list(name = chr, items = chr), ...).
.normalize_factors <- function(factors) {
  if (is.data.frame(factors)) {
    if (!all(c("name", "items") %in% names(factors))) {
      stop(validation_error("model_specification.factors entries must have 'name' and 'items'"))
    }
    items_col <- factors$items
    if (is.matrix(items_col)) {
      items_col <- lapply(seq_len(nrow(items_col)), function(i) items_col[i, ])
    }
    factors <- lapply(seq_len(nrow(factors)), function(i) {
      list(name = factors$name[[i]], items = items_col[[i]])
    })
  } else if (is.list(factors) && !is.null(names(factors)) &&
             all(c("name", "items") %in% names(factors))) {
    # single factor object sent instead of an array of one
    factors <- list(factors)
  }
  if (!is.list(factors) || length(factors) == 0L) {
    stop(validation_error("model_specification.factors must be a non-empty array"))
  }

  lapply(seq_along(factors), function(i) {
    f <- factors[[i]]
    if (!is.list(f) || is.null(f$name) || is.null(f$items)) {
      stop(validation_error(sprintf(
        "model_specification.factors[%d] must have 'name' and 'items'", i - 1L
      )))
    }
    name <- f$name
    if (!is.character(name) || length(name) != 1L || is.na(name) || !nzchar(name)) {
      stop(validation_error(sprintf(
        "model_specification.factors[%d].name must be a non-empty string", i - 1L
      )))
    }
    items <- f$items
    if (is.list(items)) items <- unlist(items)
    if (!is.character(items) || length(items) == 0L || any(is.na(items)) ||
        any(!nzchar(items))) {
      stop(validation_error(sprintf(
        "model_specification.factors[%d].items must be a non-empty array of strings", i - 1L
      )))
    }
    list(name = name, items = items)
  })
}

# ---- /ega -------------------------------------------------------------------

validate_ega_request <- function(body) {
  .require_fields(body, c("embeddings", "item_ids", "intended_dimensions", "config"))

  emb <- .as_row_matrix(body$embeddings, "embeddings")
  .check_numeric_matrix(emb, "embeddings")
  if (nrow(emb) < 2L) {
    stop(validation_error(sprintf(
      "embeddings must have at least 2 rows (got %d)", nrow(emb)
    )))
  }
  storage.mode(emb) <- "double"
  dimnames(emb) <- NULL

  item_ids <- .as_item_ids(body$item_ids)
  if (length(item_ids) != nrow(emb)) {
    stop(validation_error(sprintf(
      "item_ids length (%d) does not match embeddings rows (%d)",
      length(item_ids), nrow(emb)
    )))
  }

  dims <- body$intended_dimensions
  if (is.list(dims)) {
    dims <- unlist(lapply(dims, function(v) if (is.null(v)) NA else v))
  }
  if (!is.numeric(dims) || any(is.na(dims)) || !.is_whole(dims)) {
    stop(validation_error("intended_dimensions must be an array of integers"))
  }
  if (length(dims) != nrow(emb)) {
    stop(validation_error(sprintf(
      "intended_dimensions length (%d) does not match embeddings rows (%d)",
      length(dims), nrow(emb)
    )))
  }

  if (!is.list(body$config) || is.data.frame(body$config)) {
    stop(validation_error("config must be a JSON object"))
  }

  body$embeddings <- emb
  body$item_ids <- item_ids
  body$intended_dimensions <- as.integer(round(dims))
  body
}

# ---- /cfa -------------------------------------------------------------------

validate_cfa_request <- function(body) {
  .require_fields(body, c("responses", "item_ids", "model_specification", "ordinal"))

  resp <- .as_row_matrix(body$responses, "responses")
  .check_numeric_matrix(resp, "responses")
  if (!.is_whole(resp)) {
    stop(validation_error("responses must contain only integer values"))
  }
  if (nrow(resp) < 2L) {
    stop(validation_error(sprintf(
      "responses must have at least 2 rows (got %d)", nrow(resp)
    )))
  }
  resp <- round(resp)
  storage.mode(resp) <- "integer"
  dimnames(resp) <- NULL

  item_ids <- .as_item_ids(body$item_ids)
  if (length(item_ids) != ncol(resp)) {
    stop(validation_error(sprintf(
      "item_ids length (%d) does not match responses columns (%d)",
      length(item_ids), ncol(resp)
    )))
  }

  ms <- body$model_specification
  if (!is.list(ms) || is.data.frame(ms) || is.null(ms$factors)) {
    stop(validation_error("model_specification.factors is missing"))
  }
  factors <- .normalize_factors(ms$factors)

  factor_names <- vapply(factors, `[[`, character(1), "name")
  dup_names <- unique(factor_names[duplicated(factor_names)])
  if (length(dup_names) > 0L) {
    stop(validation_error(paste0(
      "model_specification.factors has duplicate names: ", paste(dup_names, collapse = ", ")
    )))
  }

  model_items <- unique(unlist(lapply(factors, `[[`, "items")))
  unknown <- setdiff(model_items, item_ids)
  if (length(unknown) > 0L) {
    stop(validation_error(paste0(
      "Items in model_specification not found in item_ids: ",
      paste(unknown, collapse = ", ")
    )))
  }

  ordinal <- body$ordinal
  if (!is.logical(ordinal) || length(ordinal) != 1L || is.na(ordinal)) {
    stop(validation_error("ordinal must be true or false"))
  }

  body$responses <- resp
  body$item_ids <- item_ids
  body$model_specification <- list(factors = factors)
  body$ordinal <- ordinal
  body
}
