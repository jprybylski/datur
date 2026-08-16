test_that("download platforms map supported systems and architectures", {
  expect_equal(
    datum_platform("Darwin", "arm64", "aarch64"),
    list(os = "darwin", arch = "arm64", extension = "tar.gz")
  )
  expect_equal(
    datum_platform("Linux", "x86_64", "x86_64"),
    list(os = "linux", arch = "amd64", extension = "tar.gz")
  )
  expect_equal(
    datum_platform("Windows", "AMD64", "x86_64"),
    list(os = "windows", arch = "amd64", extension = "zip")
  )
  expect_error(datum_platform("Plan9", "amd64"), class = "datur_download_error")
  expect_error(
    datum_platform("Linux", "riscv64", "riscv64"),
    class = "datur_download_error"
  )
})

test_that("download versions and release URLs are normalized", {
  expect_identical(normalize_download_version("latest"), "latest")
  expect_identical(normalize_download_version("v1.3.0"), "1.3.0")
  expect_error(normalize_download_version("nightly"), class = "datur_input_error")
  expect_error(normalize_download_version("1.2.0"), class = "datur_version_error")

  release <- datum_release_asset(
    "1.3.0",
    list(os = "linux", arch = "arm64", extension = "tar.gz")
  )
  expect_identical(release$asset, "datum_1.3.0_linux_arm64.tar.gz")
  expect_identical(
    release$url,
    "https://github.com/jprybylski/datum/releases/download/v1.3.0/datum_1.3.0_linux_arm64.tar.gz"
  )
  expect_identical(
    release$checksums_url,
    "https://github.com/jprybylski/datum/releases/download/v1.3.0/checksums.txt"
  )
})

test_that("latest release metadata resolves a version", {
  testthat::local_mocked_bindings(
    github_download_file = function(url, destination, timeout) {
      writeLines('{"tag_name":"v1.3.0"}', destination)
      destination
    }
  )
  expect_identical(github_latest_version(10), "1.3.0")
})

test_that("latest release metadata failures are typed", {
  testthat::local_mocked_bindings(
    github_download_file = function(url, destination, timeout) {
      writeLines("not json", destination)
      destination
    }
  )
  expect_error(github_latest_version(10), class = "datur_download_error")

  testthat::local_mocked_bindings(
    github_download_file = function(url, destination, timeout) {
      writeLines('{"name":"release without a tag"}', destination)
      destination
    }
  )
  expect_error(github_latest_version(10), class = "datur_download_error")
})

test_that("download helpers handle files, checksums, and destinations", {
  source <- withr::local_tempfile()
  destination <- withr::local_tempfile()
  unlink(destination)
  writeBin(charToRaw("download contents"), source)
  expect_identical(
    github_download_file(paste0("file://", source), destination, 1),
    destination
  )
  expect_identical(readBin(destination, "raw", n = 100), charToRaw("download contents"))

  platform <- list(os = "linux", arch = "amd64", extension = "tar.gz")
  expect_match(default_datum_destination(platform), "bin/datum$")
  expect_false(is_github_timeout(simpleError("connection reset")))
  expect_true(is_github_timeout(simpleError("request timed out")))

  release <- datum_release_asset("1.3.0", platform)
  checksums <- withr::local_tempfile()
  writeLines(c("abc other.tar.gz", paste("DEF", release$asset)), checksums)
  expect_identical(expected_archive_checksum(checksums, release$asset, release), "DEF")
  writeLines(c(paste("abc", release$asset), paste("def", release$asset)), checksums)
  expect_error(
    expected_archive_checksum(checksums, release$asset, release),
    class = "datur_download_error"
  )
})

test_that("release archives are extracted and installed atomically", {
  source_directory <- withr::local_tempdir()
  binary <- file.path(source_directory, "datum")
  writeLines("binary", binary)
  archive <- withr::local_tempfile(fileext = ".tar.gz")
  withr::local_dir(source_directory)
  utils::tar(archive, "datum", compression = "gzip", tar = "internal")

  extraction_directory <- withr::local_tempdir()
  extracted <- extract_datum_binary(
    archive,
    list(os = "linux", arch = "amd64", extension = "tar.gz"),
    extraction_directory
  )
  expect_identical(readLines(extracted), "binary")

  destination <- file.path(withr::local_tempdir(), "nested", "datum")
  installed <- install_datum_binary(
    extracted, destination, FALSE,
    list(os = "linux", arch = "amd64", extension = "tar.gz")
  )
  expect_identical(installed, normalizePath(destination, winslash = "/"))
  expect_identical(readLines(destination), "binary")
  expect_error(
    install_datum_binary(extracted, destination, FALSE,
                         list(os = "linux", arch = "amd64", extension = "tar.gz")),
    class = "datur_input_error"
  )
  writeLines("replacement", extracted)
  install_datum_binary(extracted, destination, TRUE,
                       list(os = "linux", arch = "amd64", extension = "tar.gz"))
  expect_identical(readLines(destination), "replacement")

  empty_archive <- withr::local_tempfile(fileext = ".tar.gz")
  decoy <- file.path(source_directory, "not-datum")
  writeLines("decoy", decoy)
  withr::local_dir(source_directory)
  utils::tar(empty_archive, "not-datum", compression = "gzip", tar = "internal")
  expect_error(
    extract_datum_binary(empty_archive,
                         list(os = "linux", arch = "amd64", extension = "tar.gz"),
                         withr::local_tempdir()),
    class = "datur_download_error"
  )
})

test_that("downloaded binaries must report the requested version", {
  binary <- withr::local_tempfile()
  writeLines("binary", binary)
  testthat::local_mocked_bindings(
    datum_version = function(executable, refresh) package_version("1.3.0")
  )
  expect_equal(as.character(validate_downloaded_datum(binary, "1.3.0")), "1.3.0")

  testthat::local_mocked_bindings(
    datum_version = function(executable, refresh) package_version("1.4.0")
  )
  expect_error(validate_downloaded_datum(binary, "1.3.0"), class = "datur_download_error")
  expect_false(file.exists(binary))
})

test_that("datum_download verifies and installs the selected release", {
  platform <- datum_platform()
  release <- datum_release_asset("1.3.0", platform)
  archive_source <- tempfile(fileext = paste0(".", platform$extension))
  writeBin(charToRaw("release archive"), archive_source)
  checksum_source <- tempfile()
  writeLines(
    paste(sha256_file(archive_source), release$asset),
    checksum_source
  )
  destination <- tempfile("installed-datum-")

  testthat::local_mocked_bindings(
    github_download_file = function(url, destination, timeout) {
      source <- if (identical(url, release$url)) archive_source else checksum_source
      file.copy(source, destination, overwrite = TRUE)
      destination
    },
    extract_datum_binary = function(archive, platform, directory, call = NULL) {
      binary <- file.path(directory, if (platform$os == "windows") "datum.exe" else "datum")
      writeLines("downloaded datum", binary)
      binary
    },
    validate_downloaded_datum = function(path, version, call = NULL) invisible(version)
  )

  result <- datum_download("1.3.0", destination = destination)
  expect_s3_class(result, "datur_download_result")
  expect_true(result$downloaded)
  expect_identical(result$version, "1.3.0")
  expect_identical(result$asset, release$asset)
  expect_identical(result$url, release$url)
  expect_identical(result$path, normalizePath(destination, winslash = "/"))
  expect_identical(readLines(destination), "downloaded datum")
})

test_that("datum_download rejects a checksum mismatch without installing", {
  platform <- datum_platform()
  release <- datum_release_asset("1.3.0", platform)
  destination <- tempfile("untrusted-datum-")

  testthat::local_mocked_bindings(
    github_download_file = function(url, destination, timeout) {
      if (identical(url, release$url)) {
        writeLines("untrusted archive", destination)
      } else {
        writeLines(paste(strrep("0", 64), release$asset), destination)
      }
      destination
    }
  )

  expect_error(
    datum_download("1.3.0", destination = destination),
    class = "datur_download_error"
  )
  expect_false(file.exists(destination))
})

test_that("datum_download preserves an existing destination by default", {
  destination <- tempfile("existing-datum-")
  writeLines("existing", destination)

  expect_error(
    datum_download("1.3.0", destination = destination),
    class = "datur_input_error"
  )
  expect_identical(readLines(destination), "existing")
})

test_that("GitHub timeouts return manual links for pinned releases", {
  platform <- datum_platform()
  release <- datum_release_asset("1.3.0", platform)
  testthat::local_mocked_bindings(
    github_download_file = function(url, destination, timeout) stop("operation timed out")
  )

  expect_message(
    result <- datum_download("1.3.0", destination = tempfile()),
    "Manual|manually"
  )
  expect_false(result$downloaded)
  expect_identical(result$url, release$url)
  expect_identical(result$asset, release$asset)
})

test_that("GitHub timeouts return the latest release page", {
  platform <- datum_platform()
  testthat::local_mocked_bindings(
    github_download_file = function(url, destination, timeout) stop("request timeout")
  )

  expect_message(
    result <- datum_download(destination = tempfile()),
    "Manual|manually"
  )
  expect_false(result$downloaded)
  expect_identical(result$version, "latest")
  expect_identical(result$url, "https://github.com/jprybylski/datum/releases/latest")
  expect_match(result$asset, platform$os, fixed = TRUE)
  expect_match(result$asset, platform$arch, fixed = TRUE)
})

test_that("latest downloads resolve before selecting an asset", {
  platform <- datum_platform()
  release <- datum_release_asset("1.3.0", platform)
  archive_source <- withr::local_tempfile()
  writeLines("archive", archive_source)
  checksum_source <- withr::local_tempfile()
  writeLines(paste(sha256_file(archive_source), release$asset), checksum_source)

  testthat::local_mocked_bindings(
    github_latest_version = function(timeout, call = NULL) "1.3.0",
    github_download_file = function(url, destination, timeout) {
      file.copy(if (identical(url, release$url)) archive_source else checksum_source,
                destination, overwrite = TRUE)
      destination
    },
    extract_datum_binary = function(archive, platform, directory, call = NULL) {
      path <- file.path(directory, if (platform$os == "windows") "datum.exe" else "datum")
      writeLines("binary", path)
      path
    },
    validate_downloaded_datum = function(path, version, call = NULL) invisible(version)
  )
  result <- datum_download(destination = withr::local_tempfile())
  expect_true(result$downloaded)
  expect_identical(result$version, "1.3.0")
})

test_that("non-timeout GitHub failures remain download errors", {
  testthat::local_mocked_bindings(
    github_download_file = function(url, destination, timeout) stop("connection refused")
  )
  expect_error(
    datum_download("1.3.0", destination = withr::local_tempfile()),
    class = "datur_download_error"
  )
})

test_that("non-timeout latest-resolution failures are rethrown", {
  testthat::local_mocked_bindings(
    github_latest_version = function(timeout, call = NULL) stop("invalid response")
  )
  expect_error(
    datum_download(destination = withr::local_tempfile()),
    "invalid response"
  )
})

test_that("download result printing is informative", {
  platform <- list(os = "linux", arch = "amd64", extension = "tar.gz")
  downloaded <- new_download_result(
    TRUE, "1.3.0", platform, "datum.tar.gz", "https://example.test", "/tmp/datum"
  )
  manual <- new_download_result(
    FALSE, "1.3.0", platform, "datum.tar.gz", "https://example.test"
  )
  expect_message(print(downloaded), "Downloaded.*datum.*1.3.0")
  expect_message(print(manual), "Manual.*datum.*download")
})
