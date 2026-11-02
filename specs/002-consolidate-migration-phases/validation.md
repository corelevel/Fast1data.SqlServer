# Implementation validation

Test layout note: the results below predate the suite split. Isolated migration command tests now live in `Migration.Tests.ps1`; live SQL cases and setup now live in `Migration.Integration.Tests.ps1`. Historical combined results have not been rerun against live SQL as part of the rename.

## User-requested T003 revert

The original local `pester_migration` connection has been restored in Migration.Tests.ps1. The file-level ConnectionString parameter and added missing-connection/catalog guards have been removed. Expanded tests, Integration-only SQL setup, nonintegration isolation and fixture-owned cleanup remain. Quickstart and migration guidance now use the test-file connection. Earlier connection-parameter and prerequisite-probe evidence below describes the implementation before this user-requested revert.

Revert verification: the final affected-suite command below was rerun with Integration excluded: 74 passed, 0 failed, 1 Unix case skipped, 7 SQL cases not run. `Invoke-ScriptAnalyzer -Path './Fast1data.SqlServer/tests/Migration.Tests.ps1'` with default rules reports zero findings; no extra parameter-traversal setting is needed for this reverted file. `git diff --check` passes. SQL integration was not run as part of the connection-setup revert.

## Environment and baseline (T001)

- Date: 2026-10-30; revision `6666d6043c6aa3b3d6a249d3cd80d0e50f9ab930`, branch `dev`. Initial worktree contained only the untracked feature specification directory; existing source was clean.
- Windows 10.0.26200, x64; PowerShell Core 7.6.9; Pester 6.2.0; PSScriptAnalyzer 1.25.0; SqlServer 22.4.5.1.
- Source manifest import succeeded. Exact exports: `Invoke-Fast1Archiving`, `Invoke-Fast1Audit`, `Invoke-Fast1Migration`.
- No repository analyzer settings found (`rg --files -g '*[Ss]cript[Aa]nalyzer*' -g '*[Ss]ettings*.psd1'`). Default analyzer rules used.
- Git repository confirmed with `git rev-parse --git-dir`. Existing `.gitignore` covers generated build/runtime assets, temporary files and editor files. No Docker, Node, Terraform or Helm setup detected; no additional ignore file needed.
- No extension configuration exists; no before/after hooks registered.
- No `FAST1_MIGRATION_TEST_CONNECTION` supplied. SQL execution, SQL persistence, case-sensitive database and Linux/macOS checks are pending/unrun, never inferred from mocks or Windows results.

### Baseline commands and results

```powershell
Import-Module ./Fast1data.SqlServer/Fast1data.SqlServer.psd1 -Force
Get-Command -Module Fast1data.SqlServer
Import-Module PSScriptAnalyzer
$baselineFiles = @(
	'Fast1data.SqlServer/tests/Migration.Tests.ps1'
	'Fast1data.SqlServer/public/Invoke-Fast1Migration.ps1'
	'Fast1data.SqlServer/private/migration/Get-Executed.ps1'
	'Fast1data.SqlServer/private/migration/Set-Executed.ps1'
	'Fast1data.SqlServer/private/shared/Get-FileChecksum.ps1'
)
foreach ($baselineFile in $baselineFiles) {
	Invoke-ScriptAnalyzer -Path $baselineFile
}
Import-Module Pester -MinimumVersion 5.0
$config = New-PesterConfiguration
$config.Run.Path = './Fast1data.SqlServer/tests/Migration.Tests.ps1'
$config.Filter.ExcludeTag = 'Integration'
$config.TestRegistry.Enabled = $false
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'
$result = Invoke-Pester -Configuration $config
```

Pester: 4 passed, 0 failed/skipped, 1 integration test not run. TestDrive retained; unused TestRegistry disabled. No framework failure. Analyzer: 0 errors/warnings; four information findings in the public command (trailing whitespace at lines 102/220 and output-type diagnostics at lines 149/157). The new evaluator/phase tests do not yet exist and are not included in the baseline analyzer scope.

## Incremental verification

Implementation evidence follows below. Unavailable checks remain listed separately.

## Final result (T029–T033)

Implementation and documentation tasks are complete; external SQL/platform verification remains unavailable as listed below. No release or database deployment was performed.

| Layer | Passed | Failed | Skipped | Unrun |
| --- | ---: | ---: | ---: | ---: |
| Isolated phase tests | 33 | 0 | 1 | 0 |
| Nonintegration command tests | 41 | 0 | 0 | 0 |
| Tagged real SQL cases | 0 | 0 | 0 | 7 |
| Total discovered Pester cases | 74 | 0 | 1 | 7 |

The skipped phase case requires a Unix case-sensitive filesystem. Windows casing/path-preservation checks passed; the conditional wrong-case file rejection branch cannot be assessed on this case-insensitive filesystem. Linux, macOS, case-sensitive filesystem lookup, PowerShell 7.4 specifically, real SQL persistence/errors/timestamps, and case-sensitive database collation remain unverified. SQL case counts describe fixtures, not passing database assertions. Pester framework/import failures in the final affected run: zero.

### Exact final affected-suite command

```powershell
Import-Module Pester -MinimumVersion 5.0 -Force
$config = New-PesterConfiguration
$config.Run.Path = @(
	'./Fast1data.SqlServer/tests/Migration.Phase.Tests.ps1'
	'./Fast1data.SqlServer/tests/Migration.Tests.ps1'
)
$config.Filter.ExcludeTag = 'Integration'
$config.TestRegistry.Enabled = $false
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Normal'
$result = Invoke-Pester -Configuration $config
$result | Select-Object Result, TotalCount, PassedCount, FailedCount, SkippedCount, NotRunCount
if ($result.Result -ne 'Passed' -or $result.PassedCount -eq 0) {
	throw 'Affected migration suites did not pass.'
}
```

Final output: Passed; total 82, passed 74, failed 0, skipped 1, not run 7. TestDrive remains enabled. The independent phase suite loads no SQL runtime files. Runnable individual-suite and explicitly parameterized SQL commands are in [quickstart.md](quickstart.md).

Final review added one relative-BasePath regression: after Push-Location, .NET's working directory remained at the repository root, causing configuration lookup to fail (0 passed/1 failed, 33 filtered out). Resolving BasePath through PowerShell's provider path before .NET full-path processing fixed it. The final combined run includes that passing regression. This preserves normal relative command usage as well as literal/bracketed absolute paths.

### Static analysis and formatting

```powershell
Import-Module PSScriptAnalyzer
$settings = @{
	Rules = @{
		PSReviewUnusedParameter = @{ CommandsToTraverse = @('BeforeAll') }
	}
}
$files = @(
	'Fast1data.SqlServer/private/migration/Resolve-MigrationPhase.ps1'
	'Fast1data.SqlServer/public/Invoke-Fast1Migration.ps1'
	'Fast1data.SqlServer/private/migration/Get-Executed.ps1'
	'Fast1data.SqlServer/private/migration/Set-Executed.ps1'
	'Fast1data.SqlServer/private/shared/Get-FileChecksum.ps1'
	'Fast1data.SqlServer/tests/Migration.Phase.Tests.ps1'
	'Fast1data.SqlServer/tests/Migration.Tests.ps1'
)
$findings = @(foreach ($file in $files) {
	Invoke-ScriptAnalyzer -Path $file -Settings $settings
})
$findings | Select-Object ScriptName, Line, Severity, RuleName, Message
git diff --check
```

PSScriptAnalyzer 1.25.0: all seven files analyzed, zero errors, warnings, or information findings. No repository settings file exists. Default rules remain enabled; the only configuration expands unused-parameter analysis into Pester's BeforeAll block. No new suppressions/exclusions were added; the existing private writer's ShouldProcess suppression remains unchanged. Baseline informational findings in the rewritten public command are resolved. AST inspection of control-flow statement blocks found zero single-line blocks or space-indented body statements; braces/tab formatting reviewed. `git diff --check` passes.

### Compatibility and governance review

- `Import-Module ./Fast1data.SqlServer/Fast1data.SqlServer.psd1 -Force` and `Test-ModuleManifest ./Fast1data.SqlServer/Fast1data.SqlServer.psd1` succeed. Exact exports remain Invoke-Fast1Archiving, Invoke-Fast1Audit, Invoke-Fast1Migration. Resolve-MigrationPhase is found inside module scope and absent from public commands. No Get-Migration runtime/test references remain (`rg 'Get-Migration' Fast1data.SqlServer` has zero matches).
- Parsed original command source from `git show HEAD:Fast1data.SqlServer/public/Invoke-Fast1Migration.ps1` and final source with PowerShell Parser; parameter lists match exactly: ConnStr, BasePath, Phase, IgnoreScripts, ForceScripts. SupportsShouldProcess/common parameters remain available.
- `git diff --exit-code -- Fast1data.SqlServer/Fast1data.SqlServer.psd1 Fast1data.SqlServer/Fast1data.SqlServer.psm1 Fast1data.SqlServer/schema/migration/tables.sql Fast1data.SqlServer/private/shared/Get-RelativePath.ps1 Fast1data.SqlServer/private/migration/Invoke-Migration.ps1 build` succeeds. Existing schema/types, SqlServer dependency, private recursive loader, PowerShell 7.4 Core baseline and platform declarations are unchanged. No database adapter, transaction, retry mechanism, alias repair, or new dependency was introduced.
- Reviewed spec.md, plan.md and constitution v1.0.0: one authoritative evaluation, buffered preflight, ordered execute/record, parameterized exact-key SQL, truthful partial progress, preview boundaries, and documented recovery align with principles I–V. Help, Fast1Migration.md and quickstart.md cover setup/permissions, administrator inputs, identity/path rules, preview reads, empty work, and idempotent recovery. SQL types remain nvarchar(32), nvarchar(255), char(64), datetime2(7); update time remains database sysutcdatetime().
- Post-execution hook check: `Test-Path -LiteralPath '.specify/extensions.yml'` is false. No hooks to dispatch.

### Requirement and outcome evidence

| Requirement | Evidence and limits |
| --- | --- |
| FR-001 | Private evaluator is the sole phase-rule boundary; isolated tests load only it and two file helpers. Public command consumes the snapshot without duplicating rules. |
| FR-002 | Literal bracketed phase selection, ordered nested scripts, empty arrays, distinct missing inputs, and relative BasePath tests pass. |
| FR-003 | Case/slash matching across all four sources, contained rooted identity conversion, filesystem spelling, normalized decisions and exact history keys pass. Case-sensitive filesystem behavior remains unrun. |
| FR-004 | Normalized duplicate/global known and unknown conflict rejection and distinct ordered unknown-selection warnings pass. |
| FR-005 | Traversal, external rooted files, sibling prefix, directory itself, ignored/forced escapes and missing non-ignored files reject. Contained missing/drifted ignored files skip without hashing. Unix comparison remains unrun. |
| FR-006 | Actual SHA-256 including bracketed files; new/unchanged/forced historical/forced new decisions, drift diagnostics, and once-per-entry hashing assertions pass. |
| FR-007 | Buffered late-invalid phase tests emit no partial results; all 30 public guard cases assert zero execution/writes in normal/WhatIf requests. |
| FR-008 | Six preview cases pass: exact ordered decisions/warnings, matching failure, empty/all-skipped no work, permitted history reads, zero mutations and actual declined confirmation. Real SQL preview remains unrun. |
| FR-009 | Controlled ordered execute/write, insert/update flag, exact original key, checksum/name/phase forwarding and no skip writes pass. Real SQL insert/update/timestamp assertions remain unrun. |
| FR-010 | Controlled execution/recording failures stop later work, preserve earlier history and support truthful retries. Recovery guidance explicitly requires idempotency. Real SQL failure/retry remains unrun. |
| FR-011 | 33 isolated phase cases pass; one Unix-specific case skips explicitly. All rules can be assessed without deployment; supported-host verification remains incomplete. |
| FR-012 | WhatIf and SQL execution/history coverage retained and expanded to seven real database fixtures. SQL availability is reported as unrun, separate from controlled orchestration success. |
| SC-001 | Every executed identity/order/decision acceptance case passes; no extra/reordered work observed. |
| SC-002 | Every executed invalid-phase guard passes with zero mutations, including late invalid entries. |
| SC-003 | Executed identical-input preview/normal cases agree and preview/decline makes zero mutations; real SQL preview remains unrun. |
| SC-004 | Controlled success/failure/retry observations pass; complete SQL durability/collation confirmation is pending. No database correctness claim is inferred from mocks. |
| SC-005 | Independent filesystem assessment passes and real SQL fixtures remain available; passed, failed, skipped, setup failures and unrun checks are distinguished throughout. |

No known material integrity failure remains in executed checks. Operational release validation is incomplete until real SQL, required collation and supported-host checks are supplied; any resulting material integrity failure blocks release. The evaluator is an unlocked snapshot and does not add rollback, concurrency or symbolic-link guarantees.

### US1 (T002–T010)

Phase harness loads only the evaluator, checksum and relative-path helpers. Initial run: 19 phase cases unavailable because the evaluator did not exist; the 4 existing command tests still passed after credential removal. This is an expected missing implementation boundary, not behavioral proof. After metadata/input handling (T007), 4 passed/15 failed: 14 intended behavioral failures plus a test spy recursion failure. Replaced the Get-Content spy implementation with File.ReadAllText to avoid recursively invoking the mocked command. After identity/eligibility implementation, all 19 phase tests passed (0 failed/skipped/unrun) in Pester 6.2, with no framework failures.

Exact phase command: baseline configuration above with `$config.Run.Path = './Fast1data.SqlServer/tests/Migration.Phase.Tests.ps1'` and no tag filter. Real bracketed file SHA-256, zero/one/many decision arrays, literal selection, exact original history keys, rooted names from every source, relative alias spelling, unknown warnings, global conflicts, and one hash per non-ignored file are asserted. T003 restricts schema setup to Integration and requires ConnectionString plus explicit Initial Catalog; SQL remains unrun.

### US2 (T011–T016)

Added late-invalid phase and command cases before implementing containment/coordination. Initial combined run: 32 passed/34 failed/1 skipped; command tests using bracketed directories exposed the old wildcard directory bug before reaching later rules. Changed the guard fixture to a plain phase so the intended late-invalid behavior could be observed: command guards alone then had 16 pass/14 fail (5 other cases filtered out). Failures included first-script execution before parent/sibling/missing/drift rejection and ignored escapes receiving no error. Phase cases independently proved external existing files and ignored escapes were accepted without containment.

After separator-boundary containment and completed-evaluation integration: 64 passed, 0 failed, 1 skipped (Unix case-sensitive sibling test), 1 SQL test not run. The 30 command guards cover 15 invalid classes in normal/WhatIf modes, asserting expected errors and zero execution/writes. Late phase errors emit zero partial results. A null optional-selection issue found by command tests was corrected with collection iteration. `Get-Migration.ps1` and its obsolete reader tests were removed; `rg 'Get-Migration' Fast1data.SqlServer` returns no matches.

Exact combined command: baseline configuration with Run.Path set to both Migration.Phase.Tests.ps1 and Migration.Tests.ps1 and Filter.ExcludeTag='Integration'. TestRegistry disabled, TestDrive enabled; no framework failures.

### US3 (T017–T020)

Preview tests pass against the coordination/presentation flow introduced by T014: 6 passed, 0 failed/skipped, 34 other tests filtered out. Exact command uses the baseline configuration with Run.Path=Migration.Tests.ps1 and Filter.FullName='*Migration preview contract*'. Ordered mixed decisions are new bracketed file, unchanged history skip, ignored skip, forced historical run, forced-new run. Normal and WhatIf warnings and decision messages match exactly; preview reads history once and calls neither mutation helper. Empty/ignored/historical phases report Nothing to run in both modes. Identical checksum failures are compared exactly. A dedicated declining PSHost in an isolated runspace actually answers No at ShouldProcess, proving one confirmation/read and no mutations. No mock phase decisions or mocked ShouldProcess method are used.

A tagged SQL WhatIf fixture snapshots real effect count plus history name/checksum/timestamp JSON before/after forced preview. It remains unrun because no disposable database connection was supplied. Documentation now covers preflight, literal identity, filesystem casing, warnings, exemptions, preview reads, and unlocked-snapshot limits.

### US4 (T021–T028)

Controlled coordination regressions initially produced 2 passes/1 failure for missing original-key forwarding. After reader/writer/command changes and correcting the mock spy to inspect Pester's bound HistoryScriptName variable (mock scriptblocks do not expose invocation values through their own PSBoundParameters), all 3 passed. Ordered traces prove execute/write/next, forced-new insert versus forced-historical update, original-key/name/checksum/phase forwarding, no skip writes, immediate stop on nonterminating boundary errors promoted by ErrorAction Stop, earlier recorded progress, and retry re-executing unrecorded work only.

Exact command: baseline Pester configuration with Run.Path=Migration.Tests.ps1, Filter.FullName='*Migration history coordination*'. Expanded combined suite then passed 73, failed 0, skipped 1 Unix-only case, with 7 Integration cases not run.

Seven real SQL cases are implemented: retained execute/record/skip/force idempotency, forced WhatIf snapshots, ordered multi-script effects/skip timestamps/changed-force/forced-new, legacy original-key updates on any supplied collation, the same legacy update requiring case-sensitive collation, actual later SQL error/retry, and successful SQL followed by missing-row recording failure/retry. Each uses unique fixture-owned phase/table cleanup. Real SQL results, database time/checksum/name persistence, durable SQL effects, and collation remain UNRUN: no explicit disposable database connection supplied. No mock result is SQL persistence evidence.

A safe prerequisite-only probe supplied a test container with ConnectionString='Data Source=unused' and Filter.Tag='Integration': setup rejected missing Initial Catalog before any connection/schema access. Pester reports seven tests blocked by this one expected BeforeAll error (0 executed SQL cases); this is a harness guard probe, not seven failed SQL behaviors. It also caught that assigning container data outside BeforeAll loses it during Pester runtime; the connection assignment was restored inside BeforeAll and the explicit-catalog guard verified. An earlier probe therefore rejected absent connection instead. These intentional setup rejections are separate from the green nonintegration suite.

Analyzer first reported five new warnings in test helpers/parameter traversal. Added genuine ShouldProcess boundaries to fixture writers, changed the plural helper noun to singular, and configured PSReviewUnusedParameter.CommandsToTraverse=['BeforeAll'] so analysis follows the Pester setup scriptblock. This expands analysis without excluding or suppressing any rule. Added the phase-fixture hashtable OutputType to resolve the remaining informational diagnostic. Full final analysis follows below.
