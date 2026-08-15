parse_datum_version <- function(raw, call = NULL) {
  text <- trimws(raw)
  match <- regexec("^datum[[:space:]]+v?([0-9]+\\.[0-9]+\\.[0-9]+)$", text)
  parts <- regmatches(text, match)[[1L]]
  if (length(parts) != 2L) {
    abort_version(
      c(
        "Could not interpret the {.file datum} version response.",
        "x" = "Received: {encodeString(text, quote = '\"')}"
      ),
      raw = raw,
      call = call
    )
  }
  package_version(parts[[2L]])
}

validate_datum_version <- function(version, raw, call = NULL) {
  if (version < minimum_datum_version) {
    abort_version(
      "{.file datum} {as.character(version)} is too old; version {as.character(minimum_datum_version)} or newer is required.",
      raw = raw,
      parsed = version,
      call = call
    )
  }
  major <- unclass(version)[[1L]][[1L]]
  if (major > maximum_datum_major) {
    abort_version(
      "{.file datum} {as.character(version)} uses an unreviewed major protocol version.",
      raw = raw,
      parsed = version,
      call = call
    )
  }
  attr(version, "raw") <- raw
  version
}

#' Report the installed datum version
#'
#' `datur` supports the implicit JSON protocol emitted by `datum` 1.2.1
#' through 1.x.
#'
#' @inheritParams datum_path
#' @return A `package_version` object with original output in attribute `raw`.
#' @export
#' @examples
#' if (datum_available()) {
#'   datum_version()
#' }
datum_version <- function(executable = NULL, refresh = FALSE) {
  call <- sys.call()
  refresh <- validate_flag(refresh, "refresh", call)
  path <- datum_path(executable = executable, refresh = refresh)
  key <- path
  if (!refresh && !is.null(.datur_state$versions[[key]])) {
    return(.datur_state$versions[[key]])
  }
  process <- run_process(
    args = "--version",
    executable = path,
    stdin = NULL,
    wd = NULL,
    env = character(),
    timeout = validate_timeout(getOption("datur.timeout", 300), call),
    echo = FALSE,
    include_version = FALSE,
    call = call
  )
  if (process$status != 0L) {
    abort_version(
      "{.file datum} responded to {.code --version} with status {process$status}.",
      raw = process$stdout,
      call = call
    )
  }
  version <- validate_datum_version(
    parse_datum_version(process$stdout, call),
    process$stdout,
    call
  )
  .datur_state$versions[[key]] <- version
  version
}
