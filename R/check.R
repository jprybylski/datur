format_cli_timeout <- function(timeout) {
  paste0(format(timeout, scientific = FALSE, trim = TRUE), "s")
}

build_check_args <- function(config, lock, timeout, concurrency) {
  args <- c(
    "--json",
    "--no-color",
    "--timeout", format_cli_timeout(timeout),
    "--concurrency", as.character(concurrency)
  )
  if (!is.null(config)) {
    args <- c(args, "--config", config)
  }
  if (!is.null(lock)) {
    args <- c(args, "--lock", lock)
  }
  c(args, "check")
}

#' Check configured data sources for updates
#'
#' Runs `datum --json check`, validates its implicit protocol v1 response, and
#' returns one normalized record per configured dataset. Changed data is a
#' successful result even when `datum` uses exit status 1 for a `fail` policy.
#'
#' `datum check` always updates its lockfile timestamps and may replace target
#' files when a dataset uses the `update` policy. It does not modify the datum
#' configuration file.
#'
#' @param targets Reserved for target selection. `datum` 1.x checks all targets,
#'   so this must currently be `NULL`.
#' @param config Optional datum configuration path.
#' @param lock Optional datum lockfile path.
#' @param ... Reserved for documented high-level options; currently empty.
#' @param executable Optional explicit executable path.
#' @param wd Optional child-process working directory.
#' @param timeout Positive finite timeout in seconds.
#' @param concurrency Number of datasets processed concurrently. Defaults to 1
#'   because `datum` documents a shared-target race at higher concurrency.
#' @param quiet Suppress automatic interactive printing. Explicit `print()`
#'   always works.
#'
#' @return Invisibly, a `datur_check_result` object.
#' @export
#' @examples
#' if (datum_available()) {
#'   result <- datum_check(quiet = TRUE)
#'   result$changed
#'   as.data.frame(result)
#' }
datum_check <- function(targets = NULL, config = NULL, lock = NULL, ...,
                        executable = NULL, wd = NULL,
                        timeout = getOption("datur.timeout", 300),
                        concurrency = 1L,
                        quiet = getOption("datur.quiet", FALSE)) {
  call <- sys.call()
  dots <- list(...)
  if (length(dots)) {
    abort_input("...", "No additional high-level check options are supported yet.", call)
  }
  if (!is.null(targets)) {
    abort_input(
      "targets",
      "datum 1.x cannot select targets for check; use NULL to check all configured datasets.",
      call
    )
  }
  config <- validate_string(config, "config", allow_null = TRUE, call = call)
  lock <- validate_string(lock, "lock", allow_null = TRUE, call = call)
  wd <- validate_wd(wd, call)
  timeout <- validate_timeout(timeout, call)
  concurrency <- validate_concurrency(concurrency, call)
  quiet <- validate_flag(quiet, "quiet", call)
  path <- datum_path(executable = executable)
  version <- datum_version(executable = path)

  process <- run_process(
    args = build_check_args(config, lock, timeout, concurrency),
    executable = path,
    stdin = NULL,
    wd = wd,
    env = character(),
    timeout = timeout,
    echo = FALSE,
    include_version = FALSE,
    call = call
  )
  process$datum_version <- version
  result <- parse_check_result(process, call)
  if (interactive() && !quiet) {
    print(result)
  }
  invisible(result)
}

