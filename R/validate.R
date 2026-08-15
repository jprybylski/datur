validate_flag <- function(value, argument, call = NULL) {
  if (!is.logical(value) || length(value) != 1L || is.na(value)) {
    abort_input(argument, "Must be one non-missing logical value.", call)
  }
  value
}

validate_string <- function(value, argument, allow_null = FALSE, call = NULL) {
  if (allow_null && is.null(value)) {
    return(NULL)
  }
  if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value)) {
    abort_input(argument, "Must be one non-empty character value.", call)
  }
  value
}

validate_timeout <- function(timeout, call = NULL) {
  if (!is.numeric(timeout) || length(timeout) != 1L || is.na(timeout) ||
      !is.finite(timeout) || timeout <= 0) {
    abort_input("timeout", "Must be one positive, finite number of seconds.", call)
  }
  as.numeric(timeout)
}

validate_wd <- function(wd, call = NULL) {
  wd <- validate_string(wd, "wd", allow_null = TRUE, call = call)
  if (!is.null(wd) && !dir.exists(wd)) {
    abort_input("wd", sprintf("Directory does not exist: %s.", wd), call)
  }
  wd
}

validate_args <- function(args, call = NULL) {
  if (!is.character(args) || anyNA(args)) {
    abort_input("args", "Must be a character vector without missing values.", call)
  }
  args
}

validate_stdin <- function(stdin, call = NULL) {
  if (is.null(stdin)) {
    return(NULL)
  }
  if (is.raw(stdin)) {
    return(stdin)
  }
  if (!is.character(stdin) || length(stdin) != 1L || is.na(stdin)) {
    abort_input("stdin", "Must be NULL, one character value, or a raw vector.", call)
  }
  stdin
}

validate_env <- function(env, call = NULL) {
  if (!is.character(env) || anyNA(env)) {
    abort_input("env", "Must be a character vector without missing values.", call)
  }
  if (length(env) && (is.null(names(env)) || any(!nzchar(names(env))))) {
    abort_input("env", "Must be named, with one environment variable per element.", call)
  }
  env
}

validate_concurrency <- function(concurrency, call = NULL) {
  if (!is.numeric(concurrency) || length(concurrency) != 1L ||
      is.na(concurrency) || !is.finite(concurrency) || concurrency < 1 ||
      concurrency != as.integer(concurrency)) {
    abort_input("concurrency", "Must be one positive integer.", call)
  }
  as.integer(concurrency)
}

validate_ids <- function(ids, argument = "ids", allow_empty = FALSE, call = NULL) {
  if (!is.character(ids) || anyNA(ids) || any(!nzchar(ids)) ||
      (!allow_empty && !length(ids))) {
    abort_input(argument, "Must be a character vector of non-empty identifiers.", call)
  }
  if (anyDuplicated(ids)) {
    abort_input(argument, "Must not contain duplicate identifiers.", call)
  }
  ids
}

datur_is_interactive <- function() interactive()
