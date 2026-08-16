# `datum` CLI contract for `datur`

**Status:** Phase 0 complete  
**Reviewed CLI release:** `datum` 1.5.0 (`v1.5.0`)
**Oldest supported CLI release:** `datum` 1.2.1  
**Protocol designation in `datur`:** implicit JSON protocol v1

This note records the process boundary that `datur` may rely on. It was verified
against the local [`jprybylski/datum`](https://github.com/jprybylski/datum)
repository, the `v1.3.0` protocol fixtures, and the `v1.5.0` source tag.

## Compatibility decision

`datum` added machine-readable output in 1.2.1 and is currently released as
1.5.0. The JSON document does not contain a separate `schema_version` field, so
`datur` will treat the CLI release version as the protocol compatibility gate:

- reject `datum` versions older than 1.2.1;
- support the implicit JSON protocol v1 emitted by `datum` 1.2.1 through 1.x;
- tolerate additive JSON fields for supported 1.x releases;
- reject unknown status values rather than guessing their meaning;
- reject `datum` 2.x until its protocol has been reviewed;
- report `datum dev` as an unparseable development version unless an explicit
  future development-mode policy is adopted.

The implicit protocol v1 designation belongs to `datur`; it is not emitted by
`datum`. Adding an explicit protocol version to `datum` remains desirable, but
the released CLI version and tagged source provide a usable compatibility
boundary for initial development.

## Commands used by `datur`

### Version

```text
datum --version
```

Release output is one line on stdout:

```text
datum v1.3.0
```

Locally built binaries omit linker metadata and print `datum dev`.

### High-level check

```text
datum --json --no-color \
  [--config PATH] [--lock PATH] \
  [--timeout DURATION] [--concurrency COUNT] \
  check
```

All flags must precede the subcommand. `datum check` checks every configured
dataset; it does not support selecting target IDs. Extra arguments after
`check` are currently ignored and must never be used by `datur` as selectors.

`datur` will initially use a concurrency of `1`. This preserves deterministic
behavior and avoids the documented race hazard when datasets share a target
directory.

### Low-level execution

`datum_run()` may execute arbitrary argument vectors. Its contract is the raw
CLI contract and is intentionally less stable than `datum_check()`.

### Configuration metadata (datum 1.4.0+)

```text
datum schema
datum --json --no-color types [TYPE ...]
```

`schema` emits the exact embedded draft-07 JSON Schema for `.data.yaml`.
`types` emits `{"types": [...]}`; each type has `type`, `description`, and a
`fields` array whose entries contain `name`, `required`, and `description`.
`datur` uses both documents when constructing and validating configuration
edits. These commands require datum 1.4.0 but do not raise the package-wide
minimum needed by older APIs.

### Audit and deletion (datum 1.3.0+)

```text
datum --json --no-color [--config PATH] [--lock PATH] audit
datum --no-color [--config PATH] [--lock PATH] --yes delete ID [ID ...]
```

Audit is read-only and emits an `entries` array with `ok`, `pending`, `deleted`,
or `orphaned` state. Delete removes tracked local files and marks lockfile
entries deleted; `datur` performs confirmation in R and always passes `--yes`
to keep the subprocess non-interactive.

### Help discovery

`datum --help` prints global usage and exits 2. There is no independent
subcommand help parser: `datum check --help` begins a normal check because Go's
flag parser stops processing flags at the subcommand. `datur` must not use
`datum check --help` for capability detection.

## Configuration and working directory

`datum` has no configuration search path or environment variable for selecting
the configuration file. It uses:

1. `--config PATH`, otherwise `.data.yaml`;
2. `--lock PATH`, otherwise `.data.lock.yaml`.

Those paths, file-handler source paths, targets, and command-handler execution
are resolved relative to the subprocess working directory. `datur` must set the
child working directory directly and must not change the R process working
directory.

### Environment references in configuration (datum 1.5.0+)

Any string value parsed from `.data.yaml` may contain a `${NAME}` environment
reference. `datum` expands references after YAML parsing and before runtime
schema validation or use. Consequently, YAML-significant characters in a
substituted value do not change the parsed document's structure.

- Names match `[A-Za-z_][A-Za-z0-9_]*`.
- An unset name is a configuration error; an explicitly empty value is valid.
- Only `${NAME}` is expanded. Plain `$NAME` remains unchanged for command
  sources.
- `$${NAME}` escapes a literal `${NAME}`.
- Expansion applies to values, not YAML mapping keys.

The original placeholders remain in `.data.yaml`, and expanded configuration
values are not copied into the lockfile. Callers must provide variables in the
child's inherited environment. This feature does not change the JSON protocol
version and does not raise the package-wide minimum required for projects that
do not use environment references.

`NO_COLOR` disables color in text mode. `--no-color` is still passed in JSON
mode for defensive consistency. `--timeout` accepts Go duration syntax, defaults
to `5m`, and accepts `0` to disable the CLI's deadline. `--concurrency` defaults
to 1; values below 1 are coerced to 1.

## Output streams

For the reviewed implementation, version text, usage, human-readable results,
JSON results, configuration errors, lock errors, and lock-write errors are all
written to stdout. The CLI does not intentionally write to stderr.

`datur` must still capture both streams because dependencies or future releases
may emit diagnostics on stderr. It must parse only stdout as JSON.

## Exit codes

| Exit | Meaning | JSON form |
| ---: | --- | --- |
| 0 | Successful run. May still contain changed data under `log` or `update` policy. | `results` document |
| 1 | At least one changed dataset under `fail`, a dataset/source failure, or a lock write failure. | `results` document |
| 2 | Invalid usage, configuration read/parse error, or lock read/parse error. | Usually top-level `error`; invalid usage remains text |

Exit 1 is not sufficient to classify the result. `datur` must inspect every
record status and `lock_write_error`. A detected update is data, not an R error.

## Implicit JSON protocol v1

### Successful or partially successful check

```json
{
  "results": [
    {
      "id": "dataset-id",
      "status": "ok",
      "message": "optional detail",
      "lock_fingerprint": "optional prior fingerprint",
      "remote_fingerprint": "optional observed fingerprint",
      "warnings": ["optional fallback warning"]
    }
  ],
  "lock_write_error": "optional lock persistence error"
}
```

Fields marked optional are omitted rather than set to null. `results` is always
an array and preserves dataset order from `.data.yaml`. One result represents
one configured dataset. Additive fields must be tolerated.

Supported check statuses are:

| Status | Meaning | Changed | Typical exit |
| --- | --- | ---: | ---: |
| `ok` | Remote fingerprint matches the lock | no | 0 |
| `updated` | Change detected under `update`; target and lock were refreshed | yes | 0 |
| `stale` | Change detected under `log`; reported without refresh | yes | 0 |
| `fail` | Change detected under `fail` | yes | 1 |
| `warn` | Unknown policy, treated as `fail`; compare fingerprints to determine change | derived | 0 or 1 |
| `error` | Fingerprint or fetch failed for every configured source | unknown | 1 |
| `deleted` | Dataset was marked deleted and skipped | no observation | 0 |

`fetched` is part of the same JSON result type but is emitted by `datum fetch`,
not `datum check`.

### Top-level error

Configuration and lockfile failures occurring before dataset processing use:

```json
{
  "error": "config error: open .data.yaml: no such file or directory"
}
```

This shape exits 2 and contains no `results` field.

### Missing protocol fields

The CLI response does not include a protocol version, check timestamp, duration,
overall status, summary counts, or CLI version. `datur` will:

- assign implicit protocol version 1 after CLI version validation;
- derive overall status and counts from records;
- use process timestamps and duration for R-facing metadata;
- retain the parsed raw document for diagnostics.

## Partial failures and fallback

Multiple sources within one dataset are attempted in order until one succeeds.
Failed attempts are preserved in that dataset's `warnings`. If every source
fails, the record status is `error`.

Processing continues across datasets, so a single response can contain usable
`ok`/changed records and `error` records. The process exits 1. `datur` should
normalize and preserve all records, then raise a structured `datur_cli_error`
containing the partial `datur_check_result`.

## Side effects

`datum check` is not read-only:

- it always rewrites the lockfile and updates `last_checked`;
- the `update` policy may fetch remote data and replace target files;
- successful `update` checks update fingerprints and per-dataset timestamps;
- failed source access may update inaccessible state in the lockfile.

The `.data.yaml` configuration file is never modified by `check`. Network and
cache behavior belongs to source handlers. The git handler maintains a cache,
normally below the user cache directory or `XDG_CACHE_HOME`.

## Timeout and interruption

The CLI deadline covers handler operations for the whole run. A timed-out
dataset normally appears as status `error` and the process exits 1; the JSON
schema does not identify timeout as a distinct machine-readable error. The
command handler may report a killed child process rather than the words
`context deadline exceeded`.

`datur` must therefore enforce its own process deadline with `processx`,
terminate the child cleanly, and raise `datur_timeout` based on the R-side
deadline rather than parsing an error message. User interrupts must terminate
the child and propagate normally.

## Security and privacy hazards

- Environment substitution, available in datum 1.5.0+, keeps resolved values
  out of `.data.yaml` and the lockfile but is not an output-redaction boundary.
  An expanded value can still reach a downstream URL, command, or error.
- HTTP errors can include the configured URL. Embedded URL credentials could
  therefore appear in JSON messages.
- Command-handler failures include combined child stdout and stderr, which may
  contain secrets printed by user commands.
- Git credentials are read from environment variables and are not intentionally
  printed, but dependency errors still require redaction before display.

`datur` redacts sensitive argument values, URL user information, values passed
through named sensitive entries in `datum_run(env = ...)`, and matching
captured messages before printing or embedding them in conditions. It cannot
reliably classify every value inherited from the parent R environment, so
users should prefer purpose-built handler authentication variables and avoid
printing secrets from commands. Raw process data should remain accessible only
where doing so does not violate the package's redaction guarantees.

## Known compatibility hazards

1. The JSON document has no explicit schema version; compatibility is keyed to
   the released CLI version.
2. `deleted` was added in `datum` 1.3.0, so 1.2.x never emits it.
3. Exit 1 combines changed data, operational errors, and lock persistence
   errors.
4. Exit 0 can still represent changed data (`stale` or `updated`).
5. `check` cannot select individual dataset IDs.
6. `check` can mutate targets under the `update` policy.
7. CLI timeout failures are not typed in JSON.
8. Errors are written to stdout, including in JSON mode.
9. Flags placed after the subcommand are not parsed.
10. Development builds report `dev` rather than a semantic version.
11. Configuration environment substitution was added in `datum` 1.5.0; older
    supported releases treat `${NAME}` as literal text.

## Fixture provenance

Sanitized fixtures live in
`tests/testthat/fixtures/datum-1.3.0/`. They were captured from a binary built
from the `v1.3.0` tag with `-ldflags '-X main.version=v1.3.0'`, using only local
file sources and synthetic paths. No credentials or machine-specific workspace
paths are present.
