#!/usr/bin/env Rscript
# Install the R packages needed by the R Statistics Service.
#
# Usage: Rscript r-service/install_packages.R
#
# Already-installed packages are skipped. The CRAN mirror can be overridden
# with the R_SERVICE_CRAN_MIRROR environment variable.

cran_mirror <- Sys.getenv("R_SERVICE_CRAN_MIRROR", unset = "https://cloud.r-project.org")
options(repos = c(CRAN = cran_mirror))

# MASS is used only by tests/generate_fixtures.R (mvrnorm). It ships with R as a
# recommended package, but is listed so a minimal R install still gets it.
required_packages <- c(
  "plumber",
  "EGAnet",
  "lavaan",
  "igraph",
  "jsonlite",
  "uuid",
  "MASS"
)

installed <- rownames(installed.packages())
missing <- setdiff(required_packages, installed)

if (length(missing) == 0) {
  message("All required packages are already installed; nothing to do.")
} else {
  message("Installing from ", cran_mirror, ": ", paste(missing, collapse = ", "))
  # Default dependencies (Depends, Imports, LinkingTo). Suggests are not needed.
  install.packages(missing)
}

# Verify. Exit 1 listing anything that still cannot be loaded.
failed <- required_packages[!vapply(
  required_packages,
  function(p) requireNamespace(p, quietly = TRUE),
  logical(1)
)]

if (length(failed) > 0) {
  message("ERROR: these packages are not available after install: ",
          paste(failed, collapse = ", "))
  quit(status = 1)
}

for (p in required_packages) {
  message(sprintf("%-10s %s", p, as.character(packageVersion(p))))
}
