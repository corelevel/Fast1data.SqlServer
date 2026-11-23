# Implementation Plan: Per-Table Bulk Copy Timeout

**Branch**: `dev` | **Feature identifier**: `009-add-bulk-copy-timeout` | **Date**: 2026-11-23 | **Spec**: [spec.md](spec.md)

**Input**: `specs/009-add-bulk-copy-timeout/spec.md`; agreed scope in `docs/bulk-copy-timeout.md`.

Setup returned `009-add-bulk-copy-timeout` as `BRANCH` from the selected feature directory. The actual Git branch remains `dev`; no branch switch is required.

## Summary

Persist one required `BulkCopyTimeout` integer per `dbo.SourceTable`, defaulting to 30 seconds. Accept zero for unlimited waiting and positive Int32 values; reject negatives with a database check constraint and nulls with `NOT NULL`. Add the value to `dbo.stp_GetSourceTable`, map it into the existing typed `Table`, and assign it unconditionally to every bulk-copy object before writing in `BulkCopySourcePK()`, `BulkCopyDestinationPK()`, and `BulkCopyTable()`.

Preserve ordinary query timeouts, streaming, batching, copy options, checkpoints, processing order, cleanup, and retry behavior. Keep table setup create-only. Existing installations require documented manual column/default/constraint preparation, backfill of every existing row to 30, and metadata-procedure deployment before running the changed module. No migration script or automatic schema repair is introduced.

## Technical Context

**Language/Version**: PowerShell 7.6+ Core and T-SQL; dependency project targets .NET 10 (`net10.0`).

**Primary Dependencies**: Existing bundled Microsoft.Data.SqlClient 7.1.2; existing Microsoft.SqlServer.TransactSql.ScriptDom 180.154.0 remains unchanged. No new dependencies or version upgrades.

**Storage**: SQL Server archiving configuration (`dbo.SourceTable`) and metadata procedure (`dbo.stp_GetSourceTable`). Existing `TableGroup`, `ProcessState`, source/destination data, and working-table formats remain unchanged.

**Testing**: Pester controlled execution tests plus SQL Server integration tests for database constraints, metadata, real copy timing, and recovery. Use PSScriptAnalyzer on every modified PowerShell file with repository settings when present. No analyzer configuration was found during planning.

**Target Platform**: x64 Windows and x64 Linux, preserving the module's current PowerShell and SQL Server prerequisites. Existing integration cases use `generate_series`, requiring SQL Server 2022+ and compatibility level 160+ for those cases.

**Project Type**: PowerShell SQL Server administration module with administrator-managed SQL configuration.

**Performance Goals**: Preserve streaming and batch sizes; add only a metadata integer and a property assignment per copy object. No new throughput target. Timing validation uses controlled blocking and broad deadlines rather than exact elapsed-time assertions.

**Constraints**: `int NOT NULL`, named default 30, named check `BulkCopyTimeout >= 0`; zero must survive unchanged. No query-timeout assignments, new public parameters, automatic alterations, compatibility fallback, migration scripts, retries, or changes to working sets and completion rules. Use tab-indented multiline PowerShell blocks. Preserve explicit manifest exports and keep `.vscode/` out of new ignore rules.

**Scale/Scope**: One configuration column, one procedure result column, one reader mapping, one typed property, three copy sites, focused existing test suites, archiving guide, command help, and release metadata when a release version is selected.

## Constitution Check

Active constitution: **2.0.0**. Pre-research gate: **PASS**. Post-design gate: **PASS** for design. These results assess the planned work; they do not claim implementation or release verification has run.

| Gate | Pre-research commitment | Post-design evidence / implementation obligation |
| --- | --- | --- |
| I. Data integrity and resumability | Change only timeout configuration and propagation | Keep working sets, batching/order, independent commits, and checkpoint rules; verify timeout/interruption failure and retry without premature completion. |
| II. Deterministic migrations | Preserve migration workflow and history | No migration files, history edits, or changes to migration execution. |
| III. Explicit database operations | Scope deployment and tests to administrator-selected databases | Keep the existing create-only guard; document manual preparation order and permissions; use parameterized test values and validated fixture identifiers. Never print secrets. |
| IV. Portable PowerShell contracts | Preserve platforms, baseline, exports, and command signatures | Extend the SQL configuration/result contract; update guide and command help together. Review manifest release notes and record an explicit release-version decision before release. |
| V. Verification and visibility | Verify copying and database behavior at appropriate boundaries | Actual-method controlled tests for all three copies; live defaults/constraints/metadata, timing and recovery tests; unchanged query timeout evidence. Record unavailable checks as unrun. |
| Database/runtime constraints | Preserve source/configuration colocation, PK and single-process requirements | No new progress format or dependency. Tests use disposable databases on an explicitly selected SQL instance. |
| Development workflow | Analyze every modified `.ps1`, `.psm1`, and `.psd1` | Use repository settings if available; resolve new findings and report unrelated baseline findings. This planning run edits Markdown only. |
| Governance and compatibility | Document the existing-installation prerequisite | Schema preparation is mandatory; no transparent old-schema support. Current module is 0.2.1. Maintainer release-version selection and matching manifest/release notes are a release gate, as specified, rather than an unresolved technical design question. |

No constitution exception is required. Unrun live checks, unresolved material recovery risks, or an absent release-version decision block release.

## Project Structure

### Documentation (this feature)

```text
specs/009-add-bulk-copy-timeout/
|-- spec.md
|-- checklists/requirements.md
|-- plan.md
|-- research.md
|-- data-model.md
|-- quickstart.md
`-- contracts/
    `-- bulk-copy-timeout.md
```

`tasks.md` is future `$speckit-tasks` output and is not generated by this workflow.

### Source Code (repository root)

```text
Fast1data.SqlServer/
|-- schema/archiving/
|   |-- tables.sql                      # Extend create-only SourceTable definition
|   `-- sprocs.sql                      # Extend stp_GetSourceTable projection
|-- private/archiving/
|   `-- ArchivingModel.psm1             # ReadSourceTables, Table, three copy methods
|-- public/
|   `-- Invoke-Fast1Archiving.ps1        # Configuration/upgrade help; same signature
|-- tests/
|   |-- Archiving.Execution.Tests.ps1   # Metadata and actual copy-method coverage
|   `-- Archiving.Integration.Tests.ps1 # Schema, timing, preparation, recovery
`-- Fast1data.SqlServer.psd1             # Release notes/version at release decision
Fast1Archiving.md                       # Configuration, preparation, recovery
```

**Structure Decision**: Extend existing storage, reader, model, and copy methods directly. Reuse `Get-ArchivingBulkCopy` as the test seam without changing its signature or adding a production abstraction. Keep feature tests in the existing archiving suites; test-local helpers are appropriate for blocking/timing fixtures.

## Phase 0: Research Outcome

[research.md](research.md) resolves provider semantics, the metadata-to-model path, test seams, create-only deployment behavior, manual preparation, and failure/query-timeout isolation. Phase 0 included delegated repository validation research and provider research against official documentation and the exact SqlClient version. No technical clarifications remain.

## Phase 1: Design

1. Inside the existing `dbo.SourceTable` creation branch, add `BulkCopyTimeout int NOT NULL` with `DF_SourceTable__BulkCopyTimeout DEFAULT (30)` and `CK_SourceTable__BulkCopyTimeout CHECK (BulkCopyTimeout >= 0)`. Keep the check/default within that guarded definition. Do not add an existing-table alteration branch.
2. Add a named `BulkCopyTimeout` result column to `dbo.stp_GetSourceTable`. Read the required field by name using `$sqlReader.GetInt32($sqlReader.GetOrdinal('BulkCopyTimeout'))` into the values passed to `Get-ArchivingTable`. Add `[int]$BulkCopyTimeout` without an initializer beside the existing batch-size properties. SQL configuration owns the default; normal execution requires and maps the database column. Private direct construction must explicitly supply a timeout before copying. Do not catch missing metadata or replace zero with 30.
3. In every new bulk-copy object in the three existing methods, assign `$bulkCopy.BulkCopyTimeout = $this.BulkCopyTimeout` before `WriteToServer`. Destination-key copying creates an object for each page, so configure each page. Preserve factory signature, readers, options, mappings, batch sizes, streaming, and resource ownership.
4. Extend controlled metadata fixtures to include the new result column. Assert loaded values and timeout at entry to the overridden `WriteToServer` while executing each real copy method. Cover 30, 120, zero, Int32 maximum, differing tables in one group, repeated reconciliation pages, and skipped/no-row stages. Existing execution tests bypass key-copy methods, so the existing archive-data write assertion alone is insufficient.
5. Extend live integration tests for defaulted inserts, valid boundaries, negative/null inserts and updates, unchanged values after rejected updates, procedure-to-model mapping, setup rerun behavior, and manual preparation of a legacy test schema. Exercise real positive timeout and zero waiting beyond 30 seconds with blocking isolated to the write target, plus timeout failure/retry. Assert existing query limits under a distinct connection `Command Timeout`, including zero bulk timeout. Preserve existing cleanup and interruption regression coverage.
6. Update `Fast1Archiving.md` with units, values, all three affected operations, query-timeout independence, and manual preparation before procedure deployment/module execution. Replace the guide's existing claim that no persistence/procedure upgrade is needed. Update command help with the new configuration prerequisite. Keep manual preparation as prose/runbook requirements, with no shipped migration or automatic alteration code. Before release, select and record the module version and align manifest release notes.

The entity and preparation invariants are in [data-model.md](data-model.md); the configuration, metadata, execution and deployment contract is in [contracts/bulk-copy-timeout.md](contracts/bulk-copy-timeout.md). [quickstart.md](quickstart.md) defines implementation-time validation and evidence. Planning ends here; production implementation and test execution are later work.

## Complexity Tracking

No constitution violations require justification. No new production module, factory parameter, dependency, progress entity, or public option is introduced.
