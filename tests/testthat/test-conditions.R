test_that("input errors expose stable fields", {
  error <- expect_error(datum_run(NA_character_), class = "datur_input_error")
  expect_s3_class(error, "datur_error")
  expect_identical(error$argument, "args")
  expect_match(error$problem, "character vector")
})

test_that("all package conditions inherit from datur_error", {
  executable <- local_fake_datum(version = "dev")
  error <- expect_error(datum_version(executable), class = "datur_version_error")
  expect_s3_class(error, "datur_error")
  expect_s3_class(error, "error")
})

