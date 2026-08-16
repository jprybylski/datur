config_dataset <- function(id, path = paste0("upstream/", id, ".csv")) {
  list(
    id = id,
    desc = paste("Dataset", id),
    source = list(type = "file", path = path),
    target = paste0("data/", id, ".csv"),
    policy = "fail"
  )
}

write_test_config <- function(path, datasets) {
  yaml::write_yaml(list(version = 1L, defaults = list(policy = "fail"), datasets = datasets), path)
}

test_that("dataset add creates and extends valid YAML", {
  executable <- local_fake_datum(version = "v1.4.0")
  local_config_metadata()
  directory <- withr::local_tempdir()
  path <- file.path(directory, ".data.yaml")

  result <- datum_dataset_add(
    "rates", "Daily rates", "data/rates.csv",
    source = list(type = "http", url = "https://example.test/rates.csv"),
    policy = "update", config = ".data.yaml", wd = directory,
    executable = executable
  )
  expect_identical(result, normalizePath(path, winslash = "/"))
  document <- yaml::read_yaml(path)
  expect_identical(document$version, 1L)
  expect_identical(document$datasets[[1L]]$source$type, "http")
  expect_identical(document$datasets[[1L]]$policy, "update")

  expect_error(
    datum_dataset_add("rates", "Duplicate", "other", source = list(type = "file", path = "x"),
                      config = path, executable = executable),
    class = "datur_input_error"
  )
})

test_that("dataset add validates schema and source requirements before writing", {
  executable <- local_fake_datum(version = "v1.4.0")
  local_config_metadata()
  path <- withr::local_tempfile(fileext = ".yaml")
  unlink(path)

  expect_error(
    datum_dataset_add("bad id", "Bad", "data/x", source = list(type = "file", path = "x"),
                      config = path, executable = executable),
    class = "datur_input_error"
  )
  expect_false(file.exists(path))
  expect_error(
    datum_dataset_add("valid", "Bad", "data/x", source = list(type = "file"),
                      config = path, executable = executable),
    class = "datur_input_error"
  )
  expect_error(
    datum_dataset_add("valid", "Bad", "data/x", source = list(type = "file", path = "x"),
                      sources = list(list(type = "file", path = "y")),
                      config = path, executable = executable),
    class = "datur_input_error"
  )
})

test_that("dataset update changes only supplied fields and switches source form", {
  executable <- local_fake_datum(version = "v1.4.0")
  local_config_metadata()
  path <- withr::local_tempfile(fileext = ".yaml")
  write_test_config(path, list(config_dataset("one"), config_dataset("two")))

  datum_dataset_update(
    "one", desc = "Updated", policy = NULL,
    sources = list(
      list(type = "http", url = "https://one.test/data"),
      list(type = "file", path = "fallback.csv")
    ),
    config = path, executable = executable
  )
  document <- yaml::read_yaml(path)
  one <- document$datasets[[1L]]
  expect_identical(one$desc, "Updated")
  expect_null(one$policy)
  expect_null(one[["source"]])
  expect_length(one$sources, 2L)
  expect_identical(document$datasets[[2L]]$target, "data/two.csv")

  expect_error(datum_dataset_update("missing", desc = "x", config = path,
                                    executable = executable),
               class = "datur_input_error")
  expect_error(datum_dataset_update("one", source = list(type = "file", path = "x"),
                                    sources = list(list(type = "file", path = "y")),
                                    config = path, executable = executable),
               class = "datur_input_error")
})

test_that("dataset remove keeps or deletes local data as requested", {
  executable <- local_fake_datum(version = "v1.4.0")
  local_config_metadata()
  path <- withr::local_tempfile(fileext = ".yaml")
  write_test_config(path, list(config_dataset("one"), config_dataset("two"), config_dataset("three")))

  datum_dataset_remove("one", delete = FALSE, config = path, executable = executable)
  expect_identical(vapply(yaml::read_yaml(path)$datasets, `[[`, character(1), "id"),
                   c("two", "three"))

  args_file <- withr::local_tempfile()
  withr::local_envvar(FAKE_DATUM_ARGS_FILE = args_file)
  datum_dataset_remove("two", delete = TRUE, config = path, lock = "custom.lock",
                       executable = executable)
  expect_true("delete" %in% readLines(args_file))
  expect_identical(yaml::read_yaml(path)$datasets[[1L]]$id, "three")

  before <- readLines(path)
  expect_error(datum_dataset_remove("three", delete = FALSE, config = path,
                                    executable = executable),
               class = "datur_input_error")
  expect_identical(readLines(path), before)
})

test_that("dataset removal asks interactively when delete is unspecified", {
  executable <- local_fake_datum(version = "v1.4.0")
  local_config_metadata()
  path <- withr::local_tempfile(fileext = ".yaml")
  write_test_config(path, list(config_dataset("one"), config_dataset("two")))
  asked <- FALSE
  testthat::local_mocked_bindings(
    datur_is_interactive = function() TRUE,
    confirm_remove_data = function(id) {
      asked <<- identical(id, "one")
      FALSE
    },
    .package = "datur"
  )
  datum_dataset_remove("one", config = path, executable = executable)
  expect_true(asked)
  expect_identical(yaml::read_yaml(path)$datasets[[1L]]$id, "two")
})

test_that("config readers reject missing, malformed, and duplicate documents", {
  executable <- local_fake_datum(version = "v1.4.0")
  local_config_metadata()
  missing <- file.path(withr::local_tempdir(), "missing.yaml")
  expect_error(datum_dataset_update("x", desc = "x", config = missing,
                                    executable = executable),
               class = "datur_input_error")

  malformed <- withr::local_tempfile(fileext = ".yaml")
  writeLines("datasets: [", malformed)
  expect_error(datum_dataset_update("x", desc = "x", config = malformed,
                                    executable = executable),
               class = "datur_input_error")

  duplicate <- withr::local_tempfile(fileext = ".yaml")
  write_test_config(duplicate, list(config_dataset("same"), config_dataset("same")))
  expect_error(datum_dataset_update("same", desc = "x", config = duplicate,
                                    executable = executable),
               class = "datur_input_error")
})

test_that("low-level config validation covers the schema vocabulary datum uses", {
  root <- list(definitions = list(named = list(
    type = "object", required = list("name"), additionalProperties = FALSE,
    properties = list(name = list(type = "string", pattern = "^[a-z]+$"))
  )))
  schema <- list(
    type = "object", required = list("kind", "items"), additionalProperties = FALSE,
    properties = list(
      kind = list(type = "string", enum = list("one", "two")),
      count = list(type = "integer", enum = list(1L, 2L)),
      enabled = list(type = "boolean"),
      ratio = list(type = "number"),
      uri = list(type = "string", format = "uri"),
      items = list(type = "array", minItems = 1L,
                   items = list(`$ref` = "#/definitions/named"))
    )
  )
  root <- c(schema, root)
  valid <- list(kind = "one", count = 1L, enabled = TRUE, ratio = 1.5,
                uri = "https://example.test", items = list(list(name = "abc")))
  expect_length(datur:::schema_node_errors(valid, root, root), 0L)
  expect_match(datur:::schema_node_errors(within(valid, kind <- "bad"), root, root)[[1L]], "one of")
  expect_match(datur:::schema_node_errors(within(valid, count <- 3L), root, root)[[1L]], "enum")
  expect_match(datur:::schema_node_errors(within(valid, enabled <- "yes"), root, root)[[1L]], "boolean")
  expect_match(datur:::schema_node_errors(within(valid, ratio <- Inf), root, root)[[1L]], "number")
  expect_match(datur:::schema_node_errors(within(valid, uri <- "relative"), root, root)[[1L]], "URI")
  expect_match(datur:::schema_node_errors(within(valid, items <- list()), root, root)[[1L]], "at least")
  expect_match(datur:::schema_node_errors(within(valid, items[[1]]$name <- "123"), root, root)[[1L]], "match")
  expect_match(datur:::schema_node_errors(within(valid, extra <- "x"), root, root)[[1L]], "unknown")
  valid$kind <- NULL
  expect_match(datur:::schema_node_errors(valid, root, root)[[1L]], "missing")

  one_of <- list(oneOf = list(list(type = "string"), list(type = "integer")))
  expect_length(datur:::schema_node_errors("x", one_of, one_of), 0L)
  expect_match(datur:::schema_node_errors(TRUE, one_of, one_of)[[1L]], "exactly one")
})

test_that("dataset and document validators explain invalid structures", {
  schema <- jsonlite::fromJSON(metadata_fixture_path("schema.json"), simplifyVector = FALSE)
  raw_types <- jsonlite::fromJSON(metadata_fixture_path("types.json"), simplifyVector = FALSE)$types
  process <- datur:::new_process_result("datum", character(), 0L, "", "", Sys.time(), 0)
  specs <- lapply(raw_types, datur:::normalize_type_spec, process = process)
  names(specs) <- vapply(specs, `[[`, character(1), "type")
  good <- config_dataset("good")

  expect_error(datur:::validate_dataset_object(unname(good), specs, schema),
               class = "datur_input_error")
  expect_error(datur:::validate_dataset_object(good[names(good) != "desc"], specs, schema),
               class = "datur_input_error")
  extra <- good; extra$surprise <- "x"
  expect_error(datur:::validate_dataset_object(extra, specs, schema), class = "datur_input_error")
  both <- good; both$sources <- list(good$source)
  expect_error(datur:::validate_dataset_object(both, specs, schema), class = "datur_input_error")
  empty <- good; empty$source <- NULL; empty$sources <- list()
  expect_error(datur:::validate_dataset_object(empty, specs, schema), class = "datur_input_error")
  bad_policy <- good; bad_policy$policy <- "sometimes"
  expect_error(datur:::validate_dataset_object(bad_policy, specs, schema), class = "datur_input_error")
  bad_value <- good; bad_value$source$path <- ""
  expect_error(datur:::validate_dataset_object(bad_value, specs, schema), class = "datur_input_error")

  expect_error(datur:::validate_config_document(list(datasets = list(good)), schema, specs),
               class = "datur_input_error")
  expect_error(datur:::validate_config_document(list(version = 2L, datasets = list(good)), schema, specs),
               class = "datur_input_error")
  duplicate <- list(version = 1L, datasets = list(good, good))
  expect_error(datur:::validate_config_document(duplicate, schema, specs), class = "datur_input_error")
})

test_that("config IO initializes missing datasets and creates parent directories", {
  path <- file.path(withr::local_tempdir(), "nested", "config.yaml")
  datur:::write_config_document(list(version = 1L, datasets = list()), path)
  expect_true(file.exists(path))

  no_datasets <- withr::local_tempfile(fileext = ".yaml")
  writeLines("version: 1", no_datasets)
  expect_identical(datur:::read_config_document(no_datasets)$datasets, list())

  scalar <- withr::local_tempfile(fileext = ".yaml")
  writeLines("hello", scalar)
  expect_error(datur:::read_config_document(scalar), class = "datur_input_error")

  mapping <- withr::local_tempfile(fileext = ".yaml")
  writeLines(c("version: 1", "datasets: wrong"), mapping)
  expect_error(datur:::read_config_document(mapping), class = "datur_input_error")
})

test_that("source and config helpers reject malformed entries", {
  schema <- jsonlite::fromJSON(metadata_fixture_path("schema.json"), simplifyVector = FALSE)
  raw_types <- jsonlite::fromJSON(metadata_fixture_path("types.json"), simplifyVector = FALSE)$types
  process <- datur:::new_process_result("datum", character(), 0L, "", "", Sys.time(), 0)
  specs <- lapply(raw_types, datur:::normalize_type_spec, process = process)
  names(specs) <- vapply(specs, `[[`, character(1), "type")

  expect_error(datur:::validate_source_object(list(path = "x"), specs),
               class = "datur_input_error")
  expect_error(datur:::validate_source_object(list(type = "unknown"), specs),
               class = "datur_input_error")
  expect_error(datur:::validate_source_object(list(type = "file", path = "x", extra = "y"), specs),
               class = "datur_input_error")
  expect_error(datur:::validate_source_object(list(type = "file", path = "x", path = "y"), specs),
               class = "datur_input_error")
  expect_true(datur:::schema_type_matches("anything", "future-type"))

  malformed <- list(datasets = list(list(id = "good"), "not a dataset"))
  expect_error(datur:::config_dataset_ids(malformed), class = "datur_input_error")
  expect_null(datur:::config_source_types(list(datasets = list())))
  expect_identical(
    datur:::config_source_types(list(datasets = list(list(source = "invalid")))),
    ""
  )

  good <- config_dataset("good")
  no_source <- good
  no_source$source <- NULL
  expect_error(datur:::validate_dataset_object(no_source, specs, schema),
               class = "datur_input_error")
  bad_id <- good
  bad_id$id <- "bad id"
  expect_error(datur:::validate_dataset_object(bad_id, specs, schema),
               class = "datur_input_error")
})

test_that("dataset edits cover alternate source forms and target updates", {
  executable <- local_fake_datum(version = "v1.4.0")
  local_config_metadata()
  path <- withr::local_tempfile(fileext = ".yaml")
  unlink(path)

  datum_dataset_add(
    "one", "One", "data/one.csv",
    sources = list(list(type = "file", path = "one.csv")),
    config = path, executable = executable
  )
  datum_dataset_update(
    "one", target = "data/revised.csv",
    source = list(type = "file", path = "revised.csv"),
    config = path, executable = executable
  )
  dataset <- yaml::read_yaml(path)$datasets[[1L]]
  expect_identical(dataset$target, "data/revised.csv")
  expect_identical(dataset$source$path, "revised.csv")
  expect_null(dataset[["sources"]])

  expect_error(
    datum_dataset_remove("missing", delete = FALSE, config = path, executable = executable),
    class = "datur_input_error"
  )
})
