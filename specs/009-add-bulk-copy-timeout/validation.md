# Bulk-copy timeout validation

Implementation date: 2026-11-23. Branch: `dev`. Scope: [spec](spec.md), [plan](plan.md), [contract](contracts/bulk-copy-timeout.md), [validation guide](quickstart.md).

## Environment and baseline (T001–T004)

- Windows x64, PowerShell 7.7.0 Core, Pester 6.2.0, PSScriptAnalyzer 1.25.0. The sandbox cannot launch the app alias, so supported-runtime validation used the installed executable outside the sandbox. Prerequisite discovery used process-scoped Windows PowerShell execution-policy bypass; feature validation used supported Core.
- Existing Windows/Linux dependency bundles are present. Loaded SqlClient informational version: `7.1.2+b1dd9db72cd9e6eb9fc83ca308558e73b57dd449` (assembly identity `7.0.0.0`). No build or dependency upgrade was needed.
- `FAST1_TEST_ARCHIVING_SQL_CONN_STR` explicitly selected the disposable SQL instance. Initial access failed with Windows network error 64; the user requested a retry, which succeeded. SQL Server **16.0.4305.5**, fixture compatibility **160**, login `sysadmin = 1`. Successful database creation/deletion, fixture DDL/DML and constraint/procedure deployment exercise required permissions. The separate `CREATE ANY DATABASE` permission expression returned SQL NULL; actual create/drop and sysadmin membership establish permission availability.
- No analyzer settings were found. Existing `.gitignore` covers generated bundles/build and universal temporary files. No detected additional tooling requires another ignore file; `.vscode/` remains trackable.
- Pre-change controlled baseline: **155 passed, 0 failed, 0 skipped** (archiving execution 28, generic query 45, SQL cleanup 82). An ordinary archiving command with connection `Command Timeout=2` reports **2 seconds**. Baseline dependency-loaded analysis: **0 findings**.
- Pre-change review confirms two required public string parameters (`ConnStr`, `GroupName`), six explicit exports, create-only setup, streaming, batch sizes, key mappings, archive `KeepIdentity | KeepNulls`, and independent effect/checkpoint commits. Recovery retains working keys and reconciles actual destination presence.
- Fresh schema assertions verify SQL `int NOT NULL`, named default `DF_SourceTable__BulkCopyTimeout` equal to 30, and enabled/trusted `CK_SourceTable__BulkCopyTimeout` equal to `BulkCopyTimeout >= 0`. The initial missing-column red run was unavailable while SQL connectivity failed; the later legacy rehearsal directly exercises missing-storage and old-projection failures.

## Commands and final suites (T024)

Run from the repository root in supported PowerShell processes. Connection strings remained in the environment and were never printed or stored in this report.

```powershell
$controlledTests = @(
	'./Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1'
	'./Fast1data.SqlServer/tests/GenericSqlQuery.Tests.ps1'
	'./Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1'
)
Invoke-Pester -Path $controlledTests -Output Normal -PassThru

Invoke-Pester -Path ./Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1 -Output Normal -PassThru

$env:FAST1_TEST_MIGRATION_SQL_CONN_STR = $env:FAST1_TEST_ARCHIVING_SQL_CONN_STR
Invoke-Pester -Path ./Fast1data.SqlServer/tests/GenericSqlQuery.Integration.Tests.ps1 -Output Normal -PassThru
```

The generic-query variable was selected only inside the validation process. Controlled runs excluded integration files by filename. Final full runs:

| Suite | Passed | Failed | Skipped | Status |
| --- | ---: | ---: | ---: | --- |
| Archiving.Execution.Tests.ps1 | 40 | 0 | 0 | PASS |
| GenericSqlQuery.Tests.ps1 | 45 | 0 | 0 | PASS |
| SqlCleanup.Tests.ps1 | 82 | 0 | 0 | PASS |
| Archiving.Integration.Tests.ps1 | 49 | 0 | 0 | PASS |
| GenericSqlQuery.Integration.Tests.ps1 | 6 | 0 | 0 | PASS |
| **Total** | **222** | **0** | **0** | **PASS** |

The final controlled run took 15.18 seconds; archiving integration 98.93 seconds; generic-query integration 0.73 seconds. Expected warnings came from intentional failure fixtures.

## Positive, default and unlimited limits (T005–T016)

- Before runtime implementation, controlled tests produced **5 relevant failures**: two independent metadata values, missing required metadata, and two actual-method write cases. US1 subsequently passed **36/36** controlled cases; default/zero/maximum and empty-reader cases expanded the suite to **40/40**.
- The PowerShell adapted reader indexer can return null for a missing field, which a typed integer property would convert to zero. Normal loading therefore uses provider `GetOrdinal('BulkCopyTimeout')` and `GetInt32(...)` accessors. This deliberate refinement of the planned named indexer preserves SQL Int32 and fails on missing metadata without fallback or repair. Controlled missing-result and live old-projection tests pass.
- Controlled tests execute actual `BulkCopySourcePK()`, `BulkCopyDestinationPK()` and `BulkCopyTable()` methods. Each owning table produces one source copy, two destination-key pages (five keys at batch size three), and three archive-data batches (batch size two). **60, 120, 30, 0 and 2147483647** are observed unchanged at write entry; paired tables and reversed traversal exercise isolation.
- Observed writes retain streaming, `Id:Id` mappings, key/data batch sizes, key options zero and archive `KeepIdentity | KeepNulls`. Empty source/data readers and empty reconciliation pages allocate no copy. Existing disabled/inactive/empty workflow coverage passes.
- Write interruptions and independent bulk/reader disposal failures at every actual stage preserve the primary interruption, attempt command/connection release, and prevent subsequent archive/overall success checkpoints. Existing checkpoint and cleanup assertions remain intact.
- Live paired-table cases observe **60/120** and **30/0** immediately before forwarding to the real provider: one source capture, three reconciliation pages and three data batches per table (batch sizes two). Each table archives keys 1–5 and completes. Initial fixture inserts omit the timeout and storage returns 30. The real procedure/model returns typed integers. Separate group/active tests exclude inactive and other-group rows.
- Real blocking begins after the archive source reader is ready and the actual write wrapper is entered. An independent connection holds `TABLOCKX/HOLDLOCK` on the real archive target. Server-side delayed rollback releases the lock independently of assertions. Real provider async writes inside the test interception permit an independent **90-second cancellation watchdog**; production remains synchronous. Fixture command limits are 120 seconds.
- Positive timeout **2 seconds** fails with provider error **-2** after **2.037 seconds** in the final full run (targeted runs: 2.042 and 2.045). `KeyCopyDate` is retained, `LastArchivedKey = 0`, archive/overall completion stay null, and working keys remain present. Cleanup releases the blocker; a fresh invocation resumes to five correct destination rows. The test makes no earlier-batch rollback assumption.
- Timeout **0** completes after a real **35.013-second** blocked write in the final run (targeted run: 35.014). No watchdog fires; blocker/resources are released. Only the first archive batch is blocked; subsequent batches complete normally.
- Ordinary command properties retain connection timeout **2** and independent source/destination defaults **30**. For bulk settings **30, 120 and 0**, actual `WAITFOR DELAY '00:00:05'` queries still fail with provider timeout **-2** at about **2 seconds**. Production query helpers and timeout assignments are unchanged.

## Existing-installation preparation (T017–T020)

- [Guide](../../Fast1Archiving.md) and [help](../../Fast1data.SqlServer/public/Invoke-Fast1Archiving.ps1) document units, defaults, valid/invalid values, three operations, query independence, and preparation before using 0.2.2.
- Standalone runbook review confirms the complete order: stop runs; select/verify configuration database; add the integer field; backfill **every** old row to 30; establish/validate non-null, default and trusted check; deploy the updated metadata procedure; verify metadata, identities and progress; resume one process per group. Column creation and backfill use separate batches. Setup reruns cannot add the field. No migration/automatic repair is shipped.
- The isolated legacy fixture has two old configurations (including an inactive row), retained process/working keys, and **two committed destination rows** with a rejected archive checkpoint. It then receives an old schema/projection lacking the timeout.
- Rerunning current `tables.sql` leaves the column absent and full configuration/progress/source-key/destination-key snapshots unchanged. Invoking the changed module fails both before preparation and after storage-only preparation with the old projection, without resetting state.
- Manual preparation adds a nullable integer, backfills all old rows to 30, enforces `NOT NULL`, adds the named default/trusted check, then deploys procedures. Both old rows are 30; a future omitted insert also receives 30. Accepted values 0, 1, 120 and Int32 maximum round-trip on inserts and updates through prepared storage, procedure and typed model.
- Configuration identities/parent relationships, progress and both working-key snapshots match before resumed execution. The same process resumes from two durable rows to **five unique destination keys**, purges five source rows and completes. Alteration code exists only inside this disposable fixture.

## Database value validation (T021–T023)

- Inserts and updates reject **-1** and **-2147483648** with error **547** naming `CK_SourceTable__BulkCopyTimeout`.
- Explicit SQL NULL inserts/updates fail with error **515** identifying `BulkCopyTimeout`. Other required fields come from valid fixture rows.
- Every rejected update retains the prior **30**. Rejected inserts leave no configuration row.
- Fresh and manually prepared schemas accept insert/update values **0, 1, 120 and 2147483647**; storage, real procedure and typed model preserve every value. Named constraints and trusted/enabled check state are verified. Int32 maximum is tested without waiting for expiration.

## Contract review, release decision and analysis (T025–T028)

- FR-001/002: create-only SQL definition adds the required integer/default/check. FR-003/004/006: named lookup, typed property loaded from the database and three unconditional assignments preserve values/ownership. FR-005: no query timeout changes. FR-007/008/009: create-only deployment and manual preparation are documented/rehearsed. FR-010/011: controlled/live success, failure and retry coverage verifies copying and recovery.
- Production review confirms one configuration column, one procedure result field, one typed property/mapping and three property assignments. Public signature/exports, factory signature, dependencies, batching/options/streaming, resource ownership, retry policy, progress formats, working sets, archive/purge order and checkpoints are preserved. No migration, compatibility fallback or automatic existing-table alteration is introduced.
- Maintainer explicitly selected **0.2.2** in this conversation (previously 0.2.1). Manifest version/release notes describe semantics and required preparation. PowerShell 7.6+ Core, x64 Windows/Linux and six exports are preserved. No release was published.
- `Invoke-ScriptAnalyzer -Path <file>` ran on all five changed PowerShell files with dependencies loaded: **0 findings**. An exploratory run without dependency loading emitted 16 informational missing-provider-type diagnostics; loading dependencies resolved them without suppression. No analyzer settings or new errors/warnings exist.

## Success criteria, cleanup and remaining checks (T029)

| Criterion | Evidence |
| --- | --- |
| SC-001 | Fresh omitted insert=30; stored value loaded into the model; every legacy configuration=30 after preparation. |
| SC-002 | Three actual writes; paired/reversed settings; repeated pages/batches; live 60/120 and 30/0. |
| SC-003 | Six intended negative/null rejections; prior 30 retained; valid boundaries round-trip in both schemas. |
| SC-004 | Pre/post command properties; real delayed-query timeouts for 30/120/zero; generic regressions. |
| SC-005 | Runbook review; legacy missing schema/projection failure, create-only rerun, manual preparation and retained-state resume. |
| SC-006 | Actual-stage interruptions/cleanup; provider timeout/fresh retry; full partial-capture, reconciliation, checkpoint, purge and cleanup regressions. |

All five affected suites pass with no skips. In the 1105-key composite regression, 200 rows committed before a rejected checkpoint, partial destination-key reconciliation was rebuilt, and retry archived all 1105 unique keys while retaining outside key 99999. Earlier-table completion remains durable across a later-table failure. Purge/checkpoint/FK restoration regressions pass.

Fixture database teardown completed in `AfterAll` in reverse order, with no cleanup errors. Barriers release in `finally` via cancellation and blocker disposal. A final read-only query found **zero** remaining archiving, legacy or generic-query fixture databases. `Test-ModuleManifest` confirms version **0.2.2** and **six** exported commands. Analysis after the final indentation edit again reports zero findings; `git diff --check` passes.

No material recovery risk identified. Linux host execution was unavailable and remains an open platform release-validation gate; this implementation was verified on supported Windows x64. No required feature acceptance scenario remains unrun on the selected host/SQL instance.

The required post-implementation check confirms `.specify/extensions.yml` does not exist, as before implementation. There are no registered pre/post hooks to dispatch. All **29 implementation tasks** are complete; checklist markers were never modified. No release was published.

## Follow-up: database-owned default

Removed the `Table.BulkCopyTimeout` initializer so the database is the sole source of the configured 30-second default. Normal execution still reads the required metadata field unchanged; private direct construction must explicitly supply a timeout before copying. Removed the direct-construction default assertion while retaining configured-value and empty-reader checks. Updated the guide, contract and design/task documents to match.

Re-ran `Archiving.Execution.Tests.ps1` in PowerShell Core: **40 passed, 0 failed, 0 skipped**. This includes metadata mapping, all three write operations, zero, Int32 maximum and missing-metadata failure. `git diff --check` passes. Live integration suites were not rerun for this follow-up; the live results above describe the original implementation validation.

## Release-version follow-up: 2026-11-24

The maintainer selected **0.3.0**, superseding the earlier 0.2.2 decision. Updated the manifest version and the bulk-copy timeout release-note heading to 0.3.0. Earlier validation results above retain the version tested at that time. `Test-ModuleManifest` confirms version **0.3.0** and **six** exported commands; PSScriptAnalyzer reports **zero findings** for the changed manifest. Feature tests were not rerun for this metadata-only change. No release was published.

