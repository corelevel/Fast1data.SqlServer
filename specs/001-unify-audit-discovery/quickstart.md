# Quickstart Validation: Unify Audit Discovery

This guide covers the implementation described in [plan.md](plan.md). The listing helper and controlled/native/real-process test suites are implemented. Available Windows checks pass; PowerShell Static Analysis remains unverified, and Windows UNC and real Linux SMB verification remain unrun. See the [contract](contracts/discovery.md) for expected behavior and [data-model.md](data-model.md) for records and lifecycle.

## Prerequisites and setup

- x64 PowerShell 7.4 or later and Pester 5 for validation.
- PSScriptAnalyzer for the mandatory static-analysis gate. If unavailable, install it with `Install-Module PSScriptAnalyzer -Scope CurrentUser`, or explicitly record the unavailable check without claiming successful validation.
- Existing module prerequisites: SqlServer module and bundled Microsoft.Data.SqlClient assets for the host runtime. Follow [README.md](../../README.md) for source setup; run `./build/build.ps1` only if those assets need building, with the .NET 8 SDK and package access available.
- Windows for native local/UNC checks; Linux with installed `smbclient`, a reachable dedicated SMB test share, and explicitly supplied test credentials for real remote checks.
- No SQL Server instance or genuine audit contents are required for discovery checks. Filename-only placeholder files are sufficient. Importing their contents is outside this guide.

Run from the repository root in PowerShell 7:

```powershell
Import-Module Pester -MinimumVersion 5.0 -MaximumVersion 5.999 -Force
Import-Module ./Fast1data.SqlServer/Fast1data.SqlServer.psd1 -Force
Get-Command -Module Fast1data.SqlServer
```

Expected: module imports and retains the existing three public commands. `Get-SqlAuditFile` and the listing helper remain private.

The saved Spec Kit selector now references `001`. To select this feature explicitly for follow-up commands without changing saved metadata:

```powershell
$env:SPECIFY_FEATURE_DIRECTORY = Join-Path (Get-Location) 'specs/001-unify-audit-discovery'
$env:SPECIFY_FEATURE_NO_PERSIST = '1'
```

## PowerShell Static Analysis

Constitution Development and Review Workflow items 6–11 require `Invoke-ScriptAnalyzer` for all new or modified `.ps1`, `.psm1`, and `.psd1` files before their tasks are complete. Include staged, unstaged, and untracked feature files. The current scope is the seven scripts below; expand it whenever further PowerShell files change.

Before running, locate the project's PSScriptAnalyzer configuration and set `$auditAnalyzerSettings` to its path when available. No configuration was identified during the artifact review; use analyzer defaults only when no project configuration is available, and record that selection. Run from the repository root:

```powershell
if (-not (Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue)) {
	throw 'PSScriptAnalyzer unavailable. Record this limitation; static-analysis validation remains pending.'
}

$auditAnalyzerSettings = $null # Set to the project configuration path when available.
$auditAnalyzerOptions = @{
	Severity = @('Error', 'Warning')
	ErrorAction = 'Stop'
}
if ($null -ne $auditAnalyzerSettings) {
	if (-not (Test-Path -LiteralPath $auditAnalyzerSettings -PathType Leaf)) {
		throw 'The selected PSScriptAnalyzer configuration does not exist.'
	}
	$auditAnalyzerOptions.Settings = $auditAnalyzerSettings
}

$auditAnalyzerFiles = @(
	'Fast1data.SqlServer/private/audit/Get-SqlAuditFile.ps1'
	'Fast1data.SqlServer/private/audit/Get-SqlAuditFileEntry.ps1'
	'Fast1data.SqlServer/public/Invoke-Fast1Audit.ps1'
	'Fast1data.SqlServer/tests/Audit.Tests.ps1'
	'Fast1data.SqlServer/tests/Audit.Discovery.Fixtures.ps1'
	'Fast1data.SqlServer/tests/Audit.Discovery.Tests.ps1'
	'Fast1data.SqlServer/tests/Audit.Smb.Tests.ps1'
)
$auditAnalyzerFindings = @(
	foreach ($auditAnalyzerFile in $auditAnalyzerFiles) {
		Invoke-ScriptAnalyzer -Path $auditAnalyzerFile @auditAnalyzerOptions
	}
)
$auditAnalyzerFindings |
	Format-Table ScriptName, Line, RuleName, Severity, Message -AutoSize
Get-Module PSScriptAnalyzer | Select-Object Name, Version
```

Classify every error and warning against a documented pre-change revision or preserved baseline, accounting for pre-existing user edits. Findings introduced by new files are new; do not label findings pre-existing merely because the implementation was already present when analysis began. Resolve every newly introduced error and warning, re-run analysis on remediated files, and repeat affected Pester checks if behavior changes. Unrelated existing findings should not block completion but must be reported with the baseline evidence. Do not disable or suppress rules solely to bypass validation; follow the repository's tab indentation and multiline control-flow conventions when editing PowerShell.

Record the date/runtime, PSScriptAnalyzer version, exact command/options, configuration path or defaults, complete file scope, finding counts and details, baseline, remediation, and remaining unrelated findings. An unavailable analyzer or execution failure must be explicitly recorded with its reason and must not be reported as successful validation. Parsing, Pester, and whitespace checks do not satisfy this gate. Keep T031 and affected PowerShell-editing tasks pending until the gate is satisfied; finish T029/T030 afterward.

## Controlled discovery and existing regression coverage

The `Audit.Discovery.Tests.ps1` suite calls discovery and controls `Get-ChildItem`, prerequisite lookup, and `smbclient` output/invocation at their existing boundaries. It does not mock the listing helper. Platform simulation stays in isolated module scope and is restored after each case.

```powershell
$discovery = Invoke-Pester -Path ./Fast1data.SqlServer/tests/Audit.Discovery.Tests.ps1 `
    -Output Detailed -PassThru
if ($discovery.FailedCount -gt 0) { throw 'Discovery validation failed' }

$regression = Invoke-Pester -Path ./Fast1data.SqlServer/tests/Audit.Tests.ps1 `
    -Output Detailed -PassThru
if ($regression.FailedCount -gt 0) { throw 'Audit regression validation failed' }
```

In a sandbox that denies Pester's unused Windows TestRegistry access, use this configuration (TestDrive stays enabled):

```powershell
$config = New-PesterConfiguration
$config.Run.Path = @(
    './Fast1data.SqlServer/tests/Audit.Discovery.Tests.ps1'
    './Fast1data.SqlServer/tests/Audit.Tests.ps1'
    './Fast1data.SqlServer/tests/Audit.Smb.Tests.ps1'
)
$config.Run.PassThru = $true
$config.TestRegistry.Enabled = $false
$config.Output.Verbosity = 'Detailed'
$result = Invoke-Pester -Configuration $config
if ($result.FailedCount -gt 0 -or $result.FailedContainersCount -gt 0) { throw 'Audit validation failed' }
```

Expected coverage:

| Scenario | Expected outcome |
| --- | --- |
| Equivalent Windows file records and realistic SMB file rows | Same accepted basenames and GUID values, correct platform full paths and GUID types. |
| Prefixes with underscores/spaces; mixed-case GUIDs; multiple files per GUID | Every valid file returned individually. |
| Empty prefix, malformed GUID, missing/nonnumeric components, trailing text | Rejected; other valid entries still returned. |
| Directory with valid-looking name; headers, status text, unrelated files | No discovered result for those entries. |
| Empty/rejected-only successful listing | Zero results, no error. |
| Nested directories and trailing root separators | Complete paths with filenames and directory components preserved. |
| Inaccessible Windows directory; partial enumeration then failure | Terminating error, zero discovery results. |
| Missing/empty Linux credentials, bad UNC root, missing executable, unsupported OS | Actionable terminating error. |
| Nonzero process output containing a valid-looking file row | Terminating error, zero discovery results. |
| Both native error preference settings | Same explicit failure behavior; caller preference preserved. |
| Windows credentials supplied | Unused, with no credential environment mutation. |
| Four credential exits, each with prior state absent/present | Exact prior `PASSWD` state restored. |
| Native diagnostics/invocation exception containing a test password | Password absent from all emitted streams and error details. |

The four credential exits are files found, no files found, nonzero listing exit, and invocation exception. Use distinct test-only sentinels for supplied and pre-existing values. The suite must clean up its own platform/environment changes even when an assertion fails.

The existing audit suite retains public export, invalid-folder, and SQL text contract checks. Its local-folder discovery cases run on Windows; affected source paths must use actual lowercase directory names so the remaining checks can run on Linux.

## Native Windows filesystem validation

The discovery suite includes unmocked Windows `TestDrive` fixtures containing the shared valid/malformed filename matrix and an audit-named directory. Run it on Windows with the same command above. For UNC scope, prepare an explicitly selected test folder on a reachable Windows share using that same matrix, then inspect private discovery through the loaded module:

```powershell
$windowsTestFolder = Read-Host 'Dedicated populated Windows UNC test folder'
$windowsFiles = @(& (Get-Module Fast1data.SqlServer) {
    param($folder)
    Get-SqlAuditFile -Folder $folder
} $windowsTestFolder)
$windowsFiles | Select-Object FileName, AuditGuid
```

Compare against the prepared fixture manifest: only valid file entries, exact full paths, and one object per file. Repeat against an empty test folder and a deliberately inaccessible or missing test path. Expect zero results for the former and a terminating error for the latter. Record UNC verification as unrun when no share is supplied; local `TestDrive` evidence does not establish UNC access.

## Real Linux SMB validation

Use dedicated, pre-provisioned share paths; the suite must not mutate arbitrary share contents. Prepare:

1. A populated folder containing the shared valid/malformed filename matrix, spaces/underscores in prefixes, two files for one GUID, an audit-named directory, and a nested directory path containing spaces.
2. An empty folder. A further rejected-only folder can reuse the same test parameter in a second run to prove successful no matches without an empty directory.
3. A known missing or access-denied path on the test share for native failure. A malformed input is not a substitute for a real process failure.

The `Audit.Smb.Tests.ps1` suite accepts the following Pester container data and uses tag `RealSmb`. It calls discovery with the real process, with no enumeration/process mocks. The exact fixture manifest is `Get-AuditDiscoveryFixture` in `Fast1data.SqlServer/tests/Audit.Discovery.Fixtures.ps1`; provision those 3 valid files, 11 rejected files, and the named directory in the dedicated populated folder. This suite only reads the fixtures. Run on Linux:

```powershell
if (-not $IsLinux) { throw 'Real SMB verification requires Linux' }
Get-Command smbclient -ErrorAction Stop
smbclient --version
$PSVersionTable.PSVersion

$populatedFolder = Read-Host 'Populated test UNC folder, e.g. \\host\share\nested folder'
$emptyFolder = Read-Host 'Empty test UNC folder'
$failureFolder = Read-Host 'Known missing or denied test UNC folder'
$testCredential = Get-Credential -Message 'Credentials for the dedicated SMB test share'

$container = New-PesterContainer -Path ./Fast1data.SqlServer/tests/Audit.Smb.Tests.ps1 -Data @{
    PopulatedFolder = $populatedFolder
    EmptyFolder = $emptyFolder
    FailureFolder = $failureFolder
    Credential = $testCredential
}
$remote = Invoke-Pester -Container $container -Tag RealSmb -Output Detailed -PassThru
if ($remote.FailedCount -gt 0) { throw 'Real SMB verification failed' }
```

Expected: the populated listing matches the fixture manifest, empty/rejected-only listing succeeds with zero results, and the failing path produces a terminating nonzero-process error with zero success objects. Run populated/nested paths with trailing separators as well. Each of these process outcomes must check credential restoration for initially absent and pre-existing `PASSWD`, using safe test sentinels and restoring the test runner's original state afterward. Controlled tests separately prove invocation-exception cleanup.

Do not put passwords in scripts, command arguments, fixture files, captured reports, or repository history. A missing platform, executable, path, or credential means the real suite is skipped/unrun with a reason; skipped tests are not proof of process behavior. Even with zero failures, inspect passed/skipped counts and confirm all three required real outcomes actually ran.

## Validation record

Record date, OS/runtime, Pester and smbclient versions, commit/worktree context, fixture categories, passed/failed/skipped counts, and credential restoration observations without secret values. Map outcomes to SC-001 through SC-005 using the [plan's coverage table](plan.md#verification-mapping). Confirm existing caller behavior and independent SQL Server service permissions in the documentation review.

| Check | Implementation validation (2026-10-28) |
| --- | --- |
| Design/constitution consistency | Reviewed against FR-001 through FR-010; no expanded production dependencies. Compliance with Workflow items 6–11 remains pending static-analysis evidence; no exception is proposed. |
| PowerShell Static Analysis | UNVERIFIED: no analyzer execution evidence recorded. Record version, settings, files analyzed, new findings, unrelated existing findings with baseline evidence, remediation, and any execution limitation. |
| Pester controlled and native discovery | 42 passed, 0 failed, 0 skipped. |
| Existing audit regressions plus export contract | 7 passed, 0 failed, 0 skipped. |
| Native Windows local behavior | Passed: shared matrix, literal paths, nonrecursive/file-only enumeration, empty/missing directories, unused credentials. |
| Native Windows UNC behavior | Unrun: no dedicated fixture supplied. Controlled UNC requests pass. |
| Real Linux SMB success/empty/failure and credential observations | 9 skipped: Linux, smbclient, dedicated share and credentials unavailable. No real process outcome established. Rejected-only folder requires a second run using EmptyFolder. |
| Manifest import and exports | Passed with SqlServer 22.4.5.1; exactly the original three public commands, discovery/helper private. |
| Bundled client build / standalone packaged runtime | Unrun: assets absent, no .NET SDK. Import here uses the client already loaded by SqlServer. |
| SQL Server audit import | Unrun and outside this discovery-only validation scope; no database behavior changes. |

Do not mark implementation accepted while required discovery/process evidence remains unavailable. Retain explicit unverified status for missing environments, and block release on unresolved material audit-integrity risks per the constitution.

## Implementation setup (2026-10-28)

Windows 10.0.26200, x64 PowerShell 7.6.6. Local Pester 5.7.1 is used (global Pester is 6.2.0); SqlServer 22.4.5.1 is installed. Manifest import succeeds because SqlServer loads Microsoft.Data.SqlClient 5.0.0.0. Standalone bundled 7.0.2 assets are absent and no .NET SDK is installed; the documented build cannot run here. No packaging change was made. WSL/Linux, smbclient, dedicated Windows UNC/SMB fixtures and credentials are unavailable. Baseline Audit.Tests.ps1: 6 passed, 0 failed, 0 skipped. Pester initially hit sandbox TestRegistry permissions; the baseline passed outside the sandbox. Subsequent runs disable unused TestRegistry via Pester configuration.

The feature selector now points to 001 (changed outside this implementation); implementation leaves it untouched and uses a session-only override. Existing user removal of the BaseFileName assertion is preserved.

### Story checkpoints

- US1 (SC-001/SC-005): initial discovery matrix caught Linux accepting an audit-named directory (4 results instead of 3). After the listing seam: 3 discovery tests passed. Shared manifest contains 3 valid files (2 sharing one GUID), 11 rejected names, and an audit-named directory; SMB rows additionally contain headers, dot directories, status and footer metadata. Native Windows uses a literal bracketed folder, trailing separator, and an additional nested file to establish nonrecursion. Exact paths, GUID values/types and result properties checked through discovery.
- US2 (SC-002/SC-004): regression-first run produced 19 passed/8 failed discovery cases, exposing invalid Linux root acceptance, partial Windows output, inherited native preference, and missing invocation context. After fixes: discovery 27 passed; existing audit regression 6 passed; real SMB 3 skipped (requires Linux). Both caller native-preference settings are observed unchanged; the helper invokes with the preference false. Empty/rejected/metadata success and native Windows empty/missing paths pass. Native immediate/partial and controlled SMB failure/exception emit zero discovery objects. Actual Windows UNC access and Linux process observations remain unrun.
- US3 (SC-003/SC-004): regression-first run produced 31 passed/7 failed, exposing loss of pre-existing PASSWD on all four exits and secret-bearing failure diagnostics. After fixes all eight absent/present lifecycle cases pass, plus present-empty environment restoration on PowerShell 7.6.6. Supplied authentication is observed during the controlled invocation and excluded from arguments. Success, nonzero exit and nested invocation-exception diagnostics are captured across all six streams; error messages, details, targets, categories, IDs and nested exception messages/data contain neither supplied nor prior test secrets. No secret values are recorded here. The real suite defines six outcome/state combinations (populated/empty/failure crossed with absent/present); all remain unrun.

### Final assessment

Worktree: branch `dev`, base commit `053963d`, uncommitted implementation and pre-existing feature artifacts/user test edits. Full affected run: **49 passed, 0 failed, 9 skipped**. PowerShell parsing succeeds for all seven affected scripts; Git whitespace validation passes. Import through the manifest succeeds and both discovery functions resolve only inside module scope. These recorded results do not establish static-analysis compliance: `Invoke-ScriptAnalyzer` execution and findings remain unverified.

| Success criterion | Evidence and remaining limit |
| --- | --- |
| SC-001 | Shared matrix accepts exactly 3/3 valid files, rejects 11 malformed/unrelated names and audit-named directories; equivalent controlled Windows/Linux values and exact paths/types pass. Native Windows local matrix passes. Native UNC/Linux parity remains unverified. |
| SC-002 | All available empty/prerequisite/failure cases pass, including partial Windows enumeration, valid-looking rows on nonzero exits, both caller native preferences, and zero failure results. Real Linux outcomes remain unverified. |
| SC-003 | All eight controlled credential outcomes pass; present-empty state also passes where supported; injected secrets do not escape captured output/error fields. Real Linux credential lifecycle remains unverified. |
| SC-004 | Discovery interface exercised throughout. Separate unmocked RealSmb suite is runnable but all 9 cases skipped; required actual success/empty/failure evidence is pending. |
| SC-005 | Existing request/results and three public exports preserved; audit/SQL text regressions pass. Caller logic is unchanged; SQL Server service permissions are documented independently. |

Review of discovery, listing helper, public caller, importer and operator guide confirms one filename rule/projection, one nonrecursive enumeration/process per request, no caller transport responsibilities, and no SQL/schema/checkpoint/manifest/loader/runtime changes. No generic adapter or production dependency was introduced. Model constraints are retained in helper/discovery comments. Importer and single-process audit-directory guidance remain intact. Test fixtures contain only test sentinels; operational examples contain no passwords.

Implementation changes are present; completion of affected PowerShell-editing tasks, T031, and final review/record tasks T029/T030 remains pending required static-analysis evidence. **Feature acceptance remains pending** static-analysis compliance, native Windows UNC, and actual Linux SMB evidence. Do not release on unresolved audit-integrity risks. Complete the analyzer procedure and supply dedicated fixtures for the native commands above before accepting the feature; controlled results do not establish real SMB process behavior. `.specify/extensions.yml` is absent, so no before/after implementation hooks are registered.
