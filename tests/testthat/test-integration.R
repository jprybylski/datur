test_that("real datum integration is opt-in", {
  skip_if_not(identical(tolower(Sys.getenv("DATUR_INTEGRATION_TESTS")), "true"))

  executable <- Sys.getenv("DATUM_PATH", unset = "")
  project <- Sys.getenv("DATUR_INTEGRATION_PROJECT", unset = "")
  skip_if(!nzchar(executable), "DATUM_PATH is required for integration tests")
  skip_if(!nzchar(project), "DATUR_INTEGRATION_PROJECT is required for integration tests")

  expect_true(datum_available(executable))
  expect_s3_class(datum_version(executable), "package_version")
  result <- datum_check(executable = executable, wd = project, quiet = TRUE)
  expect_s3_class(result, "datur_check_result")
  expect_s3_class(as.data.frame(result), "data.frame")
})

