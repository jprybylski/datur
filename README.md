
<!-- README.md is generated from README.Rmd. Please edit that file. -->

# datur <img src="man/figures/logo.png" align="right" height="139" alt="" />

<!-- badges: start -->

[![R-CMD-check](https://github.com/jprybylski/datur/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/jprybylski/datur/actions/workflows/R-CMD-check.yaml)
[![Codecov test
coverage](https://codecov.io/gh/jprybylski/datur/graph/badge.svg)](https://app.codecov.io/gh/jprybylski/datur)
<!-- badges: end -->

`datur` is a safe, typed R interface to
[`datum`](https://github.com/jprybylski/datum), the command-line data
update checker. It executes `datum` directly without shell
interpolation, validates its JSON protocol, and returns stable R objects
for interactive work and automation.

## Installation

Install the development version of `datur`:

``` r
# install.packages("pak")
pak::pak("jprybylski/datur")
```

Then explicitly download the latest `datum` release for the current
operating system and CPU architecture:

``` r
download <- datum_download()
if (download$downloaded) {
  options(datur.datum_path = download$path)
}
```

Reuse the resolved release and pin the destination when reproducibility
requires it:

``` r
datum_download(
  version = download$version,
  destination = "~/bin/datum",
  overwrite = TRUE
)
```

The archive is verified against the release’s published SHA-256 checksum
before installation. If GitHub times out, `datum_download()` prints and
returns the appropriate manual release link and expected asset name
instead of failing.

You may also install any supported `datum` release separately. Configure
a nonstandard executable location with any of:

``` r
datum_path(executable = "/opt/datum/bin/datum")
options(datur.datum_path = "/opt/datum/bin/datum")
Sys.setenv(DATUM_PATH = "/opt/datum/bin/datum")
```

## First check

With `.data.yaml` and `.data.lock.yaml` in the working directory:

``` r
library(datur)

datum_available()
datum_version()

result <- datum_check(quiet = TRUE)
print(result)
```

With a compatible installed `datum`, `datur` can also build and safely
edit `.data.yaml` from R using the schema and source requirements
embedded in that binary:

``` r
http_source <- datum_source("http", url = "https://example.com/data.csv")
datum_dataset_add("example", "Example data", "data/example.csv", http_source)
datum_dataset_update("example", policy = "update")
datum_audit()
```

Changed data is represented as data, including when `datum` uses exit
status 1 for a `fail` policy:

``` r
result$changed
result$status
as.data.frame(result)
```

Each data-frame row represents one configured datum dataset. The
normalized columns are `id`, `status`, `message`, `lock_fingerprint`,
`remote_fingerprint`, and a list-column of fallback `warnings`.

## Automation

``` r
result <- datum_check(quiet = TRUE)

if (result$changed) {
  changed <- subset(as.data.frame(result), status %in% c("updated", "stale", "fail"))
  message("Rebuild required for: ", paste(changed$id, collapse = ", "))
}
```

Partial failures preserve usable results in a typed condition:

``` r
tryCatch(
  datum_check(quiet = TRUE),
  datur_cli_error = function(error) {
    if (!is.null(error$result)) {
      print(error$result)
    }
    stop(error)
  }
)
```

## Low-level execution

Use `datum_run()` when you intentionally need raw CLI arguments:

``` r
process <- datum_run(c("--version"), error_on_status = FALSE)
process$status
process$stdout
```

Arguments remain separate process tokens and never pass through a shell.
Sensitive argument and environment values are redacted from public
process metadata and captured output.

## Important behavior

`datum check` always updates lockfile timestamps. A dataset using the
`update` policy may also fetch and replace target files. `datur` does
not modify datum configuration, download executables implicitly, or
change the R working directory. `datum_download()` only acts when
called.

See `vignette("datur", package = "datur")` for a complete, output-rich
workflow and `docs/datum-cli-contract.md` for the reviewed CLI boundary.
