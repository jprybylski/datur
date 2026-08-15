is_executable_file <- function(path) {
  if (!file.exists(path) || dir.exists(path)) {
    return(FALSE)
  }
  if (.Platform$OS.type == "windows") {
    return(TRUE)
  }
  file.access(path, mode = 1L) == 0L
}

normalize_executable <- function(path) {
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

resolve_candidate <- function(value, source, attempted, call) {
  if (is.null(value) || !length(value) || is.na(value) || !nzchar(value)) {
    return(NULL)
  }
  attempted[[source]] <- value
  if (!is_executable_file(value)) {
    abort_not_found(attempted, call)
  }
  normalize_executable(value)
}

#' Locate the datum executable
#'
#' Resolves `datum` in this order: `executable`, option
#' `datur.datum_path`, environment variable `DATUM_PATH`, then `PATH`.
#' Successful automatic `PATH` lookups are cached for the R session.
#'
#' @param executable Optional explicit executable path.
#' @param refresh Re-run automatic executable discovery.
#'
#' @return A normalized executable path.
#' @export
#' @examples
#' datum_available()
datum_path <- function(executable = NULL, refresh = FALSE) {
  call <- sys.call()
  refresh <- validate_flag(refresh, "refresh", call)
  attempted <- list()

  if (!is.null(executable)) {
    executable <- validate_string(executable, "executable", call = call)
    return(resolve_candidate(executable, "argument", attempted, call))
  }

  option_path <- getOption("datur.datum_path")
  if (!is.null(option_path)) {
    option_path <- validate_string(option_path, "getOption(\"datur.datum_path\")", call = call)
    return(resolve_candidate(option_path, "option", attempted, call))
  }

  environment_path <- Sys.getenv("DATUM_PATH", unset = "")
  if (nzchar(environment_path)) {
    return(resolve_candidate(environment_path, "environment", attempted, call))
  }

  if (!refresh && !is.null(.datur_state$path) && is_executable_file(.datur_state$path)) {
    return(.datur_state$path)
  }

  discovered <- unname(Sys.which("datum"))
  attempted$PATH <- if (nzchar(discovered)) discovered else "datum"
  if (!nzchar(discovered) || !is_executable_file(discovered)) {
    abort_not_found(attempted, call)
  }
  .datur_state$path <- normalize_executable(discovered)
  .datur_state$path
}

#' Test whether datum is available
#'
#' @inheritParams datum_path
#' @return One non-missing logical value.
#' @export
#' @examples
#' datum_available()
datum_available <- function(executable = NULL) {
  tryCatch(
    {
      datum_path(executable = executable)
      TRUE
    },
    datur_error = function(error) FALSE
  )
}

