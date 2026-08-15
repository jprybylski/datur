# `datum` 1.3.0 protocol fixtures

These files are exact stdout documents from a binary built from the `v1.3.0`
tag with release version metadata. Tests used local file sources only.

| Fixture | Exit | Meaning |
| --- | ---: | --- |
| `check-unchanged.json` | 0 | One unchanged dataset |
| `check-changed-fail.json` | 1 | One changed dataset under `fail` policy |
| `check-partial-error.json` | 1 | One usable result and one source failure |
| `check-config-error.json` | 2 | Failure before dataset processing |

Fingerprints are deterministic hashes of synthetic fixture content. Paths in
errors are relative and contain no machine-specific information.

