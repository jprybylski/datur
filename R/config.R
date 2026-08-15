resolve_config_path <- function(config, wd, call = NULL) {
  config <- validate_string(config, "config", call = call)
  wd <- validate_wd(wd, call)
  expanded <- path.expand(config)
  if (!grepl("^(/|[A-Za-z]:[/\\\\])", expanded)) {
    expanded <- file.path(if (is.null(wd)) getwd() else wd, expanded)
  }
  normalizePath(expanded, winslash = "/", mustWork = FALSE)
}

read_config_document <- function(path, create = FALSE, call = NULL) {
  if (!file.exists(path)) {
    if (create) {
      return(list(version = 1L, datasets = list()))
    }
    abort_input("config", sprintf("File does not exist: %s.", path), call)
  }
  document <- tryCatch(
    yaml::read_yaml(path, eval.expr = FALSE),
    error = function(error) {
      abort_input("config", paste("Could not parse YAML:", conditionMessage(error)), call)
    }
  )
  if (!is.list(document) || is.null(names(document))) {
    abort_input("config", "Must contain a top-level YAML mapping.", call)
  }
  if (is.null(document$datasets)) {
    document$datasets <- list()
  }
  if (!is.list(document$datasets)) {
    abort_input("config", "The 'datasets' field must be a YAML sequence.", call)
  }
  document
}

write_config_document <- function(document, path, call = NULL) {
  directory <- dirname(path)
  if (!dir.exists(directory)) {
    dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  }
  temporary <- tempfile(paste0(".", basename(path), "-"), tmpdir = directory)
  on.exit(unlink(temporary), add = TRUE)
  tryCatch(
    yaml::write_yaml(document, temporary, indent.mapping.sequence = TRUE),
    error = function(error) {
      abort_input("config", paste("Could not serialize YAML:", conditionMessage(error)), call)
    }
  )
  backup <- NULL
  if (file.exists(path)) {
    backup <- tempfile(paste0(".", basename(path), "-backup-"), tmpdir = directory)
    if (!file.rename(path, backup)) {
      abort_input("config", sprintf("Could not prepare file for replacement: %s.", path), call)
    }
    on.exit(unlink(backup), add = TRUE)
  }
  if (!file.rename(temporary, path)) {
    if (!is.null(backup)) file.rename(backup, path)
    abort_input("config", sprintf("Could not write file: %s.", path), call)
  }
  invisible(normalizePath(path, winslash = "/", mustWork = TRUE))
}

validate_source_object <- function(source, specs, argument = "source", call = NULL) {
  if (!is.list(source) || is.null(names(source)) || any(!nzchar(names(source))) ||
      anyDuplicated(names(source))) {
    abort_input(argument, "Must be a named list with one value per source field.", call)
  }
  type <- source$type
  if (!is.character(type) || length(type) != 1L || is.na(type) || !nzchar(type)) {
    abort_input(argument, "Must contain one non-empty character field named 'type'.", call)
  }
  spec <- specs[[type]]
  if (is.null(spec)) {
    abort_input(argument, sprintf("Source type '%s' is not available in this datum build.", type), call)
  }
  fields <- vapply(spec$fields, `[[`, character(1), "name")
  required <- vapply(spec$fields, `[[`, logical(1), "required")
  missing_fields <- setdiff(fields[required], names(source))
  unknown_fields <- setdiff(names(source), fields)
  if (length(missing_fields)) {
    abort_input(argument, paste("Missing required fields:", paste(missing_fields, collapse = ", ")), call)
  }
  if (length(unknown_fields)) {
    abort_input(argument, paste("Unknown fields:", paste(unknown_fields, collapse = ", ")), call)
  }
  invalid <- vapply(source, function(value) {
    !is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value)
  }, logical(1))
  if (any(invalid)) {
    abort_input(argument, "Every source field must be one non-empty character value.", call)
  }
  source
}

schema_type_matches <- function(value, type) {
  switch(
    type,
    object = is.list(value) && !is.null(names(value)),
    array = is.list(value) && is.null(names(value)),
    string = is.character(value) && length(value) == 1L && !is.na(value),
    integer = is.numeric(value) && length(value) == 1L && !is.na(value) &&
      is.finite(value) && value == as.integer(value),
    number = is.numeric(value) && length(value) == 1L && !is.na(value) && is.finite(value),
    boolean = is.logical(value) && length(value) == 1L && !is.na(value),
    TRUE
  )
}

schema_node_errors <- function(value, node, root, path = "config") {
  if (!is.null(node[["$ref"]])) {
    pieces <- strsplit(sub("^#/", "", node[["$ref"]]), "/", fixed = TRUE)[[1L]]
    resolved <- root
    for (piece in pieces) resolved <- resolved[[piece]]
    return(schema_node_errors(value, resolved, root, path))
  }
  if (!is.null(node$oneOf)) {
    matches <- vapply(node$oneOf, function(candidate) {
      !length(schema_node_errors(value, candidate, root, path))
    }, logical(1))
    if (sum(matches) != 1L) {
      return(sprintf("%s must match exactly one allowed form", path))
    }
  }
  type <- node$type
  if (!is.null(type) && !schema_type_matches(value, type)) {
    return(sprintf("%s must be of type %s", path, type))
  }
  errors <- character()
  object_keywords <- !is.null(node$required) || !is.null(node$properties) ||
    !is.null(node$additionalProperties)
  if (identical(type, "object") || (object_keywords && is.list(value) && !is.null(names(value)))) {
    required <- unlist(node$required, use.names = FALSE)
    missing <- setdiff(required, names(value))
    if (length(missing)) {
      errors <- c(errors, sprintf("%s is missing required field(s): %s",
                                  path, paste(missing, collapse = ", ")))
    }
    properties <- node$properties
    for (name in intersect(names(value), names(properties))) {
      errors <- c(errors, schema_node_errors(value[[name]], properties[[name]], root,
                                              paste0(path, "$", name)))
    }
    if (identical(node$additionalProperties, FALSE)) {
      unknown <- setdiff(names(value), names(properties))
      if (length(unknown)) {
        errors <- c(errors, sprintf("%s has unknown field(s): %s",
                                    path, paste(unknown, collapse = ", ")))
      }
    }
  }
  if (identical(type, "array")) {
    if (!is.null(node$minItems) && length(value) < node$minItems) {
      errors <- c(errors, sprintf("%s must contain at least %d item(s)", path, node$minItems))
    }
    if (!is.null(node$items)) {
      for (index in seq_along(value)) {
        errors <- c(errors, schema_node_errors(value[[index]], node$items, root,
                                                sprintf("%s[[%d]]", path, index)))
      }
    }
  }
  if (identical(type, "string")) {
    choices <- unlist(node$enum, use.names = FALSE)
    if (length(choices) && !value %in% choices) {
      errors <- c(errors, sprintf("%s must be one of: %s", path, paste(choices, collapse = ", ")))
    }
    if (!is.null(node$pattern) && !grepl(node$pattern, value)) {
      errors <- c(errors, sprintf("%s does not match %s", path, node$pattern))
    }
    if (identical(node$format, "uri") && !grepl("^[A-Za-z][A-Za-z0-9+.-]*:", value)) {
      errors <- c(errors, sprintf("%s must be a URI", path))
    }
  }
  if (!identical(type, "string")) {
    choices <- unlist(node$enum, use.names = FALSE)
    if (length(choices) && !value %in% choices) {
      errors <- c(errors, sprintf("%s contains a value outside its enum", path))
    }
  }
  errors
}

source_objects <- function(dataset) {
  if (!is.null(dataset[["source"]])) {
    return(list(dataset[["source"]]))
  }
  dataset[["sources"]]
}

validate_dataset_object <- function(dataset, specs, schema, argument = "dataset", call = NULL) {
  if (!is.list(dataset) || is.null(names(dataset))) {
    abort_input(argument, "Must be a named list.", call)
  }
  dataset_schema <- schema$properties$datasets$items
  allowed <- names(dataset_schema$properties)
  required <- unlist(dataset_schema$required, use.names = FALSE)
  missing_fields <- setdiff(required, names(dataset))
  unknown_fields <- setdiff(names(dataset), allowed)
  if (length(missing_fields)) {
    abort_input(argument, paste("Missing required fields:", paste(missing_fields, collapse = ", ")), call)
  }
  if (length(unknown_fields)) {
    abort_input(argument, paste("Unknown fields:", paste(unknown_fields, collapse = ", ")), call)
  }
  for (field in intersect(c("id", "desc", "target"), names(dataset))) {
    validate_string(dataset[[field]], paste0(argument, "$", field), call = call)
  }
  pattern <- dataset_schema$properties$id$pattern
  if (is.character(pattern) && length(pattern) == 1L && !grepl(pattern, dataset$id)) {
    abort_input(argument, sprintf("Dataset id '%s' does not match %s.", dataset$id, pattern), call)
  }
  has_source <- !is.null(dataset[["source"]])
  has_sources <- !is.null(dataset[["sources"]])
  if (has_source == has_sources) {
    abort_input(argument, "Must contain exactly one of 'source' or 'sources'.", call)
  }
  sources <- source_objects(dataset)
  if (!is.list(sources) || !length(sources)) {
    abort_input(argument, "The 'sources' field must contain at least one source.", call)
  }
  for (index in seq_along(sources)) {
    validate_source_object(sources[[index]], specs, sprintf("%s source %d", argument, index), call)
  }
  if (!is.null(dataset$policy)) {
    policies <- unlist(dataset_schema$properties$policy$enum, use.names = FALSE)
    if (!is.character(dataset$policy) || length(dataset$policy) != 1L ||
        !dataset$policy %in% policies) {
      abort_input(argument, paste("Policy must be one of:", paste(policies, collapse = ", ")), call)
    }
  }
  dataset
}

config_source_types <- function(document) {
  unique(unlist(lapply(document$datasets, function(dataset) {
    sources <- source_objects(dataset)
    vapply(sources, function(source) {
      type <- if (is.list(source)) source[["type"]] else NULL
      if (is.character(type) && length(type) == 1L && !is.na(type)) type else ""
    }, character(1))
  }), use.names = FALSE))
}

config_dataset_ids <- function(document, call = NULL) {
  vapply(seq_along(document$datasets), function(index) {
    dataset <- document$datasets[[index]]
    id <- if (is.list(dataset)) dataset[["id"]] else NULL
    if (!is.character(id) || length(id) != 1L || is.na(id) || !nzchar(id)) {
      abort_input(
        "config",
        sprintf("Dataset %d must have one non-empty character id.", index),
        call
      )
    }
    id
  }, character(1))
}

validate_config_document <- function(document, schema, specs, call = NULL) {
  schema_errors <- schema_node_errors(document, schema, schema)
  if (length(schema_errors)) {
    abort_input("config", paste0(schema_errors[[1L]], "."), call)
  }
  required <- unlist(schema$required, use.names = FALSE)
  missing_fields <- setdiff(required, names(document))
  if (length(missing_fields)) {
    abort_input("config", paste("Missing required fields:", paste(missing_fields, collapse = ", ")), call)
  }
  if (!is.numeric(document$version) || length(document$version) != 1L ||
      !document$version %in% unlist(schema$properties$version$enum, use.names = FALSE)) {
    abort_input("config", "Has an unsupported configuration version.", call)
  }
  minimum <- schema$properties$datasets$minItems
  if (is.numeric(minimum) && length(document$datasets) < minimum) {
    abort_input("config", sprintf("Must contain at least %d dataset(s).", minimum), call)
  }
  for (index in seq_along(document$datasets)) {
    validate_dataset_object(document$datasets[[index]], specs, schema,
                            sprintf("datasets[[%d]]", index), call)
  }
  ids <- vapply(document$datasets, `[[`, character(1), "id")
  if (anyDuplicated(ids)) {
    abort_input("config", "Dataset identifiers must be unique.", call)
  }
  document
}

metadata_for_config <- function(document, executable, wd, timeout, call = NULL) {
  schema <- datum_schema(executable = executable, wd = wd, timeout = timeout)
  types <- config_source_types(document)
  types <- types[nzchar(types)]
  specs <- datum_types(types, executable = executable, wd = wd, timeout = timeout)
  list(schema = schema, specs = specs)
}

#' Build a validated datum source
#'
#' Creates the named list used by [datum_dataset_add()] and
#' [datum_dataset_update()]. Field names and required values are checked against
#' the source requirements embedded in the installed datum 1.4.0-or-newer
#' executable.
#'
#' @param type One datum source type, such as `"http"`, `"file"`, `"git"`, or
#'   `"command"`.
#' @param ... Named source fields for that type.
#' @inheritParams datum_run
#' @return A named list suitable for `source` or an element of `sources`.
#' @export
#' @examples
#' \dontrun{
#' datum_source("http", url = "https://example.test/data.csv")
#' datum_source("file", path = "upstream/data.csv")
#' }
datum_source <- function(type, ..., executable = NULL, wd = NULL,
                         timeout = getOption("datur.timeout", 300)) {
  call <- sys.call()
  type <- validate_string(type, "type", call = call)
  fields <- list(...)
  if (is.null(names(fields)) || any(!nzchar(names(fields))) || anyDuplicated(names(fields))) {
    abort_input("...", "Every source field must have a unique, non-empty name.", call)
  }
  specs <- datum_types(type, executable = executable, wd = wd, timeout = timeout)
  validate_source_object(c(list(type = type), fields), specs, call = call)
}

prepare_config_edit <- function(config, wd, executable, timeout, create, call) {
  path <- resolve_config_path(config, wd, call)
  document <- read_config_document(path, create = create, call = call)
  list(path = path, document = document)
}

#' Add a dataset to `.data.yaml`
#'
#' Adds one dataset and safely rewrites the YAML file after validating the
#' complete configuration against the schema and source requirements reported
#' by the installed datum executable.
#'
#' @param id Unique dataset identifier.
#' @param desc Human-readable description.
#' @param target Local target path.
#' @param source One source created with [datum_source()] or an equivalent named list.
#' @param sources A non-empty list of fallback sources. Supply exactly one of
#'   `source` and `sources`.
#' @param policy Optional `"fail"`, `"update"`, or `"log"` override.
#' @param config Configuration path. A missing file is created with version 1.
#' @inheritParams datum_run
#' @return Invisibly, the normalized configuration path.
#' @export
#' @examples
#' \dontrun{
#' datum_dataset_add(
#'   "rates", "Daily exchange rates", "data/rates.csv",
#'   source = datum_source("http", url = "https://example.test/rates.csv")
#' )
#' }
datum_dataset_add <- function(id, desc, target, source = NULL, sources = NULL,
                              policy = NULL, config = ".data.yaml",
                              executable = NULL, wd = NULL,
                              timeout = getOption("datur.timeout", 300)) {
  call <- sys.call()
  id <- validate_string(id, "id", call = call)
  desc <- validate_string(desc, "desc", call = call)
  target <- validate_string(target, "target", call = call)
  timeout <- validate_timeout(timeout, call)
  edit <- prepare_config_edit(config, wd, executable, timeout, TRUE, call)
  if (!is.null(source) == !is.null(sources)) {
    abort_input("source", "Supply exactly one of 'source' and 'sources'.", call)
  }
  dataset <- list(id = id, desc = desc)
  if (!is.null(source)) dataset$source <- source else dataset$sources <- sources
  dataset$target <- target
  if (!is.null(policy)) dataset$policy <- policy
  existing <- config_dataset_ids(edit$document, call)
  if (id %in% existing) {
    abort_input("id", sprintf("Dataset '%s' already exists; use datum_dataset_update().", id), call)
  }
  edit$document$datasets <- c(edit$document$datasets, list(dataset))
  metadata <- metadata_for_config(edit$document, executable, wd, timeout, call)
  validate_config_document(edit$document, metadata$schema, metadata$specs, call)
  write_config_document(edit$document, edit$path, call)
}

#' Update a dataset in `.data.yaml`
#'
#' Only supplied fields are changed. Use `policy = NULL` to remove a dataset
#' policy override. Supplying `source` replaces `sources`, and vice versa.
#'
#' @inheritParams datum_dataset_add
#' @return Invisibly, the normalized configuration path.
#' @export
#' @examples
#' \dontrun{
#' datum_dataset_update("rates", policy = "update")
#' }
datum_dataset_update <- function(id, desc, target, source, sources, policy,
                                 config = ".data.yaml", executable = NULL,
                                 wd = NULL,
                                 timeout = getOption("datur.timeout", 300)) {
  call <- sys.call()
  id <- validate_string(id, "id", call = call)
  timeout <- validate_timeout(timeout, call)
  edit <- prepare_config_edit(config, wd, executable, timeout, FALSE, call)
  ids <- config_dataset_ids(edit$document, call)
  index <- which(ids == id)
  if (length(index) != 1L) {
    abort_input("id", sprintf("Dataset '%s' was not found exactly once.", id), call)
  }
  dataset <- edit$document$datasets[[index]]
  if (!missing(desc)) dataset$desc <- desc
  if (!missing(target)) dataset$target <- target
  if (!missing(policy)) {
    dataset$policy <- policy
    if (is.null(policy)) dataset$policy <- NULL
  }
  if (!missing(source) && !missing(sources)) {
    abort_input("source", "Supply at most one of 'source' and 'sources'.", call)
  }
  if (!missing(source)) {
    dataset[["sources"]] <- NULL
    dataset[["source"]] <- source
  }
  if (!missing(sources)) {
    dataset[["source"]] <- NULL
    dataset[["sources"]] <- sources
  }
  edit$document$datasets[[index]] <- dataset
  metadata <- metadata_for_config(edit$document, executable, wd, timeout, call)
  validate_config_document(edit$document, metadata$schema, metadata$specs, call)
  write_config_document(edit$document, edit$path, call)
}

confirm_remove_data <- function(id) {
  isTRUE(utils::askYesNo(
    sprintf("Also delete the tracked local files for dataset '%s'?", id),
    default = FALSE
  ))
}

#' Remove a dataset from `.data.yaml`
#'
#' Removes a dataset definition after validating the resulting configuration.
#' In an interactive session, `delete = NULL` asks whether its tracked local
#' files should also be deleted. Deletion runs before the YAML edit so datum can
#' still resolve the dataset target. In non-interactive use, `NULL` is treated
#' as `FALSE`; set `delete` explicitly for reproducible scripts.
#'
#' @param delete Whether to run [datum_delete()] before removing the definition.
#'   `NULL` asks interactively and otherwise keeps local files.
#' @param lock Optional datum lockfile path used when `delete = TRUE`.
#' @inheritParams datum_dataset_add
#' @return Invisibly, the normalized configuration path.
#' @export
#' @examples
#' \dontrun{
#' datum_dataset_remove("rates")
#' datum_dataset_remove("rates", delete = TRUE)
#' }
datum_dataset_remove <- function(id, delete = NULL, config = ".data.yaml",
                                 lock = NULL, executable = NULL, wd = NULL,
                                 timeout = getOption("datur.timeout", 300)) {
  call <- sys.call()
  id <- validate_string(id, "id", call = call)
  if (!is.null(delete)) delete <- validate_flag(delete, "delete", call)
  lock <- validate_string(lock, "lock", allow_null = TRUE, call = call)
  timeout <- validate_timeout(timeout, call)
  edit <- prepare_config_edit(config, wd, executable, timeout, FALSE, call)
  ids <- config_dataset_ids(edit$document, call)
  index <- which(ids == id)
  if (length(index) != 1L) {
    abort_input("id", sprintf("Dataset '%s' was not found exactly once.", id), call)
  }
  if (is.null(delete)) {
    delete <- if (datur_is_interactive()) confirm_remove_data(id) else FALSE
  }
  prospective <- edit$document
  prospective$datasets <- prospective$datasets[-index]
  metadata <- metadata_for_config(prospective, executable, wd, timeout, call)
  validate_config_document(prospective, metadata$schema, metadata$specs, call)
  if (delete) {
    datum_delete(id, config = config, lock = lock, yes = TRUE,
                 executable = executable, wd = wd, timeout = timeout)
  }
  write_config_document(prospective, edit$path, call)
}
