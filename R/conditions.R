abort_datur <- function(message, class, ..., call = NULL, .envir = parent.frame()) {
  fields <- list(...)
  formatted <- tryCatch(
    cli::format_message(message, .envir = .envir),
    error = function(error) {
      plain <- gsub("\\{\\.[^ ]+ ([^}]*)\\}", "\\1", unname(message))
      paste(plain, collapse = "\n")
    }
  )
  condition <- c(
    list(message = formatted, call = call),
    fields
  )
  class(condition) <- c(class, "datur_error", "error", "condition")
  stop(condition)
}

abort_input <- function(argument, problem, call = NULL) {
  abort_datur(
    c(
      "Invalid {.arg {argument}}.",
      "x" = problem
    ),
    "datur_input_error",
    argument = argument,
    problem = problem,
    call = call,
    .envir = environment()
  )
}

abort_not_found <- function(attempted, call = NULL) {
  abort_datur(
    c(
      "Could not find a usable {.file datum} executable.",
      "i" = "Set {.arg executable}, option {.code datur.datum_path}, or environment variable {.envvar DATUM_PATH}.",
      "i" = "Installation: https://jprybylski.github.io/datum/installation.html"
    ),
    "datur_not_found",
    attempted = attempted,
    call = call,
    .envir = environment()
  )
}

abort_version <- function(message, raw = NULL, parsed = NULL, call = NULL) {
  abort_datur(
    message,
    "datur_version_error",
    raw_version = raw,
    parsed_version = parsed,
    call = call,
    .envir = parent.frame()
  )
}

abort_cli <- function(message, process, result = NULL, call = NULL) {
  abort_datur(
    message,
    "datur_cli_error",
    process = process,
    result = result,
    call = call,
    .envir = parent.frame()
  )
}

abort_protocol <- function(message, process, schema = NULL, call = NULL) {
  abort_datur(
    message,
    "datur_protocol_error",
    process = process,
    schema = schema,
    supported_schema_versions = supported_schema_versions,
    call = call,
    .envir = parent.frame()
  )
}

abort_timeout <- function(timeout, process, call = NULL) {
  abort_datur(
    c(
      "The {.file datum} process exceeded its {timeout}-second deadline.",
      "i" = "Increase {.arg timeout} or inspect the partial process result."
    ),
    "datur_timeout",
    timeout = timeout,
    process = process,
    partial_result = process,
    call = call,
    .envir = environment()
  )
}
