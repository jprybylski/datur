protocol_scalar_character <- function(value, field, process, required = FALSE, call = NULL) {
  if (is.null(value) && !required) {
    return(NA_character_)
  }
  if (!is.character(value) || length(value) != 1L || is.na(value) ||
      (required && !nzchar(value))) {
    abort_protocol(
      "Machine-readable output has an invalid {.field {field}} field.",
      process,
      schema = 1L,
      call = call
    )
  }
  value
}

protocol_warnings <- function(value, process, call = NULL) {
  if (is.null(value)) {
    return(character())
  }
  if (!is.list(value) || any(!vapply(value, is.character, logical(1))) ||
      any(lengths(value) != 1L) || anyNA(unlist(value, use.names = FALSE))) {
    abort_protocol(
      "Machine-readable output has an invalid {.field warnings} field.",
      process,
      schema = 1L,
      call = call
    )
  }
  unlist(value, use.names = FALSE)
}

normalize_protocol_record <- function(record, process, call = NULL) {
  if (!is.list(record) || is.null(names(record))) {
    abort_protocol(
      "Machine-readable output contains a result that is not a JSON object.",
      process,
      schema = 1L,
      call = call
    )
  }
  id <- protocol_scalar_character(record$id, "id", process, required = TRUE, call = call)
  status <- protocol_scalar_character(
    record$status, "status", process, required = TRUE, call = call
  )
  if (!status %in% supported_check_statuses) {
    abort_protocol(
      "Machine-readable output contains unknown status {.val {status}} for target {.val {id}}.",
      process,
      schema = 1L,
      call = call
    )
  }
  list(
    id = id,
    status = status,
    message = protocol_scalar_character(record$message, "message", process, call = call),
    lock_fingerprint = protocol_scalar_character(
      record$lock_fingerprint, "lock_fingerprint", process, call = call
    ),
    remote_fingerprint = protocol_scalar_character(
      record$remote_fingerprint, "remote_fingerprint", process, call = call
    ),
    warnings = protocol_warnings(record$warnings, process, call)
  )
}

records_data_frame <- function(records) {
  if (!length(records)) {
    return(data.frame(
      id = character(),
      status = character(),
      message = character(),
      lock_fingerprint = character(),
      remote_fingerprint = character(),
      warnings = I(list()),
      stringsAsFactors = FALSE
    ))
  }
  data.frame(
    id = vapply(records, `[[`, character(1), "id"),
    status = vapply(records, `[[`, character(1), "status"),
    message = vapply(records, `[[`, character(1), "message"),
    lock_fingerprint = vapply(records, `[[`, character(1), "lock_fingerprint"),
    remote_fingerprint = vapply(records, `[[`, character(1), "remote_fingerprint"),
    warnings = I(lapply(records, `[[`, "warnings")),
    stringsAsFactors = FALSE
  )
}

parse_check_result <- function(process, call = NULL) {
  if (!nzchar(trimws(process$stdout))) {
    abort_protocol(
      "{.file datum} returned empty machine-readable output.",
      process,
      schema = NULL,
      call = call
    )
  }
  raw <- tryCatch(
    jsonlite::fromJSON(process$stdout, simplifyVector = FALSE),
    error = function(error) {
      abort_protocol(
        c(
          "Could not parse machine-readable output from {.file datum}.",
          "x" = conditionMessage(error)
        ),
        process,
        schema = NULL,
        call = call
      )
    }
  )
  if (!is.list(raw) || is.null(names(raw))) {
    abort_protocol(
      "Machine-readable output must be a top-level JSON object.",
      process,
      schema = NULL,
      call = call
    )
  }

  if (!is.null(raw$error)) {
    message <- protocol_scalar_character(raw$error, "error", process, TRUE, call)
    abort_cli(
      c(
        "{.file datum} could not start the check.",
        "x" = message
      ),
      process,
      call = call
    )
  }
  if (is.null(raw$results) || !is.list(raw$results) || !is.null(names(raw$results))) {
    abort_protocol(
      "Machine-readable output must contain a {.field results} array.",
      process,
      schema = 1L,
      call = call
    )
  }
  normalized <- lapply(raw$results, normalize_protocol_record, process = process, call = call)
  records <- records_data_frame(normalized)
  result <- new_check_result(records, raw, process, schema_version = 1L)

  lock_error <- raw$lock_write_error
  if (!is.null(lock_error)) {
    lock_error <- protocol_scalar_character(
      lock_error, "lock_write_error", process, required = TRUE, call = call
    )
  }
  failed <- any(records$status == "error") || !is.null(lock_error)
  if (failed) {
    detail <- if (!is.null(lock_error)) lock_error else "One or more targets failed."
    abort_cli(
      c(
        "{.file datum} returned usable results with operational failures.",
        "x" = detail,
        "i" = "The partial check result is attached to this condition."
      ),
      process,
      result = result,
      call = call
    )
  }
  if (!process$status %in% c(0L, 1L)) {
    abort_cli(
      "{.file datum} returned unexpected status {process$status} for a results document.",
      process,
      result = result,
      call = call
    )
  }
  result
}

