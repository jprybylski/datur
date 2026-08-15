# Run datum with a raw argument vector

This is the intentional low-level escape hatch. Arguments are passed
directly to the executable, one vector element per process argument,
without invoking a shell.

## Usage

``` r
datum_run(
  args,
  stdin = NULL,
  executable = NULL,
  wd = NULL,
  env = character(),
  timeout = getOption("datur.timeout", 300),
  echo = FALSE,
  error_on_status = TRUE
)
```

## Arguments

- args:

  Character vector of process arguments.

- stdin:

  Optional standard input accepted by
  [`processx::run()`](http://processx.r-lib.org/reference/run.md).

- executable:

  Optional explicit executable path.

- wd:

  Optional child-process working directory.

- env:

  Named character vector of environment variables to add or replace.

- timeout:

  Positive finite timeout in seconds.

- echo:

  Forward process output while it runs.

- error_on_status:

  Raise `datur_cli_error` for a nonzero exit status.

## Value

A `datur_process_result` object.

## Examples

``` r
if (datum_available()) {
  datum_run("--version")
}
```
