# Validation Guide: Per-Table Bulk Copy Timeout

**Feature**: `009-add-bulk-copy-timeout` | **Status**: Implementation-time guide

The feature and proposed test additions are not implemented by this planning run. Commands below run the relevant suites after implementation; existing suites alone do not yet prove the added behavior. Use the [contract](contracts/bulk-copy-timeout.md) and [data model](data-model.md) for exact field and deployment rules.

## Prerequisites

- Run from the repository root in a fresh PowerShell 7.6+ Core process on Windows x64 or Linux x64, with Pester and PSScriptAnalyzer installed.
- Have the module's existing SqlClient/ScriptDom runtime bundles available. If missing, use the documented dependency build (`./build/build.ps1`) with its .NET 10 prerequisites; this feature does not upgrade dependencies.
- For live checks, explicitly select a disposable SQL Server instance using `FAST1_TEST_ARCHIVING_SQL_CONN_STR`. Existing integration cases using `generate_series` require SQL Server 2022+ and database compatibility level 160+.
- The live-suite login needs create/drop database permissions, configuration-schema/procedure deployment, source/destination metadata and DDL/DML, and fixture constraint permissions. The suite creates three uniquely named configuration/source/destination databases on that instance and attempts cleanup. Never point it at operational databases.
- Keep credentials in local environment configuration. Do not commit or print connection strings containing secrets.
- Reserve a separate blocking connection and a bounded worker/watchdog for real timing cases. A zero-timeout test must release its write barrier and terminate even after an assertion fails.

## 1. Controlled execution and query regressions

```powershell
$controlledTests = @(
	'./Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1'
	'./Fast1data.SqlServer/tests/GenericSqlQuery.Tests.ps1'
	'./Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1'
)
Invoke-Pester -Path $controlledTests -Output Detailed
```

Expected additions to the archiving suite:

| Scenario | Required evidence |
| --- | --- |
| Metadata values 30, 120, zero, and 2147483647 | Reader result reaches the real typed `Table` unchanged. |
| Two tables with 60 and 120 in one group | Each table's writes receive its own value, including when traversal order changes. |
| All three copy methods | Execute each actual method; inspect the property at entry to overridden `WriteToServer`, not merely at factory allocation. |
| Destination-key reconciliation spans pages | Every newly allocated page copy has the configured value. |
| Archive data spans batches | Every newly allocated batch copy has the configured value. |
| Empty/skipped stages | Existing workflow skips remain intact; no copy is forced to run. |
| Copy failure and cleanup failure | Original error remains visible; independent cleanup attempts continue; no success checkpoint follows the failed write. |
| Ordinary commands with distinct configured timeout | Values and helper behavior match the pre-change baseline for default, positive and zero bulk settings. |

The existing harness's `RealCopy` path covers archive-data copying only. Add dedicated key-copy cases or expand readers/pages so both real key-copy methods execute. Update all metadata row fixtures to supply the required field. Retain existing public-command/export assertions.

## 2. Live database and archiving acceptance

Set the connection string locally for the intended disposable instance, then run:

```powershell
$env:FAST1_TEST_ARCHIVING_SQL_CONN_STR = 'Server=YOUR_TEST_SERVER;Initial Catalog=master;Integrated Security=True;Encrypt=True'
Invoke-Pester -Path ./Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1 -Output Detailed
```

Use authentication/encryption options appropriate to that test environment. Missing or blank configuration fails suite setup. Offline runs must exclude `*.Integration.*` by filename; tag exclusion does not prevent this suite's global SQL setup.

Required live scenarios:

| Scenario | Expected result |
| --- | --- |
| Fresh setup; insert omitting timeout | Stored value is 30; SQL metadata shows `int NOT NULL`, named default 30 and enabled/validated nonnegative check. |
| Insert/update zero, 1, 120 and 2147483647 | Values are accepted and read back unchanged through the procedure and model. |
| Insert/update negative values, including -1 and Int32 minimum | Check constraint rejects each change. Assert the database error, rather than an unrelated missing-required-field failure. |
| Insert/update explicit SQL null | `NOT NULL` rejects the change; the default must not replace explicit null. |
| Failed negative/null update | Existing valid value is unchanged. |
| Table-group and active filtering | Existing metadata selection is preserved; different tables retain independent values. |
| Real writes with default, positive and zero | Observe all three `BulkCopyTimeout` properties immediately before real `WriteToServer`, forwarding to the real provider write; verify archived keys and normal completion. |
| Setup rerun against existing table | No existing rows or schema are altered by `tables.sql`. |

Parameterize SQL values, provide valid unrelated required fields on insert tests, and isolate rejected writes so they do not invalidate later scenarios. Reuse current test-local helpers and cleanup; verify the loaded module scope name before adding mocks, since current suites use different scope-name forms.

## 3. Real timeout, unlimited wait, and recovery

Implement these scenarios in the existing live suite, using its selected disposable databases and fresh invocation per retry:

1. Prepare source readers and a target table, then coordinate an independent write-target blocker. Confirm the copy has reached the write phase. Keep source/metadata command timeouts above the test window so a query timeout cannot masquerade as a bulk timeout.
2. Configure a short positive bulk limit (for example, 2 seconds), hold the write barrier longer than that limit, and verify the provider reports a copy timeout through existing archiving failure behavior. Use a generous upper bound; do not assert exact milliseconds.
3. Inspect `ProcessState`, captured keys, working tables and destination rows. No unfinished stage may be marked complete. Do not assume earlier committed effects rolled back. Release the blocker and retry with a fresh group execution; verify captured working-set semantics, no skipped records, and eventual normal completion.
4. With bulk timeout zero, hold the barrier beyond 30 seconds (for example, 35 seconds), release it, and verify the same copy completes. Enforce an independent maximum test duration (for example, 90 seconds), with cancellation and blocker release in cleanup.
5. Exercise timeout/interruption handling at the relevant source-key, destination-key and archive-data boundaries through controlled tests, retaining existing real partial-key capture, destination reconciliation, checkpoint failure, and cleanup recovery regressions. At least one isolated real bulk timeout and the real zero-wait case are required in addition to property evidence for every stage.

Lock coordination must avoid blocking setup queries, target metadata discovery, or source reads before the intended write. Use the stage's actual target and confirm the failure source. Merely delaying `ExecuteReader` does not test bulk-copy timeout.

## 4. Query-timeout independence

Record a pre-change baseline, then compare after implementation. Use a nondefault connection `Command Timeout` (for example, 2 seconds) and repeat with bulk values 30, 120 and zero. Inspect ordinary commands created by the existing archiving factory and query helpers, then run a deliberately longer ordinary query such as `WAITFOR DELAY '00:00:05'; SELECT 1;` in a dedicated test connection. It must retain its prior timeout behavior even with zero bulk timeout.

For generic-query provider regressions, select the same intended disposable instance explicitly using that suite's separate variable:

```powershell
$env:FAST1_TEST_MIGRATION_SQL_CONN_STR = $env:FAST1_TEST_ARCHIVING_SQL_CONN_STR
Invoke-Pester -Path ./Fast1data.SqlServer/tests/GenericSqlQuery.Integration.Tests.ps1 -Output Detailed
```

The generic suite supplements the added archiving command-timeout case; it cannot alone prove timeout isolation in all archiving stages. Do not change production command timeout assignments to make the test pass.

## 5. Existing-installation rehearsal

Use only a disposable legacy fixture, with at least two preexisting source configurations and retained progress/working-set data. Capture old-schema table/procedure definitions in test-local setup; do not add a distributable migration script.

1. Confirm the old `SourceTable` lacks `BulkCopyTimeout`, and record configuration identities, row values and progress state.
2. Run the updated `tables.sql` through the existing GO-aware test helper. Verify the new column is still absent and existing rows/state are unchanged.
3. Follow the revised `Fast1Archiving.md` as an operator: stop runs, select the configuration database, manually prepare the required integer field, backfill every preexisting row to 30, and establish/validate the default, nullability and nonnegative check. Keep this preparation in test setup or the operator session.
4. Deploy the updated `dbo.stp_GetSourceTable` after storage preparation. Confirm old rows return 30; an omitted future insert defaults to 30; negatives and nulls fail; zero and positive values round-trip.
5. Run the changed module against the prepared fixture. Verify normal archiving/recovery with existing state and no reset of keys or checkpoints. Confirm unchanged configuration identities and relationships.
6. Review the guide alone for all preparation requirements and order. It must explicitly say setup reruns do not add the field and remove the old statement that no persistence/procedure upgrade is needed.

Prepared storage with an old procedure, or an old schema with the changed module, is not a supported installation state. The feature must not silently repair either state.

## 6. PowerShell analysis and evidence

After implementation, analyze every changed PowerShell file, including tests/help/manifest if changed. For the anticipated set:

```powershell
$analysisPaths = @(
	'./Fast1data.SqlServer/private/archiving/ArchivingModel.psm1'
	'./Fast1data.SqlServer/public/Invoke-Fast1Archiving.ps1'
	'./Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1'
	'./Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1'
	'./Fast1data.SqlServer/Fast1data.SqlServer.psd1'
)
foreach ($analysisPath in $analysisPaths) {
	Invoke-ScriptAnalyzer -Path $analysisPath
}
```

Use repository analyzer settings if present at implementation time (none were found during planning). Expand the list for new fixtures. Resolve new findings, retain the repository's tab/multiline control-flow convention, and report unrelated preexisting findings. Missing PSScriptAnalyzer is an explicit unrun check, not a pass.

Record runtime/provider/server versions, suite counts and outcomes, observed stage/table/timeout values, actual timing/failure source, post-failure/retry state, manual preparation evidence and cleanup outcomes. Redact secrets. Mark unavailable environments/checks as unrun and retain material recovery risks as release blockers. Select and record the release version and align manifest release notes before release; current module version is 0.2.1.

This planning session ran no feature tests or SQL operations. The setup script succeeded in a process-scoped Windows PowerShell session after the default shell blocked script execution; the discovered `pwsh` alias was inaccessible. Implementation checks require a working supported PowerShell 7.6+ executable, not that fallback shell.
