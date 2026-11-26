# tests/test_ega.R
# /ega pipeline against the recorded fixture (Requirements 3.14, 3.17, 3.20,
# 6.2, 6.3, 6.4, 6.13, 7.10, 7.11). Fixture values are TEST ONLY.
# Run via `Rscript tests/run_all.R` (helpers.R is sourced by the runner), or
# source helpers.R first when running this file directly from r-service/.

if (!exists("assert_true", mode = "function")) {
  source(file.path(if (dir.exists("tests")) "tests" else "r-service/tests", "helpers.R"))
  reset_test_state()
}

local({
  service_dir <- if (file.exists(file.path("ega", "pipeline.R"))) "." else "r-service"
  if (!file.exists(file.path(service_dir, "ega", "pipeline.R"))) {
    stop("test_ega.R: run from r-service/ (or the repo root)", call. = FALSE)
  }
  fixture_dir <- file.path(service_dir, "tests", "fixtures")

  # Same order as api.R / generate_fixtures.R.
  for (f in c("utils/conditions.R", "logging/logger.R", "config/loader.R",
              "validation/request_validator.R", "ega/nmi.R", "ega/uva.R",
              "ega/bootega.R", "ega/pipeline.R")) {
    source(file.path(service_dir, f), local = FALSE)
  }

  input_text <- paste(readLines(file.path(fixture_dir, "ega_input.json"), warn = FALSE),
                      collapse = "\n")
  expected <- jsonlite::fromJSON(file.path(fixture_dir, "ega_expected.json"),
                                 simplifyVector = FALSE)
  expected_uva <- as.character(unlist(expected$removed_uva))
  expected_boot <- as.character(unlist(expected$removed_bootega))

  # Parse the request the way the service does, fresh for each run.
  run_once <- function() execute_ega_pipeline(parse_json_body(input_text))
  item_ids <- as.character(unlist(parse_json_body(input_text)$item_ids))

  result <- run_once()
  uva_removed <- as.character(unlist(result$uva$removed_items))
  boot_removed <- as.character(unlist(result$bootega$removed_items))

  cat(sprintf("UVA removed:      %s\n", paste(uva_removed, collapse = ", ")))
  cat(sprintf("bootEGA removed:  %s\n", paste(boot_removed, collapse = ", ")))
  cat(sprintf("NMI initial:      %.15g\n", result$nmi$initial))
  cat(sprintf("NMI final:        %.15g\n", result$nmi$final))

  # Planted near-duplicate pair: exactly one of the two is removed.
  removed_from_pair <- intersect(uva_removed, c("item_003", "item_004"))
  assert_true(length(removed_from_pair) == 1,
              "UVA removes exactly one of item_003 / item_004")

  # Structural screening should not worsen agreement with intended structure.
  assert_true(result$nmi$final >= result$nmi$initial,
              "NMI final >= NMI initial")

  # UVA score entries.
  wto_scores <- result$uva$removed_wto_scores
  for (id in uva_removed) {
    entry <- wto_scores[[id]]
    assert_true(!is.null(entry), paste("UVA score entry exists for", id))
    if (is.null(entry)) next
    assert_true(is.character(entry$redundant_with) && length(entry$redundant_with) == 1L &&
                  entry$redundant_with %in% item_ids && entry$redundant_with != id,
                paste("UVA redundant_with is another valid item ID for", id))
    assert_true(is.numeric(entry$wto) && length(entry$wto) == 1L,
                paste("UVA wto is numeric for", id))
    cat(sprintf("UVA %s: redundant_with=%s wto=%.15g\n", id,
                entry$redundant_with, entry$wto))
  }

  # bootEGA score entries.
  stab_scores <- result$bootega$removed_stability_scores
  for (id in boot_removed) {
    assert_true(!is.null(stab_scores[[id]]),
                paste("bootEGA stability entry exists for", id))
    if (!is.null(stab_scores[[id]])) {
      cat(sprintf("bootEGA %s: stability=%s\n", id, format(stab_scores[[id]], digits = 15)))
    }
  }

  # Reproducibility against the recorded file.
  assert_set_equal(expected_uva, uva_removed, "UVA removed set matches recorded fixture")
  assert_set_equal(expected_boot, boot_removed, "bootEGA removed set matches recorded fixture")
  assert_near(expected$nmi_initial, result$nmi$initial, 0.001, "NMI initial matches recorded fixture")
  assert_near(expected$nmi_final, result$nmi$final, 0.001, "NMI final matches recorded fixture")

  # Repeat-request reproducibility.
  second <- run_once()
  assert_set_equal(uva_removed, as.character(unlist(second$uva$removed_items)),
                   "repeat: UVA removed set equal")
  assert_set_equal(boot_removed, as.character(unlist(second$bootega$removed_items)),
                   "repeat: bootEGA removed set equal")
  assert_near(result$nmi$initial, second$nmi$initial, 0.001, "repeat: NMI initial equal")
  assert_near(result$nmi$final, second$nmi$final, 0.001, "repeat: NMI final equal")
})
