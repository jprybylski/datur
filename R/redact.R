sensitive_name <- function(name) {
  grepl("token|password|passwd|secret|credential|authorization|api[-_]?key", name,
        ignore.case = TRUE)
}

redact_url_credentials <- function(text) {
  gsub("([A-Za-z][A-Za-z0-9+.-]*://)[^/@[:space:]]+@", "\\1<redacted>@", text,
       perl = TRUE)
}

redact_values <- function(text, secrets) {
  text <- redact_url_credentials(text)
  secrets <- unique(secrets[nzchar(secrets)])
  for (secret in secrets) {
    text <- gsub(secret, "<redacted>", text, fixed = TRUE)
  }
  text
}

redact_process_inputs <- function(args, env) {
  redacted <- args
  secrets <- unname(env[sensitive_name(names(env))])

  previous_sensitive <- FALSE
  for (index in seq_along(args)) {
    argument <- args[[index]]
    if (previous_sensitive) {
      secrets <- c(secrets, argument)
      redacted[[index]] <- "<redacted>"
      previous_sensitive <- FALSE
      next
    }
    if (grepl("^--?[^=]+=" , argument)) {
      name <- sub("=.*$", "", argument)
      value <- sub("^[^=]*=", "", argument)
      if (sensitive_name(name)) {
        secrets <- c(secrets, value)
        redacted[[index]] <- paste0(name, "=<redacted>")
      }
    } else if (grepl("^--?", argument) && sensitive_name(argument)) {
      previous_sensitive <- TRUE
    }
  }
  list(args = redacted, secrets = unique(secrets))
}

