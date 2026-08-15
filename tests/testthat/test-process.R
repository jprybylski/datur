test_that("raw arguments are passed without shell interpolation", {
  executable <- local_fake_datum()
  result <- datum_run(c("raw", "a b", "; echo injected", "$(false)"), executable = executable)
  expect_s3_class(result, "datur_process_result")
  expect_identical(result$stdout, "a b|; echo injected|$(false)")
  expect_identical(result$status, 0L)
  expect_equal(as.character(result$datum_version), "1.3.0")
})

test_that("process output uses platform-independent newlines", {
  expect_identical(normalize_process_output("one\r\ntwo\r\n"), "one\ntwo\n")
  expect_identical(normalize_process_output("one\ntwo\n"), "one\ntwo\n")
})

test_that("stdin, environment, and working directory are isolated", {
  executable <- local_fake_datum()
  result <- datum_run(c("raw", "stdin"), stdin = "hello\nworld", executable = executable)
  expect_identical(result$stdout, "hello\nworld")

  result <- datum_run(c("raw", "env", "DATUR_TEST_VALUE"), executable = executable,
                      env = c(DATUR_TEST_VALUE = "custom"))
  expect_identical(result$stdout, "custom")

  wd <- withr::local_tempdir()
  old <- getwd()
  result <- datum_run(c("raw", "wd"), executable = executable, wd = wd)
  expect_identical(normalizePath(result$stdout), normalizePath(wd))
  expect_identical(getwd(), old)
})

test_that("nonzero statuses can return or raise", {
  executable <- local_fake_datum()
  withr::local_envvar(c(FAKE_DATUM_STATUS = "9", FAKE_DATUM_STDERR = "problem"))
  result <- datum_run("raw", executable = executable, error_on_status = FALSE)
  expect_identical(result$status, 9L)
  expect_identical(result$stderr, "problem")

  error <- expect_error(datum_run("raw", executable = executable), class = "datur_cli_error")
  expect_s3_class(error$process, "datur_process_result")
  expect_identical(error$process$status, 9L)
})

test_that("timeouts terminate the process and preserve a partial result", {
  executable <- local_fake_datum()
  withr::local_envvar(FAKE_DATUM_SLEEP = "1")
  error <- expect_error(
    datum_run("raw", executable = executable, timeout = 0.05),
    class = "datur_timeout"
  )
  expect_equal(error$timeout, 0.05)
  expect_true(error$process$timed_out)
})

test_that("sensitive arguments, environment, output, and URLs are redacted", {
  executable <- local_fake_datum()
  result <- datum_run(
    c("raw", "--token", "s3cr3t", "https://user:pass@example.com/data"),
    executable = executable,
    env = c(API_KEY = "env-secret")
  )
  expect_identical(result$args[[3L]], "<redacted>")
  expect_false(grepl("s3cr3t|env-secret|user:pass", result$stdout))
  expect_match(result$stdout, "<redacted>", fixed = TRUE)
})

test_that("process printing is concise", {
  executable <- local_fake_datum()
  result <- datum_run("raw", executable = executable)
  output <- testthat::capture_messages(print(result))
  expect_match(output, "status 0")
  expect_false(any(grepl("stdout|stderr", output)))
})

test_that("process inputs are validated before launch", {
  executable <- local_fake_datum()
  expect_error(datum_run("raw", executable = executable, timeout = 0), class = "datur_input_error")
  expect_error(datum_run("raw", executable = executable, env = "x"), class = "datur_input_error")
  expect_error(datum_run("raw", executable = executable, wd = "missing"), class = "datur_input_error")
})
