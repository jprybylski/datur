test_that("schema and type metadata are parsed from datum 1.4", {
  executable <- local_fake_datum(version = "v1.4.0")
  local_config_metadata()

  schema <- datum_schema(executable = executable)
  expect_identical(schema$title, "Datum Configuration")

  types <- datum_types(c("http", "file"), executable = executable)
  expect_named(types, c("file", "http"))
  expect_true(types$http$fields[[2L]]$required)
  expect_identical(types$http$fields[[2L]]$name, "url")
})

test_that("metadata functions require datum 1.4", {
  executable <- local_fake_datum(version = "v1.3.0")
  expect_error(datum_schema(executable = executable), class = "datur_version_error")
  expect_error(datum_types(executable = executable), class = "datur_version_error")
})

test_that("metadata rejects command and protocol failures", {
  executable <- local_fake_datum(version = "v1.4.0")
  local_config_metadata()
  withr::local_envvar(FAKE_DATUM_STATUS = "2")
  expect_error(datum_schema(executable = executable), class = "datur_cli_error")

  executable <- local_fake_datum(version = "v1.4.0")
  bad <- withr::local_tempfile()
  writeLines("not json", bad)
  withr::local_envvar(c(FAKE_DATUM_SCHEMA_FILE = bad, FAKE_DATUM_STATUS = "0"))
  expect_error(datum_schema(executable = executable), class = "datur_protocol_error")

  local_json_output('{"wrong": []}')
  withr::local_envvar(FAKE_DATUM_TYPES_FILE = Sys.getenv("FAKE_DATUM_OUTPUT_FILE"))
  expect_error(datum_types(executable = executable), class = "datur_protocol_error")

  wrong_schema <- local_json_output('{"wrong": []}')
  withr::local_envvar(FAKE_DATUM_SCHEMA_FILE = wrong_schema)
  expect_error(datum_schema(executable = executable), class = "datur_protocol_error")
})

test_that("source constructors use live field requirements", {
  executable <- local_fake_datum(version = "v1.4.0")
  local_config_metadata()
  source <- datum_source("http", url = "https://example.test/data.csv",
                         executable = executable)
  expect_identical(source$type, "http")
  expect_error(datum_source("http", executable = executable),
               class = "datur_input_error")
  expect_error(datum_source("http", url = "x", extra = "y", executable = executable),
               class = "datur_input_error")
  expect_error(datum_source("unknown", value = "x", executable = executable),
               class = "datur_input_error")
})

test_that("malformed type specifications are rejected", {
  executable <- local_fake_datum(version = "v1.4.0")
  cases <- c(
    '{"types":[{"type":1,"fields":[]}]}',
    '{"types":[{"type":"file","fields":[{"name":1,"required":true}]}]}',
    '{"types":[{"type":"file","fields":[{"name":"type","required":"yes"}]}]}',
    '{"types":[{"type":"file","fields":[]},{"type":"file","fields":[]}]}'
  )
  for (json in cases) {
    path <- local_json_output(json)
    withr::local_envvar(FAKE_DATUM_TYPES_FILE = path)
    expect_error(datum_types(executable = executable), class = "datur_protocol_error")
  }
})
