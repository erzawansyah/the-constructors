# R Service Package Versions

Versions recorded with `packageVersion()` after running `Rscript r-service/install_packages.R`
(R 4.6.1, Windows, CRAN mirror `https://cloud.r-project.org`). The README task uses these as the
minimum versions.

| Package  | Version | Used for                                          |
| -------- | ------- | ------------------------------------------------- |
| plumber  | 1.3.3   | HTTP JSON API                                     |
| EGAnet   | 2.4.1   | `EGA`, `UVA`, `bootEGA`, `itemStability`          |
| lavaan   | 0.6.21  | `cfa`, `fitMeasures`                              |
| igraph   | 2.3.3   | `compare(method = "nmi")`                         |
| jsonlite | 2.0.0   | JSON parsing and serialization                    |
| uuid     | 1.2.2   | request IDs                                       |
| MASS     | 7.3.65  | `mvrnorm`, used only by `tests/generate_fixtures.R` |

Notes:

- MASS ships with R as a recommended package (installed under the R library, not the user library).
- plumber 1.3.3 was built under R 4.6.2 and prints a harmless warning on R 4.6.1.
