# datur (development version)

* Documented the `${NAME}` configuration environment references supported by
  `datum` 1.5.0 and newer, including strict expansion, escaping, and security
  behavior.

# datur 0.1.1

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
