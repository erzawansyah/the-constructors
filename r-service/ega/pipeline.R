# ega/pipeline.R
#
# /ega orchestration (design.md "/ega flow" steps 2 to 10 and Data Models;
# Requirements 3.1, 3.3, 3.6, 3.9, 3.11, 3.12, 3.13, 3.14, 3.17, 3.18, 3.20,
# 12.1, 12.8).
#
# Requires, sourced first: utils/conditions.R, config/loader.R,
# validation/request_validator.R, ega/nmi.R, ega/uva.R, ega/bootega.R.
#
# Public API:
#
#   run_ega(data, config)
#     The ONLY caller of EGAnet::EGA in the service. Calls
#     set.seed(as.numeric(config$random_seed)) immediately before
#     EGAnet::EGA(data, model = config$network_method,
#                 algorithm = config$community_algorithm,
#                 plot.EGA = FALSE, verbose = FALSE),
#     because EGA has no seed argument (PROBE_NOTES.md 3.3). Returns the EGA
#     object; callers use only $wc (named double, class EGA.community).
#
#   execute_ega_pipeline(body)
#     body: parsed /ega request (parse_json_body() output).
#     validate_ega_request -> validate_config -> t(embeddings) with
#     colnames = item_ids -> run_ega + nmi.initial -> run_uva_loop ->
#     run_bootega_loop -> run_ega on retained data + nmi.final.
#     Returns the success response list (design.md Data Models):
#       status, uva{removed_items, removed_wto_scores, reason},
#       bootega{removed_items, removed_stability_scores, reason,
#               stability_per_item}, retained_items, nmi{initial, final}.
#     The route handler (api.R) logs it with log_ega_execution().
#
# JSON shape with the service serializer (auto_unbox = TRUE, na = "null",
# digits = NA):
#   - ID arrays are unnamed lists, so [] when empty and ["x"] (not "x") with
#     one element.
#   - Score maps are named lists, so {} when empty.
#   - NA becomes null.
#
# Reproducibility: EGA is seeded by run_ega(), bootEGA by its seed argument
# (bootega.R), and UVA is deterministic, so identical requests give identical
# uva, bootega, retained_items and nmi values.
#
# No threshold or default lives in this file. All values come from `config`.

# ---- internal helpers -------------------------------------------------------

.ega_require_numeric_scalar <- function(config, field) {
  value <- config[[field]]
  if (!is.numeric(value) || length(value) != 1L || !is.finite(value)) {
    stop(validation_error(paste0("config.", field, " must be a single finite number")))
  }
  invisible(value)
}

.ega_require_string_scalar <- function(config, field) {
  value <- config[[field]]
  if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value)) {
    stop(validation_error(paste0("config.", field, " must be a single non-empty string")))
  }
  invisible(value)
}

# Number as text for the reason strings, without the lossy 7-digit default
# and without scientific notation (0.25 -> "0.25", 500L -> "500").
.ega_format_number <- function(x) {
  format(x, digits = 15, scientific = FALSE, trim = TRUE)
}

# Community vector of an EGA result aligned to `ids` by item name.
.ega_membership <- function(ega, ids) {
  wc <- ega$wc
  if (is.null(wc)) {
    stop("run_ega: EGA result has no $wc membership; rerun r-service/probe.R and check PROBE_NOTES.md 3.3",
         call. = FALSE)
  }
  if (is.null(names(wc))) {
    if (length(wc) != length(ids)) {
      stop(sprintf("run_ega: $wc has %d entries for %d items", length(wc), length(ids)),
           call. = FALSE)
    }
    names(wc) <- ids
  }
  missing_ids <- setdiff(ids, names(wc))
  if (length(missing_ids) > 0L) {
    stop(paste0("run_ega: $wc has no membership for item(s): ",
                paste(missing_ids, collapse = ", ")), call. = FALSE)
  }
  wc[ids]
}

# Named list that serializes as a JSON object, {} when empty.
.ega_as_object <- function(x) {
  if (length(x) == 0L) return(stats::setNames(list(), character(0)))
  as.list(x)
}

# ---- public -----------------------------------------------------------------

run_ega <- function(data, config) {
  set.seed(as.numeric(config$random_seed))
  EGAnet::EGA(
    data = data,
    model = config$network_method,
    algorithm = config$community_algorithm,
    plot.EGA = FALSE,
    verbose = FALSE
  )
}

execute_ega_pipeline <- function(body) {
  body <- validate_ega_request(body)
  config <- body$config
  validate_config(config, EGA_REQUIRED_CONFIG_FIELDS)

  # Values used before bootega.R runs its own checks.
  .ega_require_numeric_scalar(config, "wto_threshold")
  .ega_require_numeric_scalar(config, "random_seed")
  .ega_require_numeric_scalar(config, "stability_threshold")
  .ega_require_numeric_scalar(config, "boot_iterations")
  .ega_require_string_scalar(config, "network_method")
  .ega_require_string_scalar(config, "community_algorithm")

  item_ids <- body$item_ids
  # Request dimensions are 0-indexed; NMI comparison uses 1-indexed labels.
  intended <- stats::setNames(body$intended_dimensions + 1L, item_ids)

  # AI-GENIE: embedding dimensions become observations, items become variables.
  data <- t(body$embeddings)
  colnames(data) <- item_ids

  ega_initial <- run_ega(data, config)
  nmi_initial <- compute_nmi(.ega_membership(ega_initial, item_ids), unname(intended[item_ids]))

  uva <- run_uva_loop(data, config)
  boot <- run_bootega_loop(uva$retained_data, config)

  retained_data <- boot$retained_data
  retained_ids <- colnames(retained_data)

  ega_final <- run_ega(retained_data, config)
  nmi_final <- compute_nmi(.ega_membership(ega_final, retained_ids), unname(intended[retained_ids]))

  list(
    status = "success",
    uva = list(
      removed_items = as.list(as.character(uva$removed_items)),
      removed_wto_scores = .ega_as_object(uva$removed_wto_scores),
      reason = paste0("weighted topological overlap >= ",
                      .ega_format_number(config$wto_threshold))
    ),
    bootega = list(
      removed_items = as.list(as.character(boot$removed_items)),
      removed_stability_scores = .ega_as_object(boot$removed_stability_scores),
      reason = paste0("stability < ", .ega_format_number(config$stability_threshold),
                      " over ", .ega_format_number(config$boot_iterations), " iterations"),
      stability_per_item = .ega_as_object(boot$stability_per_item)
    ),
    retained_items = as.list(as.character(retained_ids)),
    nmi = list(initial = unname(nmi_initial), final = unname(nmi_final))
  )
}
