# Validation Guide: Generic SQL Commands

**Feature**: [spec.md](spec.md) | **Commands**: [contracts/public-commands.md](contracts/public-commands.md) | **History**: [contracts/migration-history.md](contracts/migration-history.md) | **Model**: [data-model.md](data-model.md)

This is the implementation acceptance guide and evidence record. Run the commands from the repository root. Source, staged, native-host, and live results are recorded separately; unavailable environments are not claimed as passed.

## Public-file relocation amendment — 2026-11-20

**Status**: Full source and freshly staged test suites rerun on Windows x64. The full staged run passed 507 tests with 26 expected skips. The source run had four audit-fixture setup failures, all resolved by successful source/staged audit reruns. Current query, migration, archiving and Windows audit SQL acceptance plus both public SQL smoke scenarios passed. Native Linux/macOS checks remain unverified; full cross-platform release acceptance is not established.

The required file and scope contracts are in [contracts/command-loading.md](contracts/command-loading.md). The existing parameter, query, cleanup, and history behavior contracts remain applicable. Tasks T035–T056 are complete; the execution record below documents measured outcomes and unavailable acceptance.

### A. Check layout and supported source imports

After implementation, run the source regression command in section 2, including the added archiving suite. The amended loader tests must verify all three exact public filenames, matching definitions/help, no public definitions left in `private/shared`, private support remaining hidden, 23 private dependency files, and the unchanged three-entry shared loader. Verify the model's two public references separately from private inventory counts.

Run the fresh-process root imports in section 1 for both manifest and direct `.psm1`. Also run standalone model-first loading from the repository root:

```powershell
pwsh -NoProfile -Command {
	$ErrorActionPreference = 'Stop'
	. ./Fast1data.SqlServer/private/shared/Get-RuntimeIdentifier.ps1
	. ./Fast1data.SqlServer/private/shared/Import-RequiredLibrary.ps1
	Import-RequiredLibrary -DllName Microsoft.Data.SqlClient.dll -RequiredTypeName Microsoft.Data.SqlClient.SqlConnection
	Import-Module ./Fast1data.SqlServer/private/archiving/ArchivingModel.psm1 -Force
	$model = Get-Module ArchivingModel
	$model.ExportedFunctions.Count
	& $model {
		Get-Command Invoke-Fast1GenericSqlQuery, Invoke-Fast1GenericSqlQueryReader |
			Select-Object Name, ModuleName, @{ Name = 'SourceFile'; Expression = { $_.ScriptBlock.File } }
	}
	Import-Module ./Fast1data.SqlServer/Fast1data.SqlServer.psd1 -Force
	Get-Command -Module Fast1data.SqlServer | Sort-Object Name | Select-Object Name
}
```

Expected: zero model exports, both model-local queries sourced from their matching public files, then exactly six root commands. Use the existing fresh-process loader harness for dependency/bootstrap setup and fault cases; preserve its selected-assembly ownership checks. Repeat with the staged paths after staging. Existing standalone model dependency prerequisites still apply.

The amended `ModuleLoaders.Tests.ps1` must inject missing, corrupt, and runtime-failing versions of each public query file for root and model consumers. Both must reject initialization. Root reaches these required files through its mandatory archiving model load before its public discovery loop, so root public enumeration alone is not the missing-file check.

`SharedHelpers.Import.Tests.ps1` must retain all 30 loading/order combinations, independent root/model owners, and unchanged six-command metadata. Strengthen provenance checks to exact matching public files. Keep 16 owner observations; retain the current 253-case child inventory and recalculate only if included cases are added, retaining strict unexpected-skip checks.

### B. Analyze and verify the package

Run `Invoke-ScriptAnalyzer` on every new/modified PowerShell file, including both public query files, root module, archiving model, private support file, and affected tests/fixtures. Use repository analyzer settings if present, resolve new findings without suppression, and record unavailable checks. No analyzer settings were found in the earlier implementation; recheck at implementation time.

Run `./out/publish.ps1 -StageOnly`, then the staged affected suites explicitly:

```powershell
Invoke-Pester -Path @(
	'./out/Fast1data.SqlServer/tests/GenericSqlQuery.Tests.ps1'
	'./out/Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1'
	'./out/Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1'
	'./out/Fast1data.SqlServer/tests/Migration.Tests.ps1'
	'./out/Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1'
	'./out/Fast1data.SqlServer/tests/SharedHelpers.Import.Tests.ps1'
) -Output Normal -PassThru
```

Expected: matching public files and help are packaged, source provenance points into `out/Fast1data.SqlServer`, manifest/direct and standalone model imports preserve their boundaries, and query/cleanup/history/archiving behavior has no new failures. StageOnly copies the source/test/runtime trees and runs analyzer; it does not execute these suites. No packaging script change is expected.

### C. Recheck provider behavior and record amendment evidence

Use section 4's live query/migration suites with the explicitly configured `FAST1_TEST_MIGRATION_SQL_CONN_STR`; do not print it. Repeat section 3's public smoke and available supported-host imports. Keep SQL fixture creation/destruction within the existing suites' uniquely named test databases. Missing SQL access or native hosts must be recorded as unverified rather than passed.

Record amendment results separately: command, platform/runtime, source or staged root, counts, failures, skips, analyzer findings, and unavailable environments. Compare any migration-input failures to the earlier six-case baseline; a known baseline failure does not make the overall suite green. The execution record below reports the completed checks and remaining provider/native limitations.

## Full-suite rerun — 2026-11-20

This is the latest validation checkpoint and supersedes the initial relocation status below. All 18 test files were rerun from source and from a freshly staged package, with no tag exclusions. The additional audit reruns used the repaired fixture. No application or test source code changed during this validation work.

| Run | Total | Passed | Failed | Skipped | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| Full source, before audit fixture repair | 533 | 503 | 4 | 26 | Four Windows audit setup failures; resolved by focused rerun |
| Focused source audit rerun, after repair | 40 | 15 | 0 | 25 | Passed |
| Full staged package | 533 | 507 | 0 | 26 | Passed |
| Focused staged audit rerun | 40 | 15 | 0 | 25 | Passed |

The full source run is retained with its actual four failures. All four came from the Windows audit BeforeAll fixture check:

> Audit folder is missing or inaccessible to the current Windows user: <redacted>

After the maintainer repaired the fixture, FAST1_TEST_AUDIT_FOLDER was accessible and all four live Windows audit tests passed in both focused reruns and the full staged run. The source full-suite command was not repeated after that repair; its only failed suite was rerun successfully. No unresolved Windows test failure remains in the available checks.

The 26 full-run skips are 21 Linux audit unit cases, four Linux audit integration cases, and the Windows-inapplicable case-sensitive-filesystem migration case. Each focused audit run skips the same 25 Linux cases. No tag was excluded and no test was filtered out. Native Linux/macOS execution remains unverified; this Windows result does not establish full cross-platform release acceptance.

### Per-suite results

Counts below are passed / failed / skipped for each full run. Focused audit reruns are recorded separately above.

| Test file | Full source | Full staged |
| --- | ---: | ---: |
| Archiving.Execution.Tests.ps1 | 28 / 0 / 0 | 28 / 0 / 0 |
| Archiving.Integration.Tests.ps1 | 29 / 0 / 0 | 29 / 0 / 0 |
| Audit.Common.Tests.ps1 | 4 / 0 / 0 | 4 / 0 / 0 |
| Audit.Integration.Linux.Tests.ps1 | 0 / 0 / 4 | 0 / 0 / 4 |
| Audit.Integration.Windows.Tests.ps1 | 0 / 4 / 0 | 4 / 0 / 0 |
| Audit.Linux.Tests.ps1 | 0 / 0 / 21 | 0 / 0 / 21 |
| Audit.Windows.Tests.ps1 | 7 / 0 / 0 | 7 / 0 / 0 |
| GenericSqlQuery.Integration.Tests.ps1 | 6 / 0 / 0 | 6 / 0 / 0 |
| GenericSqlQuery.Tests.ps1 | 45 / 0 / 0 | 45 / 0 / 0 |
| Migration.Command.Tests.ps1 | 16 / 0 / 0 | 16 / 0 / 0 |
| Migration.Execution.Tests.ps1 | 16 / 0 / 0 | 16 / 0 / 0 |
| Migration.Integration.Tests.ps1 | 36 / 0 / 0 | 36 / 0 / 0 |
| Migration.Phase.Tests.ps1 | 33 / 0 / 1 | 33 / 0 / 1 |
| Migration.Preflight.Tests.ps1 | 14 / 0 / 0 | 14 / 0 / 0 |
| Migration.Tests.ps1 | 56 / 0 / 0 | 56 / 0 / 0 |
| ModuleLoaders.Tests.ps1 | 101 / 0 / 0 | 101 / 0 / 0 |
| SharedHelpers.Import.Tests.ps1 | 30 / 0 / 0 | 30 / 0 / 0 |
| SqlCleanup.Tests.ps1 | 82 / 0 / 0 | 82 / 0 / 0 |

### SQL, imports, analysis and packaging

- Both full runs passed all six public-query provider cases, all 36 migration SQL cases and all 29 archiving SQL cases. The earlier Named Pipes connection failure is superseded by these successful live results.
- Windows audit acceptance now passes all four cases, including expected records/GUIDs, checkpoint reuse, ignored-record progress and lost-response recovery. Linux audit execution remains platform-skipped.
- Both source and staged section 3 public SQL smoke scenarios passed: typed Id 42, SQL NULL, System.Byte[], scalar 42, silent non-query count 0, empty first-result selection, early-stop row Id 1, reuse scalar 1 and still-open caller connection before final caller disposal.
- All 101 loader cases and all 30 shared-import combinations passed in each full run. The fixed six-command metadata, independent root/model owners, exact public provenance and empty nested exports were retained. The matrix still requires 253 child cases with strict skip checks; nested child skips are separate from the 26 outer-run skips.
- Fresh Invoke-ScriptAnalyzer validation covered all 11 changed PowerShell files with 0 warnings/errors. No suppression was added. All analyzed files match their tested staged copies.
- A fresh out/publish.ps1 -StageOnly completed successfully, including package-wide analysis. Runtime file counts match source/staging: win-x64 55/55, linux-x64 53/53, osx-x64 53/53. SqlClient and ScriptDom SHA-256 hashes match in every bundle. Bundled files do not establish native Linux/macOS execution.
- All six integration environment settings were present. SQL fixture databases were created by the existing isolated fixtures and guarded teardown paths. Connection strings, passwords and the private audit-folder value are omitted from this record.

### Runtime, timing and reproduction

Windows x64, PowerShell 7.6.10, .NET 10.0.15, Pester 6.2.0, PSScriptAnalyzer 1.25.0. No repository analyzer settings were found. Times use Europe/Bucharest:

- Full source: 2026-11-20 22:32:01 +02:00 to 2026-11-20 22:46:49 +02:00.
- Source audit rerun: 2026-11-20 22:52:52 +02:00 to 2026-11-20 22:52:57 +02:00.
- Full staged: 2026-11-20 22:49:05 +02:00 to 2026-11-20 23:03:52 +02:00.
- Staged audit rerun: 2026-11-20 22:59:21 +02:00 to 2026-11-20 22:59:26 +02:00.

Run each distribution in a fresh PowerShell process. The full runs used the configuration below; select source or staged Run.Path. Temporary registry support was disabled; no test uses TestRegistry. The audit-only reruns select all five Audit*.Tests.ps1 files with the same empty tag exclusions.

```powershell
$config = New-PesterConfiguration
$config.Run.Path = './Fast1data.SqlServer/tests' # Or ./out/Fast1data.SqlServer/tests
$config.Run.TestExtension = '.Tests.ps1'
$config.Run.PassThru = $true
$config.TestRegistry.Enabled = $false
$config.Output.Verbosity = 'Normal'
$config.Filter.ExcludeTag = @()
$result = Invoke-Pester -Configuration $config
$result | Select-Object TotalCount, PassedCount, FailedCount, SkippedCount, NotRunCount, Result
```

The initial relocation and earlier implementation records below remain intact as historical evidence. Current Windows SQL acceptance is verified; native Linux/macOS acceptance remains unavailable.

## Initial relocation execution evidence — 2026-11-20

This initial record is retained as history. The full-suite rerun above supersedes its live-SQL availability and acceptance conclusions.

### Initial amendment acceptance summary

| Scope | Initial relocation result |
| --- | --- |
| Pre-edit source baseline | 404 passed, 0 failed, 1 approved Windows skip (405 cases) |
| Focused source behavior | 211 passed, 0 failed, 0 skipped |
| Full ten-suite source command | 420 passed, 1 legacy assertion failure, 1 approved skip (422 cases) |
| Corrected source loader rerun | 101 passed, 0 failed; resolves the sole full-source failure without production changes |
| Source import matrix | All 30 combinations passed; each child 252 passed + 1 approved skip |
| Staged six-suite acceptance | 342 passed, 0 failed, 0 skipped; all 30 import combinations passed |
| Analyzer | 11 changed PowerShell files clean; package-wide StageOnly analyzer passed |
| Fresh Windows source/staged imports/help | Both entry points passed for both distributions; six exports, independent owners, complete help |
| Initial live SQL attempt | 42 setup failures: configured instance unreachable; provider/history acceptance and public smoke unverified |
| Native linux-x64 / osx-x64 | Hosts unavailable; imports and live smoke unverified |

The historical six migration-input failures did not reproduce in the current
baseline or full source run. The one amendment regression was an overbroad legacy
test matcher; it was corrected and the entire affected loader suite passed.
The red full-source run is retained below, alongside its successful targeted
rerun. No successful repeat of the full ten-suite command is claimed.

| Requirement / contract | Evidence and boundary |
| --- | --- |
| FR-001 / SC-001 | All three matching public definitions/help verified by four layout cases, intact function/help comparison and source/staged full help |
| FR-002 | No public definitions under private/shared; only binder and command factory remain in private query support; class identity/imports unchanged |
| FR-003 / SC-002 | Source/staged manifest/direct and model-first imports preserve six exports, fixed metadata, empty nested exports and independent owners on Windows; other native hosts unverified |
| FR-004 | Original function bodies/help unchanged; 211 focused source cases and staged behavior cover existing parameter, streaming and cleanup contracts; real provider unverified |
| FR-005 | History delegation/nested cleanup and independent archiving passed in source/staging; live persisted-key/collation/force/retry/preview acceptance unverified |
| FR-006 / SC-003 | Guidance, source/staged results, analyzer and packaging evidence complete; no unresolved offline regression, while provider/native acceptance remains incomplete |
| [command-loading.md](contracts/command-loading.md) | 23 private files, three shared entries, two separately verified public dependencies, 16 owner observations and all 12 dependency faults retained and verified |
| [public-commands.md](contracts/public-commands.md) | Six-command API, descriptor semantics, defaults, help and offline ownership/output behavior preserved; live SQL unavailable |
| [migration-history.md](contracts/migration-history.md) | Get-Executed unchanged; exact SELECT, NVarChar(32), stored key/checksum shape, preview and nested cleanup passed offline; real SQL unavailable |

The initial relocation execution used Windows x64, PowerShell 7.6.10, .NET 10.0.15,
Pester 6.2.0 and PSScriptAnalyzer 1.25.0. No repository analyzer settings were
found. SqlClient and ScriptDom assets exist in all three RID directories. The
opt-in SQL environment is configured; its value is not recorded. Native Linux
and macOS hosts are unavailable in this session.

Git ignores already cover build output, runtime assets, staging and temporary
files. No other detected technology needs an ignore file; `.vscode/` remains
available for tracked tasks. The requirements checklist passed 16/16 without edits.

| Amendment requirement | Acceptance checks |
| --- | --- |
| FR-001 / SC-001 | AST checks for exact public filenames, matching definitions and complete help; staged help checks |
| FR-002 | No public definitions in private shared files; only binder/command factory in query support |
| FR-003 / SC-002 | Fresh source/staged manifest and direct imports; unchanged six-command metadata snapshot; empty nested exports |
| FR-004 | Intact moved help/function comparison; factory, binding, streaming and cleanup regressions; live provider checks |
| FR-005 | Model-first/root-first exact public provenance; history/nested cleanup and archiving regressions; live migrations |
| FR-006 / SC-003 | Updated guidance, full source and staged suites, analyzer, packaging and separate native/live limitations |

The pre-edit contract requires 23 private files, three shared loader entries,
eight functions per consumer (16 owner observations), six snapshot commands and
249 shared-worker cases. Public model dependencies are counted separately.
These invariants are retained; only actual added worker cases may change its total.

### Amendment baseline and harness (T035–T037)

The section 2 ten-suite source command completed before source/test edits:
**405 total, 404 passed, 0 failed, 1 skipped**. All 88 loader cases and all
30 shared-import cases passed; each child retained 249 cases (248 passed and
the expected Windows case-sensitive-filesystem skip). The historical six
migration-input failures did not reproduce; they are not current failures.
The initial sandbox attempt failed before test execution because Pester could
not create its temporary registry key; the authorized external rerun produced
the baseline above.

The existing fault harness already accepts arbitrary contained public paths,
Missing/Corrupt/RuntimeError faults and Root/Model consumers. It requires a marked
disposable distribution, checks absolute containment before mutation, bootstraps
standalone model SqlClient using the designated loader, records caller preference
restoration, rejects usable exports after failure, and preserves dependency/error
context. No extension was required before adding the amendment assertions.

### Layout checkpoint (T038–T040)

Focused `Canonical public SQL layout` acceptance initially produced 1 pass and
3 expected failures (two missing public query files and public definitions left
in private support). After relocation: **4 passed, 0 failed**. Canonical files are
`public/Invoke-Fast1GenericSqlQuery.ps1`,
`public/Invoke-Fast1GenericSqlQueryReader.ps1` and
`public/New-Fast1GenericSqlParam.ps1`. Every file has one matching top-level
function with synopsis, description, parameter, input, output and example help;
no public duplicates remain under private/shared. Private query support contains
only Add-GenericSqlParameter and Get-GenericSqlCommand. Query files have no new
class imports; the factory is unchanged. Both extracted help/function blocks
were compared byte-for-byte with the original immediately after writing.
Runtime compatibility remains pending the consumer-loader changes and regressions.

### Consumer loading checkpoint (T041–T044)

The corrected loader red check produced **3 expected failures**: missing literal
model public dependencies and missing model-local query ownership for Direct and
ModelFirst. The first AST attempt lacked SqlClient bootstrap; the test was fixed
to use the existing designated loader before measuring the intended red failures.
After loader edits, the same three checks passed. Root now exports only public
basenames. Model explicitly loads the two public query files immediately after
shared support inside its existing try/finally boundary. Manifest, shared loader,
factory/class imports and six-command metadata snapshot remain unchanged.

Added 12 public-query fault combinations (two files × two consumers × three
faults) to the existing loader suite; their full execution is recorded below.
Exact public source provenance is now required in both ownership fixtures,
retaining distinct Module/SessionState owners and all 16 observations. Four
layout tests increase included worker inventory from 249 to 253; both worker
and outer matrix assertions were updated, retaining strict skip checks.

### Query, cleanup, history and archiving (T045–T047)

`Invoke-Pester -Path ./Fast1data.SqlServer/tests/GenericSqlQuery.Tests.ps1,./Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1,./Fast1data.SqlServer/tests/Migration.Tests.ps1,./Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1 -Output Normal -PassThru`:
**211 passed, 0 failed, 0 skipped** (45 query/layout, 82 cleanup, 56 history/migration,
28 archiving). Existing descriptor, binary/native/null, streaming/schema, partial
failure, truncation, borrowed-connection and ordered cleanup cases passed in both
scopes. Existing delegation and preview checks retain the exact history SELECT,
NVarChar(32) phase, original stored keys/checksums and nested ownership. No extra
behavior gap required new tests. Manifest, factory, shared list, Get-Executed and
the public metadata snapshot were verified unchanged against Git.

### Full source acceptance (T048–T049)

The section 2 ten-suite command after relocation discovered **422 cases**:
**420 passed, 1 failed, 1 expected Windows skip**. All 30 matrix combinations
passed; each child discovered **253 cases, 252 passed, 1 approved filesystem
skip**, with no unexpected skips. Both import forms, all five loading patterns,
all 16 owners, exact selected public provenance and unchanged metadata passed.
All 12 new public-query dependency faults passed for root/model consumers,
including preference restoration and original path/error context.

The sole failure was a legacy substring assertion in ModuleLoaders: it treated
`Invoke-Fast1GenericSqlQuery.ps1` as a direct reference to private
`GenericSqlQuery.ps1`. The assertion now requires the exact filename path
component, retaining the prohibition against loading individual shared files.
This is a test-only correction; no production behavior changed. The full loader
suite is rerun independently below; already passing behavior/matrix suites are
not repeated for this matcher change. No historical migration-input failure
reproduced: Migration.Command passed all 16 cases.

Per-suite source results before that assertion correction: query/layout 45/45,
cleanup 82/82, archiving 28/28, migration/history 56/56, phase 33 passed + 1 skip,
command 16/16, execution 16/16, preflight 14/14, loaders 100/101, import matrix
30/30. All suites except the identified loader assertion passed.

The complete affected loader-suite rerun after the exact-component matcher fix:
**101 passed, 0 failed, 0 skipped**. The original full source run remains recorded
as red above; this targeted rerun resolves its only failure. All other source
suites and all matrix combinations had passed, and no source failure remains
unresolved. The full ten-suite command was not repeated for this test-only change.

### Live SQL availability and guidance (T050–T051)

The configured environment is nonblank, but current SQL access is unavailable.
The two integration suites discovered **42 cases: 0 passed, 42 failed, 0 skipped**;
all failed shared fixture setup. A focused `*emits only the first*` rerun confirmed
SqlConnection.Open fails before database creation with Named Pipes Provider error
40 (server not found or inaccessible; underlying Win32 file-not-found). It reported
0 passed, 1 setup failure and 5 filtered cases. No connection string or credentials
were printed. The suites ran outside the sandbox, so this was not a sandbox-only
connection attempt. No production change is justified by this environment failure.

Real provider and migration acceptance are **unverified for relocation**. Section
3's public smoke cannot run against this unreachable environment and is likewise
unverified. Historical live successes remain history, not current acceptance.
Available offline/staged work continues under the plan's unavailable-SQL rule.

README now names all three canonical public files, root basename discovery and
the model's independent explicit query loading. Its stale three-command loader
reference now says six. Fast1Migration.md was reviewed: its delegation guidance
has no superseded source-location reference, so it requires no edit. Examples,
connection ownership, idempotency, dependencies and versions are unchanged.

### Changed-file analysis (T052)

PSScriptAnalyzer 1.25.0, `-Severity Error,Warning`: **11 files, 0 findings**.
No project settings were found on recheck, and no rule suppression was introduced.
Covered paths under Fast1data.SqlServer/:

- Fast1data.SqlServer.psm1
- private/archiving/ArchivingModel.psm1
- private/shared/GenericSqlQuery.ps1
- public/Invoke-Fast1GenericSqlQuery.ps1
- public/Invoke-Fast1GenericSqlQueryReader.ps1
- tests/GenericSqlQuery.Tests.ps1
- tests/ModuleLoaders.Tests.ps1
- tests/SharedHelpers.Import.Tests.ps1
- tests/fixtures/Invoke-ModuleLoaderScenario.ps1
- tests/fixtures/Invoke-SharedHelperScenario.ps1
- tests/fixtures/SharedHelpers.Scenarios.ps1

Tab-indented multiline control-flow blocks were retained. Git whitespace checking
also passed after trimming surplus trailing blank lines from the extracted files.
Definitions and parsed help were independently compared unchanged against Git.

### Staging (T053)

`./out/publish.ps1 -StageOnly` exited successfully; package-wide analyzer passed.
All three canonical public files, including their help, match source SHA-256.
SqlClient and ScriptDom SHA-256 hashes match source in all three RID bundles.
Packaging behavior, runtime and dependency declarations were unchanged. Staging
is recorded separately from the affected packaged tests that follow; no publishing
was performed.

### Fresh native imports and full help (T054–T055)

Four separate fresh Windows x64 processes verified source and staged distributions,
each through manifest and direct .psm1 imports. Runtime: PowerShell 7.6.10,
.NET 10.0.15, X64 process. Selected roots were
C:\Dev\Fast1data.SqlServer\Fast1data.SqlServer and
C:\Dev\Fast1data.SqlServer\out\Fast1data.SqlServer.
All four imports exposed exactly six commands and zero model exports. Both query
commands retained their defining root/model owners and exact matching public
ScriptBlock.File paths. Normal public factory creation returned BigInt/42.

Get-Help -Full resolved all three commands in every process: two examples and
one documented output each; parameter counts were 5 for scalar/non-query, 4 for
reader and 7 for factory (including WhatIf/Confirm). Source model-first behavior
also passed the full matrix; staged model-first/matrix acceptance is recorded next.

Runtime asset counts match source/staging: win-x64 55/55, linux-x64 53/53,
osx-x64 53/53. These counts and hashes are package evidence, not native Linux/macOS
execution. WSL is not installed, Docker is unavailable, and no macOS host is
available. Native linux-x64 and osx-x64 imports and SQL smoke remain unverified.
Source and staged Windows public SQL smoke are also unverified because the
explicitly configured SQL instance is unreachable, as established by T050.

### Final staged suites (T054)

Section B's six staged affected suites completed: **342 total, 342 passed,
0 failed, 0 skipped**. Per-suite counts: query/layout 45, cleanup 82, archiving 28,
migration/history 56, loaders 101 and shared-import matrix 30. All 30 staged child
workers retained 253 cases, 252 passes and the single approved Windows filesystem
skip, with no unexpected skips. Nested child skips are not outer-suite skips.

Staged manifest/direct/model-first loading, exact staged public provenance,
independent root/model ownership, six fixed exports, unchanged metadata and empty
nested exports passed. The complete packaged query/cleanup/history/archiving
checks passed with the corrected exact-component loader assertion. This is an
independent staged result; StageOnly did not run it.

### Completion and hooks (T056)

T035–T056 are completed, with unavailable checks recorded as required by those
tasks. No unresolved ownership or migration-integrity failure was found in the
available offline checks. Full release acceptance is **not established**: current
SQL suites failed fixture connection setup and native Linux/macOS execution is
unavailable. Historical live success and bundled-file inspection do not fill
those gaps. Required provider/host acceptance must be rerun when available.

Both pre- and post-implementation hook checks found no .specify/extensions.yml;
no extension hooks were registered or dispatched. The requirements checklist
remains unchanged at 16/16 checked.

## Historical implementation and validation record

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
	'./Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1'
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

The fixed export snapshot already contains the six public commands; retain it unchanged for relocation. Add separate source-path/layout assertions. Update hardcoded child-worker totals only if test counts actually change. Ensure the fresh-process worker includes relevant scope tests needed to prove class identity and import-order behavior. Mocks/doubles establish timing and injected errors, not actual SQL Server result metadata.

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

The historical post-implementation hook check found no `.specify/extensions.yml`; no hooks were registered or dispatched. At that checkpoint no checklist directory existed. The later public-file relocation specification now has a requirements checklist; its quality review does not establish relocation acceptance.

### Live SQL follow-up — 2026-11-20

The maintainer supplied `FAST1_TEST_MIGRATION_SQL_CONN_STR` in the process environment and requested migration integration execution and fixes against the current specification. Source checks now reach the selected SQL Server; credentials are not recorded here.

- Initial migration integration run: **32 passed, 3 failed, 0 skipped**. All three resource-trace failures came from the specified Get-Executed delegation: history discovery now uses Get-GenericSqlCommand, so the existing mock also observes its correctly disposed read command before mutation. The trace now distinguishes discovery and mutation commands by connection identity and asserts both disposals in order, preserving the mutation timeout and connection checks. Production cleanup code was unchanged.
- Empty fixture history independently emitted nonterminating ConvertFrom-Json null-input errors. A new regression with ErrorActionPreference Stop reproduced the error before the fix. The fixture now selects its FOR JSON result as a scalar subquery with COALESCE to N'[]', returning an explicit empty array when SQL supplies no JSON value. Existing populated-history checks still cover names, checksums and timestamps.
- The new public-query live suite initially failed setup with `Keyword not supported: 'InitialCatalog'`. Both assignments now use the builder's `['Initial Catalog']` key, matching the migration fixture. All **6 query provider cases passed** afterward, covering real result sets, aliases, native/null/binary values, typed parameters, stored procedures, early termination and connection reuse.
- Source offline regression command: `Invoke-Pester -Path ./Fast1data.SqlServer/tests/GenericSqlQuery.Tests.ps1,./Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1,./Fast1data.SqlServer/tests/Migration.Tests.ps1 -Output Normal`. All **179 cases passed** in the combined regression run; the repaired migration suite also passed all **36 cases** in that run. The six query cases failed setup in that run and were rerun after their fixture correction.
- Final live command: `Invoke-Pester -Path ./Fast1data.SqlServer/tests/GenericSqlQuery.Integration.Tests.ps1,./Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1 -Output Normal -PassThru`: **42 passed, 0 failed, 0 skipped**, 55.07 seconds (6 query and 36 migration cases). No ConvertFrom-Json null-input errors appeared. Migration acceptance includes case-sensitive legacy-key updates, retry, forced/skipped timestamps, preview and cleanup failures.
- Invoke-ScriptAnalyzer on both edited integration test files reported **0 warnings/errors**, with no suppression. Verification used Windows x64 and the existing PowerShell/Pester/SqlClient environment. Pester required execution outside the sandbox to create its temporary registry key.

These follow-up changes affect source integration fixtures and this acceptance record. Staged checks were not repeated for the fixture corrections. The six previously documented baseline migration-input failures were outside this targeted fix and were not rerun; native Linux/macOS execution remains unverified. This follow-up does not establish overall release acceptance.
