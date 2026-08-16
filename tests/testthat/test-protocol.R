test_that("empty and malformed output raise protocol errors", {
  executable <- local_fake_datum()
  local_json_output("", 0L)
  expect_error(datum_check(executable = executable, quiet = TRUE),
               class = "datur_protocol_error")

  local_json_output("{not json", 0L)
  expect_error(datum_check(executable = executable, quiet = TRUE),
               class = "datur_protocol_error")
})

test_that("unknown statuses are rejected", {
  executable <- local_fake_datum()
  local_json_output('{"results":[{"id":"demo","status":"mystery"}]}')
  error <- expect_error(datum_check(executable = executable, quiet = TRUE),
                        class = "datur_protocol_error")
  expect_identical(error$schema, 1L)
})

test_that("additive fields are tolerated", {
  executable <- local_fake_datum()
  local_json_output(paste0(
    '{"future_top":true,"results":[',
    '{"id":"demo","status":"ok","future_record":{"x":1}}]}'
  ))
  result <- datum_check(executable = executable, quiet = TRUE)
  expect_false(result$changed)
  expect_true(result$raw$future_top)
})

test_that("known changed statuses normalize correctly", {
  executable <- local_fake_datum()
  for (status in c("updated", "stale", "fail")) {
    local_json_output(sprintf('{"results":[{"id":"demo","status":"%s"}]}', status),
                      if (status == "fail") 1L else 0L)
    result <- datum_check(executable = executable, quiet = TRUE)
    expect_true(result$changed, info = status)
  }
})

test_that("warning status derives change from fingerprints", {
  executable <- local_fake_datum()
  local_json_output(paste0(
    '{"results":[{"id":"demo","status":"warn",',
    '"lock_fingerprint":"old","remote_fingerprint":"new",',
    '"warnings":["fallback used"]}]}'
  ), 1L)
  result <- datum_check(executable = executable, quiet = TRUE)
  expect_true(result$changed)
  expect_identical(result$records$warnings[[1L]], "fallback used")
})

test_that("lock write failures raise with normalized results", {
  executable <- local_fake_datum()
  local_json_output(paste0(
    '{"results":[{"id":"demo","status":"ok"}],',
    '"lock_write_error":"permission denied"}'
  ), 1L)
  error <- expect_error(datum_check(executable = executable, quiet = TRUE),
                        class = "datur_cli_error")
  expect_s3_class(error$result, "datur_check_result")
})

test_that("invalid record fields are rejected", {
  executable <- local_fake_datum()
  local_json_output('{"results":[{"id":1,"status":"ok"}]}')
  expect_error(datum_check(executable = executable, quiet = TRUE),
               class = "datur_protocol_error")

  local_json_output('{"results":{}}')
  expect_error(datum_check(executable = executable, quiet = TRUE),
               class = "datur_protocol_error")
})

test_that("protocol rejects malformed document and record shapes", {
  executable <- local_fake_datum()
  invalid <- c(
    "[]",
    '{}',
    '{"results":["not an object"]}',
    '{"results":[{"id":"x","status":"ok","warnings":"warning"}]}',
    '{"results":[{"id":"x","status":"ok","warnings":[null]}]}'
  )
  for (json in invalid) {
    local_json_output(json)
    expect_error(
      datum_check(executable = executable, quiet = TRUE),
      class = "datur_protocol_error",
      info = json
    )
  }
})

test_that("protocol distinguishes operational and unexpected exit failures", {
  executable <- local_fake_datum()
  local_json_output('{"results":[{"id":"only","status":"error"}]}', 1L)
  error <- expect_error(
    datum_check(executable = executable, quiet = TRUE),
    class = "datur_cli_error"
  )
  expect_identical(error$result$status, "error")

  local_json_output('{"results":[{"id":"ok","status":"ok"}]}', 2L)
  error <- expect_error(
    datum_check(executable = executable, quiet = TRUE),
    class = "datur_cli_error"
  )
  expect_s3_class(error$result, "datur_check_result")
})
