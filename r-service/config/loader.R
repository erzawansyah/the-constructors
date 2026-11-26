# config/loader.R
#
# Request config validation for the R Statistics Service.
# Requires utils/conditions.R (validation_error) to be sourced first.
#
# The service holds NO defaults for any psychometric threshold or procedure
# parameter. Every value arrives in the request `config`, which the client
# loads from app-config/psychometric-procedure.yaml. A missing or null value
# is rejected with a validation_error (HTTP 400) before any computation.
#
# Public API:
#
#   EGA_REQUIRED_CONFIG_FIELDS
#     The eight config fields required by /ega.
#
#   validate_config(config, required_fields = EGA_REQUIRED_CONFIG_FIELDS)
#     Checks fields in order. For the first failing field signals:
#       validation_error("config.<field> is missing")
#       validation_error("config.<field> is null; owner decision required")
#     After every required field passes, and if "uva_method" is required,
#     checks that tolower(uva_method) == "mbr". "ejp" (any case) and any other
#     value signal a validation_error before any UVA computation can run.
#     Returns `config` invisibly on success.
#
# Null vs missing: jsonlite::parse_json(simplifyVector = TRUE) keeps a key
# whose JSON value is null as list(<key> = NULL), so the key is present in
# names(config) while config[[key]] is NULL. A field is therefore "missing"
# when its name is absent and "null" when the name is present but the value
# is NULL, length 0, or a single NA.

EGA_REQUIRED_CONFIG_FIELDS <- c(
  "wto_threshold",
  "stability_threshold",
  "boot_iterations",
  "network_method",
  "community_algorithm",
  "random_seed",
  "uva_method",
  "bootstrap_type"
)

is_null_config_value <- function(value) {
  is.null(value) ||
    length(value) == 0L ||
    (length(value) == 1L && is.atomic(value) && is.na(value))
}

validate_uva_method <- function(uva_method) {
  value <- if (is.character(uva_method) && length(uva_method) == 1L) {
    uva_method
  } else {
    paste(format(uva_method), collapse = ", ")
  }
  normalized <- tolower(value)

  if (identical(normalized, "mbr")) {
    return(invisible(TRUE))
  }
  if (identical(normalized, "ejp")) {
    stop(validation_error(paste0(
      "config.uva_method must be \"mbr\" (case-insensitive); \"ejp\" is not ",
      "supported because UVA with uva.method \"ejp\", reduce.method \"remove\" ",
      "and auto TRUE requires interactive input and would hang a ",
      "non-interactive process"
    )))
  }
  stop(validation_error(paste0(
    "config.uva_method must be \"mbr\" (case-insensitive); got \"", value, "\""
  )))
}

validate_config <- function(config, required_fields = EGA_REQUIRED_CONFIG_FIELDS) {
  if (is.null(config)) {
    stop(validation_error("config is missing"))
  }
  if (!is.list(config) || is.data.frame(config)) {
    stop(validation_error("config must be a JSON object"))
  }

  present <- names(config)
  if (is.null(present)) present <- character(0)

  for (field in required_fields) {
    if (!(field %in% present)) {
      stop(validation_error(paste0("config.", field, " is missing")))
    }
    if (is_null_config_value(config[[field]])) {
      stop(validation_error(
        paste0("config.", field, " is null; owner decision required")
      ))
    }
  }

  if ("uva_method" %in% required_fields) {
    validate_uva_method(config[["uva_method"]])
  }

  invisible(config)
}
