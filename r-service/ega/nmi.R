# ega/nmi.R
#
# Normalized Mutual Information (NMI) between a detected community structure
# and the intended dimension assignment, used for nmi.initial and nmi.final
# in the /ega response (Requirements 3.11, 3.12).
#
# Public API:
#
#   compute_nmi(detected, intended)
#     `detected` is typically ega$wc (named double, class EGA.community; see
#     PROBE_NOTES.md section 3a), passed to igraph::compare() as is.
#     `intended` is the 1-indexed intended dimension vector, aligned
#     position by position with `detected`.
#     - Unequal lengths: error.
#     - Positions where either vector is NA are dropped (EGA can leave an
#       item unassigned, giving NA in wc) and a warning reports the count.
#     - Nothing left after dropping: error.
#     Returns igraph::compare(detected, intended, method = "nmi").
#
# Errors here are internal computation errors (HTTP 500), so they use plain
# stop() / warning(), not validation_error().
compute_nmi <- function(detected, intended) {
  if (length(detected) != length(intended)) {
    stop(sprintf(
      "compute_nmi: detected and intended must have equal length (got %d and %d)",
      length(detected), length(intended)
    ), call. = FALSE)
  }

  keep <- !is.na(detected) & !is.na(intended)
  dropped <- sum(!keep)

  if (dropped > 0L) {
    warning(sprintf(
      "compute_nmi: dropped %d position(s) where detected or intended is NA",
      dropped
    ), call. = FALSE)
    detected <- detected[keep]
    intended <- intended[keep]
  }

  if (length(detected) == 0L) {
    stop(
      "compute_nmi: no positions remain after dropping NA values",
      call. = FALSE
    )
  }

  igraph::compare(detected, intended, method = "nmi")
}
