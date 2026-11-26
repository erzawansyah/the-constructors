# Test helpers for the R service test suite.
# Shared state: failure and assertion counters live in `.test_state`.
# Tolerances are always supplied by callers; nothing is hardcoded here.

.test_state <- new.env(parent = emptyenv())
.test_state$failures <- 0L
.test_state$assertions <- 0L

reset_test_state <- function() {
  .test_state$failures <- 0L
  .test_state$assertions <- 0L
  invisible(NULL)
}

get_test_failures <- function() .test_state$failures
get_test_assertions <- function() .test_state$assertions

.record_pass <- function() {
  .test_state$assertions <- .test_state$assertions + 1L
  invisible(TRUE)
}

.record_fail <- function(label, ...) {
  .test_state$assertions <- .test_state$assertions + 1L
  .test_state$failures <- .test_state$failures + 1L
  cat(sprintf("FAIL: %s\n", label))
  details <- c(...)
  if (length(details) > 0) cat(paste0("  ", details, "\n"), sep = "")
  invisible(FALSE)
}

.fmt <- function(x) {
  if (is.null(x)) return("NULL")
  paste0("[", paste(format(x, digits = 15), collapse = ", "), "]")
}

assert_true <- function(condition, label = "assert_true") {
  ok <- is.logical(condition) && length(condition) == 1L && !is.na(condition) && condition
  if (ok) .record_pass() else .record_fail(label, paste("condition was", .fmt(condition)))
}

# Non-numeric-tolerant equality (strings, logicals, lists, ...). For numbers
# use assert_near; identical() is deliberately not used.
assert_equal <- function(expected, actual, label = "assert_equal") {
  eq <- tryCatch(isTRUE(all.equal(expected, actual, tolerance = 0)),
                 error = function(e) FALSE)
  if (eq) .record_pass()
  else .record_fail(label, paste("expected:", .fmt(expected)), paste("actual:  ", .fmt(actual)))
}

assert_near <- function(expected, actual, tolerance, label = "assert_near") {
  bad_tol <- !is.numeric(tolerance) || length(tolerance) != 1L ||
    is.na(tolerance) || tolerance < 0
  ok <- FALSE
  if (!bad_tol && is.numeric(expected) && is.numeric(actual) &&
      length(expected) == length(actual)) {
    both_na <- is.na(expected) & is.na(actual)
    one_na <- xor(is.na(expected), is.na(actual))
    diffs <- abs(expected - actual)
    ok <- !any(one_na) && all(both_na | diffs <= tolerance)
  }
  if (ok) return(.record_pass())
  .record_fail(label,
               paste("expected: ", .fmt(expected)),
               paste("actual:   ", .fmt(actual)),
               paste("tolerance:", .fmt(tolerance)))
}

assert_in_range <- function(value, lower, upper, label = "assert_in_range") {
  ok <- is.numeric(value) && length(value) >= 1L && !any(is.na(value)) &&
    is.numeric(lower) && is.numeric(upper) && length(lower) == 1L &&
    length(upper) == 1L && !is.na(lower) && !is.na(upper) &&
    all(value >= lower & value <= upper)
  if (ok) .record_pass()
  else .record_fail(label, paste("value:", .fmt(value)),
                    paste("range: [", .fmt(lower), ",", .fmt(upper), "]"))
}

assert_set_equal <- function(expected, actual, label = "assert_set_equal") {
  ok <- tryCatch(setequal(expected, actual), error = function(e) FALSE)
  if (ok) .record_pass()
  else .record_fail(label, paste("expected set:", .fmt(expected)),
                    paste("actual set:  ", .fmt(actual)))
}
