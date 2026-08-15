minimum_datum_version <- package_version("1.2.1")
maximum_datum_major <- 1L
supported_schema_versions <- 1L
supported_check_statuses <- c(
  "ok", "updated", "stale", "fail", "warn", "error", "deleted"
)
datum_config_api_version <- package_version("1.4.0")
supported_audit_statuses <- c("ok", "pending", "deleted", "orphaned")

.datur_state <- new.env(parent = emptyenv())
.datur_state$path <- NULL
.datur_state$versions <- list()
