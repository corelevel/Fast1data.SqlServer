# Implementation Plan: Own Archiving Execution

**Branch**: `dev` (actual Git branch) | **Feature identifier**: `003-own-archiving-execution` | **Date**: 2026-10-30 | **Spec**: [spec.md](spec.md)

**Input**: `specs/003-own-archiving-execution/spec.md`. Setup reports the feature identifier as BRANCH because feature context is resolved independently of Git. No branch switch is required.

**Status**: Implementation complete and validated on x64 Windows. See [tasks.md](tasks.md) and [validation.md](validation.md) for execution results and unverified platforms.

## Summary

Deepen the existing archiving model into an execution owner. Preserve public Invoke-Fast1Archiving and private Invoke-ArchivingProcess signatures; reduce the latter to requesting execution and handling outcome. An inert TableGroup constructor stores inputs; its Execute() operation owns guarded initialization, ordering, recovery transitions, constraint restoration and disposal. Table operations own preparation/capture/reconciliation, copy plus checkpoint and purge plus checkpoint. Retain ProcessState internally; callers never inspect or mutate progress to drive execution.

Effects and checkpoints remain independently committed. Failed checkpoints stop sequencing while preserving durable effects and recovery information. Register source FK obligations before disabling; restore each constraint independently before new purge/overall completion. Preserve the primary error and expose every cleanup failure. See [research.md](research.md).

## Technical Context

**Language/Version**: PowerShell 7.6 or later, Core edition, per active constitution and manifest; existing .NET SQL facilities.

**Primary Dependencies**: Existing Microsoft.Data.SqlClient (build pins 7.1.1), SqlServer module and versioned SQL setup scripts. No new production dependency.

**Storage**: Existing SQL Server dbo.TableGroup, dbo.SourceTable, dbo.ProcessState and configuration-database working tables; configured source/destination connections. No schema or persisted-format change.

**Testing**: Pester controlled ownership/error tests plus real SQL Server failure/retry fixtures using independent observers; PSScriptAnalyzer for every changed PowerShell file. Planning host: PowerShell 7.6.9, Pester 6.2.0, PSScriptAnalyzer 1.25.0, SqlServer 22.4.5.1. Verify runner behavior during implementation.

**Target Platform**: x64 Windows, Linux and macOS; SQL Server database dependency. Report unavailable platforms separately.

**Project Type**: PowerShell administrative module with exported commands and private execution/model code.

**Performance Goals**: Preserve streaming transfers, configured batches/delays and supplied traversal. No new throughput SLA. Buffer existing metadata/state, one bounded captured-key reconciliation page, per-batch counters and affected FK identities, never the full selected row set. Constraint handling adds scoped metadata work and individual actions per distinct FK.

**Constraints**: Configuration/source on one SQL Server instance; source PKs; one process per group; stable retry configuration. No distributed transaction, concurrency, cancellation, automatic integrity repair or exact-count reconstruction. Preserve archive-only, purge-only, combined, disabled/no-work and destination preparation/reconciliation behavior. Tab-indented multiline PowerShell control flow per AGENTS.md.

**Scale/Scope**: One group per invocation using existing working positions. Archiving execution/model, narrowly required shared SQL resource handling, tests, help and recovery guidance. No audit/migration feature or packaging change; shared-helper changes require affected regressions.

## Constitution Check

Active constitution: `.specify/memory/constitution.md` version 1.0.0. Initial pre-research evaluation: **PASS**. Post-design evaluation: **PASS**. These are design gates, not implementation test results.

| Gate | Initial | Post-design evidence and required validation |
| --- | --- | --- |
| I: integrity/resumability | PASS | Effect precedes checkpoint; failed transition stops later work. Retain sets, reconcile copies, revisit purge ranges, distinguish incomplete capture. Real SQL evidence required. |
| II: migrations | N/A | No history/ordering change. Check affected regressions if shared SQL cleanup changes. |
| III: explicit operations | PASS | Existing selection/DisableFK and source inbound FK scope retained; parameterized metadata and validated/quoted DDL identifiers; explicit disposable test targets and secret-free diagnostics. |
| IV: portable contracts | PASS | Signature/exports, PowerShell 7.6, x64 platforms, dependencies, schema/configuration and existing incomplete state retained. |
| V: verification/visibility | PASS | Retain interruption fixtures; add checkpoint, initialization, FK and cleanup cases through one request. Document count limitations and residual obligations. |
| Database/runtime constraints | PASS | PKs, same-instance configuration/source, single-process restriction and setup order retained. No upgrade needed. |
| Workflow 2 and 6–11 | PASS | No framework. Analyze every changed .ps1/.psm1/.psd1, including tests, with project settings if available; resolve new findings and report baseline findings/unavailable tools. |

No exception proposed. Missing required SQL evidence or unresolved material integrity failures block release.

## Project Structure

### Documentation (this feature)

```text
specs/003-own-archiving-execution/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/archiving-execution.md
├── tasks.md                       # Implementation task tracking
└── validation.md                  # Executed checks and SQL evidence
```

### Source Code (repository root)

```text
Fast1data.SqlServer/
├── public/Invoke-Fast1Archiving.ps1           # Signature retained; update help
├── private/
│   ├── archiving/
│   │   ├── Invoke-ArchivingProcess.ps1        # Thin execution request
│   │   ├── ArchivingModel.psm1               # Group/table execution and internal state
│   │   ├── Metadata.psm1                     # Retain metadata
│   │   ├── Compare-Column.ps1                # Retain preparation
│   │   └── Get-DelayIntervalInSecond.ps1      # Retain delay interpretation
│   └── shared/GenericSqlQuery.ps1         # Focused cleanup correction if needed
├── schema/archiving/{tables,sprocs}.sql      # Retain schema/procedure signatures
├── Fast1data.SqlServer.{psd1,psm1}            # Verify contract/import; no new export
└── tests/
    ├── Archiving.Integration.Tests.ps1                   # Retain/expand SQL; explicit inputs
    └── Archiving.Execution.Tests.ps1          # New SQL-independent ownership/error cases
Fast1Archiving.md                             # Recovery/count/source FK guidance
```

**Structure Decision**: Keep class loading and module layout. Deepen group/table operations rather than add a public executor or make file splitting the objective. Scoped internal cleanup routines support independent attempts and failure collection; no resource framework/database adapter. Narrow private operations may be replaced in controlled tests; no public fault-injection parameters.

## Phase 0 outcome

[research.md](research.md) resolves ownership, state representation, effect/checkpoint ordering, set recovery, FK scope, error precedence and test isolation. No unresolved design clarification. Dedicated SQL targets are an implementation validation prerequisite.

## Phase 1 design

### Execution lifetime and depth

Invoke-ArchivingProcess constructs an inert group and requests Execute. Constructor opens no connections or disposable resources. Execute establishes its protected lifetime before allocation, registers each connection before Open and owns all exits, including failed source/destination initialization and unknown/empty groups. Instances are single-use; retry creates a fresh owner and reloads SQL state.

Consume active tables in supplied order, skip both-disabled tables, prepare destinations as before and finish preparation/archive traversal before purge sorted by PurgeOrder. Do not add ordering guarantees for unordered rows or tied values. Required failure stops later processing while cleanup continues. Earlier completed tables retain outcomes.

Table operations own preparation/capture/reconciliation, effect/checkpoint pairs and completion. Hide Table.State/progress-mutating members from the caller contract; retain ProcessState field/procedure mapping. Moving only storage helpers or deleting the type is insufficient: operations must own transition timing.

### Progress and recovery

1. Load latest incomplete state or insert new state. Without KeyCopyDate, recreate/recapture keys as before, then confirm maximum position and capture date in order. Either write failure stops later phases. Confirmed capture makes that source set authoritative on retry.
2. Preserve destination preparation and the incomplete-process/AlwaysRunCheck reconciliation trigger, including existing purge-only preparation behavior. Correct destination snapshot acquisition: determine actual destination presence for retained captured PKs independently of current KeyQuery eligibility. Page captured keys by working position, closing the configuration reader before snapshot writes; query destination with typed, parameterized exact-key predicates supporting composite keys, then stream matches into the existing destination working table. Bound each page by min(KeyCopyBatchSize, floor(2000 / PK column count)), reserving parameter headroom. Keep existing skip-flag/repaired-position SQL. Never replace a completed captured source set because eligibility changed. A partial snapshot failure stops work; next execution recreates that destination snapshot before reconciling.
3. Reset transient activity; execute copy; persist candidate position/count; accept transition and continue only after persistence succeeds. Callback activity never checkpoints. Copy/checkpoint failure can leave destination rows; fresh execution reloads/reconciles actual keys.
4. Record archive completion after confirmed batches. Archive-only then records overall completion and removes tables. Combined processing can retain archive completion while purge is incomplete. Failed required marker blocks following work/removal.
5. Preserve purge reset rules, captured ranges, affected-row counts and delays. Register/disable FKs when enabled; delete range then checkpoint. Retry tolerates absent rows without selecting new keys or inventing missing counts.
6. Restore FKs after purge and on every failing exit after disabling starts. Successful restoration gates new purge completion, overall completion and normal table removal. Failed restoration/transition retains incomplete state and required tables.

Positions are working-table surrogate positions, not numeric source PK ranges. Counts retain recorded-processing meaning and can lag effects. No cross-connection rollback or exactly-once accounting. A write response can fail after commit: stop and reload persisted truth rather than roll markers back. Later drop/disposal failure returns failure but cannot erase durable completion.

### Source FKs and cleanup

Replace the defective table FK path with internal source metadata enumeration and per-constraint DDL. Capture distinct inbound FKs referencing the configured source table, matching existing procedure scope. Parameterize metadata predicates and validate/quote database/schema/table/constraint identifiers. Retain installed procedure signatures; this internal path requires no SQL upgrade.

Register the full possibly affected list before the first disable, including initially disabled entries under the existing scope policy. Disable with NOCHECK; restore each using WITH NOCHECK CHECK CONSTRAINT. Partial disable failure restores the registered scope conservatively. Guard every restore independently. DisableFK=false performs no toggle-list acquisition or purge-related DDL. This replaces current incorrect connection/process-ID routing; fixtures use unequal table/process IDs.

Guard every reader, bulk-copy object, command and connection release independently. Release short-lived readers before checkpoint SQL reuses their connection. Restore before releasing required group connections. Correct local cleanup holes in model operations. If Invoke-GenericSqlQuery changes, protect acquisition/parameter setup through disposal, retain signature/primary error and run affected regressions.

Preserve original operation ErrorRecord. Merge cleanup failures into `Exception.Data['Fast1Archiving.CleanupFailures']`, retaining nested contexts: action, group, optional table/process, resource/source constraint, safe error type/message. If processing succeeded, first cleanup failure becomes primary; later cleanup still runs. Logging follows the same precedence and cannot bypass cleanup or disclose secrets. Do not obscure the primary with an unconditional aggregate. See [contract](contracts/archiving-execution.md).

Durable completion and invocation success differ: a later disposal/drop failure cannot undo committed completion. Restoration has a sequencing gate before new purge/overall markers.

### Guidance and verification

Update public help and Fast1Archiving.md together: stable retries, retained sets, independent commits, lagging counts, primary/secondary errors, cleanup attempts versus restoration success, hard-termination limits. Correct trust warning to identify source child FKs. Enabling does not validate historical rows, establish trust or repair integrity.

| Requirements / outcomes | Layer | Required observations |
| --- | --- | --- |
| FR-001,015; SC-005 | Boundary/caller review | Same request; zero caller state/checkpoint/FK/disposal sequencing; internal operations own transitions. |
| FR-002,014; SC-006 | Order tests + SQL | All modes, inactive/disabled/no-work/unknown; destination column/schema behavior; traversal, copy-before-purge, PurgeOrder, batches/delays retained. |
| FR-003,007; SC-006 | SQL | Capture recovery, confirmed-set stability including changed eligibility after committed copy/checkpoint failure, composite-key/parameter-bound reconciliation, failed set retained and earlier completion preserved. |
| FR-004–006,012–013; SC-001–002 | Retained/new SQL | Copy/delete interruption and post-effect checkpoint failure; independent keys/state before/after retry; no duplicates, skipped keys or outside deletion. |
| FR-004,007; SC-002 | Transition failures + SQL | Fail maximum/capture/archive/purge/overall completion writes; block later work/removal; persisted-truth retry. |
| FR-008,011–012; SC-003–004 | Controlled resources | Both partial-open cases, failed-open handle cleanup, no-work/success cleanup, multiple failures and remaining attempts. |
| FR-009–010,012–013; SC-003–004 | Attempts + SQL FKs | Delete/checkpoint failure with DisableFK, partial disabling, failed restore then independent attempt; source enabled/trusted bits; no new success on restore failure; no toggles when off. |
| FR-011; SC-004 | Error contract | Original cause plus all cleanup contexts; cleanup-only failure terminates; logging cannot mask. |
| FR-013–014; all SC | Reporting/import/analyzer | Explicit targets, SQL evidence, signature/exports/state compatibility, analyzer on all changed PowerShell; unavailable hosts/SQL unverified. |

See [quickstart.md](quickstart.md). Retain copy/delete fixtures and parameterize fixed targets before running them. Controlled seams prove attempts/error precedence; SQL proves durability/constraint status.

## Complexity Tracking

No constitution violations or exceptions. Internal progress representation and scoped cleanup records avoid new formats/frameworks.

## Post-design gate and handoff

Design gates passed. Implementation subsequently completed the task breakdown and recorded real SQL durability, FK status, controlled ownership, contract and analyzer evidence in [validation.md](validation.md). Linux/macOS execution remains unverified.
