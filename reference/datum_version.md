# Report the installed datum version

`datur` supports the implicit JSON protocol emitted by `datum` 1.2.1
through 1.x.

## Usage

``` r
datum_version(executable = NULL, refresh = FALSE)
```

## Arguments

- executable:

  Optional explicit executable path.

- refresh:

  Re-run automatic executable discovery.

## Value

A `package_version` object with original output in attribute `raw`.

## Examples

``` r
if (datum_available()) {
  datum_version()
}
```
