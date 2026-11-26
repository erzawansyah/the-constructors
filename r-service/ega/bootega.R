# ega/bootega.R
#
# bootEGA stability loop for the /ega endpoint (design.md, /ega flow step 7;
# Requirements 3.7, 3.8, 3.9, 3.10, 3.17, 3.19, 10.4).
# Requires utils/conditions.R (validation_error) to be sourced first.
#
# Public API:
#
#   run_bootega_loop(data, config)
#     data:   numeric matrix, observations (embedding dimensions) in rows and
#             items in columns, colnames = item IDs (the UVA-retained data).
#     config: the validated request config (validate_config() already ran).
#
#     Each pass calls EGAnet::bootEGA with
#       model     = config$network_method
#       algorithm = config$community_algorithm
#       iter      = config$boot_iterations
#       type      = config$bootstrap_type
#       seed      = as.numeric(config$random_seed)   # bootEGA rejects integer
#                                                     # seeds; fromJSON gives int
#     plus the fixed arguments ncores = 1, plot.itemStability = FALSE,
#     verbose = FALSE. Per-item stability is read from
#       EGAnet::itemStability(boot, IS.plot = FALSE)$item.stability$empirical.dimensions
#     (PROBE_NOTES.md 3.5). Only that named numeric vector is kept; the
#     bootEGA object and the itemStability `plot` element (a ggplot) are
#     discarded inside the pass and never returned, logged or serialized.
#
#     Every item with stability < config$stability_threshold is removed and its
#     stability in that pass is recorded. Passes repeat on the retained items
#     until a pass removes nothing. Each pass that continues removes at least
#     one item, so the loop ends after at most ncol(data) passes.
#
#     Returns a list:
#       removed_items            character vector, in removal order
#       removed_stability_scores named list: item ID -> stability in the pass
#                                that removed it (empty named list if none)
#       retained_data            matrix of the retained items (colnames intact)
#       stability_per_item       named list: item ID -> stability from the last
#                                pass (the pass in which every item was stable)
#
# Named lists (not named vectors) are returned so both score maps serialize as
# JSON objects, including the empty case ({}), with the service serializer.
#
# Errors:
#   - Bad input shape or a non-numeric / non-scalar config value used here:
#     validation_error (HTTP 400).
#   - No items in the input (UVA retained 0), bootEGA / itemStability failing,
#     unusable stability output (missing items, NA values), or every remaining
#     item falling below the threshold:
#     plain stop() (HTTP 500), with the pass number and item count in the
#     message. No minimum item count is assumed: the probe showed bootEGA fails
#     on 1 item and on 2 unrelated items but can run on 3, depending on the
#     data, so the failure is reported from bootEGA itself.
#
# No threshold or default lives in this file. All values come from `config`.

.bootega_require_numeric_scalar <- function(config, field) {
  value <- config[[field]]
  if (!is.numeric(value) || length(value) != 1L || !is.finite(value)) {
    stop(validation_error(paste0(
      "config.", field, " must be a single finite number for bootEGA"
    )))
  }
  invisible(value)
}

.bootega_require_string_scalar <- function(config, field) {
  value <- config[[field]]
  if (!is.character(value) || length(value) != 1L || !nzchar(value)) {
    stop(validation_error(paste0(
      "config.", field, " must be a single non-empty string for bootEGA"
    )))
  }
  invisible(value)
}

.bootega_check_inputs <- function(data, config) {
  if (!is.matrix(data) || !is.numeric(data)) {
    stop(validation_error("bootEGA input must be a numeric matrix (observations x items)"))
  }
  if (ncol(data) == 0L) {
    stop(
      "bootEGA has no items to analyze: UVA retained 0 items. Review the item pool and config.wto_threshold.",
      call. = FALSE
    )
  }
  ids <- colnames(data)
  if (is.null(ids) || anyNA(ids) || any(!nzchar(ids))) {
    stop(validation_error("bootEGA input must have item IDs as column names"))
  }
  if (anyDuplicated(ids) > 0L) {
    stop(validation_error(paste0(
      "bootEGA input has duplicate item IDs: ",
      paste(unique(ids[duplicated(ids)]), collapse = ", ")
    )))
  }

  .bootega_require_numeric_scalar(config, "stability_threshold")
  .bootega_require_numeric_scalar(config, "boot_iterations")
  .bootega_require_numeric_scalar(config, "random_seed")
  if (config$boot_iterations < 1 || config$boot_iterations != round(config$boot_iterations)) {
    stop(validation_error("config.boot_iterations must be a positive whole number"))
  }
  .bootega_require_string_scalar(config, "network_method")
  .bootega_require_string_scalar(config, "community_algorithm")
  .bootega_require_string_scalar(config, "bootstrap_type")
  invisible(TRUE)
}

# One bootEGA pass. Returns only the per-item stability vector, ordered as
# colnames(data). The bootEGA and itemStability objects stay local.
.bootega_pass_stability <- function(data, config, pass) {
  ids <- colnames(data)

  stability <- tryCatch({
    boot <- EGAnet::bootEGA(
      data = data,
      model = config$network_method,
      algorithm = config$community_algorithm,
      iter = config$boot_iterations,
      type = config$bootstrap_type,
      seed = as.numeric(config$random_seed),
      ncores = 1,
      plot.itemStability = FALSE,
      verbose = FALSE
    )
    EGAnet::itemStability(boot, IS.plot = FALSE)$item.stability$empirical.dimensions
  }, error = function(e) {
    stop(sprintf(
      "bootEGA pass %d failed on %d item(s): %s. Too few or unconnected items can make bootEGA fail; review the items retained by UVA.",
      pass, length(ids), conditionMessage(e)
    ), call. = FALSE)
  })

  if (!is.numeric(stability) || is.null(names(stability))) {
    stop(sprintf(
      "bootEGA pass %d: itemStability did not return a named numeric vector at $item.stability$empirical.dimensions; rerun r-service/probe.R and check PROBE_NOTES.md 3.5",
      pass
    ), call. = FALSE)
  }

  missing_ids <- setdiff(ids, names(stability))
  if (length(missing_ids) > 0L) {
    stop(sprintf(
      "bootEGA pass %d: itemStability returned no stability for item(s): %s",
      pass, paste(missing_ids, collapse = ", ")
    ), call. = FALSE)
  }

  stability <- stats::setNames(as.numeric(stability[ids]), ids)

  na_ids <- ids[is.na(stability)]
  if (length(na_ids) > 0L) {
    # NA stability cannot be compared with the threshold. Removing or keeping
    # such items would be an undocumented decision, so fail explicitly.
    stop(sprintf(
      "bootEGA pass %d: stability is NA for item(s): %s (no community assignment in the empirical structure). Handling of NA stability is not defined; owner decision required.",
      pass, paste(na_ids, collapse = ", ")
    ), call. = FALSE)
  }

  stability
}

run_bootega_loop <- function(data, config) {
  .bootega_check_inputs(data, config)
  threshold <- config$stability_threshold

  removed_items <- character(0)
  removed_scores <- stats::setNames(list(), character(0))
  current <- data
  pass <- 0L

  repeat {
    pass <- pass + 1L
    stability <- .bootega_pass_stability(current, config, pass)

    unstable <- names(stability)[stability < threshold]
    if (length(unstable) == 0L) break

    if (length(unstable) == ncol(current)) {
      stop(sprintf(
        "bootEGA pass %d: all %d remaining item(s) have stability < %s; no items would be retained. Review the item pool or config.stability_threshold.",
        pass, ncol(current), format(threshold, digits = 15)
      ), call. = FALSE)
    }

    removed_items <- c(removed_items, unstable)
    removed_scores[unstable] <- as.list(unname(stability[unstable]))
    current <- current[, setdiff(colnames(current), unstable), drop = FALSE]
  }

  list(
    removed_items = removed_items,
    removed_stability_scores = removed_scores,
    retained_data = current,
    stability_per_item = as.list(stability)
  )
}
