new_check_result <- function(records, raw, process, schema_version = 1L) {
  changed_rows <- records$status %in% c("updated", "stale", "fail") |
    (records$status == "warn" &
       !is.na(records$lock_fingerprint) &
       !is.na(records$remote_fingerprint) &
       records$lock_fingerprint != records$remote_fingerprint)
  failed_rows <- records$status == "error"
  changed <- any(changed_rows)
  status <- if (any(failed_rows)) {
    if (any(!failed_rows)) "partial_failure" else "error"
  } else if (changed) {
    "changed"
  } else {
    "unchanged"
  }
  summary <- c(
    total = nrow(records),
    changed = sum(changed_rows),
    unchanged = sum(records$status == "ok"),
    failed = sum(failed_rows),
    skipped = sum(records$status == "deleted")
  )
  structure(
    list(
      changed = changed,
      status = status,
      summary = summary,
      records = records,
      checked_at = process$started_at + process$duration,
      duration = process$duration,
      datum_version = process$datum_version,
      schema_version = as.integer(schema_version),
      raw = raw,
      process = process
    ),
    class = "datur_check_result"
  )
}

#' @export
print.datur_check_result <- function(x, ...) {
  total <- unname(x$summary[["total"]])
  changed <- unname(x$summary[["changed"]])
  failed <- unname(x$summary[["failed"]])
  skipped <- unname(x$summary[["skipped"]])

  if (failed > 0L) {
    cli::cli_text(
      "{.strong datum check}: {failed} failure{?s} across {total} target{?s} ({format_duration(x$duration)})"
    )
  } else if (changed > 0L) {
    cli::cli_text(
      "{.strong datum check}: {changed} change{?s} across {total} target{?s} ({format_duration(x$duration)})"
    )
  } else {
    cli::cli_text(
      "{.strong datum check}: no changes across {total} target{?s} ({format_duration(x$duration)})"
    )
  }

  visible <- x$records$status %in% c("updated", "stale", "fail", "warn", "error")
  if (any(visible)) {
    for (index in which(visible)) {
      cli::cli_text("{x$records$status[[index]]}  {x$records$id[[index]]}")
    }
  }
  if (skipped > 0L) {
    cli::cli_text("skipped  {skipped} deleted target{?s}")
  }
  invisible(x)
}

#' @export
summary.datur_check_result <- function(object, ...) {
  structure(
    list(
      changed = object$changed,
      status = object$status,
      counts = object$summary,
      duration = object$duration,
      checked_at = object$checked_at,
      datum_version = object$datum_version
    ),
    class = "summary.datur_check_result"
  )
}

#' @export
print.summary.datur_check_result <- function(x, ...) {
  cli::cli_text("{.strong datum check summary}: {x$status}")
  cli::cli_dl(c(
    "Targets" = as.character(x$counts[["total"]]),
    "Changed" = as.character(x$counts[["changed"]]),
    "Failed" = as.character(x$counts[["failed"]]),
    "Duration" = format_duration(x$duration)
  ))
  invisible(x)
}

#' @export
as.data.frame.datur_check_result <- function(x, row.names = NULL, optional = FALSE, ...) {
  x$records
}

