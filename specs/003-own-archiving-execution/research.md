# Research: Own Archiving Execution

**Date**: 2026-10-30 | **Feature**: [spec.md](spec.md)

Independent execution and validation research was consolidated with direct source inspection. Paths are repository-relative. Design questions are resolved; environment-dependent checks remain implementation prerequisites.

## 1. Execution and initialization ownership

**Decision**: Preserve the existing execution request; make TableGroup construction inert and Execute own acquisition, work and cleanup. Retain ProcessState internally and move sequencing into group/table operations.

**Rationale**: public/Invoke-Fast1Archiving.ps1:23 already forwards only connection/group/log inputs. private/archiving/Invoke-ArchivingProcess.ps1:89–229 currently sequences progress, effects and completion. ArchivingModel.psm1:26–78 opens three connections before constructor assignment; failure leaves earlier connections beyond caller ownership. Register resources before Open under Execute's protected lifetime.

**Alternatives considered**: A static factory adds a type without improving the existing group boundary. Returning a disposable object leaves caller ordering rules. Deleting ProcessState or splitting files alone leaves shallow execution. A generic resource/adapter framework is unnecessary.

## 2. Effects, checkpoints and accounting

**Decision**: Each operation owns effect then checkpoint; stop on required transition failure. Accept candidate state after persistence succeeds, reset transient counters, and reload persisted truth on retry. Callback activity never authorizes progress.

**Rationale**: ArchivingModel.psm1:976–1024 uses destination bulk copy separately from configuration state; purge/checkpoint calls are separate too. [Microsoft's bulk-copy transaction documentation](https://learn.microsoft.com/en-us/sql/connect/ado-net/sql/transaction-bulk-copy-operations?view=sql-server-ver17) describes committed batches surviving a later non-transacted copy failure. [SqlBulkCopy.RowsCopied documentation](https://learn.microsoft.com/en-ie/dotnet/api/microsoft.data.sqlclient.sqlbulkcopy.rowscopied?view=sqlclient-dotnet-core-7.0) distinguishes callback activity from commit. Applied to this code's independent operations, the design inference is that checkpoint failure cannot imply rollback. Recorded totals can lag effects; missing counts need not be reconstructable.

**Alternatives considered**: Distributed transactions change operational compatibility and are excluded. Callback checkpointing can claim unfinished work. Reconstructing deleted-row history/exact totals changes semantics. Continuing from unconfirmed candidate progress risks skipping work.

## 3. Working sets and retry

**Decision**: Retain confirmed captured sets, existing incomplete-capture recreation, reconciliation triggers/skip flags/repaired positions and purge joins. Correct destination snapshot acquisition to check retained captured keys independently of current eligibility. No schema change.

**Rationale**: KeyCopyDate confirms capture (ArchivingModel.psm1:323–324). Working tables contain surrogate positions plus actual PKs (:829–854). Missing confirmation retains recreation; afterward the set remains authoritative. schema/archiving/sprocs.sql:355–429 flags destination matches and finds unfinished copy positions. Purge (:232–300) joins captured keys in persisted ranges, tolerating absent rows. Completion and working-table drop are separate steps; failed drop returns failure without rewriting history.

Review found an additional recovery hole: BulkCopyDestinationPK (ArchivingModel.psm1:945–946) reruns KeyQuery against destination. A rolling predicate or changed eligibility can exclude already committed copies, causing duplicate retry attempts even though source capture is retained. Use bounded captured-key pages, typed parameterized destination PK predicates (including composite keys), and the existing destination working table. Close each configuration read before writing the snapshot; buffer at most one page. Choose min(KeyCopyBatchSize, floor(2000 / PK column count)) keys per query, with headroom below SQL Server's documented [2,100 procedure parameter limit](https://learn.microsoft.com/en-us/sql/relational-databases/stored-procedures/specify-parameters). This is an internal query-shaping bound, not a changed copy/purge batch setting. Each reconciliation failure stops; retry rebuilds the snapshot. Add real SQL coverage combining committed copies, checkpoint failure and changed eligibility, plus composite-key/large-page coverage.

**Alternatives considered**: Streaming all destination PKs would avoid eligibility filtering but scan unrelated data; bounded captured-key lookups keep work tied to this process. Reusing filtered KeyQuery can miss durable copies. Reselecting eligibility after confirmed capture changes the set. Numeric source-key ranges break composite/nonsequential keys. New version tables or exact-count recovery are unnecessary for safe retry.

## 4. Constraints and partial disabling

**Decision**: Capture/register distinct inbound source FKs before disabling; perform independent actions with quoted identifiers. Restore with WITH NOCHECK CHECK; gate new purge/overall completion on successful restoration. Retain installed procedure signatures while replacing the defective model call with internal enumeration/DDL.

**Rationale**: sprocs.sql:437–483 discovers source child constraints referencing the selected source table and emits nonvalidating restoration in concatenated DDL. ArchivingModel.psm1:785–804 uses a nonexistent table connection and table ID instead of process ID; its flag misses partial failure. Captured identities cover uncertain changes and permit independent attempts. Existing scope includes initially disabled entries; no new initial-state policy is introduced. DisableFK off means no toggles.

[Microsoft's FK documentation](https://learn.microsoft.com/en-us/sql/relational-databases/tables/disable-foreign-key-constraints-with-insert-and-update-statements?view=sql-server-ver17) distinguishes enabled status from trust and identifies ALTER permission. Preserve the existing nonvalidating policy. Correct Fast1Archiving.md:32, which currently locates the warning in the archiving database, to identify source child constraints.

**Alternatives considered**: Finally guarded by the old flag misses partial failure. One restore batch can skip later independent constraints. WITH CHECK CHECK changes trust policy. Restoring only confirmed disables misses uncertain results. Automatic integrity repair is excluded.

## 5. Error precedence and resources

**Decision**: Guard each resource/constraint cleanup independently. Preserve initial ErrorRecord; append safe contexts at Exception.Data['Fast1Archiving.CleanupFailures']. First cleanup-only error becomes primary. Logging cannot mask the cause or block cleanup. Do not drop recovery tables on failure.

**Rationale**: Group Dispose (ArchivingModel.psm1:124–128) and batch finalizers (:917–925,963–971,1013–1021) stop on the first exception and may mask processing. Shared Invoke-GenericSqlQuery builds parameters before try and has unguarded disposal. Correct narrowly required patterns while retaining helper signature and adding affected regressions. Release readers before checkpoint reuse and restore before connection release.

**Alternatives considered**: Warning-only cleanup gives false success. Unconditional aggregate errors hide original identity. An outer Dispose guard cannot reach resources skipped inside a failing Dispose. A cleanup dependency expands scope unnecessarily.

## 6. Compatibility and verification setup

**Decision**: Preserve PowerShell 7.6 Core/x64 Windows/Linux/macOS, exports, dependencies and formats. Separate controlled ownership tests from SQL setup; add explicit target inputs/guards before running retained fixtures.

**Rationale**: Manifest/build specify existing runtime/dependencies (net10.0, SqlClient 7.1.1). stp_GetSourceTable filters Active without ORDER BY; retain supplied traversal/PurgeOrder semantics. tests/Archiving.Tests.ps1:423–498 retains copy interruption, committed earlier rows and counts distinct from destination population; :500–590 retains delete interruption. Global setup currently uses fixed SQL targets/credentials even for untagged checks. Excluding Integration does not make it SQL independent. Existing fresh observer connections provide a useful evidence pattern.

**Alternatives considered**: Mocks cannot prove durable rows/trust bits. Guessing targets violates explicit selection. Public injection flags change the operator contract; private seams and test-only triggers/procedure wrappers suffice.

## Planning validation status

Read-only discovery found PowerShell 7.6.9, Pester 6.2.0, PSScriptAnalyzer 1.25.0, SqlServer 22.4.5.1 and bundled runtime assets. No SQL connection/fixture was run. No production PowerShell changed. SQL durability, future implementation/analyzer checks and Linux/macOS execution remain unverified.
