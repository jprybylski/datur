test_that("scalar, stream, environment, and id validators cover invalid shapes", {
  expect_error(datur:::validate_string(NULL, "value"), class = "datur_input_error")
  expect_null(datur:::validate_string(NULL, "value", allow_null = TRUE))

  bytes <- charToRaw("input")
  expect_identical(datur:::validate_stdin(bytes), bytes)
  expect_identical(datur:::validate_stdin("input"), "input")
  expect_error(datur:::validate_stdin(c("one", "two")), class = "datur_input_error")

  expect_identical(datur:::validate_env(c(KEY = "value")), c(KEY = "value"))
  expect_error(datur:::validate_env(NA_character_), class = "datur_input_error")
  expect_error(datur:::validate_env("value"), class = "datur_input_error")

  expect_identical(datur:::validate_ids(character(), allow_empty = TRUE), character())
  expect_error(datur:::validate_ids(c("one", "one")), class = "datur_input_error")
  expect_error(datur:::validate_ids(""), class = "datur_input_error")
})
