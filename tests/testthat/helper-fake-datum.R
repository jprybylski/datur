fixture_path <- function(name) {
  testthat::test_path("fixtures", "datum-1.3.0", name)
}

metadata_fixture_path <- function(name) {
  testthat::test_path("fixtures", "datum-1.4.0", name)
}

write_fake_file <- function(path, lines) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, path, useBytes = TRUE)
  path
}

local_fake_datum <- function(version = "v1.3.0", directory = NULL,
                             name = "datum", .local_envir = parent.frame()) {
  if (is.null(directory)) {
    directory <- tempfile("fake-datum-")
    dir.create(directory, recursive = TRUE)
  } else {
    dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  }
  script_directory <- directory
  if (.Platform$OS.type == "windows") {
    script_directory <- tempfile("fake-datum-script-")
    dir.create(script_directory, recursive = TRUE)
  }
  script <- file.path(script_directory, "fake-datum.R")
  write_fake_file(script, c(
    "args <- commandArgs(trailingOnly = TRUE)",
    "version <- Sys.getenv('FAKE_DATUM_VERSION', 'v1.3.0')",
    "if ('--version' %in% args) { cat('datum ', version, '\\n', sep = ''); quit(status = as.integer(Sys.getenv('FAKE_DATUM_VERSION_STATUS', '0'))) }",
    "delay <- suppressWarnings(as.numeric(Sys.getenv('FAKE_DATUM_SLEEP', '0')))",
    "if (is.finite(delay) && delay > 0) Sys.sleep(delay)",
    "args_file <- Sys.getenv('FAKE_DATUM_ARGS_FILE', '')",
    "if (nzchar(args_file)) write(args, file = args_file, append = file.exists(args_file))",
    "if (length(args) && identical(args[[1L]], 'raw')) {",
    "  mode <- if (length(args) >= 2L) args[[2L]] else 'args'",
    "  if (identical(mode, 'stdin')) { cat(paste(readLines(file('stdin'), warn = FALSE), collapse = '\\n'))",
    "  } else if (identical(mode, 'env')) { cat(Sys.getenv(args[[3L]], ''))",
    "  } else if (identical(mode, 'wd')) { cat(getwd())",
    "  } else { cat(paste(args[-1L], collapse = '|')) }",
    "  stderr_text <- Sys.getenv('FAKE_DATUM_STDERR', '')",
    "  if (nzchar(stderr_text)) cat(stderr_text, file = stderr())",
    "  quit(status = as.integer(Sys.getenv('FAKE_DATUM_STATUS', '0'))) ",
    "}",
    "command <- if (length(args)) tail(args, 1L) else ''",
    "if ('schema' %in% args) command <- 'schema'",
    "if ('types' %in% args) command <- 'types'",
    "if ('audit' %in% args) command <- 'audit'",
    "if ('delete' %in% args) command <- 'delete'",
    "output_file <- switch(command,",
    "  schema = Sys.getenv('FAKE_DATUM_SCHEMA_FILE', ''),",
    "  types = Sys.getenv('FAKE_DATUM_TYPES_FILE', ''),",
    "  audit = Sys.getenv('FAKE_DATUM_AUDIT_FILE', ''),",
    "  delete = Sys.getenv('FAKE_DATUM_DELETE_FILE', ''),",
    "  Sys.getenv('FAKE_DATUM_OUTPUT_FILE', ''))",
    "if (nzchar(output_file)) { cat(readChar(output_file, file.info(output_file)$size, useBytes = TRUE))",
    "} else { cat('{\\n  \"results\": []\\n}\\n') }",
    "stderr_text <- Sys.getenv('FAKE_DATUM_STDERR', '')",
    "if (nzchar(stderr_text)) cat(stderr_text, file = stderr())",
    "quit(status = as.integer(Sys.getenv('FAKE_DATUM_STATUS', '0')))"
  ))

  rscript <- file.path(R.home("bin"), "Rscript")
  if (.Platform$OS.type == "windows") {
    executable <- file.path(directory, paste0(name, ".bat"))
    write_fake_file(executable, c(
      "@echo off",
      paste(shQuote(rscript, type = "cmd"), shQuote(script, type = "cmd"), "%*")
    ))
  } else {
    executable <- file.path(directory, name)
    write_fake_file(executable, c(
      "#!/bin/sh",
      paste("exec", shQuote(rscript), shQuote(script), '"$@"')
    ))
    Sys.chmod(executable, mode = "0755")
  }
  withr::local_envvar(FAKE_DATUM_VERSION = version, .local_envir = .local_envir)
  executable
}

local_config_metadata <- function(.local_envir = parent.frame()) {
  withr::local_envvar(
    c(
      FAKE_DATUM_SCHEMA_FILE = normalizePath(metadata_fixture_path("schema.json")),
      FAKE_DATUM_TYPES_FILE = normalizePath(metadata_fixture_path("types.json"))
    ),
    .local_envir = .local_envir
  )
}

local_protocol_output <- function(name, status = 0L, .local_envir = parent.frame()) {
  withr::local_envvar(
    c(
      FAKE_DATUM_OUTPUT_FILE = fixture_path(name),
      FAKE_DATUM_STATUS = as.character(status)
    ),
    .local_envir = .local_envir
  )
}

local_json_output <- function(text, status = 0L, .local_envir = parent.frame()) {
  path <- withr::local_tempfile(.local_envir = .local_envir)
  writeLines(text, path, useBytes = TRUE)
  withr::local_envvar(
    c(FAKE_DATUM_OUTPUT_FILE = path, FAKE_DATUM_STATUS = as.character(status)),
    .local_envir = .local_envir
  )
  path
}
