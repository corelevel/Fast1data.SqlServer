# Implementation Plan: Unify Audit Discovery

**Branch**: `dev` (existing Git branch) | **Date**: 2026-10-28 | **Spec**: [spec.md](spec.md)

**Feature context**: `001-unify-audit-discovery`; the setup script's `BRANCH` field is this feature identifier, not the current Git branch.
**Input**: `specs/001-unify-audit-discovery/spec.md`

## Summary

Keep one audit filename interpretation and one result projection in `Get-SqlAuditFile`. Introduce one private `Get-SqlAuditFileEntry` helper for Windows file enumeration and Linux SMB execution/row interpretation. Buffer listings before projection, reject remote process failures, and restore borrowed process credentials on every exit path. Preserve discovery's request/results, caller responsibilities, and SQL Server's independent file access.

Phase 0 decisions and primary-source evidence are recorded in [research.md](research.md). Phase 1 defines the [data model](data-model.md), [discovery contract](contracts/discovery.md), and [validation guide](quickstart.md). Implementation and task generation are subsequent workflows.

## Technical Context

**Language/Version**: PowerShell 7.4 or later, Core edition, matching the manifest and constitution.

**Primary Dependencies**: Existing PowerShell filesystem cmdlets and Linux `smbclient`. The module already requires `SqlServer` and bundles `Microsoft.Data.SqlClient`; discovery adds no dependency. Pester 5 is a development/test prerequisite for the existing test style.

**Static Analysis Prerequisite**: PSScriptAnalyzer is required for development validation; install it with `Install-Module PSScriptAnalyzer -Scope CurrentUser` when unavailable. It adds no production runtime dependency. Use the project's analyzer configuration when available.

**Storage**: Filesystem listing metadata only. No SQL schema, checkpoint, persisted state, or audit-content change. `PASSWD` is temporary process state.

**Testing**: Pester through `Get-SqlAuditFile`, native Windows filesystem cases, controlled enumeration/process cases, and a separate real Linux SMB suite. Retain existing audit/module contract tests. Record unavailable checks as unrun.

**Target Platform**: Discovery supports x64 Windows local/UNC folders and x64 Linux UNC shares with supplied credentials. Other discovery operating systems terminate as unsupported. Module-wide Windows/Linux/macOS support remains unchanged.

**Project Type**: PowerShell library module with public command `Invoke-Fast1Audit` and private discovery functions.

**Performance Goals**: One nonrecursive enumeration/process per discovery call and one filename-rule application per file candidate. Linear processing in listing size; no throughput or latency target is introduced. Buffering requires memory proportional to the listing, including non-audit entries on Linux.

**Constraints**: Preserve `Folder`/`Credential`, `FileName`/`AuditGuid`, one result per file, and existing platform scope. No generic filesystem framework, public adapter selector, new transport, recursive search, sorting, or deduplication. Never emit supplied passwords. Borrowed process environment assumes serialized discovery within the host process.

**Scale/Scope**: One directory per call; one new private helper, focused discovery/test changes, and audit help/documentation. The importer, SQL objects, batching, checkpoints, and other module features retain their current responsibilities.

## Constitution Check

Pre-research gates were assessed against the specification and current code; the post-design assessment uses the artifacts linked above.

| Gate | Pre-research | Post-design evidence |
| --- | --- | --- |
| I: prevent silent discovery omissions and preserve resumability | PASS: errors remain distinguishable from empty success; no persisted-progress change | PASS: buffer listings, reject failed enumeration before results, preserve individual files and caller grouping |
| II: deterministic migrations | PASS: migration behavior is outside scope | PASS: no migration files, execution paths, or history changes |
| III: surface failures and protect secrets | PASS: terminating errors and cleanup are explicit requirements | PASS: native status checking, sanitized exceptions/diagnostics, and exact credential restoration on all exits |
| IV: preserve PowerShell contracts and runtime/platform scope | PASS: existing private interface and public exports retained | PASS: one private helper loaded by the existing loader; no manifest/runtime/dependency change; audit documentation updates planned |
| V: verification and operational visibility | PASS: discovery-interface and real SMB evidence required | PASS for design: coverage matrix and runnable guide distinguish controlled tests from real process checks and record unavailable environments |
| Workflow: focused abstractions and affected documentation | PASS: two existing transports justify one seam | PASS: no generic adapter framework; changes limited to discovery, affected tests, help, and audit guidance |
| Workflow 6–11: PowerShell Static Analysis | Required for every new or modified `.ps1`, `.psm1`, and `.psd1`, including tests and fixtures | PENDING: analyzer execution with project settings when available, finding classification, remediation, and recorded results |

**Gate result**: Static-analysis compliance remains pending; no exception is proposed. PowerShell-changing tasks cannot be considered complete until analyzer validation is recorded and all newly introduced errors and warnings are resolved. Required native Windows UNC and Linux SMB evidence also remains pending, as recorded in the quickstart. SQL Server execution is not changed, so this feature requires no new database integration scenario; existing SQL/audit contract regression coverage remains required.

## Project Structure

### Documentation (this feature)

```text
specs/001-unify-audit-discovery/
|-- spec.md
|-- checklists/requirements.md
|-- plan.md
|-- research.md
|-- data-model.md
|-- quickstart.md
`-- contracts/discovery.md
```

`tasks.md` is a later `$speckit-tasks` output and is not generated by this planning run.

### Source Code (repository root)

```text
Fast1data.SqlServer/
|-- Fast1data.SqlServer.psd1                 # existing exports/baseline
|-- Fast1data.SqlServer.psm1                 # existing recursive private loader
|-- private/audit/
|   |-- Get-SqlAuditFile.ps1                 # single filename rule + projection
|   |-- Get-SqlAuditFileEntry.ps1            # planned private listing seam
|   `-- Import-SqlAuditFile.ps1              # existing SQL reader boundary
|-- public/Invoke-Fast1Audit.ps1             # existing discovery caller
`-- tests/
    |-- Audit.Tests.ps1                     # existing contracts/local smoke checks
    |-- Audit.Discovery.Tests.ps1           # planned controlled/native discovery cases
    `-- Audit.Smb.Tests.ps1                 # planned tagged real Linux SMB cases
Fast1Audit.md                               # affected operator guidance
```

**Structure Decision**: Use the current module layout. Keep the filename rule and public-facing result projection together. The single new helper owns both existing listing implementations and returns transport-neutral file candidates. It remains private and requires no loader change.

## Phase 0: Research outcome

Resolved the private seam, filename ownership, SMB row interpretation, successful empty-listing strategy, native error preferences, credential lifecycle, test boundaries, and SQL read permissions. See [research.md](research.md) for decisions, rationale, alternatives, and sources. No unresolved technical clarification remains.

## Phase 1: Design

### Discovery flow

1. `Get-SqlAuditFile` binds the existing request and captures the complete output of `Get-SqlAuditFileEntry` before publishing any result.
2. The helper selects the platform. Windows enumerates files with literal paths and terminating errors. Credentials remain unused on Windows.
3. Linux validates a UNC share root, credentials, and the executable; splits share and nested directory without losing spaces; invokes `smbclient` with separate argument values and static command `ls`.
4. Around native invocation, snapshot `PASSWD` presence/value, temporarily assign the supplied password, capture output/status, and restore prior state in `finally`. Locally control native error preference. Surface invocation/nonzero-exit failures only through sanitized terminating errors.
5. On successful listing, normalize only genuine file rows to `Name`/`FullName`; ignore directories, headers, and status/footer text.
6. Discovery applies its single anchored filename rule and returns `FileName` plus GUID-typed `AuditGuid` for each match. Successful zero matches emit no objects.
7. `Invoke-Fast1Audit` continues grouping GUIDs and calling the importer. It receives no new transport or parsing responsibilities.

The [data model](data-model.md) describes transient records and lifecycle. The [contract](contracts/discovery.md) defines observable behavior and internal responsibilities.

### Verification mapping

| Requirement / outcome | Required evidence |
| --- | --- |
| FR-001, FR-002, FR-003; SC-001 | Equivalent controlled listings through discovery, shared filename cases, repeated GUIDs, type/full-path assertions, metadata and directory rejection |
| FR-004; SC-002 | Windows local/UNC scope, Linux credential/UNC/prerequisite validation, Windows credential non-use, unsupported OS; isolate platform state in tests |
| FR-005, FR-006; SC-002 | Empty/rejected-only success, terminating Windows failure, invocation exception, nonzero SMB exit containing valid-looking rows, zero failure results |
| FR-007; SC-003 | Four exit conditions crossed with absent/pre-existing process credentials; inspect all output streams and error details for sentinel secrets |
| FR-008, FR-009; SC-004 | Tests call discovery and mock existing transport boundaries; separate real Linux SMB populated/empty/failure runs without process mocks |
| FR-010; SC-005 | Preserve discovery call/result shape and existing caller regressions; document separate SQL Server permissions |
| Constitution Workflow 6–11 | `Invoke-ScriptAnalyzer` on every new or modified PowerShell file, project configuration when available, resolution of new errors/warnings, reporting of unrelated existing findings and unavailable execution; no rule suppression solely to bypass validation |

Use isolated module-scope platform variables only in controlled tests; restore them and environment state after each case. Native Windows and real Linux tests run on their actual platforms. Correct existing test-path casing to `private/audit` and `schema/audit`, and gate existing local-folder discovery scenarios to Windows. Preserve the user's existing test edits. Do not infer Linux support from Windows fixtures.

Static-analysis evidence must identify the analyzer version, configuration, complete file scope, findings, baseline used to classify pre-existing findings, and remediation. Re-run analysis on files changed during remediation, plus affected Pester coverage when behavior changes. Unrelated existing findings must be reported and should not block completion. If analysis cannot run, record the reason and retain pending status; do not report validation as successful. The quickstart provides the procedure and T031 schedules this gate before the final review and evidence record.

### Operational documentation

Update discovery helper help and `Fast1Audit.md` with Linux prerequisites and credential usage, empty-success versus terminating-error behavior, credential restoration, and independent SQL Server service access. Preserve the documented single-process audit-directory requirement.

## Validation status and workflow context

Planning host observations: PowerShell 7.6.6 on Windows; only Pester 3.4.0 detected. Pester 5, SqlServer, bundled client assets, Linux `smbclient`, and a real share/credential environment were unavailable. No runtime or database verification was performed. [quickstart.md](quickstart.md) specifies implementation-time commands and expected evidence.

The saved `.specify/feature.json` points to nonexistent specification context `002-unify-audit-discovery`. This planning run used explicit `SPECIFY_FEATURE_DIRECTORY` for `001` and `SPECIFY_FEATURE_NO_PERSIST=1`, leaving saved metadata unchanged. Use the same override for follow-up workflows, as shown in the quickstart. Git remains on `dev`.

## Complexity Tracking

No constitution exceptions. One private helper is justified by the two existing transports; no additional abstraction layer or dependency is planned.
