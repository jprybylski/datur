build_common_path_args <- function(config, lock) {
  args <- c("--no-color")
  if (!is.null(config)) {
    args <- c(args, "--config", config)
  }
  if (!is.null(lock)) {
    args <- c(args, "--lock", lock)
  }
  args
}

confirm_delete_datasets <- function(ids) {
  isTRUE(utils::askYesNo(
    sprintf(
      "Delete %d dataset%s and %s tracked local files?",
      length(ids), if (length(ids) == 1L) "" else "s",
      if (length(ids) == 1L) "its" else "their"
    ),
    default = FALSE
  ))
}

#' Delete tracked local dataset files
#'
#' Runs `datum delete` for one or more configured datasets. The command removes
#' their tracked local files and marks the datasets deleted in the lockfile; it
#' does not modify `.data.yaml`. By default an interactive R session asks for
#' confirmation. Set `yes = TRUE` for non-interactive use.
#'
#' @param ids Character vector of dataset identifiers.
#' @param config Optional datum configuration path.
#' @param lock Optional datum lockfile path.
#' @param yes Skip the R confirmation prompt. Required in non-interactive use.
#' @inheritParams datum_run
#' @return Invisibly, a `datur_process_result`, or `NULL` if the user declines.
#' @export
#' @examples
#' \dontrun{
#' datum_delete("large_extract")
#' datum_delete(c("one", "two"), yes = TRUE)
#' }
datum_delete <- function(ids, config = NULL, lock = NULL, yes = FALSE,
                         executable = NULL, wd = NULL,
                         timeout = getOption("datur.timeout", 300)) {
  call <- sys.call()
  ids <- validate_ids(ids, call = call)
  config <- validate_string(config, "config", allow_null = TRUE, call = call)
  lock <- validate_string(lock, "lock", allow_null = TRUE, call = call)
  yes <- validate_flag(yes, "yes", call)
  wd <- validate_wd(wd, call)
  timeout <- validate_timeout(timeout, call)
  if (!yes) {
    if (!datur_is_interactive()) {
      abort_input("yes", "Must be TRUE when deleting datasets non-interactively.", call)
    }
    if (!confirm_delete_datasets(ids)) {
      return(invisible(NULL))
    }
  }
  path <- datum_path(executable = executable)
  require_datum_feature(path, package_version("1.3.0"), "datum_delete()", call)
  args <- c(build_common_path_args(config, lock), "--yes", "delete", ids)
  process <- run_process(
    args = args, executable = path, stdin = NULL, wd = wd,
    env = character(), timeout = timeout, echo = FALSE,
    include_version = FALSE, call = call
  )
  process$datum_version <- datum_version(executable = path)
  if (process$status != 0L) {
    abort_cli("{.file datum} could not delete every requested dataset.", process, call = call)
  }
  invisible(process)
}

audit_scalar <- function(value, type, field, process, call = NULL) {
  if (is.null(value)) {
    return(if (type == "logical") NA else NA_character_)
  }
  valid <- switch(
    type,
    character = is.character(value) && length(value) == 1L && !is.na(value),
    logical = is.logical(value) && length(value) == 1L && !is.na(value)
  )
  if (!valid) {
    abort_protocol("Audit output has an invalid {.field {field}} field.",
                   process, call = call)
  }
  value
}

audit_time <- function(value, field, process, call = NULL) {
  value <- audit_scalar(value, "character", field, process, call)
  if (is.na(value)) {
    return(as.POSIXct(NA, tz = "UTC"))
  }
  normalized <- sub("Z$", "+0000", value)
  normalized <- sub("([+-][0-9]{2}):([0-9]{2})$", "\\1\\2", normalized)
  parsed <- as.POSIXct(normalized, format = "%Y-%m-%dT%H:%M:%OS%z", tz = "UTC")
  if (is.na(parsed)) {
    abort_protocol("Audit output has an invalid {.field {field}} timestamp.",
                   process, call = call)
  }
  parsed
}

normalize_audit_entry <- function(entry, process, call = NULL) {
  if (!is.list(entry)) {
    abort_protocol("Audit output contains an entry that is not an object.",
                   process, call = call)
  }
  id <- audit_scalar(entry$id, "character", "id", process, call)
  status <- audit_scalar(entry$status, "character", "status", process, call)
  in_config <- audit_scalar(entry$in_config, "logical", "in_config", process, call)
  if (is.na(id) || !nzchar(id) || is.na(status) ||
      !status %in% supported_audit_statuses || is.na(in_config)) {
    abort_protocol("Audit output contains an invalid required field.",
                   process, call = call)
  }
  list(
    id = id, status = status, in_config = in_config,
    policy = audit_scalar(entry$policy, "character", "policy", process, call),
    target = audit_scalar(entry$target, "character", "target", process, call),
    remote_fingerprint = audit_scalar(entry$remote_fingerprint, "character", "remote_fingerprint", process, call),
    local_sha256 = audit_scalar(entry$local_sha256, "character", "local_sha256", process, call),
    checked_at = audit_time(entry$checked_at, "checked_at", process, call),
    deleted_at = audit_time(entry$deleted_at, "deleted_at", process, call),
    inaccessible_at = audit_time(entry$inaccessible_at, "inaccessible_at", process, call),
    inaccessible_error = audit_scalar(entry$inaccessible_error, "character", "inaccessible_error", process, call),
    note = audit_scalar(entry$note, "character", "note", process, call)
  )
}

audit_records <- function(entries) {
  if (!length(entries)) {
    return(data.frame(
      id = character(), status = character(), in_config = logical(),
      policy = character(), target = character(), remote_fingerprint = character(),
      local_sha256 = character(), checked_at = as.POSIXct(character(), tz = "UTC"),
      deleted_at = as.POSIXct(character(), tz = "UTC"),
      inaccessible_at = as.POSIXct(character(), tz = "UTC"),
      inaccessible_error = character(), note = character(),
      stringsAsFactors = FALSE
    ))
  }
  data.frame(
    id = vapply(entries, `[[`, character(1), "id"),
    status = vapply(entries, `[[`, character(1), "status"),
    in_config = vapply(entries, `[[`, logical(1), "in_config"),
    policy = vapply(entries, `[[`, character(1), "policy"),
    target = vapply(entries, `[[`, character(1), "target"),
    remote_fingerprint = vapply(entries, `[[`, character(1), "remote_fingerprint"),
    local_sha256 = vapply(entries, `[[`, character(1), "local_sha256"),
    checked_at = as.POSIXct(vapply(entries, function(x) as.numeric(x$checked_at), numeric(1)), origin = "1970-01-01", tz = "UTC"),
    deleted_at = as.POSIXct(vapply(entries, function(x) as.numeric(x$deleted_at), numeric(1)), origin = "1970-01-01", tz = "UTC"),
    inaccessible_at = as.POSIXct(vapply(entries, function(x) as.numeric(x$inaccessible_at), numeric(1)), origin = "1970-01-01", tz = "UTC"),
    inaccessible_error = vapply(entries, `[[`, character(1), "inaccessible_error"),
    note = vapply(entries, `[[`, character(1), "note"),
    stringsAsFactors = FALSE
  )
}

#' Audit datum configuration and lockfile state
#'
#' Runs the read-only `datum audit` command and returns one normalized row for
#' every dataset known to either `.data.yaml` or the lockfile.
#'
#' @param config Optional datum configuration path.
#' @param lock Optional datum lockfile path.
#' @inheritParams datum_run
#' @return A `datur_audit_result`. Use `as.data.frame()` for its records.
#' @export
#' @examples
#' \dontrun{
#' audit <- datum_audit()
#' subset(as.data.frame(audit), status != "ok")
#' }
datum_audit <- function(config = NULL, lock = NULL, executable = NULL, wd = NULL,
                        timeout = getOption("datur.timeout", 300)) {
  call <- sys.call()
  config <- validate_string(config, "config", allow_null = TRUE, call = call)
  lock <- validate_string(lock, "lock", allow_null = TRUE, call = call)
  wd <- validate_wd(wd, call)
  timeout <- validate_timeout(timeout, call)
  path <- datum_path(executable = executable)
  version <- require_datum_feature(path, package_version("1.3.0"), "datum_audit()", call)
  args <- c("--json", build_common_path_args(config, lock), "audit")
  process <- run_process(
    args = args, executable = path, stdin = NULL, wd = wd,
    env = character(), timeout = timeout, echo = FALSE,
    include_version = FALSE, call = call
  )
  process$datum_version <- version
  raw <- parse_json_document(process, "the audit report", call)
  if (!is.list(raw) || !is.list(raw$entries)) {
    abort_protocol("{.file datum} returned an invalid audit report.", process, call = call)
  }
  entries <- lapply(raw$entries, normalize_audit_entry, process = process, call = call)
  structure(
    list(records = audit_records(entries), raw = raw, process = process,
         datum_version = version),
    class = "datur_audit_result"
  )
}

#' @export
print.datur_audit_result <- function(x, ...) {
  counts <- table(factor(x$records$status, levels = supported_audit_statuses))
  cli::cli_text(
    "{.strong datum audit}: {nrow(x$records)} dataset{?s}; {counts[['ok']]} ok, {counts[['pending']]} pending, {counts[['deleted']]} deleted, {counts[['orphaned']]} orphaned"
  )
  invisible(x)
}

#' @export
as.data.frame.datur_audit_result <- function(x, row.names = NULL,
                                             optional = FALSE, ...) {
  x$records
}
