# Probe Notes (task 1.3)

Findings from `Rscript r-service/probe.R > r-service/probe_output.txt 2>&1` (run from the repo root).
Raw output: `r-service/probe_output.txt` (about 3,250 lines; most of it is a `ggplot` object dump inside
`itemStability`/`bootEGA` results, search for the `---` and numbered section headers).

Rule (design.md, Development probe, rule 4): where the probe and the documentation disagree, the probe wins.
Wrapper tasks 4.x and 5.x must follow this file.

Nothing here sets a production threshold. All values mentioned (`0.25`, `20`, `"MBR"`, ...) are probe-only.

## 1. Versions

| Item     | Version                       |
| -------- | ----------------------------- |
| R        | 4.6.1 (2026-06-24, ucrt)      |
| plumber  | 1.3.3                         |
| EGAnet   | 2.4.1                         |
| lavaan   | 0.6.21                        |
| igraph   | 2.3.3                         |
| jsonlite | 2.0.0                         |
| uuid     | 1.2.2                         |

## 2. Changes made to `probe.R` in this task

The first run had one failing section (3a-2). The cause is real package behavior, not a casing or script typo.
`probe.R` was changed minimally and rerun:

- Section 3a-2: added `reduce.method = "remove"` to the `uva.method = "EJP"` call (see 3.2 below).
- Added a comment that `EJP` + `reduce = TRUE` + `reduce.method = "remove"` + `auto = TRUE` is deliberately not probed, because it hangs waiting for keyboard input.
- Added sections: 3a-3 (UVA when nothing is redundant), second UVA pass, per-removed-item wTO, `keep_remove` vs `reduced_data` consistency check, `igraph::compare()` directly on `ega$wc`, `bootEGA` with `iter = 5L` and `seed = as.numeric(1L)`, and the per-item stability path.

The remaining `ERROR` line in the output (section 5b, `seed = 1L`) is intentional: it records the integer-seed failure.

## 3. Argument names and result paths (probe results)

### 3.1 `EGAnet::UVA`

Formals (probe section 1):
`UVA(data = NULL, network = NULL, n = NULL, key = NULL, uva.method = c("MBR", "EJP"), cut.off = 0.25, reduce = TRUE, reduce.method = c("latent", "mean", "remove", "sum"), auto = TRUE, verbose = FALSE, ...)`

All five names the task lists exist: `cut.off`, `uva.method`, `reduce`, `reduce.method`, `auto`.

Result for `uva.method = "MBR"`, `reduce = TRUE`, `reduce.method = "remove"`, `auto = TRUE` (class `UVA`, a list):

| What                                  | Path                                  | Type / notes                                                                                           |
| ------------------------------------- | ------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Reduced data (retained items)         | `$reduced_data`                       | numeric matrix, observations in rows, retained items in columns. `colnames()` are the item IDs; `rownames` are NULL. Class stays `matrix` even if a data frame was passed in. |
| Pairwise wTO                          | `$wto$pairwise`                       | data frame with columns `node_i`, `node_j`, `wto`. Sorted by `wto` descending. 65 rows for 12 items (66 possible pairs), so one pair is missing; do not assume all pairs are present. |
| wTO matrix                            | `$wto$matrix`                         | 12 x 12, dimnames = item IDs                                                                           |
| Cut-off echoed back                   | `$wto$cut_off`                        | numeric                                                                                                |
| Redundant sets                        | `$redundant`                          | named list: name = target item, value = character vector of items redundant with it                    |
| Keep / remove                         | `$keep_remove$keep`, `$keep_remove$remove` | character vectors. **Not reliable**: see 4.5                                                       |
| Method echoed back                    | `attr(result, "methods")$uva.method`  | lowercase (`"mbr"`) even though `"MBR"` was passed                                                     |

There is **no per-item wTO score field**. A removed item's score has to be derived. Probe output shows one workable derivation: the maximum `wto` over rows of `$wto$pairwise` where the removed item is `node_i` or `node_j` (printed in the probe under "Per-removed-item max pairwise wTO"). This is a derivation choice, not something EGAnet reports (see 4.4).

`uva.method` values: only `"MBR"` or `"EJP"` are accepted, matched case-insensitively (`"mbr"` and `"MBR"` both work). `"wTO"` fails with: `Invalid argument: uva.method = "wto"  Please choose from: "mbr", "ejp"`.

Integer `cut.off` (`0L`) is accepted. The numeric double `0.25` is what JSON normally delivers.

### 3.2 `uva.method = "EJP"` (the failing probe section)

The error `'arg' must be of length 1` is **real package behavior, not a probe typo**. I found the failing call by running it
interactively: it is `match.arg(reduce.method)`. With `uva.method = "EJP"`, UVA calls `match.arg(reduce.method)` even when
`reduce = FALSE`, and `reduce.method` still has its 4-element default vector. Passing `reduce.method = "remove"` makes the call succeed.
`"MBR"` with `reduce = FALSE` does not hit this.

Three further EJP differences were found (EJP is not usable with the design's fixed arguments):

1. **Different result structure.** `EJP` with `reduce = FALSE` returns `names(result) = c("redundancy", "Methods")`. There is no `$redundant`, `$wto$pairwise`, `$wto$matrix`, `$reduced_data` or `$keep_remove` at the top level. Pairwise weights are in `$redundancy$weights` (matrix) and `$redundancy$descriptives$centralTendency`; redundant sets in `$redundancy$redundant`. With `reduce = TRUE`, `reduce.method = "latent"` the names are `redundancy`, `reduced`, `adhoc`, `Methods`.
2. **`EJP` + `reduce = TRUE` + `reduce.method = "remove"` + `auto = TRUE` hangs a non-interactive R process.** It prints `Warning: Automated UVA is not available for 'reduce.method = "remove"'`, sets `auto` to `FALSE`, then loops on a `Selection:` prompt. I confirmed this with `timeout 60` and stdin from `/dev/null`: exit code 124 (timed out), printing `Inappropriate input. Try again.` repeatedly. An HTTP request would never return.
3. This contradicts the EGAnet help text, which says automated removal is defined for `reduce.method = "remove"`. The probe wins: automated removal works for `MBR` only.

`MBR` with `auto = FALSE` also prompts interactively (confirmed the same way), so `auto = TRUE` is required, not optional.

### 3.3 `EGAnet::EGA`

Formals: `EGA(data, n = NULL, corr = c("auto", "cor_auto", "cosine", "pearson", "spearman"), na.data = c("pairwise", "listwise"), model = c("BGGM", "glasso", "TMFG"), algorithm = c("leiden", "louvain", "walktrap"), uni.method = c("expand", "LE", "louvain"), plot.EGA = TRUE, verbose = FALSE, ...)`

- `model` and `algorithm` exist as named in the design. Values are matched case-insensitively (`"Walktrap"` and `"GLASSO"` both ran).
- There is **no `seed` argument** in the formals. `EGA(..., seed = 1)` does not error, but only because `...` swallows it; I did not verify that it has any effect. In the probe data, `louvain` and `leiden` gave identical memberships across repeated calls with and without `set.seed()`, so reproducibility on this data is not evidence either way.
- `plot.EGA` defaults to `TRUE`. The service must pass `plot.EGA = FALSE`.
- Result (class `EGA`) names: `network`, `wc`, `n.dim`, `correlation`, `n`, `dim.variables`, `TEFI`.
- **`ega$wc`**: class `EGA.community`, `typeof` double, **named** by item ID. `ega$n.dim` is an integer. `anyNA(wc)` was `FALSE` in the probe. `igraph::compare(ega$wc, intended + 1, method = "nmi")` works directly on the `EGA.community` object and on `as.integer(wc)`, both giving 0.8180536 on the probe data. NA handling in `compute_nmi()` is still needed for real data; the probe did not produce an NA.
- `ega$dim.variables` is a data frame (`items`, `dimension` as character) and can be used as a cross-check of `wc`.

### 3.4 `EGAnet::bootEGA`

Formals: `bootEGA(data, n = NULL, corr = ..., na.data = ..., model = ..., algorithm = ..., uni.method = ..., iter = 500, type = c("parametric", "resampling"), ncores, EGA.type = c("EGA", "EGA.fit", "hierEGA", "riEGA"), plot.itemStability = TRUE, typicalStructure = FALSE, plot.typicalStructure = FALSE, seed = NULL, verbose = TRUE, ...)`

- `model`, `algorithm`, `iter`, `type`, `seed`, `verbose` exist as named in the design.
- Required extra arguments the design does not list: `ncores` has no default in the formals (the help text says it defaults to half the machine's cores); `plot.itemStability` defaults to `TRUE`; `verbose` defaults to `TRUE`. The probe passes `ncores = 1`, `plot.itemStability = FALSE`, `verbose = FALSE`. `bootEGA` also ran without `ncores`.
- `type` accepts `"parametric"` and `"resampling"` (lowercase, as in the formals). Both ran.
- **`seed` must be a double.** `seed = 1L` (also `12345L`, `0L`) fails with `REAL() can only be applied to a 'numeric', not a 'integer'`. `seed = 1`, `12345`, `0` and `as.numeric(1L)` work. `jsonlite::fromJSON()` returns whole numbers as integer (`"seed": 1` gives `int`; `1.0` gives `num`), so the wrapper must call `as.numeric(config$random_seed)`.
- **`iter` and `cut.off` do not have this problem.** `iter = 20L` and `iter = 5L` ran, and `UVA(cut.off = 0L)` ran. Only `seed` was found to be affected. Still, coercing `iter` with `as.numeric()` costs nothing; `boot_iterations` is stored as `int` in the result (`$iter`).
- With the same data and `seed = 7`, two calls gave identical `boot.wc` (reproducible).
- Result (class `bootEGA`) names: `summary.table`, `frequency`, `stability`, `bootGraphs`, `bootCorrs`, `boot.wc`, `boot.ndim`, `TEFI`, `EGA`, `EGA.type`, `type`, `iter`.
- `$stability` holds `dimension.stability` and `item.stability` already computed (the bootEGA call runs `itemStability` internally).

### 3.5 `EGAnet::itemStability`

Formals: `itemStability(bootega.obj, IS.plot = TRUE, structure = NULL, ...)`.

- Called on the `bootEGA` result as the design says. Pass `IS.plot = FALSE` (default is `TRUE`).
- Result (class `itemStability`) names: `membership`, `item.stability`, `plot`.
  - `$membership$empirical`: `EGA.community` vector. `$membership$bootstrap`: matrix (iterations x items). `$membership$structure`: same as `empirical` when `structure = NULL`.
  - **Per-item stability: `$item.stability$empirical.dimensions`**, a named numeric vector (names = item IDs), proportion 0 to 1 of bootstrap samples in which the item stayed in its empirical community. Probe values: `1.00` for most items, `0.95` for `item_006`, `0.85` for `item_008`.
  - `$item.stability$all.dimensions`: numeric matrix (items x dimensions), proportion of replications in each dimension.
  - `$plot`: a `ggplot` object; it is large and must not be serialized or logged.
- Confirmed identical: `itemStability(boot, IS.plot = FALSE)$item.stability$empirical.dimensions` equals `boot$stability$item.stability$item.stability$empirical.dimensions`. The task brief mentioned `$item.stability$item.stability`; that path is correct only when starting from `boot$stability` (where `item.stability` is the whole `itemStability` object), not from the return value of `itemStability()`.
- With `structure = NULL`, stability is measured against the **empirical** EGA structure found inside `bootEGA`, not against the request's `intended_dimensions`.

### 3.6 lavaan (0.6.21)

- `lavaan::cfa(model, data, ordered = <colnames>, estimator = "WLSMV", std.lv = TRUE)` ran with 0 warnings; `lavInspect(fit, "converged")` returned `TRUE`.
- `lavInspect(fit, "options")$estimator` is reported as **`"DWLS"`**, not `"WLSMV"`; the scaled test is `scaled.shifted` (attribute on `fitMeasures()`). WLSMV is DWLS estimation plus robust standard errors and a mean-and-variance adjusted test. Anything that logs `estimator` must take it from the wrapper's own choice (`"WLSMV"` / `"ML"`), not from `lavInspect`.
- `fitMeasures(fit)` returns 70 named values. All nine names the design uses exist: `chisq`, `df`, `pvalue`, `cfi`, `tli`, `rmsea`, `rmsea.ci.lower`, `rmsea.ci.upper`, `srmr`. The result has class `lavaan.vector` with names; `unname()` gives plain numbers.
- **For WLSMV the unsuffixed names are the unscaled ("naive") statistics.** Probe values (6 items, 200 persons, probe-only): `chisq = 4.713`, `df = 8`, **`pvalue = NA`**, `cfi = 1.000`, `tli = 1.020`, `rmsea = 0.000`, `rmsea.ci.upper = 0.055`, `srmr = 0.035`. The scaled and robust versions that `summary()` reports exist under suffixes: `chisq.scaled = 7.409`, `df.scaled = 8`, `pvalue.scaled = 0.493`, `cfi.scaled`, `tli.scaled`, `rmsea.scaled`, `cfi.robust = 0.995`, `tli.robust = 0.991`, `rmsea.robust = 0.025`, `rmsea.ci.lower.robust`, `rmsea.ci.upper.robust`. `srmr` has no suffixed variant used here.
- `standardizedSolution(fit)`: class `lavaan.data.frame`, columns `lhs`, `op`, `rhs`, `est.std`, `se`, `z`, `pvalue`, `ci.lower`, `ci.upper`. The field name `est.std` matches the design.
  - Loadings: rows with `op == "=~"`, `lhs` = factor name, `rhs` = item ID.
  - Factor correlations: rows with `op == "~~"` and `lhs != rhs`. In the ordinal fit there were also rows with `op` `"|"` (thresholds), `"~*~"` (scaling factors) and `"~1"` (intercepts); they are excluded by filtering on `op`. Only `F1 ~~ F2` matched.

### 3.7 Type notes for the JSON layer (jsonlite 2.0.0)

- `fromJSON()`: `1` becomes `integer`, `1.0` and `0.25` become `numeric`.
- `toJSON()` default for numeric `NA` is the **string** `"NA"` (`{"pvalue":"NA"}`). With `na = "null"` it is `null`. The CFA `pvalue` is `NA` for WLSMV unsuffixed output, so the response writer needs `na = "null"` (or the field must be handled), or clients will receive a string in a numeric field.

## 4. Differences from design.md (action list)

### 4.1 Comparison table

| #  | design.md name / assumption                                              | Probe result                                                                                           | Verdict    |
| -- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------ | ---------- |
| 1  | `UVA(cut.off = ...)`                                                     | exists                                                                                                 | match      |
| 2  | `UVA(uva.method = ...)` from config                                      | exists; only `"mbr"` / `"ejp"` valid (case-insensitive); `"wTO"` invalid; EJP unusable with the fixed args (3.2) | **differs** (valid values, EJP) |
| 3  | `UVA(reduce = TRUE)`                                                     | exists                                                                                                 | match      |
| 4  | `UVA(reduce.method = "remove")`                                          | exists, works for MBR. For EJP it must also be passed when `reduce = FALSE`                            | match for MBR; **differs** for EJP |
| 5  | `UVA(auto = TRUE)`                                                       | exists; works for MBR + `remove`; EJP + `remove` hangs on an interactive prompt                        | match for MBR; **differs** for EJP |
| 6  | UVA reduced data                                                         | `$reduced_data` (matrix, item columns); **absent (NULL) when nothing is redundant**                    | match; **differs** in the no-redundancy case |
| 7  | UVA wTO score "recorded" for each removed item                           | no per-item field; `$wto$pairwise` (`node_i`, `node_j`, `wto`) only; per-item value must be derived    | **differs** |
| 8  | Removed items = "present before but absent from the reduced data"        | correct; `$keep_remove` is inconsistent and must not be used (4.5)                                     | match      |
| 9  | UVA repeated until a pass removes nothing                                | a second pass on the reduced data removed more items (retained 5 -> 3 in the probe)                    | match (loop is needed) |
| 10 | `EGA(model = ..., algorithm = ...)`                                      | exist                                                                                                  | match      |
| 11 | `EGA` seeded "where supported"                                           | `EGA` has no `seed` argument                                                                           | **differs** (not supported) |
| 12 | `ega$wc` membership, usable with `igraph::compare`                       | `ega$wc`, named double, class `EGA.community`; `compare()` works as is                                 | match      |
| 13 | `bootEGA(model, algorithm, iter, type, seed, verbose)`                   | all exist                                                                                              | match      |
| 14 | `bootEGA(seed = config$random_seed)` directly from JSON                  | integer seed errors; needs `as.numeric()`                                                              | **differs** |
| 15 | `bootEGA(iter = config$boot_iterations)`                                 | integer accepted                                                                                       | match      |
| 16 | `bootEGA(type = ...)` (`"resampling"` for AI-GENIE)                      | `"parametric"` and `"resampling"` both valid                                                           | match      |
| 17 | `bootEGA` fixed args: `verbose = FALSE` only                             | also needs `plot.itemStability = FALSE` and an explicit `ncores`; `EGA` needs `plot.EGA = FALSE`       | **differs** (extra args) |
| 18 | `EGAnet::itemStability` called on the bootEGA result                     | works; call with `IS.plot = FALSE`                                                                     | match      |
| 19 | per-item stability field                                                 | `itemStability(boot)$item.stability$empirical.dimensions` (named numeric)                              | match (path now fixed) |
| 20 | `lavaan::cfa(..., ordered, estimator = "WLSMV", std.lv = TRUE)`          | works, converged, no warnings                                                                          | match      |
| 21 | `lavInspect(fit, "converged")`                                           | works                                                                                                  | match      |
| 22 | `estimator` logged as `WLSMV`                                            | `lavInspect(fit, "options")$estimator` returns `"DWLS"`                                                | **differs** (log from wrapper choice) |
| 23 | `fitMeasures(fit, c("chisq", ..., "srmr"))` names                        | all nine names exist                                                                                   | match      |
| 24 | those unsuffixed names are the reported fit indices (WLSMV)              | unsuffixed = unscaled; `pvalue` is `NA`; scaled/robust values are under `.scaled` / `.robust`          | **differs** (needs owner decision) |
| 25 | `standardizedSolution()` rows `op == "=~"`, `est.std`                    | columns `lhs`, `op`, `rhs`, `est.std`, ...                                                             | match      |
| 26 | factor correlations: `op == "~~"`, `lhs != rhs`, factor names on both sides | matches; ordinal fits add `\|`, `~*~`, `~1` rows, excluded by `op`                                  | match      |
| 27 | JSON response with numeric fields                                        | `toJSON()` writes numeric `NA` as `"NA"` by default                                                    | **differs** (use `na = "null"`) |

### 4.2 Documentation cross-check (EGAnet 2.4.1 installed help, lavaan tutorial via Context7)

EGAnet is not indexed in Context7 (the library search returned unrelated packages). The cross-check used the help pages installed with
EGAnet 2.4.1 (`tools::Rd2txt()` on `help("UVA")`, `help("bootEGA")`, `help("itemStability")`), which are the same text as the CRAN reference manual
for that version. lavaan was checked through Context7 (`/websites/lavaan_ugent_be_tutorial`).

| Topic                                             | Documentation says                                                                                  | Probe shows                                                                    | Disagreement |
| ------------------------------------------------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ | ------------ |
| `UVA` argument names                              | `uva.method`, `cut.off`, `reduce`, `reduce.method`, `auto`                                          | same                                                                           | none         |
| `uva.method` values                               | `"MBR"` or `"EJP"`                                                                                  | same; case-insensitive                                                         | none         |
| `UVA` `auto` with `reduce.method = "remove"`      | "automated decision process" defined for `remove`, no mention of a limitation                       | MBR: automated. EJP: prints "not available" and prompts                        | **yes** (EJP) |
| `UVA` return value                                | no `Value` section in the help page                                                                 | structure documented only by the probe (3.1)                                   | docs silent  |
| `UVA` `cut.off`                                   | numeric, between 0 and 1                                                                            | integer `0L` accepted                                                          | none relevant |
| `EGA` / `bootEGA` `model`, `algorithm` defaults   | `model` defaults to `"glasso"`, `algorithm` to `"walktrap"` (text); formals show `c("BGGM", "glasso", "TMFG")` / `c("leiden", ...)` | formals as printed                              | **yes** (text vs formals). Always pass both explicitly (design already does). |
| `bootEGA` `seed`                                  | "Numeric (length = 1)"                                                                              | integer fails, double works                                                    | **yes** (integer is not accepted although it is numeric in R) |
| `bootEGA` `type`                                  | `"parametric"` or `"resampling"`                                                                    | same                                                                           | none         |
| `bootEGA` `ncores`                                | defaults to half the cores                                                                          | formals show no default; call works without it                                 | minor        |
| `itemStability` value                             | `membership`, `item.stability` (`empirical.dimensions`, `all.dimensions`), `plot`                   | same                                                                           | none         |
| lavaan `ordered =` selects WLSMV                  | automatically selects WLSMV (DWLS with robust SE and adjusted test)                                 | `estimator` reported as `DWLS`; scaled test `scaled.shifted`                   | none (same thing, different label) |
| lavaan `standardizedSolution()` columns           | standardized estimates with SE, z, p, CI                                                            | `est.std`, `se`, `z`, `pvalue`, `ci.lower`, `ci.upper`                         | none         |

The lavaan documentation consulted does not describe which `fitMeasures()` names are scaled; the probe values in 3.6 are the evidence.

### 4.3 Implications per later task

- **Task 2 (checkpoint):** rows 2, 4, 5, 7, 11, 14, 17, 22, 24 and 27 differ from the design. Rows 2 and 24 need an owner decision (4.6); the others are wrapper details with a determined fix.
- **Task 4.2 (`ega/uva.R`):**
  - Compute removed items as `setdiff(colnames(data), colnames(result$reduced_data))`.
  - If `result$reduced_data` is NULL (no redundancy), treat every item as retained and stop the loop. Without this guard, `colnames(NULL)` makes `setdiff()` return all items.
  - Do not read `$keep_remove`.
  - Per-item wTO scores are derived from `$wto$pairwise`, see 4.4.
  - Keep `auto = TRUE`; use `reduce.method = "remove"` and `verbose = FALSE`.
  - Convert `reduced_data` back with `colnames` intact before the next pass; the second pass is meaningful (5 -> 3 items in the probe).
  - Refuse `uva_method` other than `"mbr"` with a 400 until the owner decides how to handle EJP (4.6).
- **Task 4.3 (`ega/bootega.R`):** `seed = as.numeric(config$random_seed)`; also pass `ncores = 1` (or a documented setting), `plot.itemStability = FALSE`, `verbose = FALSE`; read stability from `itemStability(boot, IS.plot = FALSE)$item.stability$empirical.dimensions`; do not keep or serialize the `plot` element.
- **Task 4.4 (`ega/pipeline.R`):** call `EGA(..., plot.EGA = FALSE, verbose = FALSE)`; use `ega$wc` directly with `igraph::compare()`; keep NA handling. `EGA` has no `seed`; if seeding is wanted for `leiden` / `louvain`, that is a design decision (for example `set.seed(as.numeric(random_seed))` before the call), and the probe did not show it to be needed.
- **Task 5.2/5.3 (CFA):** log `estimator` from the wrapper's own choice. `extract_fit_indices` for the ordinal case needs the owner decision in 4.6 before it is written.
- **Task 6 (`api.R`) and 3.1 (logger):** serialize with `toJSON(..., auto_unbox = TRUE, na = "null")`.
- **Task 8 (fixtures):** unaffected, but the EGA fixture config must use `"mbr"` for `uva_method`.

### 4.4 Per-item wTO score (design gap, not an EGAnet field)

design.md says each removed item's wTO score is recorded; EGAnet provides only pairwise values. The probe output prints `max(wto over pairs involving the removed item)` as one derivation (for example `item_002 0.529`, `item_003 0.384`, `item_005 0.455`, `item_006 0.398`, `item_009 0.269`, `item_010 0.257`, `item_012 0.306`). Whether this, or the wTO with the item it was redundant with, should be reported in `removed_wto_scores` is a reporting choice. A single UVA pass can also remove items whose pairwise partners were removed in the same pass. I did not decide this; the 4.2 wrapper needs one definition, documented in the response and logs.

### 4.5 `keep_remove` is inconsistent with `reduced_data`

In the probe: `reduced_data` retained `item_001 item_004 item_007 item_008 item_011` (5 items), while `keep_remove$keep` was `item_001 item_004 item_006 item_007 item_009 item_011` (6 items, including `item_006` and `item_009`) and `keep_remove$remove` listed `item_005` and `item_012` twice, and also contained `item_006` and `item_009`. The probe prints `keep_remove consistent with reduced_data? FALSE`. Use `$reduced_data` only.

### 4.6 Questions for the owner (not decided here)

1. **`uva_method` values and EJP.** Valid values are `"mbr"` and `"ejp"`. `"ejp"` cannot run non-interactively with `reduce.method = "remove"` and `auto = TRUE` (the process hangs) and returns a different result structure. Options: accept only `"mbr"` (reject `"ejp"` with 400); or design a separate EJP path. The service must not allow a request that can hang the process.
2. **Which fit-index variants for `ordinal = true`.** With WLSMV, the unsuffixed `chisq`, `df`, `cfi`, `tli`, `rmsea` are unscaled, and `pvalue` is `NA`. The scaled/robust values (`chisq.scaled`, `pvalue.scaled`, `cfi.robust`, `tli.robust`, `rmsea.robust` and its CI) are the ones `lavaan` reports in `summary()`. design.md and `03-statistics-contract.md` return the unsuffixed names. Options: return the `.robust` / `.scaled` values under the same output keys for ordinal fits; or return unsuffixed as designed and accept `null` for `pvalue`. These are not psychometric thresholds, but they change what the report shows for the technical rehearsal, so the choice is the owner's.
3. **Per-item wTO score definition** (4.4).

## 5. Reproduce

```bash
Rscript r-service/probe.R > r-service/probe_output.txt 2>&1
```

Run it with stdin closed in automation (for example `< /dev/null`) so an unexpected interactive UVA prompt cannot block it.
Rerun after any EGAnet or lavaan upgrade, and update this file and the table in 4.1.
