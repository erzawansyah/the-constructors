# cfa/extractor.R
#
# Extraction of fit indices, standardized loadings and factor correlations
# from a lavaan CFA fit (design.md "/cfa flow" steps 6 to 8; Requirements 4.5,
# 4.6, 4.7, 4.10 to 4.15). Field names follow r-service/PROBE_NOTES.md 3.6.
#
# Public API:
#
#   extract_fit_indices(fit, ordinal)
#     Returns list(fit_variant = "scaled_robust" | "standard",
#                  fit_indices = named list with the fixed response keys).
#     NA values stay NA (serialized as JSON null with na = "null").
#     No fit cut-off is applied: these are technical-rehearsal (smoke test)
#     output, not a validation verdict.
#
#   extract_loadings(fit, model_specification)
#     Returns loadings[[factor]][[item]] = est.std (standardizedSolution()).
#
#   extract_factor_correlations(fit, model_specification)
#     Returns a named list keyed "<lhs>_<rhs>"; a named empty list (JSON {})
#     for single-factor models.
#
# `model_specification` comes from jsonlite::fromJSON(), so `factors` can be
# a data.frame (simplifyVector = TRUE) or a list of lists. Both are handled.

# Response key -> lavaan fitMeasures() name, per variant (design.md step 6).
# For WLSMV the unsuffixed names are the unscaled statistics and `pvalue` is
# NA (PROBE_NOTES 3.6), hence the scaled / robust names for ordinal fits.
.CFA_FIT_NAMES <- list(
  scaled_robust = c(
    chisq          = "chisq.scaled",
    df             = "df.scaled",
    pvalue         = "pvalue.scaled",
    cfi            = "cfi.robust",
    tli            = "tli.robust",
    rmsea          = "rmsea.robust",
    rmsea_ci_lower = "rmsea.ci.lower.robust",
    rmsea_ci_upper = "rmsea.ci.upper.robust",
    srmr           = "srmr"
  ),
  standard = c(
    chisq          = "chisq",
    df             = "df",
    pvalue         = "pvalue",
    cfi            = "cfi",
    tli            = "tli",
    rmsea          = "rmsea",
    rmsea_ci_lower = "rmsea.ci.lower",
    rmsea_ci_upper = "rmsea.ci.upper",
    srmr           = "srmr"
  )
)

# A named empty list serializes as {} (an unnamed list() would give []).
.empty_object <- function() {
  stats::setNames(list(), character(0))
}

# Factor names from model_specification$factors, in specification order.
.cfa_factor_names <- function(model_specification) {
  factors <- model_specification$factors
  if (is.data.frame(factors)) {
    return(as.character(factors$name))
  }
  vapply(factors, function(f) as.character(f$name)[1], character(1))
}

extract_fit_indices <- function(fit, ordinal) {
  fit_variant <- if (isTRUE(ordinal)) "scaled_robust" else "standard"
  lavaan_names <- .CFA_FIT_NAMES[[fit_variant]]

  measures <- lavaan::fitMeasures(fit, unname(lavaan_names))
  measure_names <- names(measures)
  measures <- unname(as.numeric(measures))

  fit_indices <- lapply(unname(lavaan_names), function(lavaan_name) {
    idx <- match(lavaan_name, measure_names)
    if (is.na(idx)) NA_real_ else measures[[idx]]
  })
  names(fit_indices) <- names(lavaan_names)

  list(fit_variant = fit_variant, fit_indices = fit_indices)
}

extract_loadings <- function(fit, model_specification) {
  factor_names <- .cfa_factor_names(model_specification)
  solution <- lavaan::standardizedSolution(fit)
  rows <- solution[solution$op == "=~", , drop = FALSE]

  loadings <- lapply(factor_names, function(factor_name) {
    factor_rows <- rows[rows$lhs == factor_name, , drop = FALSE]
    if (nrow(factor_rows) == 0L) {
      return(.empty_object())
    }
    values <- as.list(unname(as.numeric(factor_rows$est.std)))
    names(values) <- as.character(factor_rows$rhs)
    values
  })
  names(loadings) <- factor_names
  loadings
}

extract_factor_correlations <- function(fit, model_specification) {
  factor_names <- .cfa_factor_names(model_specification)
  solution <- lavaan::standardizedSolution(fit)

  # Filtering on op also excludes the "|", "~*~" and "~1" rows of ordinal fits.
  keep <- solution$op == "~~" &
    solution$lhs != solution$rhs &
    solution$lhs %in% factor_names &
    solution$rhs %in% factor_names
  rows <- solution[keep, , drop = FALSE]

  if (nrow(rows) == 0L) {
    return(.empty_object())
  }

  correlations <- as.list(unname(as.numeric(rows$est.std)))
  names(correlations) <- paste0(rows$lhs, "_", rows$rhs)
  correlations
}
