new_process_result <- function(command, args, status, stdout, stderr, started_at,
                               duration, datum_version = NULL, timed_out = FALSE) {
  structure(
    list(
      command = command,
      args = args,
      status = as.integer(status),
      stdout = stdout,
      stderr = stderr,
      started_at = started_at,
      duration = as.numeric(duration),
      datum_version = datum_version,
      timed_out = isTRUE(timed_out)
    ),
    class = "datur_process_result"
  )
}

merge_process_env <- function(env) {
  inherited <- Sys.getenv()
  if (length(env)) {
    inherited[names(env)] <- unname(env)
  }
  inherited
}

normalize_process_output <- function(output) {
  gsub("\r\n", "\n", output, fixed = TRUE)
}

run_process <- function(args, executable, stdin, wd, env, timeout, echo,
                        include_version = TRUE, call = NULL) {
  redaction <- redact_process_inputs(args, env)
  stdin_file <- NULL
  if (!is.null(stdin)) {
    stdin_file <- tempfile("datur-stdin-")
    connection <- file(stdin_file, open = "wb")
    on.exit({
      if (inherits(connection, "connection")) {
        close(connection)
      }
      unlink(stdin_file)
    }, add = TRUE)
    writeBin(if (is.raw(stdin)) stdin else charToRaw(stdin), connection)
    close(connection)
    connection <- NULL
  }
  started_at <- Sys.time()
  raw <- processx::run(
    command = executable,
    args = args,
    error_on_status = FALSE,
    wd = wd,
    echo = echo,
    echo_cmd = FALSE,
    timeout = timeout,
    stdin = stdin_file,
    env = merge_process_env(env),
    cleanup_tree = FALSE,
    windows_hide_window = TRUE
  )
  duration <- as.numeric(difftime(Sys.time(), started_at, units = "secs"))
  version <- NULL
  if (include_version) {
    version <- tryCatch(
      datum_version(executable = executable),
      datur_error = function(error) NULL
    )
  }
  result <- new_process_result(
    command = executable,
    args = redaction$args,
    status = raw$status,
    stdout = redact_values(normalize_process_output(raw$stdout), redaction$secrets),
    stderr = redact_values(normalize_process_output(raw$stderr), redaction$secrets),
    started_at = started_at,
    duration = duration,
    datum_version = version,
    timed_out = raw$timeout
  )
  if (isTRUE(raw$timeout)) {
    abort_timeout(timeout, result, call)
  }
  result
}

#' Run datum with a raw argument vector
#'
#' This is the intentional low-level escape hatch. Arguments are passed
#' directly to the executable, one vector element per process argument, without
#' invoking a shell.
#'
#' @param args Character vector of process arguments.
#' @param stdin Optional standard input accepted by [processx::run()].
#' @param executable Optional explicit executable path.
#' @param wd Optional child-process working directory.
#' @param env Named character vector of environment variables to add or replace.
#' @param timeout Positive finite timeout in seconds.
#' @param echo Forward process output while it runs.
#' @param error_on_status Raise `datur_cli_error` for a nonzero exit status.
#'
#' @return A `datur_process_result` object.
#' @export
#' @examples
#' if (datum_available()) {
#'   datum_run("--version")
#' }
datum_run <- function(args, stdin = NULL, executable = NULL, wd = NULL,
                      env = character(), timeout = getOption("datur.timeout", 300),
                      echo = FALSE, error_on_status = TRUE) {
  call <- sys.call()
  args <- validate_args(args, call)
  stdin <- validate_stdin(stdin, call)
  wd <- validate_wd(wd, call)
  env <- validate_env(env, call)
  timeout <- validate_timeout(timeout, call)
  echo <- validate_flag(echo, "echo", call)
  error_on_status <- validate_flag(error_on_status, "error_on_status", call)
  path <- datum_path(executable = executable)

  result <- run_process(
    args = args,
    executable = path,
    stdin = stdin,
    wd = wd,
    env = env,
    timeout = timeout,
    echo = echo,
    include_version = !identical(args, "--version"),
    call = call
  )
  if (error_on_status && result$status != 0L) {
    abort_cli(
      c(
        "{.file datum} exited with status {result$status}.",
        "i" = "Inspect the attached process result for captured output."
      ),
      result,
      call = call
    )
  }
  result
}

#' @export
print.datur_process_result <- function(x, ...) {
  cli::cli_text("{.file {basename(x$command)}}: status {x$status} ({format_duration(x$duration)})")
  invisible(x)
}

format_duration <- function(seconds) {
  if (seconds < 1) {
    return(sprintf("%.0fms", seconds * 1000))
  }
  sprintf("%.1fs", seconds)
}
