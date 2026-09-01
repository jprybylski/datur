# datur (development version)

* Added full compatibility with `datum` 1.6.0: `datum_init()` creates empty or
  single-dataset configurations, HTTP sources accept structured headers and
  request bodies, and dataset helpers manage per-dataset VCS ignore settings.
* Fixed `datum_path(executable = ...)` to cache the validated path for later
  `datum_available()`, `datum_path()`, and `datum_version()` calls in the same R
  session without modifying global options.
* Fixed `datum_download()` so a GitHub timeout reported by `download.file()` as
  a warning is recognized even when the subsequent error omits the timeout
  detail. The function now returns the documented manual-download result.

# datur 0.1.1

* Documented the `${NAME}` configuration environment references supported by
  `datum` 1.5.0 and newer, including strict expansion, escaping, and security
  behavior.

* Added schema-driven `.data.yaml` helpers: `datum_source()`,
  `datum_dataset_add()`, `datum_dataset_update()`, and `datum_dataset_remove()`.
* Added typed wrappers for datum's `schema`, `types`, `audit`, and `delete`
  commands, including interactive confirmation before destructive operations.
* Added a dedicated `.data.yaml` vignette and grouped all new functions in the
  pkgdown reference index.

# datur 0.1.0

* Added typed executable discovery, version validation, and low-level process execution.
* Added the high-level `datum_check()` API and stable S3 result objects.
* Added fixture-driven protocol validation for `datum` 1.2.1 through 1.x.
