test_that("unchanged checks return stable structured results", {
  executable <- local_fake_datum()
  local_protocol_output("check-unchanged.json", 0L)
  result <- datum_check(executable = executable, quiet = TRUE)
  expect_s3_class(result, "datur_check_result")
  expect_false(result$changed)
  expect_identical(result$status, "unchanged")
  expect_identical(result$schema_version, 1L)
  expect_identical(result$summary[["total"]], 1L)
  expect_identical(result$records$status, "ok")
})

test_that("changed fail-policy output is data despite exit status 1", {
  executable <- local_fake_datum()
  local_protocol_output("check-changed-fail.json", 1L)
  result <- datum_check(executable = executable, quiet = TRUE)
  expect_true(result$changed)
  expect_identical(result$status, "changed")
  expect_identical(result$records$status, "fail")
  expect_identical(result$process$status, 1L)
})

test_that("partial failures preserve usable records in the condition", {
  executable <- local_fake_datum()
  local_protocol_output("check-partial-error.json", 1L)
  error <- expect_error(datum_check(executable = executable, quiet = TRUE),
                        class = "datur_cli_error")
  expect_s3_class(error$result, "datur_check_result")
  expect_identical(error$result$status, "partial_failure")
  expect_identical(error$result$records$id, c("available", "unavailable"))
})

test_that("top-level CLI errors preserve the process result", {
  executable <- local_fake_datum()
  local_protocol_output("check-config-error.json", 2L)
  error <- expect_error(datum_check(executable = executable, quiet = TRUE),
                        class = "datur_cli_error")
  expect_s3_class(error$process, "datur_process_result")
  expect_null(error$result)
})

test_that("check builds flags before the subcommand", {
  executable <- local_fake_datum()
  local_protocol_output("check-unchanged.json", 0L)
  args_file <- withr::local_tempfile()
  withr::local_envvar(FAKE_DATUM_ARGS_FILE = args_file)
  datum_check(config = "custom config.yaml", lock = "custom lock.yaml",
              timeout = 12.5, concurrency = 3, executable = executable, quiet = TRUE)
  args <- readLines(args_file)
  expect_identical(tail(args, 1L), "check")
  expect_true(all(c("--json", "--no-color", "--config", "custom config.yaml",
                    "--lock", "custom lock.yaml", "--timeout", "12.5s",
                    "--concurrency", "3") %in% args))
})

test_that("unsupported target selection and dots fail before launch", {
  executable <- local_fake_datum()
  expect_error(datum_check(targets = "one", executable = executable),
               class = "datur_input_error")
  expect_error(datum_check(executable = executable, speculative = TRUE),
               class = "datur_input_error")
})

test_that("concurrency and quiet are validated", {
  executable <- local_fake_datum()
  expect_error(datum_check(executable = executable, concurrency = 0),
               class = "datur_input_error")
  expect_error(datum_check(executable = executable, quiet = NA),
               class = "datur_input_error")
})

