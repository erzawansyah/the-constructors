# ega/uva.R
#
# Repeated Unique Variable Analysis (UVA) for the /ega pipeline
# (design.md "/ega flow" step 6; Requirements 3.4, 3.5, 3.6, 3.14, 3.15, 3.16,
# 10.3). Argument names and result paths follow r-service/PROBE_NOTES.md 3.1
# and 4.3 to 4.5.
#
# Public API:
#
#   run_uva_loop(data, config)
#     `data`: numeric matrix, observations (embedding dimensions) in rows,
#     items in columns, colnames = item IDs (the transposed embeddings).
#     `config`: the validated /ega config. Only config$wto_threshold and
#     config$uva_method are read; validate_config() has already rejected null
#     values and any uva_method other than "mbr" (case-insensitive), so "ejp"
#     (which hangs on an interactive prompt) never reaches EGAnet::UVA.
#     Returns list(
#       removed_items      = character vector, in removal order,
#       removed_wto_scores = named list keyed by removed item ID, each entry
#                            list(redundant_with = <item ID>, wto = <number>);
#                            NA_character_ / NA_real_ (JSON null with
#                            na = "null") when no partner pair has a wTO row,
#       retained_data      = matrix of the retained items, colnames intact
#     )
#
# Each pass calls EGAnet::UVA with the fixed arguments reduce = TRUE,
# reduce.method = "remove", auto = TRUE (auto = FALSE prompts interactively),
# verbose = FALSE. Removed items are setdiff(colnames(input), colnames(
# result$reduced_data)); result$keep_remove is never read (PROBE_NOTES 4.5).
# result$reduced_data is NULL when nothing is redundant; that ends the loop
# with all of the pass's input retained. The loop also ends when a pass
# removes nothing.
#
# removed_wto_scores (EGAnet has no per-item wTO, PROBE_NOTES 4.4): for a
# removed item r, its partners are result$redundant[[r]] plus the names of
# $redundant entries whose vector contains r. Their wTO values come from the
# same pass's result$wto$pairwise (node_i, node_j, wto), matched in either
# order. Partners without a row are skipped. The highest-wTO partner is
# reported. If no partner has a row, both fields are NA and a warning is
# raised with warning().
#
# Errors here are internal computation errors (HTTP 500), so they use plain
# stop(), not validation_error().

# Partners of removed item `r` according to one pass's $redundant list.
.uva_partners <- function(r, redundant) {
  if (is.null(redundant) || length(redundant) == 0L) {
    return(character(0))
  }
  own <- if (!is.null(redundant[[r]])) as.character(redundant[[r]]) else character(0)
  targets <- names(redundant)[vapply(
    redundant,
    function(v) r %in% as.character(v),
    logical(1)
  )]
  setdiff(unique(c(own, targets)), r)
}

# Highest-wTO partner of `r` from one pass's $wto$pairwise data frame.
.uva_wto_entry <- function(r, partners, pairwise) {
  best_partner <- NA_character_
  best_wto <- NA_real_
  if (length(partners) > 0L && !is.null(pairwise) && nrow(pairwise) > 0L) {
    node_i <- as.character(pairwise$node_i)
    node_j <- as.character(pairwise$node_j)
    wto <- as.numeric(pairwise$wto)
    for (p in partners) {
      rows <- which((node_i == r & node_j == p) | (node_i == p & node_j == r))
      if (length(rows) == 0L) next
      value <- max(wto[rows], na.rm = TRUE)
      if (!is.finite(value)) next
      if (is.na(best_wto) || value > best_wto) {
        best_partner <- p
        best_wto <- value
      }
    }
  }
  if (is.na(best_partner)) {
    warning(sprintf(
      "run_uva_loop: no wto$pairwise row for removed item %s and its redundant partners (%s); redundant_with and wto are null",
      r, if (length(partners) > 0L) paste(partners, collapse = ", ") else "none"
    ), call. = FALSE)
  }
  list(redundant_with = best_partner, wto = best_wto)
}

run_uva_loop <- function(data, config) {
  data <- as.matrix(data)
  if (is.null(colnames(data))) {
    stop("run_uva_loop: data must have item IDs as column names", call. = FALSE)
  }

  removed_items <- character(0)
  removed_wto_scores <- list()
  current <- data

  repeat {
    result <- EGAnet::UVA(
      data = current,
      cut.off = config$wto_threshold,
      uva.method = config$uva_method,
      reduce = TRUE,
      reduce.method = "remove",
      auto = TRUE,
      verbose = FALSE
    )

    # Nothing redundant: reduced_data is NULL (PROBE_NOTES 3.1, 4.3).
    if (is.null(result$reduced_data)) break

    reduced <- as.matrix(result$reduced_data)
    removed_this_pass <- setdiff(colnames(current), colnames(reduced))
    if (length(removed_this_pass) == 0L) break

    for (r in removed_this_pass) {
      partners <- .uva_partners(r, result$redundant)
      removed_wto_scores[[r]] <- .uva_wto_entry(r, partners, result$wto$pairwise)
    }
    removed_items <- c(removed_items, removed_this_pass)
    current <- reduced
  }

  list(
    removed_items = removed_items,
    removed_wto_scores = removed_wto_scores,
    retained_data = current
  )
}
