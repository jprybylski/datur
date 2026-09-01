test_that("init builds an empty configuration command with explicit defaults", {
  executable <- local_fake_datum(version = "v1.6.0")
  args_file <- withr::local_tempfile()
  withr::local_envvar(FAKE_DATUM_ARGS_FILE = args_file)

  result <- datum_init(
    empty = TRUE, policy = "update", ignore = FALSE,
    config = "custom.yaml", executable = executable
  )

  expect_s3_class(result, "datur_process_result")
  expect_equal(as.character(result$datum_version), "1.6.0")
  expect_identical(
    readLines(args_file),
    c("--no-color", "--config", "custom.yaml", "init", "--empty",
      "--policy", "update", "--ignore=false")
  )
})

test_that("init builds a complete initial dataset command", {
  executable <- local_fake_datum(version = "v1.6.0")
  args_file <- withr::local_tempfile()
  working <- withr::local_tempdir()
  withr::local_envvar(FAKE_DATUM_ARGS_FILE = args_file)

  datum_init(
    id = "rates", type = "http", source = "https://example.test/rates.csv",
    target = "data/rates.csv", desc = "Daily rates", policy = "log",
    ignore = TRUE, wd = working, executable = executable
  )

  expect_identical(
    readLines(args_file),
    c(
      "--no-color", "--config", ".data.yaml", "init",
      "--id", "rates", "--type", "http",
      "--source", "https://example.test/rates.csv",
      "--target", "data/rates.csv", "--desc", "Daily rates",
      "--policy", "log", "--ignore=true"
    )
  )
})

test_that("init validates modes, values, versions, and CLI failures", {
  executable <- local_fake_datum(version = "v1.6.0")
  expect_error(datum_init(empty = TRUE, id = "x", executable = executable),
               class = "datur_input_error")
  expect_error(datum_init(executable = executable), class = "datur_input_error")
  expect_error(
    datum_init(id = "bad id", type = "file", source = "x", target = "x",
               executable = executable),
    class = "datur_input_error"
  )
  expect_error(
    datum_init(id = "x", type = "git", source = "x", target = "x",
               executable = executable),
    class = "datur_input_error"
  )
  expect_error(datum_init(empty = TRUE, policy = "sometimes", executable = executable),
               class = "datur_input_error")
  expect_error(datum_init(empty = TRUE, ignore = NA, executable = executable),
               class = "datur_input_error")

  old <- local_fake_datum(version = "v1.5.0")
  expect_error(datum_init(empty = TRUE, executable = old), class = "datur_version_error")

  withr::local_envvar(c(FAKE_DATUM_VERSION = "v1.6.0", FAKE_DATUM_STATUS = "2"))
  error <- expect_error(datum_init(empty = TRUE, executable = executable),
                        class = "datur_cli_error")
  expect_identical(error$process$status, 2L)
})

test_that("init propagates process timeouts", {
  executable <- local_fake_datum(version = "v1.6.0")
  withr::local_envvar(FAKE_DATUM_SLEEP = "1")
  expect_error(
    datum_init(empty = TRUE, executable = executable, timeout = 0.05),
    class = "datur_timeout"
  )
})
