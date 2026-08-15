test_that("release versions are parsed and retain raw text", {
  executable <- local_fake_datum(version = "v1.3.0")
  version <- datum_version(executable)
  expect_s3_class(version, "package_version")
  expect_equal(as.character(version), "1.3.0")
  expect_identical(attr(version, "raw"), "datum v1.3.0\n")
})

test_that("version lookup is cached unless refreshed", {
  executable <- local_fake_datum(version = "v1.3.0")
  expect_equal(as.character(datum_version(executable)), "1.3.0")
  Sys.setenv(FAKE_DATUM_VERSION = "v1.2.1")
  expect_equal(as.character(datum_version(executable)), "1.3.0")
  expect_equal(as.character(datum_version(executable, refresh = TRUE)), "1.2.1")
})

test_that("old, development, and new major versions are rejected", {
  old <- local_fake_datum(version = "v1.2.0", name = "old")
  dev <- local_fake_datum(version = "dev", name = "dev")
  future <- local_fake_datum(version = "v2.0.0", name = "future")
  expect_error(datum_version(old), class = "datur_version_error")
  expect_error(datum_version(dev), class = "datur_version_error")
  expect_error(datum_version(future), class = "datur_version_error")
})

test_that("failed version commands raise typed errors", {
  executable <- local_fake_datum()
  withr::local_envvar(FAKE_DATUM_VERSION_STATUS = "7")
  error <- expect_error(datum_version(executable, refresh = TRUE), class = "datur_version_error")
  expect_identical(error$raw_version, "datum v1.3.0\n")
})
