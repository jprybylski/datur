# Check configured data sources for updates

Runs `datum --json check`, validates its implicit protocol v1 response,
and returns one normalized record per configured dataset. Changed data
is a successful result even when `datum` uses exit status 1 for a `fail`
policy.

## Usage

``` r
datum_check(
  targets = NULL,
  config = NULL,
  lock = NULL,
  ...,
  executable = NULL,
  wd = NULL,
  timeout = getOption("datur.timeout", 300),
  concurrency = 1L,
  quiet = getOption("datur.quiet", FALSE)
)
```

## Arguments

- targets:

  Reserved for target selection. `datum` 1.x checks all targets, so this
  must currently be `NULL`.

- config:

  Optional datum configuration path.

- lock:

  Optional datum lockfile path.

- ...:

  Reserved for documented high-level options; currently empty.

- executable:

  Optional explicit executable path.

- wd:

  Optional child-process working directory.

- timeout:

  Positive finite timeout in seconds.

- concurrency:

  Number of datasets processed concurrently. Defaults to 1 because
  `datum` documents a shared-target race at higher concurrency.

- quiet:

  Suppress automatic interactive printing. Explicit
  [`print()`](https://rdrr.io/r/base/print.html) always works.

## Value

Invisibly, a `datur_check_result` object.

## Details

`datum check` always updates its lockfile timestamps and may replace
target files when a dataset uses the `update` policy. It does not modify
the datum configuration file.

## Examples

``` r
if (datum_available()) {
  result <- datum_check(quiet = TRUE)
  result$changed
  as.data.frame(result)
}
```
