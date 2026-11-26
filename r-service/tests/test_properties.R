# tests/test_properties.R
# Property-based tests (testthat + hedgehog) for three pure helpers:
# compute_nmi(), validate_config(), build_lavaan_model().
# No property tests for EGA, UVA, bootEGA or CFA (fixture tests cover those).
#
# Run through testthat, not sourced like the custom-helper tests:
#   Rscript tests/run_all.R   (run_all.R calls testthat::test_file on this file)
#   Rscript -e 'testthat::test_file("tests/test_properties.R")'   (from r-service/)
#
# Test-only dependencies: testthat 3.3.2, hedgehog 0.2 (see install_packages.R).
# Never loaded by api.R.
#
# Hedgehog names verified against the installed package (hedgehog 0.2) with
# ls("package:hedgehog"), args() and gen.example() on 2026 install:
#   forall(generator, property, tests, size.limit, shrink.limit, discard.limit, curry)
#       generator is a list of generators, property takes one argument per element
#   gen.c(generator, from = 1, to = NULL, of = NULL)   vector of generated elements
#   gen.element(x, prob = NULL)                        one element of x
#   gen.unif(from, to, shrink.median = T)              uniform number
#   gen.sample(x, size, replace = FALSE, prob = NULL)  sample of x, shrinks
#   gen.sample.int(n, size, replace = FALSE, prob = NULL)  sample of 1..n
#   gen.with(g, m)                                     map m over generator g
#   gen.and_then(g, f)                                 dependent generator
#   gen.subsequence(x)                                 subsequence of x
#   generate(for (x in gen) ...)                       documented in the vignette
#
# Reproducibility: seed documented below. hedgehog draws from R's RNG.
set.seed(20260101)  # fixed seed for reproducible property runs

library(testthat)
library(hedgehog)

local({
  # test_file() may change the working directory; find r-service/ robustly.
  candidates <- c(".", "r-service", "..", "../r-service")
  hit <- candidates[file.exists(file.path(candidates, "cfa", "model_builder.R"))]
  if (length(hit) == 0L) stop("test_properties.R: cannot locate r-service/", call. = FALSE)
  service_dir <- hit[1]
  for (f in c("utils/conditions.R", "config/loader.R", "ega/nmi.R",
              "cfa/model_builder.R")) {
    source(file.path(service_dir, f), local = FALSE)
  }
})

# Feature: r-statistics-spike, Property 1: compute_nmi() is invariant under relabeling
# Validates: Requirements 3.11, 3.12
test_that("Property 1: compute_nmi() is invariant under relabeling", {
  # Codes 0..24 decode to a (detected, intended) pair of labels in 1..5.
  # Two fixed leading positions (1,1) and (2,2) guarantee at least two distinct
  # labels in each vector. Both vectors have equal length by construction.
  gen_codes <- gen.c(gen.element(0:24), from = 2, to = 40)
  gen_perm <- gen.sample.int(5, 5)  # permutation of the label set 1..5
  gen_mode <- gen.element(c("detected", "intended", "both"))

  forall(
    list(codes = gen_codes, p1 = gen_perm, p2 = gen_perm, mode = gen_mode),
    function(codes, p1, p2, mode) {
      detected <- c(1L, 2L, as.integer(codes %/% 5L) + 1L)
      intended <- c(1L, 2L, as.integer(codes %% 5L) + 1L)
      original <- compute_nmi(detected, intended)

      relabeled <- switch(mode,
        detected = compute_nmi(p1[detected], intended),
        intended = compute_nmi(detected, p1[intended]),
        both     = compute_nmi(p1[detected], p2[intended])
      )
      # TEST ONLY tolerance: floating-point error, absolute (not relative)
      expect_true(is.finite(original) && is.finite(relabeled))
      expect_true(abs(relabeled - original) <= 1e-9)
    }
  )
})

# Feature: r-statistics-spike, Property 2: validate_config() rejects any config with a null or missing field
# Validates: Requirements 2.1, 2.2, 3.2
test_that("Property 2: validate_config() rejects a config with any null or missing field", {
  fields <- EGA_REQUIRED_CONFIG_FIELDS
  # TEST ONLY: arbitrary non-null filler values, not psychometric values.
  # Never read from or written to app-config/psychometric-procedure.yaml.
  gen_numbers <- gen.c(gen.unif(-1, 1), of = length(fields))
  gen_modes <- gen.c(gen.element(c("keep", "null", "remove")), of = length(fields))
  gen_forced_index <- gen.element(seq_along(fields))
  gen_forced_mode <- gen.element(c("null", "remove"))

  forall(
    list(nums = gen_numbers, modes = gen_modes, idx = gen_forced_index,
         forced = gen_forced_mode),
    function(nums, modes, idx, forced) {
      modes[idx] <- forced  # guarantees a non-empty affected subset
      config <- as.list(nums)
      names(config) <- fields
      # TEST ONLY: fixed non-null filler. With at least one null or missing
      # field, validate_config() stops in the per-field loop and never reaches
      # the uva_method value check, so this value has no effect on the result.
      config[["uva_method"]] <- "mbr"
      for (i in seq_along(fields)) {
        if (modes[i] == "null") config[fields[i]] <- list(NULL)
        if (modes[i] == "remove") config[[fields[i]]] <- NULL
      }
      err <- tryCatch({
        validate_config(config)
        NULL
      }, condition = function(e) e)
      # validate_config() checks fields in EGA_REQUIRED_CONFIG_FIELDS order and
      # stops at the first affected one, using that field's own mode.
      first <- which(modes != "keep")[1]
      expected <- if (modes[first] == "null") {
        paste0("config.", fields[first], " is null; owner decision required")
      } else {
        paste0("config.", fields[first], " is missing")
      }
      expect_true(inherits(err, "validation_error"))
      expect_identical(conditionMessage(err), expected)
    }
  )
})

# Feature: r-statistics-spike, Property 3: build_lavaan_model() contains every item exactly once
# Validates: Requirements 4.4
test_that("Property 3: build_lavaan_model() contains every item exactly once", {
  # Identifier-safe pools. Factor names never collide with item IDs.
  item_pool <- c(sprintf("item_%03d", 1:30), sprintf("q%d_a", 1:30))
  factor_pool <- c("AnticDread", "WorkRumination", "Factor_B", "Gamma", "delta")
  max_factors <- 4L
  max_items_per_factor <- 5L

  gen_sizes <- gen.c(gen.element(1:max_items_per_factor), from = 1, to = max_factors)
  gen_factor_names <- gen.sample(factor_pool, size = max_factors)
  gen_items <- gen.sample(item_pool, size = max_factors * max_items_per_factor)

  forall(
    list(sizes = gen_sizes, fnames = gen_factor_names, pool = gen_items),
    function(sizes, fnames, pool) {
      k <- length(sizes)
      ends <- cumsum(sizes)
      starts <- ends - sizes + 1L
      factors <- lapply(seq_len(k), function(i) {
        list(name = fnames[i], items = pool[starts[i]:ends[i]])
      })
      all_items <- pool[seq_len(sum(sizes))]

      syntax <- build_lavaan_model(list(factors = factors))
      tokens <- strsplit(syntax, "=~|\\+|\\s+")[[1]]
      tokens <- tokens[nzchar(tokens)]

      item_tokens <- setdiff(tokens, fnames[seq_len(k)])
      expect_equal(sort(item_tokens), sort(all_items))      # no others, none missing
      expect_true(all(table(item_tokens) == 1L))             # each exactly once
      expect_true(all(vapply(all_items, function(id) sum(tokens == id) == 1L, logical(1))))
    }
  )
})
