# Download a prebuilt datum executable

Downloads the `datum` release archive matching the current operating
system and CPU architecture, verifies its published SHA-256 checksum,
extracts the executable, and installs it at `destination`. This is an
explicit operation; `datur` never downloads or updates executables
automatically.

## Usage

``` r
datum_download(
  version = "latest",
  destination = NULL,
  overwrite = FALSE,
  timeout = getOption("datur.download_timeout", 60)
)
```

## Arguments

- version:

  Release version such as `"1.3.0"` or `"v1.3.0"`. The default,
  `"latest"`, resolves GitHub's latest published release.

- destination:

  Path where the executable should be installed. Defaults to a
  package-owned user data directory.

- overwrite:

  Replace an existing destination file.

- timeout:

  Positive finite GitHub download timeout in seconds.

## Value

A `datur_download_result`. When `downloaded` is `TRUE`, `path` contains
the normalized installed executable path. On timeout, `url` contains the
manual download link and `asset` identifies the correct file.

## Details

If GitHub times out while resolving or downloading a release, the
function returns a `datur_download_result` with `downloaded = FALSE` and
prints the appropriate manual release URL and expected asset name.

## Examples

``` r
if (FALSE) { # \dontrun{
download <- datum_download()
if (download$downloaded) {
  options(datur.datum_path = download$path)
}

datum_download(version = "1.3.0", destination = "~/bin/datum")
} # }
```
