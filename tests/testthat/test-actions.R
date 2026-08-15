test_that("delete is non-interactive and puts flags before the command", {
  executable <- local_fake_datum(version = "v1.4.0")
  args_file <- withr::local_tempfile()
  withr::local_envvar(FAKE_DATUM_ARGS_FILE = args_file)
  result <- datum_delete(c("one", "two"), config = "custom.yaml",
                         lock = "custom.lock.yaml", yes = TRUE,
                         executable = executable)
  expect_s3_class(result, "datur_process_result")
  args <- readLines(args_file)
  expect_identical(tail(args, 3L), c("delete", "one", "two"))
  expect_true(match("--yes", args) < match("delete", args))
  expect_true(all(c("--config", "custom.yaml", "--lock", "custom.lock.yaml") %in% args))
})

test_that("delete validates confirmation, ids, versions, and failures", {
  executable <- local_fake_datum(version = "v1.4.0")
  expect_error(datum_delete(character(), yes = TRUE, executable = executable),
               class = "datur_input_error")
  expect_error(datum_delete("one", executable = executable), class = "datur_input_error")

  old <- local_fake_datum(version = "v1.2.1")
  expect_error(datum_delete("one", yes = TRUE, executable = old),
               class = "datur_version_error")

  withr::local_envvar(c(FAKE_DATUM_STATUS = "1", FAKE_DATUM_VERSION = "v1.4.0"))
  expect_error(datum_delete("one", yes = TRUE, executable = executable),
               class = "datur_cli_error")
})

test_that("delete can be declined before launching datum", {
  testthat::local_mocked_bindings(
    datur_is_interactive = function() TRUE,
    confirm_delete_datasets = function(ids) FALSE,
    .package = "datur"
  )
  expect_null(datum_delete("one"))
})

test_that("audit returns normalized typed records", {
  executable <- local_fake_datum(version = "v1.4.0")
  withr::local_envvar(FAKE_DATUM_AUDIT_FILE = metadata_fixture_path("audit.json"))
  result <- datum_audit(config = "custom.yaml", lock = "custom.lock.yaml",
                        executable = executable)
  expect_s3_class(result, "datur_audit_result")
  records <- as.data.frame(result)
  expect_identical(records$id, c("ready", "old"))
  expect_s3_class(records$checked_at, "POSIXct")
  expect_true(is.na(records$checked_at[[2L]]))
  expect_identical(records$in_config, c(TRUE, FALSE))
  expect_match(capture_messages(print(result)), "1 orphaned")
})

test_that("audit handles empty and malformed reports", {
  executable <- local_fake_datum(version = "v1.4.0")
  empty <- local_json_output('{"entries": []}')
  withr::local_envvar(FAKE_DATUM_AUDIT_FILE = empty)
  expect_equal(nrow(as.data.frame(datum_audit(executable = executable))), 0L)

  malformed <- local_json_output('{"entries": [{"id":"x","status":"mystery","in_config":true}]}')
  withr::local_envvar(FAKE_DATUM_AUDIT_FILE = malformed)
  expect_error(datum_audit(executable = executable), class = "datur_protocol_error")

  malformed <- local_json_output('{"entries": ["not-an-object"]}')
  withr::local_envvar(FAKE_DATUM_AUDIT_FILE = malformed)
  expect_error(datum_audit(executable = executable), class = "datur_protocol_error")

  malformed <- local_json_output('{"entries": [{"id":"x","status":"ok","in_config":true,"checked_at":"yesterday"}]}')
  withr::local_envvar(FAKE_DATUM_AUDIT_FILE = malformed)
  expect_error(datum_audit(executable = executable), class = "datur_protocol_error")

  malformed <- local_json_output('{"entries": [{"id":1,"status":"ok","in_config":true}]}')
  withr::local_envvar(FAKE_DATUM_AUDIT_FILE = malformed)
  expect_error(datum_audit(executable = executable), class = "datur_protocol_error")

  malformed <- local_json_output('{"not_entries": []}')
  withr::local_envvar(FAKE_DATUM_AUDIT_FILE = malformed)
  expect_error(datum_audit(executable = executable), class = "datur_protocol_error")
})
