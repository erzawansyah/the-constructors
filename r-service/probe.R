# probe.R - development probe for EGAnet and lavaan result structures.
#
# Purpose: record the exact argument names and result field paths of the
# installed EGAnet / lavaan versions BEFORE any wrapper is written, and again
# after package upgrades or unexpected missing fields (design.md,
# "Development probe"). Wrapper code must follow this script's output.
#
# Run (from the repository root):
#   Rscript r-service/probe.R > r-service/probe_output.txt 2>&1
#
# Every sample parameter value in this file is for probing only. None of them
# is a production value, none comes from app-config/psychometric-procedure.yaml,
# and the service never reads them. Each is labeled
# "PROBE ONLY - not a production value".
#
# Each section runs inside tryCatch, so one failing call prints its error and
# the remaining sections still run.

options(width = 100, warn = 1)

# ---- helpers ---------------------------------------------------------------

banner <- function(title) {
  cat("\n", strrep("=", 90), "\n", title, "\n", strrep("=", 90), "\n", sep = "")
}

# Run one probe section; print the error (and do not stop) if it fails.
section <- function(title, expr) {
  banner(title)
  tryCatch(
    withCallingHandlers(
      expr,
      warning = function(w) {
        cat("[WARNING] ", conditionMessage(w), "\n", sep = "")
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) {
      cat("[ERROR in section '", title, "'] ", conditionMessage(e), "\n", sep = "")
      invisible(NULL)
    }
  )
}

# Print class, names() and str() of an object under a label. Errors in the
# individual print are caught so the rest of the section continues.
show <- function(label, x, max.level = 3) {
  cat("\n--- ", label, " ---\n", sep = "")
  tryCatch({
    cat("class: ", paste(class(x), collapse = ", "), "\n", sep = "")
    cat("names: ")
    print(names(x))
    cat("str:\n")
    str(x, max.level = max.level, list.len = 60)
  }, error = function(e) {
    cat("[ERROR showing '", label, "'] ", conditionMessage(e), "\n", sep = "")
  })
  invisible(NULL)
}

# Print the argument names and defaults of an exported function.
show_args <- function(fn_name, pkg) {
  cat("\n--- ", pkg, "::", fn_name, " ---\n", sep = "")
  tryCatch({
    fn <- getExportedValue(pkg, fn_name)
    cat("names(formals()):\n")
    print(names(formals(fn)))
    cat("args():\n")
    print(args(fn))
    cat("formals() defaults:\n")
    str(formals(fn), max.level = 1)
  }, error = function(e) {
    cat("[ERROR reading formals of ", fn_name, "] ", conditionMessage(e), "\n", sep = "")
  })
  invisible(NULL)
}

# ---- 0. environment and package versions -----------------------------------

section("0. R and package versions", {
  cat(R.version.string, "\n")
  for (pkg in c("plumber", "EGAnet", "lavaan", "igraph", "jsonlite", "uuid")) {
    v <- tryCatch(as.character(packageVersion(pkg)),
                  error = function(e) paste("NOT INSTALLED:", conditionMessage(e)))
    cat(sprintf("%-10s %s\n", pkg, v))
  }
})

# ---- 1. argument names -----------------------------------------------------

section("1. args() / formals() of UVA, EGA, bootEGA, itemStability", {
  for (fn_name in c("UVA", "EGA", "bootEGA", "itemStability")) {
    show_args(fn_name, "EGAnet")
  }
})

# ---- 2. sample data --------------------------------------------------------

# PROBE ONLY - not a production value
probe_seed <- 20260101
set.seed(probe_seed)

# Item x embedding-dimension matrix: 3 clusters of 4 items in 30 dimensions.
# Item 2 is a near-duplicate of item 1 so UVA has something to find, and
# item 8 mixes clusters 2 and 3. Sizes below are small to keep the probe fast.
n_dim <- 30L            # PROBE ONLY - not a production value
items_per_cluster <- 4L # PROBE ONLY - not a production value
n_clusters <- 3L        # PROBE ONLY - not a production value
noise_sd <- 0.4         # PROBE ONLY - not a production value
dup_noise_sd <- 0.05    # PROBE ONLY - not a production value

probe_item_ids <- NULL
probe_embeddings <- NULL
probe_intended <- NULL
probe_ega_data <- NULL

section("2a. Sample embedding data (items x dimensions, then transposed)", {
  centers <- matrix(rnorm(n_clusters * n_dim), nrow = n_clusters)
  n_items <- n_clusters * items_per_cluster
  intended <- rep(seq_len(n_clusters) - 1L, each = items_per_cluster) # 0-indexed
  emb <- t(vapply(seq_len(n_items), function(i) {
    centers[intended[i] + 1L, ] + rnorm(n_dim, sd = noise_sd)
  }, numeric(n_dim)))
  emb[2, ] <- emb[1, ] + rnorm(n_dim, sd = dup_noise_sd)
  emb[8, ] <- (centers[2, ] + centers[3, ]) / 2 + rnorm(n_dim, sd = noise_sd)

  probe_item_ids <- sprintf("item_%03d", seq_len(n_items))
  probe_embeddings <- emb
  probe_intended <- intended
  rownames(probe_embeddings) <- probe_item_ids

  # design.md step 4: transpose so rows = embedding dimensions (observations)
  # and columns = items (variables).
  probe_ega_data <- t(probe_embeddings)
  colnames(probe_ega_data) <- probe_item_ids

  cat("embeddings (items x dims): ", paste(dim(probe_embeddings), collapse = " x "), "\n")
  cat("transposed (dims x items): ", paste(dim(probe_ega_data), collapse = " x "), "\n")
  cat("intended_dimensions (0-indexed): ", paste(probe_intended, collapse = " "), "\n")
})

# ---- 3. UVA ----------------------------------------------------------------

probe_cut_off <- 0.25      # PROBE ONLY - not a production value
probe_uva_method <- "MBR"  # PROBE ONLY - not a production value

probe_uva_raw <- NULL
probe_uva_reduced <- NULL

section("3a. EGAnet::UVA, reduce = FALSE (raw wTO fields)", {
  probe_uva_raw <- EGAnet::UVA(
    data = probe_ega_data,
    uva.method = probe_uva_method, # PROBE ONLY - not a production value
    cut.off = probe_cut_off,       # PROBE ONLY - not a production value
    reduce = FALSE,                # PROBE ONLY - not a production value
    verbose = FALSE
  )
  show("UVA (reduce = FALSE) result", probe_uva_raw, max.level = 4)
  if (is.list(probe_uva_raw)) {
    for (nm in names(probe_uva_raw)) {
      show(paste0("UVA$", nm), probe_uva_raw[[nm]], max.level = 3)
    }
  }
})

section("3a-2. EGAnet::UVA, uva.method = 'EJP', reduce = FALSE (compare field names)", {
  uva_ejp <- EGAnet::UVA(
    data = probe_ega_data,
    uva.method = "EJP",       # PROBE ONLY - not a production value
    cut.off = probe_cut_off,  # PROBE ONLY - not a production value
    reduce = FALSE,           # PROBE ONLY - not a production value
    # Added after the first run: with uva.method = "EJP" UVA calls
    # match.arg(reduce.method) even when reduce = FALSE, so the default
    # 4-element vector fails with "'arg' must be of length 1". See PROBE_NOTES.md.
    reduce.method = "remove", # PROBE ONLY - not a production value
    verbose = FALSE
  )
  show("UVA (EJP, reduce = FALSE) result", uva_ejp, max.level = 3)
  # NOT probed on purpose: uva.method = "EJP" with reduce = TRUE, reduce.method = "remove",
  # auto = TRUE prints "Automated UVA is not available" and then waits for keyboard
  # input (hangs a non-interactive process). See PROBE_NOTES.md.
})

section("3a-3. UVA reduced data when nothing is redundant (cut.off = 0.99)", {
  uva_none <- EGAnet::UVA(
    data = probe_ega_data,
    uva.method = probe_uva_method, # PROBE ONLY - not a production value
    cut.off = 0.99,                # PROBE ONLY - not a production value
    reduce = TRUE,                 # PROBE ONLY - not a production value
    reduce.method = "remove",      # PROBE ONLY - not a production value
    auto = TRUE,                   # PROBE ONLY - not a production value
    verbose = FALSE
  )
  cat("names: ", paste(names(uva_none), collapse = ", "), "\n")
  cat("is.null(reduced_data): ", is.null(uva_none$reduced_data), "\n")
  cat("is.null(keep_remove): ", is.null(uva_none$keep_remove), "\n")
  cat("length(redundant): ", length(uva_none$redundant), "\n")
})

section("3b. EGAnet::UVA, reduce = TRUE, reduce.method = 'remove', auto = TRUE", {
  probe_uva_reduced <- EGAnet::UVA(
    data = probe_ega_data,
    uva.method = probe_uva_method, # PROBE ONLY - not a production value
    cut.off = probe_cut_off,       # PROBE ONLY - not a production value
    reduce = TRUE,                 # PROBE ONLY - not a production value
    reduce.method = "remove",      # PROBE ONLY - not a production value
    auto = TRUE,                   # PROBE ONLY - not a production value
    verbose = FALSE
  )
  show("UVA (reduce = TRUE) result", probe_uva_reduced, max.level = 4)
  if (is.list(probe_uva_reduced)) {
    for (nm in names(probe_uva_reduced)) {
      show(paste0("UVA$", nm), probe_uva_reduced[[nm]], max.level = 3)
    }
    cat("\n--- UVA reduced data / wTO field search ---\n")
    rd <- probe_uva_reduced$reduced_data
    if (!is.null(rd)) {
      cat("reduced_data dim: ", paste(dim(rd), collapse = " x "), "\n")
      cat("reduced_data colnames: ", paste(colnames(rd), collapse = " "), "\n")
      cat("items removed (original columns not in reduced_data): ",
          paste(setdiff(colnames(probe_ega_data), colnames(rd)), collapse = " "), "\n")
    } else {
      cat("$reduced_data is NULL; inspect the str() output above for the real path.\n")
    }
    pw <- probe_uva_reduced$wto$pairwise
    if (!is.null(pw)) {
      cat("wto$pairwise (node_i, node_j, wto), top rows:\n")
      print(utils::head(pw, 10))
    }
    cat("keep_remove (if present):\n")
    print(probe_uva_reduced$keep_remove)
    cat("\nkeep_remove consistent with reduced_data? (keep == colnames(reduced_data)): ",
        identical(sort(probe_uva_reduced$keep_remove$keep), sort(colnames(rd))), "\n")
    cat("Per-removed-item max pairwise wTO (candidate removed_wto_scores):\n")
    removed_items <- setdiff(colnames(probe_ega_data), colnames(rd))
    print(vapply(removed_items, function(r) {
      max(pw$wto[pw$node_i == r | pw$node_j == r])
    }, numeric(1)))
    cat("pairwise rows: ", nrow(pw), " of ", choose(ncol(probe_ega_data), 2), " possible pairs\n")

    # Second pass on the reduced data (the service repeats UVA until nothing is removed).
    pass2 <- EGAnet::UVA(
      data = rd,
      uva.method = probe_uva_method, # PROBE ONLY - not a production value
      cut.off = probe_cut_off,       # PROBE ONLY - not a production value
      reduce = TRUE,                 # PROBE ONLY - not a production value
      reduce.method = "remove",      # PROBE ONLY - not a production value
      auto = TRUE,                   # PROBE ONLY - not a production value
      verbose = FALSE
    )
    cat("\nsecond UVA pass names: ", paste(names(pass2), collapse = ", "), "\n")
    cat("second pass retained: ", paste(colnames(pass2$reduced_data), collapse = " "), "\n")
  }
})

# ---- 4. EGA ----------------------------------------------------------------

probe_model <- "glasso"        # PROBE ONLY - not a production value
probe_algorithm <- "walktrap"  # PROBE ONLY - not a production value

probe_ega <- NULL

section("4. EGAnet::EGA on the transposed matrix", {
  probe_ega <- EGAnet::EGA(
    data = probe_ega_data,
    model = probe_model,         # PROBE ONLY - not a production value
    algorithm = probe_algorithm, # PROBE ONLY - not a production value
    plot.EGA = FALSE,            # PROBE ONLY - not a production value
    verbose = FALSE
  )
  show("EGA result", probe_ega, max.level = 3)
  show("ega$wc (community membership)", probe_ega$wc, max.level = 1)
  cat("\nnames(ega$wc): ")
  print(names(probe_ega$wc))
  cat("ega$wc values:\n")
  print(probe_ega$wc)
  cat("anyNA(ega$wc): ", anyNA(probe_ega$wc), "\n")
  cat("ega$n.dim: ", probe_ega$n.dim, "\n")

  # NMI path used by the wrapper: igraph::compare(method = "nmi")
  wc <- probe_ega$wc
  nmi_value <- igraph::compare(as.integer(wc), as.integer(probe_intended + 1L), method = "nmi")
  cat("igraph::compare(wc, intended + 1, method = 'nmi'): ", nmi_value, "\n")
  cat("igraph::compare(<EGA.community> as is, intended + 1 (double)): ",
      igraph::compare(probe_ega$wc, probe_intended + 1, method = "nmi"), "\n")
  cat("typeof(ega$wc): ", typeof(probe_ega$wc), "\n")
})

# ---- 5. bootEGA ------------------------------------------------------------

probe_iter <- 20L                 # PROBE ONLY - not a production value
probe_type <- "resampling"        # PROBE ONLY - not a production value
probe_boot_seed <- 1              # PROBE ONLY - not a production value

probe_boot <- NULL

section("5. EGAnet::bootEGA", {
  probe_boot <- EGAnet::bootEGA(
    data = probe_ega_data,
    model = probe_model,         # PROBE ONLY - not a production value
    algorithm = probe_algorithm, # PROBE ONLY - not a production value
    iter = probe_iter,           # PROBE ONLY - not a production value
    type = probe_type,           # PROBE ONLY - not a production value
    seed = probe_boot_seed,      # PROBE ONLY - not a production value
    ncores = 1L,                 # PROBE ONLY - not a production value
    plot.itemStability = FALSE,  # PROBE ONLY - not a production value
    verbose = FALSE
  )
  show("bootEGA result", probe_boot, max.level = 2)
  if (is.list(probe_boot)) {
    for (nm in names(probe_boot)) {
      show(paste0("bootEGA$", nm), probe_boot[[nm]], max.level = 2)
    }
  }
})

section("5b. bootEGA seed type check (jsonlite parses whole numbers as integer)", {
  # Earlier smoke runs showed bootEGA(seed = <integer>) fails with
  # "REAL() can only be applied to a 'numeric'". JSON request values arrive as
  # integer, so wrappers may need as.numeric(). This records the behavior for
  # the installed version.
  res <- tryCatch({
    EGAnet::bootEGA(
      data = probe_ega_data,
      model = probe_model,         # PROBE ONLY - not a production value
      algorithm = probe_algorithm, # PROBE ONLY - not a production value
      iter = 5,                    # PROBE ONLY - not a production value
      type = probe_type,           # PROBE ONLY - not a production value
      seed = 1L,                   # PROBE ONLY - not a production value (integer on purpose)
      ncores = 1,                  # PROBE ONLY - not a production value
      plot.itemStability = FALSE,
      verbose = FALSE
    )
    "seed = 1L (integer): OK"
  }, error = function(e) paste("seed = 1L (integer): ERROR:", conditionMessage(e)))
  cat(res, "\n")

  res2 <- tryCatch({
    EGAnet::bootEGA(
      data = probe_ega_data,
      model = probe_model,         # PROBE ONLY - not a production value
      algorithm = probe_algorithm, # PROBE ONLY - not a production value
      iter = 5L,                   # PROBE ONLY - not a production value (integer on purpose)
      type = probe_type,           # PROBE ONLY - not a production value
      seed = as.numeric(1L),       # PROBE ONLY - not a production value (coerced)
      ncores = 1,                  # PROBE ONLY - not a production value
      plot.itemStability = FALSE,
      verbose = FALSE
    )
    "iter = 5L (integer), seed = as.numeric(1L): OK"
  }, error = function(e) paste("iter = 5L, seed = as.numeric(1L): ERROR:", conditionMessage(e)))
  cat(res2, "\n")
})

# ---- 6. itemStability ------------------------------------------------------

probe_is <- NULL

section("6. EGAnet::itemStability on the bootEGA result", {
  if (is.null(probe_boot)) stop("bootEGA result not available (section 5 failed)")
  probe_is <- EGAnet::itemStability(probe_boot, IS.plot = FALSE)
  show("itemStability result", probe_is, max.level = 3)
  if (is.list(probe_is)) {
    for (nm in names(probe_is)) {
      show(paste0("itemStability$", nm), probe_is[[nm]], max.level = 2)
    }
    cat("\n--- itemStability$membership (if present) ---\n")
    print(probe_is$membership)
    cat("\n--- itemStability$item.stability (if present) ---\n")
    print(probe_is$item.stability)
    cat("\n--- per-item path: itemStability(boot)$item.stability$empirical.dimensions ---\n")
    print(probe_is$item.stability$empirical.dimensions)
    cat("\n--- same values already stored at bootEGA$stability$item.stability$item.stability$empirical.dimensions? ---\n")
    cat(identical(probe_is$item.stability$empirical.dimensions,
                  probe_boot$stability$item.stability$item.stability$empirical.dimensions), "\n")
  }
})

# ---- 7. lavaan CFA (ordinal, WLSMV) ----------------------------------------

# Two correlated factors, 3 ordinal items each, 5-point scale.
probe_n_persons <- 200L        # PROBE ONLY - not a production value
probe_factor_cor <- 0.5        # PROBE ONLY - not a production value
probe_loading <- 0.7           # PROBE ONLY - not a production value
probe_n_categories <- 5L       # PROBE ONLY - not a production value

probe_resp <- NULL
probe_fit <- NULL

section("7a. Sample ordinal response data frame", {
  set.seed(probe_seed + 1L)
  f1 <- rnorm(probe_n_persons)
  f2 <- probe_factor_cor * f1 + sqrt(1 - probe_factor_cor^2) * rnorm(probe_n_persons)
  make_items <- function(f, prefix) {
    out <- sapply(1:3, function(j) {
      cont <- probe_loading * f + sqrt(1 - probe_loading^2) * rnorm(probe_n_persons)
      # Equal-probability bins to get roughly 1..5; PROBE ONLY
      cut_points <- qnorm(seq_len(probe_n_categories - 1L) / probe_n_categories)
      as.integer(cut(cont, breaks = c(-Inf, cut_points, Inf), labels = FALSE))
    })
    colnames(out) <- paste0(prefix, 1:3)
    out
  }
  probe_resp <- as.data.frame(cbind(make_items(f1, "a"), make_items(f2, "b")))
  cat("response df dim: ", paste(dim(probe_resp), collapse = " x "), "\n")
  str(probe_resp)
  cat("category counts, item a1:\n")
  print(table(probe_resp$a1))
})

section("7b. lavaan::cfa (ordered, estimator = 'WLSMV', std.lv = TRUE)", {
  model_syntax <- paste("F1 =~ a1 + a2 + a3", "F2 =~ b1 + b2 + b3", sep = "\n")
  cat("model syntax:\n", model_syntax, "\n", sep = "")
  captured <- character(0)
  probe_fit <- withCallingHandlers(
    lavaan::cfa(
      model = model_syntax,
      data = probe_resp,
      ordered = colnames(probe_resp), # PROBE ONLY - not a production value
      estimator = "WLSMV",            # PROBE ONLY - not a production value
      std.lv = TRUE                   # PROBE ONLY - not a production value
    ),
    warning = function(w) {
      captured <<- c(captured, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  cat("captured warnings: ", length(captured), "\n")
  if (length(captured)) print(captured)
  cat("class(fit): ", paste(class(probe_fit), collapse = ", "), "\n")
  cat("lavInspect(fit, 'converged'): ", lavaan::lavInspect(probe_fit, "converged"), "\n")
  cat("lavInspect(fit, 'options')$estimator: ",
      lavaan::lavInspect(probe_fit, "options")$estimator, "\n")
})

section("7c. fitMeasures()", {
  if (is.null(probe_fit)) stop("lavaan fit not available (section 7b failed)")
  wanted <- c("chisq", "df", "pvalue", "cfi", "tli", "rmsea",
              "rmsea.ci.lower", "rmsea.ci.upper", "srmr")
  fm_all <- lavaan::fitMeasures(probe_fit)
  show("fitMeasures(fit) (all)", fm_all, max.level = 1)
  cat("\nall fitMeasures names:\n")
  print(names(fm_all))
  cat("\nwanted names present in fitMeasures(fit): \n")
  print(wanted %in% names(fm_all))
  names(wanted) <- wanted
  cat("\nfitMeasures(fit, wanted):\n")
  fm <- lavaan::fitMeasures(probe_fit, wanted)
  print(fm)
  show("fitMeasures(fit, wanted)", fm, max.level = 1)
  cat("\nunname(fitMeasures(fit, 'cfi')): ")
  print(unname(lavaan::fitMeasures(probe_fit, "cfi")))
  cat("\nNote: with WLSMV, check whether '.scaled' / '.robust' variants exist in the names above\n")
  cat("and which of them the unsuffixed 'cfi' / 'rmsea' correspond to.\n")
  cat("\nscaled / robust variants:\n")
  print(lavaan::fitMeasures(probe_fit, c("chisq.scaled", "df.scaled", "pvalue.scaled",
                                        "cfi.scaled", "tli.scaled", "rmsea.scaled",
                                        "cfi.robust", "tli.robust", "rmsea.robust",
                                        "rmsea.ci.lower.scaled", "rmsea.ci.upper.scaled",
                                        "rmsea.ci.lower.robust", "rmsea.ci.upper.robust")))
})

section("7d. standardizedSolution()", {
  if (is.null(probe_fit)) stop("lavaan fit not available (section 7b failed)")
  ss <- lavaan::standardizedSolution(probe_fit)
  cat("str(standardizedSolution(fit)):\n")
  str(ss)
  cat("\nnames: ")
  print(names(ss))
  cat("\nfull table:\n")
  print(ss)
  cat("\nrows with op == '=~' (loadings):\n")
  print(ss[ss$op == "=~", c("lhs", "op", "rhs", "est.std")])
  cat("\nrows with op == '~~' and lhs != rhs (factor correlations):\n")
  print(ss[ss$op == "~~" & ss$lhs != ss$rhs, c("lhs", "op", "rhs", "est.std")])
})

banner("probe finished")
