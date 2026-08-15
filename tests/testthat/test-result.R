test_that("data frame and summary methods are stable", {
  executable <- local_fake_datum()
  local_protocol_output("check-unchanged.json", 0L)
  result <- datum_check(executable = executable, quiet = TRUE)
  records <- as.data.frame(result)
  expect_s3_class(records, "data.frame")
  expect_named(records, c("id", "status", "message", "lock_fingerprint",
                          "remote_fingerprint", "warnings"))

  result_summary <- summary(result)
  expect_s3_class(result_summary, "summary.datur_check_result")
  expect_identical(result_summary$status, "unchanged")
  expect_identical(result_summary$counts[["total"]], 1L)
})

test_that("check result printing is concise and informative", {
  executable <- local_fake_datum()
  local_protocol_output("check-changed-fail.json", 1L)
  result <- datum_check(executable = executable, quiet = TRUE)
  output <- testthat::capture_messages(print(result))
  expect_true(any(grepl("1 change", output)))
  expect_true(any(grepl("fail[[:space:]]+local_config", output)))
  expect_false(any(grepl("fingerprint", output)))

  summary_output <- testthat::capture_messages(print(summary(result)))
  expect_true(any(grepl("Changed", summary_output)))
})

test_that("empty successful results are distinct from parse failure", {
  executable <- local_fake_datum()
  local_json_output('{"results":[]}')
  result <- datum_check(executable = executable, quiet = TRUE)
  expect_false(result$changed)
  expect_identical(nrow(result$records), 0L)
  expect_identical(result$summary[["total"]], 0L)
})
