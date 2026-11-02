# Implementation validation

Revision before implementation: `c7d313781ca73a6f7073b19ea0692ea6c2d7ccaa` on `dev`.
Host: Linux x64. PowerShell 7.6.6; Pester 6.2.0; PSScriptAnalyzer 1.25.0; SqlServer 22.4.5.1.
Bundled SqlClient assets are present for win-x64, linux-x64 and osx-x64.

## Fresh baseline

`Audit.Common.Tests.ps1` in a fresh `pwsh -NoProfile` process: 4 discovered, 3 passed, 1 failed, 0 skipped. The retained adverse-import regression expected exactly one verbose message and received zero. This execution independently reproduces the planning evidence. No logger mock or assertion change was made.

The public contract was captured before production edits in `tests/fixtures/SharedHelpers.PublicContract.json`. It includes manifest exports/runtime, declared parameter AST (defaults/validation/attributes), normalized command metadata, aliases, common parameters and parameter sets.

## Environment

The user authorized the existing integration test configuration for disposable SQL validation. No credentials are reproduced here. Alternate host connection locations have not been supplied. Controlled discovery excludes integration filenames before Pester discovery; packaging runs live tests.

## Regression and controlled development results

- Audit common after the repair: 4/4 passed, including the unchanged adverse-import exact-one assertion.
- Archiving execution after the repair: 28/28 passed. The new behavioral test failed before production edits (zero instead of three real verbose records), then passed. It asserts one configuration allocation, one completion write and one release, plus real nested archive/purge progress.
- Root/model SQL and cleanup suite: 25/25 passed. Command text/type, parameter types/values/null/size/precision/scale, scalar/non-query output, borrowed connection lifetime, construction/validation/execution errors and cleanup-only/combined failures are covered.
- A complete representative L5/MRA worker passed all 135 assertions before the final failure-preference case was added. Final workers require exactly 136 assertions, not merely nonzero discovery.
- Migration preview assertions previously compared unformatted message strings. They now normalize only the timestamp/level prefix, check actual stream record types and retain exact semantic contents/counts, including evaluation and no-work messages.

### Forced import scope

L5 forces all three internal modules twice, including ArchivingModel. PowerShell retains the root adapter's original parsed class-module instance while a forced import registers a refreshed instance. Initial tests incorrectly placed class-provider mocks in the refreshed instance. Targeting Pester's `Fast1data.SqlServer/ArchivingModel` nested scope correctly exercises the original class consumer; direct owner/SQL assertions also inspect the refreshed model. A full L5/MRA worker passes 136/136 with these scopes. No global mock routing, favorable re-import, class replacement or production loader change is used. This is unchanged-module import compatibility, not changed-class hot reload.

## Live source SQL

The first sandboxed run could not connect. The same command was retried with network escalation using the user-selected existing fixtures: **40 passed, 0 failed, 0 skipped** (Archiving 29, Migration 7, Linux audit 4). No fixture credentials are recorded here.

Evidence includes real interrupted copy/delete/checkpoint retry, composite-key/page-bound recovery, earlier-table completion, independent FK restoration attempts, migration SHA-256/force/ignore/WhatIf/history recovery, and audit saved-offset/ignored-record/lost-response recovery. Linux audit used four immutable files containing four source records. Every suite retains unique database allocation and teardown.

## Final source acceptance

`evidence/source-controlled.json`: **190 discovered, 183 passed, 0 failed, 7 expected Windows-only skips** on Linux. The matrix independently passed **30 unique tuples × 136 cases = 4,080 worker cases**, with zero failures, skipped cases or missing tuples. Retained audit regression: 4/4. The worker includes six ambient/explicit combinations, both sequential directions, function-local ambient settings and unchanged preferences after failures; warnings retain stream 3 and verbose messages stream 4. Helper definitions retain their expected module/session state and selected-root source paths; literal classes and fixed full public metadata pass.

`evidence/source-live.json`: the final live rerun also passed **40/40**, with no skips. Together these complete the controlled source and live source gates. Windows-only skips do not establish Windows validation.

`evidence/analyzer.json`: all 16 changed/new PowerShell files passed PSScriptAnalyzer 1.25.0 with **zero warnings/errors**. No repository analyzer settings file was found. An AST-based control-block check found no single-line control-flow blocks or combined closing-brace lines; `git diff --check` also passed. No rules or packaging filters were suppressed.

## Requirement review

| Requirement | Evidence | Remaining gate |
|---|---|---|
| FR-001 / FR-002 | Inventory owner/session-state/path assertions in every tuple; root identity retained across adverse imports; zero internal command exports | None on Linux; T029 covers alternate hosts |
| FR-003 / SC-001 / SC-002 | Real stream records, timestamp/level format and exact semantic counts; six ambient/explicit combinations, both sequential orders, local ambient and failure preference checks | None on Linux; T029 covers alternate hosts |
| FR-004 | Original exact-one adverse-import audit regression unchanged; source 4/4 | None on Linux; T029 covers alternate hosts |
| FR-005 | Real nested archiving logs and warnings; actual class execution through local query/cleanup helpers | None on Linux; T029 covers alternate hosts |
| FR-006 / SC-003 | Fixed manifest/parameter/command-attribute snapshot, exactly three public commands, all three runtime directories | T029: Windows/macOS execution |
| FR-007 | Literal using-module fixture constructs seven classes; old Execute(), typed overload, and single-use checks pass | T029: Windows/macOS execution |
| FR-008 / FR-009 / SC-004 | 128 supplemental controlled cases per worker and 40 live SQL cases establish unchanged order/checksum/checkpoint/retry/cleanup/constraint outcomes | None on Linux; T029 covers alternate hosts |
| FR-010 / SC-005 | Source 30/30 tuples, each with all three operations in the selected order and 136 cases | T029: Windows/macOS execution |

No implementation changes were made to public commands, manifest, schemas, SQL bodies, runtime assets, dependencies, root loading order or packaging code. Existing user changes to AGENTS.md and the Linux audit fixture share were retained. `.vscode/` is not ignored.

## Host availability

Linux x64 source validation is complete. Windows/macOS connection instructions were requested but not supplied; the existing test settings describe SQL and SMB resources rather than remote PowerShell hosts. Windows/macOS execution is therefore unverified. T029 remains open; runtime asset presence and platform skips are not host validation.

## Actual packaging gate

`out/publish.ps1` completed successfully without modification, staging **Fast1data.SqlServer 0.0.4**. Its complete analyzer gate passed and Pester reported **223 passed, 0 failed, 11 expected Windows-only skips** (234 discovered). This includes the packaged matrix and live SQL suites; no validation bypass or gallery publication was used. See `evidence/package-build.json`.

`evidence/runtime-assets.json` records equal source/package SHA-256 hashes for all three declared SqlClient runtime DLLs. Manifest, production files and fixed public-contract snapshot also match the staged copies.

The required separate fresh-process packaged live run passed **40/40**, with no skips (`evidence/package-live.json`), matching the source live outcomes. Fresh controlled package comparison also passed: **190 discovered, 183 passed, 0 failed, 7 expected Windows-only skips**. All 30 package tuples passed exactly 136 cases each without inner skips.

## Final parity and completion

`evidence/parity.json` verifies exactly **60 unique distribution/loading/order tuples**, **8,160 passing worker cases**, and equal normalized source/package observations. Both fresh controlled runs have identical counts and each fresh live run passes 40/40. The retained audit regression passes in both distributions. All 49 repository module files match their staged copies byte-for-byte; the three runtime DLL hashes match as recorded separately.

**31 of 32 tasks are complete.** T029 remains unchecked solely because no Windows/macOS host access was provided. Linux source/package, complete local packaging, live SQL, changed-file analysis, formatting and requirement review gates passed. Full cross-platform acceptance is not claimed. No extension hooks were registered (`.specify/extensions.yml` is absent).
