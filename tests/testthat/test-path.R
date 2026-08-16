test_that("explicit executable paths are normalized", {
  executable <- local_fake_datum()
  expect_identical(datum_path(executable), normalizePath(executable, winslash = "/"))
})

test_that("discovery honors option then environment", {
  option_executable <- local_fake_datum(name = "datum-option")
  environment_executable <- local_fake_datum(name = "datum-environment")
  withr::local_envvar(DATUM_PATH = environment_executable)
  withr::local_options(datur.datum_path = option_executable)
  expect_identical(datum_path(), normalizePath(option_executable, winslash = "/"))

  options(datur.datum_path = NULL)
  expect_identical(datum_path(), normalizePath(environment_executable, winslash = "/"))
})

test_that("PATH discovery works and caches success", {
  directory <- withr::local_tempdir()
  executable <- local_fake_datum(directory = directory)
  withr::local_options(datur.datum_path = NULL)
  withr::local_envvar(c(DATUM_PATH = NA, PATH = paste(directory, Sys.getenv("PATH"), sep = .Platform$path.sep)))
  state <- get(".datur_state", asNamespace("datur"))
  state$path <- NULL
  expect_identical(datum_path(refresh = TRUE), normalizePath(executable, winslash = "/"))
  expect_identical(datum_path(), normalizePath(executable, winslash = "/"))
})

test_that("missing executables are quiet through datum_available", {
  missing <- file.path(tempdir(), "definitely-not-datum")
  expect_false(datum_available(missing))
  error <- expect_error(datum_path(missing), class = "datur_not_found")
  expect_named(error$attempted, "argument")
})

test_that("paths with spaces and non-ASCII characters work", {
  directory <- file.path(tempdir(), paste0("datur space-", intToUtf8(233), "-", sample.int(1e6, 1)))
  executable <- local_fake_datum(directory = directory)
  expect_true(datum_available(executable))
  expect_equal(as.character(datum_version(executable)), "1.3.0")
})

test_that("non-executable files are rejected on Unix", {
  skip_on_os("windows")
  path <- withr::local_tempfile()
  writeLines("not executable", path)
  Sys.chmod(path, "0644")
  expect_error(datum_path(path), class = "datur_not_found")
})

test_that("empty candidates and exhausted PATH discovery are handled", {
  expect_null(datur:::resolve_candidate("", "test", list(), NULL))
  state <- get(".datur_state", asNamespace("datur"))
  state$path <- NULL
  withr::local_options(datur.datum_path = NULL)
  withr::local_envvar(c(DATUM_PATH = NA, PATH = withr::local_tempdir()))
  expect_error(datum_path(refresh = TRUE), class = "datur_not_found")
})
