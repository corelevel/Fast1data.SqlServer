# Research: Per-Table Bulk Copy Timeout

**Date**: 2026-11-23 | **Feature**: `009-add-bulk-copy-timeout`

## 1. SqlClient timeout semantics

**Decision**: Assign the configured Int32 directly to `SqlBulkCopy.BulkCopyTimeout` before every write. Default to 30 in SQL configuration; preserve zero without truthiness checks or coercion.

**Rationale**: The provider documents a default of 30 seconds and zero as unlimited waiting. Its setter rejects negative values. The exact bundled 7.1.2 source uses an Int32 and rejects only values below zero, so 2,147,483,647 is a valid configuration/property boundary. Acceptance of that boundary does not require waiting for such a timeout to elapse.

**Alternatives considered**: Connection-string `Command Timeout` controls ordinary commands, not this property. A global factory timeout cannot represent independent table settings without expanding the factory interface. A fallback such as `if ($value)` would replace a valid zero. No provider upgrade is needed.

**Sources**: [Microsoft SqlBulkCopy.BulkCopyTimeout documentation](https://learn.microsoft.com/en-us/dotnet/api/microsoft.data.sqlclient.sqlbulkcopy.bulkcopytimeout?view=sqlclient-dotnet-7.1), [SqlClient v7.1.2 SqlBulkCopy source](https://github.com/dotnet/SqlClient/blob/v7.1.2/src/Microsoft.Data.SqlClient/src/Microsoft/Data/SqlClient/SqlBulkCopy.cs).

## 2. Existing propagation path and query isolation

**Decision**: Extend `TableGroup.ReadSourceTables()` and `Table` in `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1`, then configure each copy in `BulkCopySourcePK()`, `BulkCopyDestinationPK()`, and `BulkCopyTable()`.

**Rationale**: `ReadSourceTables()` maps named reader fields into a hashtable cast to `[Table]`. Each real copy method already configures its own streaming/batching properties after `Get-ArchivingBulkCopy`. Destination reconciliation creates a new copy per page. This provides a direct path with no shared mutable timeout state. Leave the private typed property without an initializer so SQL configuration owns the default; private direct construction must explicitly supply a timeout before copying. The normal reader must access the required result field, with no old-schema fallback.

`Get-ArchivingCommand` constructs ordinary SqlClient commands without overriding their timeout. In SqlClient 7.1.2, `SqlCommand.CommandTimeout` falls back to the active connection's configured timeout unless explicitly overridden. Leave this path and public query helpers unchanged; test both command properties and actual delayed queries with distinct command/bulk limits. Reader/network command timeouts can still occur during streaming into an unlimited bulk copy.

**Alternatives considered**: A timeout factory parameter adds plumbing without reducing complexity at three existing property-configuration sites. A public command switch would conflict with per-table database configuration. A group-wide setting would violate table independence. Additional validation or automatic defaults for missing metadata would obscure the explicit preparation prerequisite.

**Sources**: Repository `ArchivingModel.psm1`, `public/Invoke-Fast1GenericSqlQuery.ps1`, and `public/Invoke-Fast1GenericSqlQueryReader.ps1`; [Microsoft SqlCommand.CommandTimeout documentation](https://learn.microsoft.com/en-us/dotnet/api/microsoft.data.sqlclient.sqlcommand.commandtimeout?view=sqlclient-dotnet-7.1), [SqlClient v7.1.2 SqlCommand source](https://github.com/dotnet/SqlClient/blob/v7.1.2/src/Microsoft.Data.SqlClient/src/Microsoft/Data/SqlClient/SqlCommand.cs).

## 3. SQL validation and deployment boundaries

**Decision**: Add the column, named default, and named check only inside the existing `dbo.SourceTable` creation branch. Extend the existing procedure projection in `schema/archiving/sprocs.sql`.

**Rationale**: `tables.sql` creates `SourceTable` only when absent. Existing PK/FK/index changes are already inside that branch. `sprocs.sql` uses create-stub/alter deployment, so a prepared existing database can receive the new projection. Named constraints match existing default naming and provide stable inspection targets. `NOT NULL` rejects explicit null; a default handles omitted insert values; the check enforces nonnegative integers even for direct administrative edits.

**Alternatives considered**: An `ALTER TABLE` repair branch, migration script, or version-detection fallback violates the agreed scope. Requiring manual preparation does not authorize silently changing existing rows during setup. Tests may construct and manually prepare disposable legacy schemas; this is fixture behavior, not an upgrade facility.

**Sources**: Repository `schema/archiving/tables.sql`, `schema/archiving/sprocs.sql`, `docs/bulk-copy-timeout.md`, and feature requirements FR-001/002/007/008.

## 4. Verification seams and live provider evidence

**Decision**: Reuse both archiving Pester suites. Controlled tests must execute all three actual copy methods and inspect the configured timeout when writing; live tests establish SQL and timing behavior.

**Rationale**: `Archiving.Execution.Tests.ps1` already creates real SqlClient objects while replacing connections/commands and overriding writes. Its metadata reader uses DataTables, permitting exact propagation assertions. However, the normal harness bypasses source capture using a completed key-copy state and replaces destination reconciliation; `RealCopy` currently reaches only archive-data copying. Add actual-method cases with source rows and multiple captured-key pages rather than assuming existing coverage reaches all three stages.

`Archiving.Integration.Tests.ps1` requires `FAST1_TEST_ARCHIVING_SQL_CONN_STR`, selects an instance, and creates three uniquely named configuration/source/destination databases. Global setup runs even when the Integration tag is excluded, so exclude the filename for offline runs. The login must create/drop databases and deploy/operate fixture objects. Some existing cases use `generate_series`, requiring SQL Server 2022+ and database compatibility level 160+.

Use write-target blocking with an independent connection and bounded fixture coordination to isolate real bulk waiting from query execution. Release a zero-timeout copy after more than 30 seconds; verify actual completion. For a short positive timeout, hold the same write barrier past the limit, verify failure/checkpoints, release the barrier, and retry. Use broad timing windows and a separate watchdog; always release locks and resources on failure. Readers must be ready before blocking the target; delaying `ExecuteReader` alone proves command timeout rather than bulk timeout.

**Alternatives considered**: Text searches cannot prove assignment ordering or propagation. Mocked writes cannot prove SQL constraints or real elapsed waiting. Exact timing thresholds are flaky. Tests must not wait for Int32 maximum or block indefinitely under zero. Do not introduce transactions or promise rollback of earlier bulk batches; preserve the existing independent effect/checkpoint model.

**Sources**: Repository `tests/Archiving.Execution.Tests.ps1`, `tests/Archiving.Integration.Tests.ps1`, `tests/SqlCleanup.Tests.ps1`, and `Fast1Archiving.md` test/recovery guidance.

## 5. Compatibility documentation and release governance

**Decision**: Document a required manual preparation sequence and reconcile the guide and command help. Treat release-version selection as a required release decision; do not invent maintainer approval or change versions during planning.

**Rationale**: Existing rows and future omitted inserts both need 30. Operators must add/backfill the required column, establish the default/check, and deploy `stp_GetSourceTable` before the changed module runs. Rerunning table setup alone does not prepare an existing installation. The guide currently says no persistence or procedure upgrade is required; that sentence must change. Current module version is 0.2.1, and constitution 2.0.0 requires an explicit release decision for compatibility changes.

**Alternatives considered**: A silent fallback contradicts manual preparation and hides deployment errors. Automatically selecting a release version during this design run would substitute an assumption for the specified release decision. No constitution amendment is necessary: explicit preparation, documentation, and verification satisfy the current principles.

**Sources**: Feature spec, `Fast1Archiving.md`, `public/Invoke-Fast1Archiving.ps1`, module manifest, `.specify/memory/constitution.md`.

## Resolution

All technical design questions are resolved. The release version remains an explicit pre-release governance gate. This research is evidence for design, not a report that the proposed tests passed.
