# Implementation Plan: Consolidate Migration Phase Validation

**Branch**: `dev` | **Date**: 2026-10-30 | **Spec**: [spec.md](spec.md)

**Input**: `specs/002-consolidate-migration-phases/spec.md`

**Status**: Phase 0 research and Phase 1 design complete. Implementation and task generation have not started.

## Summary

Replace the shallow `Get-Migration` reader with one private `Resolve-MigrationPhase` responsibility that reads the selected phase and produces a fully validated, ordered evaluation. It owns literal phase selection, shared script identity, duplicate/conflict detection, unknown-selection warnings, containment, file existence, checksums, and run/skip decisions. No script may execute or history change until evaluation succeeds for the entire phase.

`Invoke-Fast1Migration` continues reading history, presenting decisions, handling `ShouldProcess`, executing eligible scripts, and recording each success through existing helpers. Preserve raw stored history keys for correct forced updates while recording normalized phase-relative names. Retain checksum and execution helpers, SQL implementation, public parameters, manifest exports, schema, runtime baseline, and dependencies. Preview consumes the same evaluation. See [research.md](research.md).

## Technical Context

**Language/Version**: PowerShell 7.4 or later, Core edition; existing .NET path and SHA-256 facilities.

**Primary Dependencies**: Existing SqlServer module (`Invoke-Sqlcmd`) and Microsoft.Data.SqlClient. No new production dependency.

**Storage**: Existing `migration.json`, phase script directories, and SQL Server `dbo.fast1_migration_history`; no schema migration.

**Testing**: Pester phase tests with real temporary files and supplied history; command tests with controlled existing SQL boundaries; retained/expanded `Integration` SQL Server tests; PSScriptAnalyzer on every changed PowerShell file. Current installed Pester is 6.2.0; use a verified compatible test runner and record its version.

**Target Platform**: x64 Windows, Linux, and macOS, preserving host-specific filesystem lookup and containment comparisons.

**Project Type**: PowerShell module with exported administrative commands and private helpers.

**Performance Goals**: No new latency SLA. One configuration read, one history read per command, and one checksum per non-ignored configured file per evaluation. Use indexed identity sets/maps and preserve configured order; buffer decisions proportional to selected-phase size. Whole-phase file I/O intentionally occurs before execution.

**Constraints**: No database adapter/framework/public phase API; no history/schema repair, transaction/rollback promise, concurrency control, symbolic-link policy, or filesystem case-resolution feature. Evaluation performs no execution or history writes. Tab-indented multiline PowerShell control flow per `AGENTS.md`.

**Scale/Scope**: One selected phase per invocation. Focused changes to migration scripts, checksum literal-path handling, migration tests, help, and guidance. Audit/archiving behavior is outside scope.

## Constitution Check

The active constitution is `.specify/memory/constitution.md` version 1.0.0. Initial evaluation before research: **PASS**, with no proposed exceptions. Post-design evaluation: **PASS**, with implementation/release checks below still required.

| Gate | Initial | Post-design evidence and required validation |
| --- | --- | --- |
| I: truthful completed progress | PASS | Record only after successful execution; retain earlier durable history on failure. Tests cover execution and recording failure, including retry. |
| II: deterministic migrations | PASS | One evaluator preserves order, SHA-256, normalized identity, global conflicts, and containment before execution. Preview shares evaluation without mutations. Idempotency guidance remains explicit. |
| III: explicit database operations | PASS | Keep selected-phase history reads, parameterized writes, and terminating SQL execution; use exact stored key for forced updates. No SQL during evaluation. Integration requires an explicitly selected disposable database. Logs exclude secrets. |
| IV: portable contracts | PASS | Public signature/exports, JSON format, schema, dependencies, PowerShell 7.4, and x64 platforms remain compatible. Literal operations preserve bracketed names. Import/export and platform cases verify the boundary. |
| V: verification and recovery | PASS | Phase, command, real SQL, failure/retry, and WhatIf coverage mapped below; docs describe preflight and successful-execution/failed-recording recovery. Unavailable checks are recorded as unrun. |
| Workflow 2 and 6–11: scope and analyzer | PASS | Reuse file/SQL helpers; remove shallow reader. Analyze all changed PowerShell including tests with project settings where available; resolve new errors/warnings, report baseline findings or analyzer unavailability, and do not suppress rules to bypass checks. |

Design compliance does not claim implementation tests passed. Material unresolved integrity failures block release; unavailable SQL/platform checks remain visible in the implementation report.

## Project Structure

### Documentation (this feature)

```text
specs/002-consolidate-migration-phases/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── migration-command.md
└── tasks.md             # Future speckit-tasks output; not generated by planning
```

### Source Code (repository root)

```text
Fast1data.SqlServer/
├── Fast1data.SqlServer.psd1               # Contract/import verification only
├── Fast1data.SqlServer.psm1               # Existing private discovery
├── public/Invoke-Fast1Migration.ps1       # Coordination and help
├── private/
│   ├── migration/
│   │   ├── Resolve-MigrationPhase.ps1     # New authoritative evaluator
│   │   ├── Get-Migration.ps1              # Removed
│   │   ├── Get-Executed.ps1               # Keep SQL read; return stored spelling
│   │   ├── Set-Executed.ps1               # Keep SQL write; exact history key
│   │   └── Invoke-Migration.ps1           # Retain terminating execution
│   └── shared/
│       ├── Get-FileChecksum.ps1           # Retain SHA-256; use LiteralPath
│       └── Get-RelativePath.ps1           # Retain phase-relative conversion
├── schema/migration/tables.sql           # Existing schema, unchanged
└── tests/
    ├── Migration.Phase.Tests.ps1          # New phase tests, no SQL access
    ├── Migration.Tests.ps1               # Isolated command tests
    └── Migration.Integration.Tests.ps1   # Live SQL integration
Fast1Migration.md                         # Preflight, preview, recovery guidance
```

**Structure Decision**: Keep the existing module layout. The new private script contains phase responsibility and narrowly scoped name handling. No separate shallow normalizer module, storage layer, or public export is introduced. The contract documents the existing command; internal shapes belong in [data-model.md](data-model.md).

## Phase 0 outcome

[research.md](research.md) resolves evaluator inputs/output, normalization and literal selection, containment, checksum decisions, SQL stored-key preservation, preview coordination, and test setup. Existing SQL names must remain available until forced updates locate their row. Required environment checks are separate from design questions. No unresolved design clarifications remain.

## Phase 1 design

### Private phase boundary

`Resolve-MigrationPhase -BasePath <string> -Phase <string> -History <object[]> [-IgnoreScripts <string[]>] [-ForceScripts <string[]>]` returns one complete evaluation or throws a terminating validation error. Accept empty history/selection collections. It has no connection string or mutation callback.

1. Resolve/check configuration and phase directory with literal paths. Read JSON, select the literal named property, and preserve its ordered script list, including an existing empty array.
2. Normalize names consistently. Check all configured duplicates and ignore/force conflicts before per-script eligibility. Collect unknown-selection warnings without adding work.
3. Resolve every configured path and enforce containment. Ignored contained entries become skips. For every other entry, require a file, obtain SHA-256, match supplied history, and choose new/forced/already-executed or reject drift.
4. Return the completed evaluation and ordered warnings. Do not stream executable decisions while validation continues.

Use explicit arrays so empty/single-script results have the same shape. Keep identity casing separate from filesystem lookup. Resolved paths establish containment; relative identity spelling does not introduce alias deduplication. See [data-model.md](data-model.md).

### Command and history changes

The command reads history once, calls the evaluator once, emits returned warnings/decision diagnostics, and uses phase-level `ShouldProcess` to authorize mutations. A zero-eligible result reports `Nothing to run`. With `-WhatIf`, perform history reads and full validation and report eligible names in order, but call neither `Invoke-Migration` nor `Set-Executed`.

For each eligible decision, call `Invoke-Migration` with its resolved path, then `Set-Executed` with evaluated name/checksum. Update only when forced and previously recorded; forced new scripts insert. Preserve the original stored key through `Get-Executed` and the evaluator, and use a parameterized `HistoryScriptName` predicate when updating. Write normalized `ScriptName`, current checksum, and database timestamp. This accommodates legacy separators and case-sensitive collations without a new schema or adapter.

Execution failure prevents recording that script. Recording failure after successful execution stops later work but leaves the executed effect in place. Preserve terminating errors at both boundaries and the idempotent-script requirement. No retry, rollback, transaction, or concurrency guarantee is added.

### Documentation and compatibility

Update migration help and `Fast1Migration.md` together to explain whole-phase validation before mutation, matching across all sources, ignored-path containment, unknown-selection warnings, preview reads, and failure/retry behavior. Preserve idempotency guidance, setup order, executable-administrator-input expectations, and parameter/configuration/schema contracts. Document host-correct file casing and that validation does not lock files/history.

### Verification mapping

| Requirements / outcomes | Validation layer | Required observations |
| --- | --- | --- |
| FR-001–004; SC-001 | Phase interface | Literal bracketed phase, other phases excluded, nonalphabetical nested order, empty/missing phase, missing config/directory, separator/case matching across all four sources, duplicates, conflicts including unknown names, warning-only unmatched selections. |
| FR-005–007; SC-002 | Phase plus command guards | Escaping relative/absolute paths, sibling prefix, directory itself, ignored/forced escapes, missing non-ignored files, ignored missing/drifted files, expected/current checksum details. Valid first plus invalid later entries cause zero executions/writes, including preview. |
| FR-006; SC-001 | Phase interface | New, unchanged, changed-unforced, forced historical, forced new, real SHA-256 files and supplied history; ignored files never hashed. |
| FR-008; SC-003 | Command controlled boundaries | Paired preview/execution decisions, order, warnings/errors; history reads allowed; preview calls no mutating helper. Empty/all-skipped phases report no work. |
| FR-009–010; SC-004 | Command and real SQL | Ordered execute/write, insert/update, normalized names, checksum/timestamp updates, legacy history lookup, execution and recording failure, earlier progress retained, later work blocked, idempotent retry. Include real case-sensitive-collation validation. |
| FR-011–012; SC-005 | All layers / reporting | Retain SQL and WhatIf coverage; record passed, failed, skipped/unavailable distinctly. Run platform-sensitive cases on supported hosts or mark unrun. |
| Constitution IV and workflow 6–11 | Import, help, analyzer | Public exports unchanged; evaluator private; removed reader has no callers; analyze every modified PowerShell file including tests and resolve new findings. |

Runnable validation and prerequisites are in [quickstart.md](quickstart.md). SQL integration uses explicit test-container connections and fixture cleanup; remove committed test credentials. Do not run destructive fixtures against an inferred database.

## Post-design gate and handoff

The design satisfies applicable constitution gates without exceptions. Research, data model, command contract, and validation guide are complete. Next is `$speckit-tasks`; this invocation does not generate `tasks.md` or implement code.
