# `datur`: R Companion Package for `datum`

**Document type:** Product and engineering specification  
**Status:** Draft for implementation  
**Primary audience:** Codex and package maintainers  
**Working package name:** `datur`  

## 1. Purpose

`datur` is an R package that provides a safe, typed, and user-friendly interface
to the `datum` command-line tool. It allows R users to invoke `datum` data-update
checks, inspect the results programmatically, and incorporate those checks into
scripts, reports, pipelines, and interactive workflows.

The package is a **thin integration layer**. `datum` remains the source of truth
for update detection, configuration, networking, and comparison logic. `datur`
owns process execution, R-facing input validation, result normalization,
conditions, printing, and documentation.

## 2. Product summary

### One-line description

> An R interface to the `datum` command-line data update checker.

### Primary user story

> As an R user, I want to run a `datum` update check and receive a structured R
> result so that I can react to changed data without parsing terminal output or
> managing a subprocess myself.

### Secondary user stories

- As an analyst, I can check whether upstream data changed before rebuilding an
  analysis.
- As a package author, I can call `datum` from R without shell interpolation.
- As an interactive user, I receive concise, readable output explaining whether
  changes were found.
- As an automation author, I can inspect stable fields and condition classes
  rather than scraping messages.
- As a maintainer, I can support new `datum` releases through a small internal
  adapter rather than changing the public API.

## 3. Goals and non-goals

### Goals

1. Expose the core `datum` update-check workflow through idiomatic R functions.
2. Return structured, stable R objects for both changed and unchanged results.
3. Execute `datum` safely without invoking a shell.
4. Provide actionable errors for missing executables, incompatible versions,
   timeouts, CLI failures, and malformed output.
5. Work on Linux, macOS, and Windows.
6. Be testable without network access or a locally installed `datum` binary.
7. Meet CRAN package standards.
8. Preserve access to the underlying CLI for advanced use without making raw
   process details the default experience.

### Non-goals for version 1.0

- Reimplementing `datum` update-detection logic in R.
- Automatically installing or updating the `datum` executable.
- Running a persistent scheduler or background daemon.
- Providing notification integrations such as email or Slack.
- Replacing `datum` configuration with a separate R-only configuration system.
- Parsing human-oriented terminal output as the primary integration contract.
- Providing a GUI or Shiny application.
- Mutating user data in response to a detected update.
- Supporting every `datum` subcommand before the core check workflow is stable.

## 4. Required discovery before implementation

The `datum` repository and CLI contract were not available when this
specification was written. Codex MUST complete this discovery phase before
implementing the process adapter.

### Inspect the CLI

Run and record, where supported:

```text
datum --version
datum --help
datum check --help
```

Also inspect the `datum` source and documentation for:

- the exact update-check subcommand and arguments;
- whether a JSON or other machine-readable output mode exists;
- the output schema and any schema-version field;
- exit-code semantics, including whether “changes found” is a successful exit;
- stdout versus stderr behavior;
- color, progress, and interactive prompt controls;
- configuration-file discovery and precedence;
- behavior when a source is unreachable;
- version-string format;
- platform-specific executable behavior;
- handling of multiple sources and partial failures;
- whether checks can modify files or caches;
- whether secrets can appear in commands, output, or errors.

### Produce a contract note

Before implementation, create `docs/datum-cli-contract.md` in the package
repository containing:

1. commands and options used by `datur`;
2. representative stdout and stderr;
3. exit codes for unchanged, changed, partial-failure, and error cases;
4. the complete machine-readable schema;
5. the oldest supported `datum` version;
6. any known compatibility hazards.

### Stop condition

If `datum` does not expose a stable machine-readable output mode, Codex MUST
stop after discovery and report that limitation. The preferred resolution is to
add a versioned JSON mode to `datum`. A human-readable output parser may only be
implemented after an explicit maintainer decision, and it must be isolated,
fixture-tested, version-gated, and documented as provisional.

## 5. Naming conventions

- Package name: `datur`.
- Exported functions that operate on the CLI use the `datum_` prefix. This makes
  calls self-explanatory: `datur::datum_check()`.
- Package-owned S3 classes and condition classes use the `datur_` prefix.
- Internal helpers use a leading dot only when necessary; otherwise use clear,
  unexported names such as `run_datum()` and `parse_check_result()`.
- Do not export ambiguous names such as `check()`, `run()`, or `status()`.

## 6. Proposed public API

The exact arguments that map to CLI concepts may be refined during discovery,
but the function responsibilities and return contracts should remain stable.

### `datum_check()`

Run the primary data-update check.

```r
datum_check(
  targets = NULL,
  config = NULL,
  ..., 
  executable = NULL,
  wd = NULL,
  timeout = getOption("datur.timeout", 300),
  quiet = FALSE
)
```

Requirements:

- `targets` selects one or more `datum` sources if the CLI supports selection.
- `config` explicitly selects a configuration file when supported.
- `...` contains documented, high-level check options only; it must not become
  an unvalidated string pass-through.
- `executable` overrides executable discovery for this call.
- `wd` sets the subprocess working directory without changing the R process
  working directory.
- `timeout` is expressed in seconds and must be a positive finite scalar.
- `quiet = TRUE` suppresses informational output, not warnings or errors.
- The function returns a `datur_check_result` for both changed and unchanged
  successful checks.
- A detected update is data, not an error or warning.
- Partial failures follow the CLI contract discovered in Section 4. If usable
  results exist, preserve them in the raised condition.
- User-friendly, nicely formatted output leveraging the `cli` package.

### `datum_run()`

Provide an intentional low-level escape hatch.

```r
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

Requirements:

- `args` must be a character vector with one process argument per element.
- The command must be executed directly, never through a shell command string.
- `env` adds subprocess environment variables without discarding the inherited
  environment.
- `echo` controls live forwarding of output when supported.
- Return a `datur_process_result`.
- When `error_on_status = TRUE`, an unsuccessful CLI status raises
  `datur_cli_error` containing the result object.
- Document that this function is less stable than the high-level API because
  its arguments are defined by `datum`.

### `datum_available()`

```r
datum_available(executable = NULL)
```

Return one non-missing logical value. This function must not emit a warning or
error when `datum` is absent.

### `datum_path()`

```r
datum_path(executable = NULL, refresh = FALSE)
```

Return the normalized executable path or raise `datur_not_found`. Cache a
successful automatic lookup within the R session; `refresh = TRUE` repeats
discovery.

### `datum_version()`

```r
datum_version(executable = NULL, refresh = FALSE)
```

Return a parsed version object when possible. Attach the original version text
as an attribute if normalization is required. Raise `datur_version_error` when
the executable responds but its version cannot be interpreted.

### S3 methods

Provide:

- `print.datur_check_result()`
- `summary.datur_check_result()`
- `as.data.frame.datur_check_result()`
- `print.datur_process_result()`

`as.data.frame()` must return one row per checked target or detected change,
based on the actual CLI schema. The choice must be documented and stable before
1.0. If both views are useful, expose explicit accessors instead of overloading
one ambiguous representation.

### Optional phase-two API

Only add these functions when corresponding CLI capabilities exist and user
need is demonstrated:

- `datum_sources()`
- `datum_config()` for read-only configuration inspection
- `datum_history()`
- `datum_diff()`

Do not include speculative exports in the initial release.

## 7. Executable discovery

Resolve the `datum` executable in this order:

1. the function-level `executable` argument;
2. `getOption("datur.datum_path")`;
3. the `DATUM_PATH` environment variable;
4. `Sys.which("datum")`.

Rules:

- Validate that an explicit path exists and is executable where the platform
  exposes executable permissions.
- Support spaces and non-ASCII characters in paths.
- Normalize paths for returned metadata, but do not rewrite user input before
  process execution in a way that breaks platform behavior.
- Do not search broad filesystem locations.
- Do not download binaries.
- The missing-executable message must show the supported configuration methods
  and link to `datum` installation documentation.

## 8. Process execution

Use `processx` for subprocess execution unless discovery uncovers a compelling
technical reason not to.

Requirements:

- Never use `system()` with a constructed command string.
- Never pass user values through a shell.
- Pass every CLI token as a separate argument.
- Capture stdout, stderr, status, duration, and the effective command metadata.
- Disable color and interactive prompts when the CLI supports those controls.
- Propagate user interrupts and terminate the child process cleanly.
- Terminate timed-out processes and raise `datur_timeout`.
- Preserve stderr in conditions without printing it twice.
- Avoid leaking secrets in printed commands, messages, snapshots, or logs.
- Do not change global R options, environment variables, or the process working
  directory.
- Treat networking as behavior owned by `datum`; `datur` must not duplicate
  remote requests.

## 9. Machine-readable protocol

The high-level API must consume a versioned machine-readable response from
`datum`, preferably JSON.

### Adapter boundary

All protocol-specific behavior belongs in a small internal adapter with these
conceptual steps:

1. build CLI arguments;
2. execute the process;
3. classify the exit status;
4. parse the output;
5. validate required fields and schema version;
6. normalize into the stable R result object.

Do not expose the raw CLI schema directly as the only public contract. Preserve
the parsed raw response in the result for diagnostics, but document normalized
fields as the stable interface.

### Protocol requirements

- Reject malformed machine-readable output with `datur_protocol_error`.
- Reject unsupported schema versions with an error that reports both supported
  and received versions.
- Tolerate additive fields in a known schema version.
- Do not silently discard unknown status values.
- Distinguish an empty successful response from parse failure.
- Store protocol fixtures exactly as emitted by supported `datum` releases,
  after removing secrets and machine-specific paths.

## 10. Result objects

### `datur_process_result`

An immutable-by-convention S3 list with at least:

```text
command          executable path
args             character vector of arguments
status           integer exit status
stdout           captured standard output
stderr           captured standard error
started_at       POSIXct timestamp
duration         difftime or numeric seconds, documented consistently
datum_version    parsed version or NULL
```

Printing must show the command name, exit status, and duration. It must not dump
full stdout or stderr by default.

### `datur_check_result`

An S3 list with at least these normalized concepts, adjusted to the real CLI
schema during discovery:

```text
changed          one non-missing logical value
status           normalized overall status
summary          named counts or other concise summary
records          data frame with one documented unit per row
checked_at       POSIXct timestamp
duration         check duration
datum_version    CLI version
schema_version   protocol schema version
raw              parsed raw machine-readable response
process          associated datur_process_result
```

Potential normalized record fields:

- target identifier;
- target display name;
- normalized status such as `changed`, `unchanged`, or `failed`;
- previous fingerprint or version;
- current fingerprint or version;
- observed update time;
- human-readable detail;
- structured metadata in a list column only when unavoidable.

Final field names must be based on the real `datum` output. Do not invent data
that the CLI cannot supply.

### Printing

Interactive printing should be concise:

```text
datum check: 2 changes across 8 targets (1.4s)

changed  customers.csv
changed  exchange-rates
```

For no changes:

```text
datum check: no changes across 8 targets (1.1s)
```

Use color only in interactive terminals that support it. Meaning must never
depend on color. `quiet = TRUE` suppresses this automatic print messaging, but
explicitly printing the returned object still works.

## 11. Conditions and errors

All package errors inherit from `datur_error`. Use structured condition fields
so callers can respond programmatically.

Required subclasses:

| Class | Meaning | Required fields |
| --- | --- | --- |
| `datur_not_found` | No usable `datum` executable | attempted sources |
| `datur_version_error` | Missing, invalid, or unsupported version | raw and parsed version |
| `datur_timeout` | Process exceeded its deadline | timeout and partial result |
| `datur_cli_error` | CLI reported an unsuccessful status | process result |
| `datur_protocol_error` | Machine-readable output was invalid or unsupported | process result and schema details |
| `datur_input_error` | R input could not be mapped safely | argument and problem |

Messages must:

- state what failed;
- include the relevant target or command without exposing secrets;
- suggest a concrete next action;
- avoid dumping a stack trace or full raw response;
- preserve the underlying result in the condition when available.

Do not use warnings to represent changed data. Reserve warnings for successful
operations with compatibility or deprecation concerns.

## 12. Version compatibility

After discovery, define and test:

- the minimum supported `datum` version;
- the set of supported protocol schema versions;
- behavior for a newer, untested `datum` major version;
- behavior for development or non-semantic version strings.

Recommended policy:

- error for versions older than the documented minimum;
- error for known-incompatible protocol versions;
- warn once per session for a newer, untested CLI major version, unless its
  protocol is explicitly incompatible;
- compare parsed versions rather than version strings;
- keep compatibility constants in one internal file.

Never silently reinterpret an unknown exit code or status value.

## 13. Configuration and precedence

`datur` should pass explicit user choices to `datum` and otherwise allow the CLI
to use its native configuration discovery.

Package-level settings:

| Setting | Default | Purpose |
| --- | --- | --- |
| `datur.datum_path` | `NULL` | Explicit executable location |
| `datur.timeout` | `300` | Default subprocess timeout in seconds |
| `datur.quiet` | `FALSE` | Optional default for informational output |

Rules:

- Function arguments override package options.
- Package options override environment variables only where explicitly stated.
- Do not write configuration files in version 1.0.
- Do not read or modify unrelated global options.
- Use `tools::R_user_dir("datur", ...)` if package-owned cache or state becomes
  necessary in a future release.

## 14. Security and privacy

- No shell interpolation.
- No automatic executable download or execution from temporary remote content.
- No telemetry.
- No credential collection by `datur`.
- Redact values whose argument names or environment keys indicate tokens,
  passwords, secrets, credentials, or authorization headers.
- Ensure errors and print methods do not expose full environment variables.
- Document that `datum` may perform network access according to its own command
  and configuration.
- Tests must use synthetic credentials and local fixtures only.
- Do not serialize or cache raw output unless explicitly requested by the user.

## 15. Package structure

Recommended initial layout:

```text
datur/
├── DESCRIPTION
├── LICENSE or LICENSE.md
├── NAMESPACE
├── NEWS.md
├── README.Rmd
├── README.md
├── R/
│   ├── check.R
│   ├── conditions.R
│   ├── path.R
│   ├── process.R
│   ├── protocol.R
│   ├── result.R
│   ├── version.R
│   └── datur-package.R
├── man/
├── tests/
│   ├── testthat.R
│   └── testthat/
│       ├── fixtures/
│       ├── helper-fake-datum.R
│       ├── test-check.R
│       ├── test-conditions.R
│       ├── test-path.R
│       ├── test-process.R
│       ├── test-protocol.R
│       └── test-version.R
├── vignettes/
│   └── datur.Rmd
└── docs/
    └── datum-cli-contract.md
```

Generated files such as `NAMESPACE`, `man/`, and `README.md` must be regenerated
from their sources rather than edited manually.

## 16. Dependencies

Keep runtime dependencies small.

### Proposed `Imports`

- `processx` for safe subprocess management;
- `jsonlite` for JSON parsing;
- `cli` for terminal-aware messages and formatting.

### Proposed `Suggests`

- `testthat` edition 3;
- `withr` for temporary environment and option state in tests;
- `knitr` and `rmarkdown` for vignettes;
- `covr` for optional coverage reporting.

Avoid `R6`, a tibble dependency, or a large framework unless a demonstrated
requirement justifies it. Base data frames are sufficient for the initial
normalized result.

### R version

Proposed minimum: R 4.1.0. Confirm this against the intended user base before
release. Do not use newer language features unless the minimum version is
raised deliberately.

## 17. Documentation requirements

The package must include:

- a README with installation, executable setup, first check, changed and
  unchanged examples, and troubleshooting;
- complete roxygen2 documentation for every exported function and S3 method;
- a getting-started vignette showing interactive and scripted use;
- documentation of executable discovery and precedence;
- a compatibility table listing supported `datum` and protocol versions;
- examples that do not require network access or an installed `datum` binary
  during `R CMD check`;
- a clear statement that `datum` is an external system requirement;
- links to the `datum` installation and configuration documentation.

Proposed `DESCRIPTION` title:

```text
Interface to the 'datum' Data Update Checker
```

Proposed `DESCRIPTION` description:

```text
Provides a typed interface to the 'datum' command-line application for
checking data sources for updates. Runs the external process safely, parses
machine-readable results, and exposes structured R objects for interactive
and automated workflows. The 'datum' executable is installed separately.
```

License is a maintainer decision. MIT is a reasonable default but MUST be
confirmed before package scaffolding is finalized.

## 18. Test strategy

### Unit tests

Tests must not require the real `datum` executable. Provide a controllable fake
executable or process fixture that can emit arbitrary stdout, stderr, delays,
and exit statuses.

Required cases:

- executable found via each supported discovery mechanism;
- executable not found;
- paths containing spaces and non-ASCII characters;
- valid version strings and malformed version output;
- minimum, older, and newer CLI versions;
- unchanged result;
- one changed target;
- multiple changed targets;
- partial failure if supported by the CLI;
- ordinary CLI error;
- nonzero “changes found” status if that is part of the CLI contract;
- timeout and child-process termination;
- user interrupt where testable;
- empty stdout;
- malformed JSON;
- unsupported schema version;
- additive unknown JSON fields;
- unknown normalized status;
- stderr preservation without duplicate printing;
- `quiet` and non-interactive behavior;
- secret redaction;
- `print()`, `summary()`, and `as.data.frame()` stability;
- working-directory isolation;
- option and environment restoration after errors.

### Protocol fixtures

Store sanitized fixtures for every supported response shape and schema version.
Each fixture must identify the `datum` version that produced it. Prefer full
representative responses over hand-built fragments.

### Integration tests

Real-CLI tests must be opt-in, skipped on CRAN, and gated by an explicit
environment variable such as `DATUR_INTEGRATION_TESTS=true`. Integration tests
must use temporary, non-sensitive data and a deterministic local or approved
test source.

### Continuous integration

Test at least:

- current R release on Linux, macOS, and Windows;
- R devel on Linux;
- the oldest supported R version on Linux.

Run `R CMD check` without an installed `datum` binary to prove that package
checks and examples are self-contained.

## 19. Quality requirements

- `R CMD check` completes with zero errors and zero warnings.
- New-submission notes are documented and minimized.
- Exported functions have runnable examples or explicitly justified
  `\dontrun{}` examples.
- All public behavior is covered by deterministic tests.
- Code is formatted consistently and passes the repository's configured linter.
- Public functions validate inputs before launching a process.
- Package startup is silent; do not emit attachment messages.
- Results print legibly in narrow and non-color terminals.
- No test or example writes outside a temporary directory.
- No test depends on the public internet.

## 20. Implementation phases

### Phase 0: CLI contract

Deliverables:

- `docs/datum-cli-contract.md`;
- captured, sanitized protocol fixtures;
- explicit exit-code and version-compatibility decisions;
- confirmation that a stable machine-readable mode exists.

Exit criterion: maintainers can review the exact boundary between `datum` and
`datur` without reading implementation code.

### Phase 1: Package skeleton and executable discovery

Deliverables:

- package metadata and license decision;
- `datum_path()`, `datum_available()`, and `datum_version()`;
- typed conditions for discovery and version failures;
- unit tests using a fake executable.

Exit criterion: discovery works on supported operating systems and tests pass
without a real `datum` installation.

### Phase 2: Low-level process adapter

Deliverables:

- `datum_run()`;
- `datur_process_result`;
- timeout, interrupt, stderr, redaction, and working-directory handling;
- exhaustive process tests.

Exit criterion: arbitrary argument vectors are executed without a shell and all
failure modes produce structured conditions.

### Phase 3: High-level check API

Deliverables:

- `datum_check()`;
- protocol validation and normalization;
- `datur_check_result` and S3 methods;
- fixture-based tests for every supported response shape.

Exit criterion: changed and unchanged checks return stable, documented R
objects, and malformed or incompatible responses fail clearly.

### Phase 4: Documentation and release hardening

Deliverables:

- README and vignette;
- compatibility table and troubleshooting guide;
- cross-platform CI;
- package website configuration if desired;
- CRAN preparation files and reverse-dependency review if applicable.

Exit criterion: the package passes checks on all target platforms and a new
user can complete the getting-started workflow from documentation alone.

## 21. Version 1.0 acceptance criteria

Version 1.0 is complete when all of the following are true:

1. `datur::datum_available()` reliably reports executable availability.
2. `datur::datum_version()` reports and validates the installed CLI version.
3. `datur::datum_check()` can represent both “changed” and “unchanged” as
   successful structured results.
4. Multiple detected changes are available as documented tabular data.
5. `datur::datum_run()` safely supports advanced CLI arguments without a shell.
6. Missing executables, timeouts, CLI errors, and protocol errors use distinct
   condition classes.
7. Paths and arguments containing spaces work on Linux, macOS, and Windows.
8. Automated package checks pass without network access or a real `datum`
   executable.
9. The package never installs `datum`, changes the R working directory, or
   mutates global options as a side effect.
10. README and vignette examples explain executable setup, checks, result
    inspection, and error handling.
11. The supported `datum` versions and protocol schemas are documented.
12. `R CMD check` reports zero errors and zero warnings on the target matrix.

## 22. Open decisions

The maintainer must resolve these items during Phase 0:

- canonical `datum` command and machine-readable option;
- exact exit-code semantics;
- normalized unit represented by each `records` row;
- minimum supported `datum` version;
- whether partial source failures return a result, a warning, or an error;
- whether the initial release supports target selection;
- desired package license;
- source repository and documentation URLs;
- minimum supported R version;
- whether Windows is a release-blocking platform for `datum` itself;
- whether `datum` has a stable protocol schema version or needs one added.

Record resolved decisions in this document and `docs/datum-cli-contract.md`.
Do not leave implementation behavior implicit.

## 23. Instructions for Codex

When implementing this specification:

1. Inspect repository instructions and existing code before making changes.
2. Complete Phase 0 before writing the protocol parser.
3. Do not guess CLI arguments, output fields, exit codes, or version semantics.
4. Keep CLI-specific logic behind the internal adapter boundary.
5. Implement one phase at a time and run the narrowest relevant tests after
   each change.
6. Preserve unrelated user changes in the worktree.
7. Prefer small runtime dependencies and base S3 objects.
8. Do not add speculative exports.
9. Do not invoke a shell with user-controlled values.
10. Do not make internet access or a real CLI installation necessary for normal
    package tests.
11. Update documentation and tests in the same change as public behavior.
12. Stop and report a blocker when the CLI lacks a stable machine-readable
    contract rather than hiding the problem in brittle parsing code.

### Suggested first Codex task

```text
Read datur-package-spec.md and the datum repository documentation. Complete
Phase 0 only: inspect the actual datum CLI, document its commands, JSON schema,
exit codes, version behavior, configuration precedence, and failure modes in
docs/datum-cli-contract.md. Add sanitized output fixtures where appropriate.
Do not scaffold or implement the R package yet. Report any mismatch between the
CLI and the assumptions in the specification, especially the absence of a
stable machine-readable output mode.
```
