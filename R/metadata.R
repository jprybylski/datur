require_datum_feature <- function(path, minimum, feature, call = NULL) {
  version <- datum_version(executable = path)
  if (version < minimum) {
    abort_version(
      "{.code {feature}} requires {.file datum} {as.character(minimum)} or newer; found {as.character(version)}.",
      parsed = version,
      call = call
    )
  }
  version
}

parse_json_document <- function(process, label, call = NULL) {
  if (process$status != 0L) {
    abort_cli(
      "{.file datum} could not return {label}.",
      process,
      call = call
    )
  }
  tryCatch(
    jsonlite::fromJSON(process$stdout, simplifyVector = FALSE),
    error = function(error) {
      abort_protocol(
        c(
          "Could not parse {label} from {.file datum}.",
          "x" = conditionMessage(error)
        ),
        process,
        call = call
      )
    }
  )
}

#' Read datum's configuration schema
#'
#' Returns the exact JSON Schema embedded in the installed `datum` executable.
#' This requires `datum` 1.4.0 or newer.
#'
#' @inheritParams datum_run
#' @return A named list containing the parsed JSON Schema.
#' @export
#' @examples
#' if (datum_available() && datum_version() >= "1.4.0") {
#'   schema <- datum_schema()
#'   schema$title
#' }
datum_schema <- function(executable = NULL, wd = NULL,
                         timeout = getOption("datur.timeout", 300)) {
  call <- sys.call()
  wd <- validate_wd(wd, call)
  timeout <- validate_timeout(timeout, call)
  path <- datum_path(executable = executable)
  require_datum_feature(path, datum_config_api_version, "datum_schema()", call)
  process <- run_process(
    args = "schema", executable = path, stdin = NULL, wd = wd,
    env = character(), timeout = timeout, echo = FALSE,
    include_version = FALSE, call = call
  )
  schema <- parse_json_document(process, "the configuration schema", call)
  if (!is.list(schema) || is.null(names(schema)) || is.null(schema$properties) ||
      is.null(schema$required)) {
    abort_protocol("{.file datum} returned an invalid configuration schema.",
                   process, call = call)
  }
  schema
}

normalize_type_spec <- function(spec, process, call = NULL) {
  if (!is.list(spec) || !is.character(spec$type) || length(spec$type) != 1L ||
      !is.list(spec$fields)) {
    abort_protocol("{.file datum} returned an invalid source type specification.",
                   process, call = call)
  }
  fields <- lapply(spec$fields, function(field) {
    if (!is.list(field) || !is.character(field$name) || length(field$name) != 1L ||
        !is.logical(field$required) || length(field$required) != 1L ||
        is.na(field$required)) {
      abort_protocol("{.file datum} returned an invalid source field specification.",
                     process, call = call)
    }
    list(
      name = field$name,
      required = field$required,
      description = if (is.character(field$description) && length(field$description) == 1L) {
        field$description
      } else {
        ""
      }
    )
  })
  list(
    type = spec$type,
    description = if (is.character(spec$description) && length(spec$description) == 1L) {
      spec$description
    } else {
      ""
    },
    fields = fields
  )
}

#' List datum source types and their fields
#'
#' With no `types`, lists every source type included in the installed build.
#' Supplying names returns the required and optional fields for those types.
#' This requires `datum` 1.4.0 or newer.
#'
#' @param types Optional character vector of source type names.
#' @inheritParams datum_run
#' @return A named list of source type specifications, indexed by type.
#' @export
#' @examples
#' if (datum_available() && datum_version() >= "1.4.0") {
#'   datum_types("http")
#' }
datum_types <- function(types = NULL, executable = NULL, wd = NULL,
                        timeout = getOption("datur.timeout", 300)) {
  call <- sys.call()
  if (is.null(types)) {
    types <- character()
  }
  types <- validate_ids(types, "types", allow_empty = TRUE, call = call)
  wd <- validate_wd(wd, call)
  timeout <- validate_timeout(timeout, call)
  path <- datum_path(executable = executable)
  require_datum_feature(path, datum_config_api_version, "datum_types()", call)
  process <- run_process(
    args = c("--json", "--no-color", "types", types), executable = path,
    stdin = NULL, wd = wd, env = character(), timeout = timeout, echo = FALSE,
    include_version = FALSE, call = call
  )
  raw <- parse_json_document(process, "source type requirements", call)
  if (!is.list(raw) || !is.list(raw$types)) {
    abort_protocol("{.file datum} returned invalid source type requirements.",
                   process, call = call)
  }
  specs <- lapply(raw$types, normalize_type_spec, process = process, call = call)
  names(specs) <- vapply(specs, `[[`, character(1), "type")
  if (anyDuplicated(names(specs))) {
    abort_protocol("{.file datum} returned duplicate source type specifications.",
                   process, call = call)
  }
  specs
}
