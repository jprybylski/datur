datum_repository <- "jprybylski/datum"
datum_github_base <- paste0("https://github.com/", datum_repository)
datum_api_base <- paste0("https://api.github.com/repos/", datum_repository)

datum_platform <- function(sysname = Sys.info()[["sysname"]],
                           machine = Sys.info()[["machine"]],
                           r_arch = R.version$arch,
                           call = NULL) {
  os <- switch(
    tolower(sysname),
    darwin = "darwin",
    linux = "linux",
    windows = "windows",
    abort_download(
      "No prebuilt {.file datum} binary is published for operating system {.val {sysname}}.",
      call = call
    )
  )
  architecture <- tolower(paste(machine, r_arch, collapse = " "))
  arch <- if (grepl("arm64|aarch64", architecture)) {
    "arm64"
  } else if (grepl("amd64|x86_64|x64", architecture)) {
    "amd64"
  } else {
    abort_download(
      "No prebuilt {.file datum} binary is published for architecture {.val {machine}}.",
      call = call
    )
  }
  list(os = os, arch = arch, extension = if (os == "windows") "zip" else "tar.gz")
}

normalize_download_version <- function(version, call = NULL) {
  version <- validate_string(version, "version", call = call)
  if (identical(tolower(version), "latest")) {
    return("latest")
  }
  version <- sub("^v", "", version, ignore.case = TRUE)
  if (!grepl("^[0-9]+\\.[0-9]+\\.[0-9]+$", version)) {
    abort_input(
      "version",
      "Must be 'latest' or a semantic version such as '1.3.0'.",
      call
    )
  }
  parsed <- package_version(version)
  if (parsed < minimum_datum_version) {
    abort_version(
      "Requested {.file datum} {version}, but datur requires {as.character(minimum_datum_version)} or newer.",
      raw = version,
      parsed = parsed,
      call = call
    )
  }
  version
}

datum_release_asset <- function(version, platform = datum_platform()) {
  asset <- sprintf(
    "datum_%s_%s_%s.%s",
    version,
    platform$os,
    platform$arch,
    platform$extension
  )
  tag <- paste0("v", version)
  list(
    version = version,
    tag = tag,
    asset = asset,
    url = sprintf("%s/releases/download/%s/%s", datum_github_base, tag, asset),
    checksums_url = sprintf("%s/releases/download/%s/checksums.txt", datum_github_base, tag),
    release_url = sprintf("%s/releases/tag/%s", datum_github_base, tag)
  )
}

github_download_file <- function(url, destination, timeout) {
  old_options <- options(timeout = max(1L, ceiling(timeout)))
  on.exit(options(old_options), add = TRUE)
  utils::download.file(
    url,
    destination,
    quiet = TRUE,
    mode = "wb",
    headers = c(
      Accept = "application/vnd.github+json",
      `User-Agent` = "datur-r-package"
    )
  )
  destination
}

github_latest_version <- function(timeout, call = NULL) {
  metadata_file <- tempfile("datur-release-", fileext = ".json")
  on.exit(unlink(metadata_file), add = TRUE)
  github_download_file(
    paste0(datum_api_base, "/releases/latest"),
    metadata_file,
    timeout
  )
  metadata <- tryCatch(
    jsonlite::fromJSON(metadata_file, simplifyVector = FALSE),
    error = function(error) {
      abort_download(
        "GitHub returned invalid release metadata for {.file datum}.",
        url = paste0(datum_api_base, "/releases/latest"),
        parent = error,
        call = call
      )
    }
  )
  tag <- metadata$tag_name
  if (!is.character(tag) || length(tag) != 1L || is.na(tag)) {
    abort_download(
      "GitHub's latest release metadata did not contain a usable tag.",
      url = paste0(datum_api_base, "/releases/latest"),
      call = call
    )
  }
  normalize_download_version(tag, call)
}

is_github_timeout <- function(error) {
  inherits(error, "datur_github_timeout") ||
    grepl("timed? ?out|timeout", conditionMessage(error), ignore.case = TRUE)
}

default_datum_destination <- function(platform = datum_platform()) {
  file.path(
    tools::R_user_dir("datur", "data"),
    "bin",
    if (platform$os == "windows") "datum.exe" else "datum"
  )
}

new_download_result <- function(downloaded, version, platform, asset, url,
                                path = NULL, reason = NULL) {
  structure(
    list(
      downloaded = isTRUE(downloaded),
      version = version,
      os = platform$os,
      arch = platform$arch,
      asset = asset,
      url = url,
      path = path,
      reason = reason
    ),
    class = "datur_download_result"
  )
}

manual_download_result <- function(version, platform, asset, url, reason) {
  result <- new_download_result(
    downloaded = FALSE,
    version = version,
    platform = platform,
    asset = asset,
    url = url,
    reason = reason
  )
  cli::cli_inform(c(
    "GitHub did not respond before the download deadline.",
    "i" = "Download the appropriate {.file datum} release manually: {url}",
    "i" = "Expected asset: {.file {asset}}"
  ))
  result
}

expected_archive_checksum <- function(path, asset, release, call = NULL) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  pieces <- strsplit(trimws(lines), "[[:space:]]+")
  matches <- vapply(
    pieces,
    function(piece) length(piece) >= 2L && identical(piece[[length(piece)]], asset),
    logical(1)
  )
  if (sum(matches) != 1L) {
    abort_download(
      "Release checksums did not contain exactly one entry for {.file {asset}}.",
      url = release$checksums_url,
      version = release$version,
      asset = asset,
      call = call
    )
  }
  pieces[[which(matches)]][[1L]]
}

extract_datum_binary <- function(archive, platform, directory, call = NULL) {
  if (platform$extension == "zip") {
    utils::unzip(archive, exdir = directory)
  } else {
    utils::untar(archive, exdir = directory)
  }
  binary_name <- if (platform$os == "windows") "datum.exe" else "datum"
  contents <- list.files(directory, recursive = TRUE, full.names = TRUE)
  candidates <- contents[basename(contents) == binary_name]
  if (length(candidates) != 1L) {
    abort_download(
      "The release archive did not contain exactly one {.file {binary_name}} executable.",
      call = call
    )
  }
  candidates[[1L]]
}

install_datum_binary <- function(source, destination, overwrite, platform, call = NULL) {
  if (file.exists(destination) && !overwrite) {
    abort_input(
      "destination",
      sprintf("File already exists: %s. Set overwrite = TRUE to replace it.", destination),
      call
    )
  }
  dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
  temporary <- paste0(destination, ".tmp")
  on.exit(unlink(temporary), add = TRUE)
  if (!file.copy(source, temporary, overwrite = TRUE, copy.mode = TRUE)) {
    abort_download("Could not copy the downloaded {.file datum} binary into place.", call = call)
  }
  if (platform$os != "windows") {
    Sys.chmod(temporary, mode = "0755")
  }
  if (file.exists(destination)) {
    unlink(destination)
  }
  if (!file.rename(temporary, destination)) {
    abort_download("Could not atomically install the downloaded {.file datum} binary.", call = call)
  }
  normalizePath(destination, winslash = "/", mustWork = TRUE)
}

validate_downloaded_datum <- function(path, version, call = NULL) {
  actual <- datum_version(executable = path, refresh = TRUE)
  if (!identical(as.character(actual), version)) {
    unlink(path)
    abort_download(
      "Downloaded {.file datum} reported version {as.character(actual)}, not requested version {version}.",
      version = version,
      call = call
    )
  }
  invisible(actual)
}

#' Download a prebuilt datum executable
#'
#' Downloads the `datum` release archive matching the current operating system
#' and CPU architecture, verifies its published SHA-256 checksum, extracts the
#' executable, and installs it at `destination`. This is an explicit operation;
#' `datur` never downloads or updates executables automatically.
#'
#' If GitHub times out while resolving or downloading a release, the function
#' returns a `datur_download_result` with `downloaded = FALSE` and prints the
#' appropriate manual release URL and expected asset name.
#'
#' @param version Release version such as `"1.3.0"` or `"v1.3.0"`. The default,
#'   `"latest"`, resolves GitHub's latest published release.
#' @param destination Path where the executable should be installed. Defaults to
#'   a package-owned user data directory.
#' @param overwrite Replace an existing destination file.
#' @param timeout Positive finite GitHub download timeout in seconds.
#'
#' @return A `datur_download_result`. When `downloaded` is `TRUE`, `path`
#'   contains the normalized installed executable path. On timeout, `url`
#'   contains the manual download link and `asset` identifies the correct file.
#' @export
#' @examples
#' \dontrun{
#' download <- datum_download()
#' if (download$downloaded) {
#'   options(datur.datum_path = download$path)
#' }
#'
#' datum_download(version = "1.3.0", destination = "~/bin/datum")
#' }
datum_download <- function(
    version = "latest",
    destination = NULL,
    overwrite = FALSE,
    timeout = getOption("datur.download_timeout", 60)) {
  call <- sys.call()
  requested_version <- normalize_download_version(version, call)
  overwrite <- validate_flag(overwrite, "overwrite", call)
  timeout <- validate_timeout(timeout, call)
  platform <- datum_platform(call = call)
  if (is.null(destination)) {
    destination <- default_datum_destination(platform)
  } else {
    destination <- validate_string(destination, "destination", call = call)
    destination <- path.expand(destination)
  }
  if (file.exists(destination) && !overwrite) {
    abort_input(
      "destination",
      sprintf("File already exists: %s. Set overwrite = TRUE to replace it.", destination),
      call
    )
  }

  if (identical(requested_version, "latest")) {
    resolved <- tryCatch(
      github_latest_version(timeout, call),
      error = function(error) {
        if (is_github_timeout(error)) return(error)
        stop(error)
      }
    )
    if (inherits(resolved, "error")) {
      pattern <- sprintf(
        "datum_<version>_%s_%s.%s",
        platform$os, platform$arch, platform$extension
      )
      return(invisible(manual_download_result(
        version = "latest",
        platform = platform,
        asset = pattern,
        url = paste0(datum_github_base, "/releases/latest"),
        reason = conditionMessage(resolved)
      )))
    }
    requested_version <- resolved
  }

  release <- datum_release_asset(requested_version, platform)
  archive <- tempfile("datur-archive-", fileext = paste0(".", platform$extension))
  checksums <- tempfile("datur-checksums-")
  extracted <- tempfile("datur-extracted-")
  dir.create(extracted)
  on.exit(unlink(c(archive, checksums, extracted), recursive = TRUE, force = TRUE), add = TRUE)

  download_error <- tryCatch(
    {
      github_download_file(release$url, archive, timeout)
      github_download_file(release$checksums_url, checksums, timeout)
      NULL
    },
    error = identity
  )
  if (!is.null(download_error)) {
    if (is_github_timeout(download_error)) {
      return(invisible(manual_download_result(
        version = requested_version,
        platform = platform,
        asset = release$asset,
        url = release$url,
        reason = conditionMessage(download_error)
      )))
    }
    abort_download(
      c(
        "Could not download {.file datum} {requested_version} from GitHub.",
        "x" = conditionMessage(download_error),
        "i" = "Manual download: {release$url}"
      ),
      url = release$url,
      version = requested_version,
      asset = release$asset,
      parent = download_error,
      call = call
    )
  }

  expected <- expected_archive_checksum(checksums, release$asset, release, call)
  actual <- unname(tools::sha256sum(archive))
  if (!identical(tolower(actual), tolower(expected))) {
    abort_download(
      "SHA-256 verification failed for {.file {release$asset}}; the archive was not installed.",
      url = release$url,
      version = requested_version,
      asset = release$asset,
      call = call
    )
  }

  binary <- extract_datum_binary(archive, platform, extracted, call)
  if (platform$os != "windows") {
    Sys.chmod(binary, mode = "0755")
  }
  validate_downloaded_datum(binary, requested_version, call)
  installed <- install_datum_binary(binary, destination, overwrite, platform, call)
  .datur_state$versions[[installed]] <- NULL
  new_download_result(
    downloaded = TRUE,
    version = requested_version,
    platform = platform,
    asset = release$asset,
    url = release$url,
    path = installed
  )
}

#' @export
print.datur_download_result <- function(x, ...) {
  if (x$downloaded) {
    cli::cli_text("Downloaded {.file datum} {x$version} to {.path {x$path}}")
  } else {
    cli::cli_text("Manual {.file datum} download: {x$url}")
    cli::cli_text("Expected asset: {.file {x$asset}}")
  }
  invisible(x)
}
