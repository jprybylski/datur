build_init_args <- function(config, id, type, source, target, desc, policy,
                            ignore, empty) {
  args <- c("--no-color", "--config", config, "init")
  if (empty) {
    args <- c(args, "--empty")
  } else {
    args <- c(
      args, "--id", id, "--type", type, "--source", source,
      "--target", target
    )
    if (!is.null(desc)) args <- c(args, "--desc", desc)
  }
  if (!is.null(policy)) args <- c(args, "--policy", policy)
  if (!is.null(ignore)) args <- c(args, paste0("--ignore=", tolower(ignore)))
  args
}

#' Initialize a datum configuration
#'
#' Runs datum 1.6.0's non-interactive `init` command. Create either an empty,
#' schema-valid configuration or a configuration containing one HTTP or file
#' dataset. Existing configuration files are never overwritten by datum.
#'
#' @param id,type,source,target Initial dataset values. All four are required
#'   unless `empty = TRUE`.
#' @param desc Optional initial dataset description.
#' @param policy Optional default `"fail"`, `"update"`, or `"log"` policy.
#' @param ignore Optional default logical VCS-ignore setting. `NULL` leaves the
#'   flag unspecified.
#' @param empty Create a configuration with no datasets.
#' @param config Configuration path.
#' @inheritParams datum_run
#' @return Invisibly, a `datur_process_result`.
#' @export
#' @examples
#' \dontrun{
#' datum_init(empty = TRUE)
#' datum_init(
#'   id = "rates", type = "http",
#'   source = "https://example.test/rates.csv",
#'   target = "data/rates.csv"
#' )
#' }
datum_init <- function(id = NULL, type = NULL, source = NULL, target = NULL,
                       desc = NULL, policy = NULL, ignore = NULL, empty = FALSE,
                       config = ".data.yaml", executable = NULL, wd = NULL,
                       timeout = getOption("datur.timeout", 300)) {
  call <- sys.call()
  empty <- validate_flag(empty, "empty", call)
  config <- validate_string(config, "config", call = call)
  wd <- validate_wd(wd, call)
  timeout <- validate_timeout(timeout, call)
  desc <- validate_string(desc, "desc", allow_null = TRUE, call = call)
  policy <- validate_string(policy, "policy", allow_null = TRUE, call = call)
  if (!is.null(policy) && !policy %in% c("fail", "update", "log")) {
    abort_input("policy", "Must be one of 'fail', 'update', or 'log'.", call)
  }
  if (!is.null(ignore)) ignore <- validate_flag(ignore, "ignore", call)

  dataset <- list(id = id, type = type, source = source, target = target)
  supplied <- !vapply(dataset, is.null, logical(1))
  if (empty) {
    if (any(supplied) || !is.null(desc)) {
      abort_input("empty", "Cannot be combined with dataset-specific arguments.", call)
    }
  } else {
    if (!all(supplied)) {
      abort_input(
        "id", "Supply id, type, source, and target unless empty is TRUE.", call
      )
    }
    dataset <- lapply(names(dataset), function(name) {
      validate_string(dataset[[name]], name, call = call)
    })
    names(dataset) <- c("id", "type", "source", "target")
    if (!grepl("^[a-zA-Z0-9_-]+$", dataset$id)) {
      abort_input("id", "Must contain only letters, numbers, underscores, or hyphens.", call)
    }
    if (!dataset$type %in% c("http", "file")) {
      abort_input("type", "Must be 'http' or 'file'.", call)
    }
  }

  path <- datum_path(executable = executable)
  version <- require_datum_feature(path, datum_init_api_version, "datum_init()", call)
  process <- run_process(
    args = build_init_args(
      config, dataset$id, dataset$type, dataset$source, dataset$target,
      desc, policy, ignore, empty
    ),
    executable = path, stdin = NULL, wd = wd, env = character(),
    timeout = timeout, echo = FALSE, include_version = FALSE, call = call
  )
  process$datum_version <- version
  if (process$status != 0L) {
    abort_cli("{.file datum} could not initialize the configuration.", process, call = call)
  }
  invisible(process)
}
