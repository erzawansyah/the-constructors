# Test runner for the R service.
# Usage (from r-service/):  Rscript tests/run_all.R
# Also works from the repo root:  Rscript r-service/tests/run_all.R
#
# Sources helpers.R, then every test_*.R in this directory (sorted by name).
# Each file runs inside tryCatch; a file that errors counts as a failure.
# Exit 0 when nothing failed, exit 1 otherwise.

local({
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
  tests_dir <- if (length(file_arg) > 0) {
    dirname(normalizePath(file_arg[1], winslash = "/", mustWork = TRUE))
  } else {
    normalizePath("tests", winslash = "/", mustWork = TRUE)
  }
  assign(".tests_dir", tests_dir, envir = globalenv())
})

# Test files resolve paths relative to r-service/, so run from there.
setwd(dirname(.tests_dir))

source(file.path(.tests_dir, "helpers.R"), local = FALSE)
reset_test_state()

test_files <- sort(list.files(.tests_dir, pattern = "^test_.*\\.R$", full.names = TRUE))
errored_files <- character(0)

for (f in test_files) {
  name <- basename(f)
  cat(sprintf("\n== %s ==\n", name))
  before <- get_test_failures()
  ok <- tryCatch({
    source(f, local = FALSE)
    TRUE
  }, error = function(e) {
    cat(sprintf("ERROR in %s: %s\n", name, conditionMessage(e)))
    FALSE
  })
  if (!ok) errored_files <- c(errored_files, name)
  cat(sprintf("-- %s: %d failed assertion(s)%s\n", name,
              get_test_failures() - before,
              if (ok) "" else " (file errored)"))
}

failures <- get_test_failures()
cat("\n==== Summary ====\n")
cat(sprintf("Test files run:     %d\n", length(test_files)))
cat(sprintf("Assertions run:     %d\n", get_test_assertions()))
cat(sprintf("Failed assertions:  %d\n", failures))
cat(sprintf("Errored test files: %d\n", length(errored_files)))
if (length(errored_files) > 0) {
  cat(paste0("  - ", errored_files, "\n"), sep = "")
}

if (failures == 0L && length(errored_files) == 0L) {
  cat("All tests passed\n")
  quit(status = 0L)
} else {
  cat(sprintf("TESTS FAILED: %d failed assertion(s), %d errored file(s)\n",
              failures, length(errored_files)))
  quit(status = 1L)
}
