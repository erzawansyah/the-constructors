# cfa/pipeline.R
#
# /cfa orchestration (design.md "/cfa flow" steps 2 to 10 and Data Models;
# Requirements 4.1, 4.8, 4.9, 4.13, 12.1, 12.7).
#
# Requires, sourced first: utils/conditions.R, validation/request_validator.R,
# cfa/model_builder.R, cfa/estimator.R, cfa/extractor.R.
#
# Public API:
#
#   execute_cfa_pipeline(body)
#     body: parsed /cfa request (parse_json_body() output).
#     validate_cfa_request -> build_lavaan_model -> data frame with
#     colnames = item_ids -> run_cfa -> extraction.
#     Returns the response list only (same pattern as execute_ega_pipeline):
#       converged:     status = "success", fit_variant, fit_indices, loadings,
#                      factor_correlations, warnings
#       not converged: status = "warning", message = "Model did not converge",
#                      partial_fit_indices ({} if extraction fails),
#                      lavaan_warnings
#     The route handler (api.R) logs it with log_cfa_execution(body, result,
#     ...). That function derives estimator ("WLSMV" / "ML") from
#     body$ordinal and persona_count / item_count / factor_count from the
#     request body, so no non-contract metadata is added to the response.
#
# JSON shape with the service serializer (auto_unbox = TRUE, na = "null",
# digits = NA):
#   - warnings / lavaan_warnings are unnamed lists: [] when empty, ["x"] with
#     one element.
#   - factor_correlations and an unavailable partial_fit_indices are named
#     empty lists: {}.
#   - NA fit values become null.
#
# Validation failures signal validation_error (HTTP 400). lavaan errors
# propagate as plain errors (HTTP 500). Non-convergence is not an error
# (Requirement 4.8). No fit cut-off is applied: the indices are
# technical-rehearsal (smoke test) output, not a validation verdict.

# Named empty list that serializes as {}.
.cfa_empty_object <- function() {
  stats::setNames(list(), character(0))
}

# Character messages as an unnamed list, so JSON is always an array.
.cfa_as_array <- function(x) {
  if (length(x) == 0L) return(list())
  as.list(unname(as.character(unlist(x))))
}

execute_cfa_pipeline <- function(body) {
  body <- validate_cfa_request(body)
  item_ids <- body$item_ids
  ordinal <- body$ordinal
  model_specification <- body$model_specification

  model_syntax <- build_lavaan_model(model_specification)

  response_df <- as.data.frame(body$responses)
  colnames(response_df) <- item_ids

  cfa <- run_cfa(model_syntax, response_df, item_ids, ordinal)
  fit <- cfa$fit

  if (!isTRUE(cfa$converged)) {
    partial <- tryCatch(
      {
        fi <- suppressWarnings(extract_fit_indices(fit, ordinal))$fit_indices
        if (length(fi) == 0L) .cfa_empty_object() else fi
      },
      error = function(e) .cfa_empty_object()
    )
    return(list(
      status = "warning",
      message = "Model did not converge",
      partial_fit_indices = partial,
      lavaan_warnings = .cfa_as_array(cfa$warnings)
    ))
  }

  fit_result <- extract_fit_indices(fit, ordinal)

  list(
    status = "success",
    fit_variant = fit_result$fit_variant,
    fit_indices = fit_result$fit_indices,
    loadings = extract_loadings(fit, model_specification),
    factor_correlations = extract_factor_correlations(fit, model_specification),
    warnings = .cfa_as_array(cfa$warnings)
  )
}
