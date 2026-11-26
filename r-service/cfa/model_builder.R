# cfa/model_builder.R
#
# Builds lavaan model syntax from a CFA request's model_specification.
# Self-contained: no dependency on other r-service files, so it can be sourced
# on its own by tests (including the property test for Requirement 4.4).
#
# Input: `model_specification` is either the normalized form returned by
# validate_cfa_request():
#   list(factors = list(list(name = <chr>, items = <chr vector>), ...))
# or the raw jsonlite-parsed form, where `factors` is a data.frame with a
# character column `name` and a list column `items` (simplifyVector = TRUE).
# Both forms are accepted.
#
# Public API:
#
#   build_lavaan_model(model_specification)
#     Returns a single character string with one line per factor, in input
#     order, joined by "\n":
#       <name> =~ <item_1> + <item_2> + ...
#     Signals a plain error if `factors` is missing, empty, or an entry lacks
#     a non-empty `name` or `items`. Request validation (validation_error /
#     HTTP 400) happens earlier in validate_cfa_request().

# Convert `factors` to list(list(name = chr, items = chr), ...).
.factors_as_list <- function(factors) {
  if (is.data.frame(factors)) {
    items_col <- factors$items
    if (is.matrix(items_col)) {
      # equal-length item arrays may be simplified to a matrix
      items_col <- lapply(seq_len(nrow(items_col)), function(i) items_col[i, ])
    }
    return(lapply(seq_len(nrow(factors)), function(i) {
      list(name = factors$name[[i]], items = items_col[[i]])
    }))
  }
  if (is.list(factors) && !is.null(names(factors)) &&
      all(c("name", "items") %in% names(factors))) {
    # single factor object instead of an array of one
    return(list(factors))
  }
  factors
}

build_lavaan_model <- function(model_specification) {
  factors <- model_specification$factors
  if (is.null(factors)) {
    stop("model_specification.factors is missing")
  }
  factors <- .factors_as_list(factors)
  if (!is.list(factors) || length(factors) == 0L) {
    stop("model_specification.factors must be a non-empty list")
  }

  lines <- vapply(seq_along(factors), function(i) {
    f <- factors[[i]]
    name <- f$name
    items <- f$items
    if (is.list(items)) items <- unlist(items)
    if (!is.character(name) || length(name) != 1L || is.na(name) || !nzchar(name)) {
      stop(sprintf("model_specification.factors[%d].name must be a non-empty string", i - 1L))
    }
    if (!is.character(items) || length(items) == 0L || any(is.na(items)) ||
        any(!nzchar(items))) {
      stop(sprintf("model_specification.factors[%d].items must be a non-empty array of strings", i - 1L))
    }
    paste0(name, " =~ ", paste(items, collapse = " + "))
  }, character(1))

  paste(lines, collapse = "\n")
}
