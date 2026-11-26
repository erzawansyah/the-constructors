# cfa/estimator.R
#
# lavaan CFA fit for the /cfa pipeline (design.md "/cfa flow" step 5;
# Requirements 4.2, 4.3, 4.8, 10.2). Behavior follows
# r-service/PROBE_NOTES.md 3.6 and 4.3.
#
# Public API:
#
#   run_cfa(model_syntax, response_df, item_ids, ordinal)
#     `model_syntax`: character lavaan syntax from build_lavaan_model().
#     `response_df`: data frame of responses, columns named by item IDs.
#     `item_ids`: character vector of item IDs (used as `ordered =`).
#     `ordinal`: TRUE -> estimator "WLSMV" with ordered = item_ids;
#                FALSE -> estimator "ML". std.lv = TRUE in both cases.
#     Returns list(
#       fit       = lavaan fit object,
#       converged = TRUE / FALSE from lavaan::lavInspect(fit, "converged"),
#       warnings  = list of character messages captured during the fit
#                   (a list, so a single warning still serializes as a JSON
#                   array with auto_unbox = TRUE; empty list -> []),
#       estimator = "WLSMV" or "ML"
#     )
#
# The estimator is always passed explicitly, never left to lavaan's default
# for ordered data. The returned `estimator` is this wrapper's own choice:
# lavInspect(fit, "options")$estimator reports "DWLS" for a WLSMV fit
# (PROBE_NOTES 3.6), so it is not used for logging (Requirement 10.2).
#
# Warnings are muffled so they do not reach the R console; they are returned
# for the response (`warnings` / `lavaan_warnings`). Non-convergence is not an
# error here: the pipeline turns converged = FALSE into the HTTP 200
# "warning" response (Requirement 4.8). Errors raised by lavaan propagate as
# computation errors (HTTP 500), so they use plain stop(), not
# validation_error().

run_cfa <- function(model_syntax, response_df, item_ids, ordinal) {
  if (!is.logical(ordinal) || length(ordinal) != 1L || is.na(ordinal)) {
    stop("run_cfa: ordinal must be a single TRUE or FALSE", call. = FALSE)
  }
  item_ids <- as.character(item_ids)
  response_df <- as.data.frame(response_df)

  estimator <- if (ordinal) "WLSMV" else "ML"
  captured <- list()

  fit <- withCallingHandlers(
    {
      if (ordinal) {
        lavaan::cfa(
          model = model_syntax,
          data = response_df,
          ordered = item_ids,
          estimator = "WLSMV",
          std.lv = TRUE
        )
      } else {
        lavaan::cfa(
          model = model_syntax,
          data = response_df,
          estimator = "ML",
          std.lv = TRUE
        )
      }
    },
    warning = function(w) {
      captured[[length(captured) + 1L]] <<- conditionMessage(w)
      invokeRestart("muffleWarning")
    }
  )

  converged <- isTRUE(lavaan::lavInspect(fit, "converged"))

  list(
    fit = fit,
    converged = converged,
    warnings = captured,
    estimator = estimator
  )
}
