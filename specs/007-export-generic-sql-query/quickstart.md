# Validation Guide: Generic SQL Commands

**Feature**: [spec.md](spec.md) | **Commands**: [contracts/public-commands.md](contracts/public-commands.md) | **History**: [contracts/migration-history.md](contracts/migration-history.md) | **Model**: [data-model.md](data-model.md)

This is the implementation acceptance guide and evidence record. Run the commands from the repository root. Source, staged, native-host, and live results are recorded separately; unavailable environments are not claimed as passed.

The live SQL follow-up at the end of this document supersedes the initial implementation's unavailable-live status below. Earlier source/staged results remain historical evidence.

## Implementation evidence — 2026-11-20

- Maintainer confirmed the complete contract: "Yes, confirm and implement" (T001).
- Baseline: Windows x64, PowerShell Core 7.6.10, .NET runtime bundled with PowerShell; Pester 6.2.0 and PSScriptAnalyzer 1.25.0 available. No repository analyzer settings found. Build target remains net10.0 with SqlClient 7.1.2 and ScriptDom 180.154.0. Both DLLs exist in win-x64, linux-x64, and osx-x64 bundles; other native hosts are unavailable.
- `FAST1_TEST_MIGRATION_SQL_CONN_STR` is absent/blank. Live SQL acceptance remains unverified; no connection string was printed.
- Existing git ignores cover build output, bundled assemblies, staging and temporary/editor files. No additional technology-specific ignore file is needed; `.vscode/` remains tracked.
- Baseline command: `Invoke-Pester -Path ./Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1,./Fast1data.SqlServer/tests/Migration.Tests.ps1,./Fast1data.SqlServer/tests/Migration.Phase.Tests.ps1,./Fast1data.SqlServer/tests/Migration.Command.Tests.ps1,./Fast1data.SqlServer/tests/Migration.Execution.Tests.ps1,./Fast1data.SqlServer/tests/Migration.Preflight.Tests.ps1,./Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1,./Fast1data.SqlServer/tests/SharedHelpers.Import.Tests.ps1 -Output Normal`.
- Baseline outcome: **283 passed, 6 failed, 1 skipped**, 655.19 seconds. All 86 module-loader cases and all 30 shared-import matrix cases passed. The six pre-existing failures are Migration.Command invalid connection-string cases (malformed/unknown keyword/invalid typed value, for empty and executable files); the executable variants unexpectedly retain `ambient suppression failed`. The platform-specific case-sensitive sibling-directory case is skipped on Windows. The first sandbox attempt could not create Pester's temporary registry key; the authorized rerun outside the sandbox produced these results.
- Foundation red check: `Invoke-Pester -Path ./Fast1data.SqlServer/tests/fixtures/GenericSqlQuery.CleanupCases.ps1 -ExcludeTag QueryRows -Output Normal`: 4 passed, 4 failed as expected, proving nonnullable Type and binary-array coercion in both root/model scopes before implementation. Row tests were excluded (24 not run).

## Prerequisites

- PowerShell 7.6+ Core, Pester 6+, and PSScriptAnalyzer. Use project analyzer settings when available; report unavailable checks.
- Existing SqlClient/ScriptDom bundles for the selected host. If absent, build through `./build/build.ps1` with the .NET 10 SDK and NuGet access.
- Native x64 Windows, Linux, and macOS hosts for supported-platform acceptance. Cross-built DLLs alone do not prove native behavior.
- For live checks, explicitly configure `FAST1_TEST_MIGRATION_SQL_CONN_STR` from the test environment's secret store. The new query integration suite reuses this existing opt-in and must skip when blank, just as the migration suite does. A skip is not a pass.
- Both live suites create uniquely named disposable databases and clean them up. The selected test SQL instance/login needs create/drop-database and fixture/schema/procedure permissions. Do not target production or print secrets.

## 1. Verify imports and the public factory in fresh processes

Run once with the manifest path and again in a fresh process using the root `.psm1` path.

```powershell
pwsh -NoProfile -Command {
	$ErrorActionPreference = 'Stop'
	Import-Module ./Fast1data.SqlServer/Fast1data.SqlServer.psd1 -Force
	Get-Command -Module Fast1data.SqlServer | Sort-Object Name | Select-Object Name
	$parameter = New-Fast1GenericSqlParam -Type BigInt -Value 42
	$parameter.Type
	$parameter.Value
	Get-Help Invoke-Fast1GenericSqlQuery -Full
	Get-Help Invoke-Fast1GenericSqlQueryReader -Full
	Get-Help New-Fast1GenericSqlParam -Full
}
```

Expected: exactly the six exports in the public contract; BigInt and 42; complete help. No `using module`, private class name, or private module import is required. Existing commands retain their parameter metadata. An explicit null/invalid Type fails binding; an omitted mandatory Type uses normal PowerShell parameter binding and must not silently default to BigInt. Use noninteractive binding tests for missing-type verification to avoid waiting on a prompt.

## 2. Run focused offline regressions

```powershell
Invoke-Pester -Path @(
	'./Fast1data.SqlServer/tests/GenericSqlQuery.Tests.ps1'
	'./Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1'
	'./Fast1data.SqlServer/tests/Migration.Tests.ps1'
	'./Fast1data.SqlServer/tests/Migration.Phase.Tests.ps1'
	'./Fast1data.SqlServer/tests/Migration.Command.Tests.ps1'
	'./Fast1data.SqlServer/tests/Migration.Execution.Tests.ps1'
	'./Fast1data.SqlServer/tests/Migration.Preflight.Tests.ps1'
	'./Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1'
	'./Fast1data.SqlServer/tests/SharedHelpers.Import.Tests.ps1'
) -Output Detailed
```

Expected coverage:

| Area | Required observations |
|---|---|
| Factory/binder | Typed null, mandatory Type, nullable missing Type rejection, BigInt zero acceptance, positive metadata, zero/default semantics, negative factory Size rejection, native binary parameter values. |
| Existing execution | Scalar values/empty/DBNull behavior unchanged; non-query emits no row count; CommandType and command timeout retained; borrowed connection untouched. |
| Row selection/schema | Zero/one/many rows; no tabular result; leading non-tabular result; first empty result followed by populated result; later results ignored; invalid names/duplicates fail before output even for empty results. |
| Native values | Column names/order, null, numeric/date values, byte arrays of lengths zero, one, and multiple bytes. |
| Streaming | First output observed before the second read; a later read failure leaves the first row observed; Select-Object -First 1 stops application reads and releases owned resources. |
| Cleanup | Command construction/binding, reader creation, result navigation, schema inspection, reads, reader disposal, and command disposal failures; all owned disposals attempted in order; operation error retained with safe cleanup details. |
| History delegation | Exact query/open connection, NVarChar(32) phase descriptor, empty/populated history, exact stored script names/checksums, connection-only outer ownership, nested reader-command-connection disposal on success/failure/truncation. |
| Isolation/imports | Root and model shared helpers keep their defining scopes; model/type modules export no commands; exactly six root exports; original three command contracts preserved. |

Revise the fixed export snapshot deliberately. Update hardcoded child-worker totals only if test counts actually change. Ensure the fresh-process worker includes any new shared-scope query tests needed to prove class identity and import-order behavior. Mocks/doubles establish timing and injected errors, not actual SQL Server result metadata.

## 3. Run a public SQL smoke scenario

The following uses the explicitly supplied test connection and performs constant queries plus a session SET statement. It creates no persistent schema/data. The integration suites in step 4 own their separate fixture databases.

```powershell
Import-Module ./Fast1data.SqlServer/Fast1data.SqlServer.psd1 -Force
if ([string]::IsNullOrWhiteSpace($env:FAST1_TEST_MIGRATION_SQL_CONN_STR)) {
	throw 'Select a test SQL environment before running live validation.'
}

$connection = [Microsoft.Data.SqlClient.SqlConnection]::new($env:FAST1_TEST_MIGRATION_SQL_CONN_STR)
try {
	$connection.Open()
	$parameters = @{
		Id = New-Fast1GenericSqlParam -Type BigInt -Value 42
		Name = New-Fast1GenericSqlParam -Type NVarChar -Size 100
	}
	Invoke-Fast1GenericSqlQueryReader -SqlConn $connection `
		-Query 'SELECT @Id AS Id, @Name AS Name, CAST(0x0102 AS varbinary(2)) AS Payload' `
		-Parameters $parameters |
		ForEach-Object {
			$_.Id
			$null -eq $_.Name
			$_.Payload.GetType().FullName
		}
	Invoke-Fast1GenericSqlQuery -SqlConn $connection -Query 'SELECT CAST(42 AS bigint)' -Scalar
	$nonQueryOutput = @(Invoke-Fast1GenericSqlQuery -SqlConn $connection -Query 'SET NOCOUNT ON;')
	$nonQueryOutput.Count
	Invoke-Fast1GenericSqlQueryReader -SqlConn $connection `
		-Query 'SELECT CAST(1 AS int) AS FirstValue WHERE 1 = 0; SELECT 2 AS LaterValue;'
	Invoke-Fast1GenericSqlQueryReader -SqlConn $connection `
		-Query 'SELECT value AS Id FROM (VALUES (1), (2), (3)) AS source(value);' |
		Select-Object -First 1
	Invoke-Fast1GenericSqlQuery -SqlConn $connection -Query 'SELECT 1' -Scalar
	$connection.State
}
finally {
	$connection.Dispose()
}
```

Expected: 42, True, System.Byte[], scalar 42, non-query output count 0, no object from the empty first result, one Id row, then scalar 1 and Open. The final query verifies reader cleanup permits reuse while the connection remains caller-owned. No output from later result sets is promised; later SQL statements may still execute during provider processing/cleanup.

## 4. Run real provider and migration acceptance

```powershell
Invoke-Pester -Path @(
	'./Fast1data.SqlServer/tests/GenericSqlQuery.Integration.Tests.ps1'
	'./Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1'
) -Output Detailed
```

The new query suite must validate real empty/multiple/non-tabular result handling, aliases and invalid empty-result schemas, native numeric/date/binary values, SQL NULL, typed BigInt/null parameters, StoredProcedure input parameters, no affected-row output, early termination with connection reuse, and provider errors. Use controlled doubles for deterministic late-read failure timing and disposal exceptions; provider buffering makes SQL batch text alone insufficient proof of read timing.

Migration acceptance must retain persisted legacy names on normal reads, original-key forced updates including case-sensitive database coverage, checksum/skip timestamps, empty history, idempotent retries, failure stopping, and WhatIf. Add targeted history delegation/nested cleanup cases rather than rewriting phase evaluation. A SQL failure after earlier row delivery or committed statements is not a rollback guarantee.

## 5. Analyze changed PowerShell and validate staged imports

Run Invoke-ScriptAnalyzer on every modified `.ps1`, `.psm1`, and `.psd1`, including fixtures/tests, using repository settings if any exist. Resolve newly introduced errors/warnings without suppression. Record unrelated existing findings separately. Planning does not alter PowerShell files and does not require an analyzer claim.

After source checks pass:

```powershell
./out/publish.ps1 -StageOnly
pwsh -NoProfile -Command {
	$ErrorActionPreference = 'Stop'
	Import-Module ./out/Fast1data.SqlServer/Fast1data.SqlServer.psd1 -Force
	Get-Command -Module Fast1data.SqlServer | Sort-Object Name | Select-Object Name
	New-Fast1GenericSqlParam -Type BigInt -Value 42
}
```

Expected: existing stage validation succeeds; the package exposes six commands, includes new public/help/test files, and retains all runtime assets. In a fresh process, also import the staged `.psm1` and run the staged ModuleLoaders/SharedHelpers/query suites using their paths under `out/Fast1data.SqlServer/tests/`. Repeat native import and live-query smoke checks on supported hosts. StageOnly avoids invoking unrelated live suites; review its analyzer output as well as exit status.

Record commands, runtime/platform, counts, failures, skipped live checks, unavailable environments, and source versus staged evidence during implementation. Unrun native/live checks remain unverified; material unresolved resource or migration integrity failures block release.

### US1 checkpoint

- Foundation cleanup run: 56 passed, 0 failed; 24 future row cases excluded.
- Factory red: 10 expected missing-command failures. Focused factory/binding/scalar compatibility afterward: 34 passed, 0 failed.
- Fresh manifest and direct `.psm1` public-caller tests: 2 passed. Five exports verified, BigInt factory usable without private class lookup; direct public binding reaches normal closed-connection provider failure.
- Shared worker L1/ARM: total inventory 194, 169 passed, 0 failed, 1 Windows skip, 24 future row cases excluded. Original public command metadata compared unchanged before extending the snapshot. Full final matrix remains required after row/history implementation.
- Direct import required a literal class import in the factory itself. A trial shared-file class import disrupted archiving generic-type resolution and was removed; the worker then passed. No shared behavior import or class identity was changed.
- US2 red: 54 expected missing-row-command failures across schema/streaming/cleanup cases before implementation.

### US2 / US3 and revised API

- Maintainer requested `Invoke-Fast1GenericSqlQueryReader` instead of the plural command name and chose API revision over analyzer exceptions. References, exports, help, tests, and contracts use the new name; it emits row objects and never returns a live reader.
- `New-Fast1GenericSqlParam` supports standard WhatIf/Confirm with low confirmation impact. WhatIf emits no descriptor. History discovery explicitly uses `-WhatIf:$false -Confirm:$false` on the factory so migration preview still reads persisted checksums; the new ambient-WhatIf history regression covers this.
- US2 checkpoint before the rename: 90 focused tests passed, 6 live query cases skipped, 118 unrelated cases filtered. The L1/ARM worker passed 233 of 234 cases, with the expected Windows skip.
- History red: 2 passed and 9 expected delegation failures before refactoring. History/phase/command/execution/preflight/cleanup plus live migration discovery afterward: 210 passed, the same 6 baseline connection-string failures, 36 skipped (35 live migration cases and the Windows case).
- Added reusable test-only fixtures: GenericSqlQuery.Doubles.ps1; GenericSqlQuery.CleanupCases.ps1 is discovered by SqlCleanup.Tests.ps1, and GenericSqlQuery.HistoryCases.ps1 by Migration.Tests.ps1. History uses temporary type-data overrides removed after each test, with state stored in the selected module rather than global variables. No production seams or descriptor class duplicates were added.
- A deterministic probe confirmed PowerShell suppresses outer observation of cleanup throws during downstream truncation. The regression intercepts the actual cleanup helper throw before engine suppression and verifies reader/command attempts and safe combined failure details. Normal operation and cleanup errors remain terminating.
- Original three public command metadata entries were compared unchanged before regenerating the extended snapshot. Final worker inventory is 249 cases after factory WhatIf, ambient-preview, and truncation-disposal cases were added.

### Final focused validation and analyzer

- Runtime: Windows x64, PowerShell 7.6.10, .NET 10.0.15. Final focused command: `Invoke-Pester -Path ./Fast1data.SqlServer/tests/GenericSqlQuery.Tests.ps1,./Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1,./Fast1data.SqlServer/tests/Migration.Tests.ps1 -Output Normal`: **179 passed, 0 failed, 0 skipped** (41 query, 82 cleanup, 56 migration cases).
- `Invoke-ScriptAnalyzer -Path <each changed PowerShell file> -Severity Error,Warning`: **21 files, 0 warnings/errors**, no rule suppression or disabled rules. No project settings file exists. The final cleanup fixture was reanalyzed after its last edit and remained clear.
- Analyzer coverage: root .psm1/.psd1; private migration/Get-Executed.ps1 and shared GenericSqlParam.psm1/GenericSqlQuery.ps1; public New-Fast1GenericSqlParam.ps1; tests Archiving.Execution, Migration, Migration.Integration, ModuleLoaders, SharedHelpers.Import, SqlCleanup, GenericSqlQuery, GenericSqlQuery.Integration; fixtures Invoke-ModuleLoaderScenario, Invoke-SharedHelperScenario, SharedHelpers.Classes, SharedHelpers.Scenarios, GenericSqlQuery.Doubles, GenericSqlQuery.CleanupCases, GenericSqlQuery.HistoryCases.
- No analyzer exception was accepted. The requested singular Reader name, proper factory ShouldProcess implementation, test-fixture Get naming, and module-owned test state resolved all eight initial findings.

### Final source distribution

The final nine-suite offline run used the path list in section 2 with `-Output Normal -PassThru`, suppressing only routine information-stream output and selecting TotalCount/PassedCount/FailedCount/SkippedCount/Result plus failed case names for a structured JSON report.

| Scope | Passed | Failed | Skipped | Outcome |
| --- | ---: | ---: | ---: | --- |
| Final source suites (379 cases) | 372 | 6 | 1 | Same six baseline migration-input failures; no new failures |
| ModuleLoaders, included above | 88 | 0 | 0 | Direct/manifest public use, six exports, shared ownership and fault handling passed |
| SharedHelpers.Import, included above | 30 | 0 | 0 | All five loading patterns × six operation orders passed |
| Each matrix child inventory | 248 | 0 | 1 | 249 total; only the approved Windows filesystem skip |

The six failures are the malformed/unknown-keyword/invalid-typed-value ConnStr cases in Migration.Command.Tests.ps1, each with executable=false and executable=true. They reproduce the pre-edit baseline; Invoke-Migration.ps1 and those tests were left unchanged. The overall source suite remains red and is not a release approval. Follow-up on the existing migration-input failures and required live SQL acceptance remains a release gate.

### Staging and supported-host evidence

`./out/publish.ps1 -StageOnly` succeeded, including the package-wide analyzer. No publishing behavior or dependency/runtime versions changed. All runtime file counts match source: win-x64 55, linux-x64 53, osx-x64 53. SHA-256 hashes of SqlClient and ScriptDom match source in all three bundles. Staged public help resolves with two examples for each new command.

Windows x64 source direct/manifest import and offline query execution are verified. The staged full import/query matrix is recorded below when complete. Linux and macOS native imports/smoke checks are **unverified** because those hosts are unavailable. Their copied bundles and matching assembly hashes do not establish native execution.

Live query/migration acceptance and the public SQL smoke are **unverified** because FAST1_TEST_MIGRATION_SQL_CONN_STR is blank. Integration discovery explicitly skipped 6 generic-query cases and 35 migration cases. This includes unavailable real-provider result metadata, SQL NULL/binary/StoredProcedure behavior, connection reuse, persisted legacy-key updates/collation, retry and preview acceptance. Controlled offline tests do not replace those checks.

### Final staged result and completion

The staged command used `Invoke-Pester -Path ./out/Fast1data.SqlServer/tests/GenericSqlQuery.Tests.ps1,./out/Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1,./out/Fast1data.SqlServer/tests/SharedHelpers.Import.Tests.ps1 -Output Normal -PassThru` with the same structured summary as source: **159 total, 159 passed, 0 failed, 0 skipped**. This includes 41 query cases, 88 fresh-process loader cases and all 30 shared-import scenarios. Each matrix child retained its 249-case inventory and expected Windows filesystem skip; unexpected skips are rejected. Staged manifest and direct .psm1 public factory/reader contracts, selected-root assembly ownership and original command metadata passed.

All 34 implementation tasks are completed and marked. Source/staged offline behavior, public help, analyzer and packaging checks are complete. The six pre-existing source migration-input failures remain unresolved; overall regression/release acceptance is not green. Real SQL-provider and native Linux/macOS acceptance remain unverified as detailed above. No material new resource-ownership or migration-identity failure was found in the available checks.

The mandatory post-implementation hook check found no `.specify/extensions.yml`; no hooks were registered or dispatched. No checklist directory exists for this feature, and no reviewer checklist markers were changed.

### Live SQL follow-up — 2026-11-20

The maintainer supplied `FAST1_TEST_MIGRATION_SQL_CONN_STR` in the process environment and requested migration integration execution and fixes against the current specification. Source checks now reach the selected SQL Server; credentials are not recorded here.

- Initial migration integration run: **32 passed, 3 failed, 0 skipped**. All three resource-trace failures came from the specified Get-Executed delegation: history discovery now uses Get-GenericSqlCommand, so the existing mock also observes its correctly disposed read command before mutation. The trace now distinguishes discovery and mutation commands by connection identity and asserts both disposals in order, preserving the mutation timeout and connection checks. Production cleanup code was unchanged.
- Empty fixture history independently emitted nonterminating ConvertFrom-Json null-input errors. A new regression with ErrorActionPreference Stop reproduced the error before the fix. The fixture now selects its FOR JSON result as a scalar subquery with COALESCE to N'[]', returning an explicit empty array when SQL supplies no JSON value. Existing populated-history checks still cover names, checksums and timestamps.
- The new public-query live suite initially failed setup with `Keyword not supported: 'InitialCatalog'`. Both assignments now use the builder's `['Initial Catalog']` key, matching the migration fixture. All **6 query provider cases passed** afterward, covering real result sets, aliases, native/null/binary values, typed parameters, stored procedures, early termination and connection reuse.
- Source offline regression command: `Invoke-Pester -Path ./Fast1data.SqlServer/tests/GenericSqlQuery.Tests.ps1,./Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1,./Fast1data.SqlServer/tests/Migration.Tests.ps1 -Output Normal`. All **179 cases passed** in the combined regression run; the repaired migration suite also passed all **36 cases** in that run. The six query cases failed setup in that run and were rerun after their fixture correction.
- Final live command: `Invoke-Pester -Path ./Fast1data.SqlServer/tests/GenericSqlQuery.Integration.Tests.ps1,./Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1 -Output Normal -PassThru`: **42 passed, 0 failed, 0 skipped**, 55.07 seconds (6 query and 36 migration cases). No ConvertFrom-Json null-input errors appeared. Migration acceptance includes case-sensitive legacy-key updates, retry, forced/skipped timestamps, preview and cleanup failures.
- Invoke-ScriptAnalyzer on both edited integration test files reported **0 warnings/errors**, with no suppression. Verification used Windows x64 and the existing PowerShell/Pester/SqlClient environment. Pester required execution outside the sandbox to create its temporary registry key.

These follow-up changes affect source integration fixtures and this acceptance record. Staged checks were not repeated for the fixture corrections. The six previously documented baseline migration-input failures were outside this targeted fix and were not rerun; native Linux/macOS execution remains unverified. This follow-up does not establish overall release acceptance.
