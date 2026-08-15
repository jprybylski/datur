# Locate the datum executable

Resolves `datum` in this order: `executable`, option `datur.datum_path`,
environment variable `DATUM_PATH`, then `PATH`. Successful automatic
`PATH` lookups are cached for the R session.

## Usage

``` r
datum_path(executable = NULL, refresh = FALSE)
```

## Arguments

- executable:

  Optional explicit executable path.

- refresh:

  Re-run automatic executable discovery.

## Value

A normalized executable path.

## Examples

``` r
datum_available()
#> [1] FALSE
```
