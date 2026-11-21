# Implementation validation: Drop macOS x64 support

Execution: 2026-11-20–2026-11-21. Branch: `dev`. No release publication is authorized or performed.

## Native Linux follow-up on 2026-11-21

**25 of 26 tasks complete.** Native Linux SQL acceptance (T023) passed from both distributions. T021 remains open on the shared-helper matrix. Release readiness remains false.

Tested commit `6d237f8` on Ubuntu 26.04.1 LTS, x64 OS and process, with PowerShell 7.7.0, Pester 6.2.0 and PSScriptAnalyzer 1.25.0. The run used an isolated archive of the clean commit and the checkout’s existing linux-x64 and win-x64 bundles. Running `pwsh -NoProfile -File out/publish.ps1 -StageOnly` produced a fresh staged package and passed its analyzer. Both distributions contained the same 108 files under lib, with matching source/stage SHA-256 hashes. This run reused locally built assets. Eight hashes differed from the earlier Windows build inventory (the three SqlClientLoader outputs and System.Security.Cryptography.Pkcs.dll in each RID).

| Native Linux check | Source | Fresh stage |
|---|---|---|
| Manifest, Direct, ModelFirst in fresh processes | 3/3 passed | 3/3 passed |
| Packaging and simulated runtime | 110 passed | 94 passed, 16 source-only packaging cases skipped |
| Module loaders | 101 passed | 101 passed |
| Remaining 11 offline suites | 316 passed, 7 Windows-only skips | 316 passed, 7 Windows-only skips |
| Shared-helper matrix | 30 of 30 tuples failed | 30 of 30 tuples failed |
| Live SQL and SMB | 75 passed, zero skipped | 75 passed, zero skipped |

Used the fresh-worker and Pester suite selections in quickstart sections 4–5, plus the focused Packaging and RuntimeSupport suites. Each worker loaded SqlClient and ScriptDom from its own linux-x64 bundle and reported six exports. All 21 Linux audit unit cases and all 34 migration-phase cases ran successfully in each distribution, including the case-sensitive path check.

All 30 matrix tuples in each distribution reported the same first difference in the frozen public metadata snapshot. An independent field-by-field comparison of the source contract found exactly 54 differing values. PowerShell supplied assembly version `7.7.0.500` for 30 ValidateVariableName and 24 ArgumentTypeConverterAttribute values where the snapshot records `7.6.0.500`. The snapshot assertion failed as written. No assertion or snapshot was modified for this run.

The sandboxed SQL connectivity probe failed. With network access to the configured fixtures, source and stage ran sequentially and each passed 36 migration, 6 public query, 29 archiving and 4 Linux audit integration cases. Per-suite counts are in the `NativeLinux` section of [validation-results.json](validation-results.json). The Windows-era entries below describe the earlier execution.

## Prerequisites (T001)

- Native Windows `Microsoft Windows 10.0.26300`; reported OS and process architecture: X64/X64.
- PowerShell 7.6.10 Core; .NET SDK 11.0.100 (supports the existing `net10.0` project).
- Pester 6.2.0; PSScriptAnalyzer 1.25.0. No repository analyzer settings found.
- Existing source bundles: linux-x64, osx-x64, win-x64.
- Explicit migration/query, archiving and audit SQL test settings and audit folder are configured. Values are intentionally not recorded. All configured Windows SQL/audit acceptance scenarios subsequently passed.
- No configured native Linux or macOS host. WSL reports it is not installed. Native Linux acceptance remains required and unrun; native macOS rejection is supplemental and unrun.
- Git ignore rules cover generated dependency bundles, build bin/obj and stage, plus universal temporary files. No other technology-specific ignore files are needed. `.vscode/` remains tracked.

## Preserved baseline (T002)

Inspected manifest, root module, public contract snapshot, ModuleLoaders suite, dependency project and shared-helper fixture.

- Six explicit exports: Invoke-Fast1Audit, Invoke-Fast1Migration, Invoke-Fast1Archiving, Invoke-Fast1GenericSqlQuery, Invoke-Fast1GenericSqlQueryReader, New-Fast1GenericSqlParam.
- Public snapshot SHA-256: `107952ED7D1DA2E57ACA511D04BB96E1C2C50366D59711671C4D38C9B81163B3`; keep unchanged.
- Private inventory: 23 files; parameterless runtime resolver; no production helper additions planned.
- Root order: inert GenericSqlParam declaration, resolver, SqlClient bootstrap, ScriptDom bootstrap, shared behavior, audit/migration, archiving declarations/adapter, public commands.
- Model-first workers explicitly bootstrap SqlClient before model import; preserve model/behavior ownership.
- Baseline: module 0.1.0; PowerShell 7.6 Core; net10.0; SqlClient 7.1.2; ScriptDom 180.154.0. No dependency changes planned.

Baseline loader/shared-helper suites: 131/131 passed; see recorded baseline below.

## Acceptance ledger

| Check | Status |
|---|---|
| Controlled packaging regressions and pre-change failures | PASS: failures established, 16/16 green |
| Simulated native-fact selector/rejection matrix | PASS: 94/94, source and stage |
| Supported-host loader diagnostics | PASS: 101/101 source and 101/101 stage |
| Real clean/reused build and stage with hashes | PASS: 108 matching files per pair |
| Native Windows source/stage offline acceptance | PASS: focused, 101 loaders, 301 offline passes and all 30 matrix tuples each |
| Native Linux source/stage offline acceptance | Unrun: host unavailable |
| Native Windows source/stage SQL acceptance | PASS: 75/75 each; source audit retried outside sandbox |
| Native Linux source/stage SQL acceptance | Unrun: host unavailable |
| Native macOS rejection | Unrun: no native host; simulated macOS cases pass |
| Changed-file and staged package analyzer | PASS: no introduced findings; 11 baseline Write-Host warnings |
| Metadata, policy and current help consistency | PASS: module 0.2.0, constitution 2.0.0, two targets |

Evidence will distinguish controlled external publishing, simulated native facts, real builds and native execution. Missing prerequisites and skipped tests do not count as passes.

## Focused regressions and implementation progress

- T003/T004: controlled packaging worker executes actual copied build/staging scripts in fresh processes. Pre-change final suite: 15 total, 6 passed, 9 failed, 0 skipped (`.tmp/008-packaging-red-final.json`). Failures establish three publishes, macOS source prerequisite/redistribution and absent exact-set checks. Initial fixture errors were corrected before this baseline; they are not feature evidence.
- T005/T006: two-target allowlists, exact source/stage checks, bounded obsolete cleanup. Packaging green: 16 total, 16 passed, 0 failed/skipped (`.tmp/008-packaging-green.json`); includes the added obsolete-cleanup containment case. Controlled analyzer interception is fixture-only; real analysis remains required.
- T009–T011: pre-change combined run: 109 total, 8 passed, 101 failed, 0 skipped (`.tmp/008-focused-red.json`). Runtime portion: 94 total, 2 passed, 92 failed; only the two valid X64/X64 selectors passed. Failures establish macOS acceptance, missing process checks/alternative guidance and downstream access under unsupported facts. All fact substitutions are confined to marked distribution copies.
- User confirmed no native Linux test host is available. T021/T023 remain open.
- T015–T018: module 0.2.0, Windows/Linux tags, immediate-removal release notes and host transition; constitution 2.0.0 adopted on 2026-11-20 with ratification and Amendment 1.1.0 retained. Reviewed Fast1Audit.md, Fast1Migration.md, Fast1Archiving.md and all six public .ps1 files for conflicting support promises; none found, no changes required there.

Baseline T002 completed: 131 total, 131 passed, 0 failed/skipped. Loader suite 101 plus all 30 shared-helper tuples; each tuple retains its 253-test inventory. Initial sandbox-only run failed because Pester could not create its temporary registry key; the authorized rerun outside the sandbox passed. Build/stage scripts and documentation were edited while this import-only baseline ran; the resolver and runtime-asset assertion were retained until the baseline finished.

Runtime implementation: the parameterless selector rejects unsupported OS before architecture checks; both reported architectures must be X64; all rejection messages identify both retained targets. No loader/bootstrap ordering or public parameter changes. Preliminary T014 runtime green: 94 total, 94 passed, 0 failed/skipped (`.tmp/008-runtime-green.json`), all substituted-fact simulation. The 34 root-import cases cover both entry points, macOS X64/ARM64 with stale valid assets/cold or compatible preloads, unknown OS and retained-OS architecture failures. All rejection probes remain zero (bundle lookup, assembly reuse/loading, operational loading and database attempts). The 60 selector cases include every non-X64 Architecture enum value exposed by this .NET runtime.

Changed-file analyzer: all 11 changed/new PowerShell paths analyzed with PSScriptAnalyzer 1.25.0, default settings (none provided by repository). Eleven existing PSAvoidUsingWriteHost findings in out/publish.ps1, reproduced on HEAD's original script; no introduced warnings/errors. No rules suppressed. Real staged package analyzer validation is separate and already passed for clean/reused staging.

## Real packaging (T019)

Disposable checkout: `C:\Dev\Fast1data.SqlServer\.tmp\008-real-28131dd3a32c43be8e8f611f980ecdb0`.
Source distribution: `<checkout>/Fast1data.SqlServer`; staged distribution: `<checkout>/out/Fast1data.SqlServer`.
Inputs were copied from the implemented working tree; no developer bundles, build caches, installed modules or historical releases were deleted/rebuilt.

Executed `pwsh -NoProfile -File <checkout>/build/build.ps1` and `pwsh -NoProfile -File <checkout>/out/publish.ps1 -StageOnly` for clean, reused and final-restoration builds/stages (all exit 0). Between runs, seeded obsolete source/stage directories with markers and valid managed DLLs. Reused builds removed source macOS assets; standalone `-StageOnly` excluded stale source/stage macOS assets while leaving source fixtures intact. Rebuilt and staged once more before final native tests.

Each build publishes exactly win-x64 and linux-x64. Clean, reused and final source/stage pairs each have exactly those two directories, both required DLLs, and 108 bundle files with matching relative paths, lengths and SHA-256 hashes. [Full final bundle inventory](validation-assets.json) SHA-256: `418A719EFB83927542114B6CAD601696A857D8BEEE05BC34ED47E0B482F5B6BD`. This includes Windows SNI native assets and both libraries' culture resources. The cross-published Linux assets establish packaging only.

Actual commands/results and separate clean/reused/final hash lists remain in `.tmp/008-evidence/real-packaging.json`, `*-assets.json` and step logs. Four real stage passes imported the module and passed package-wide analyzer validation. A fifth real StageOnly after the test-only preload correction also passed; all 108 bundle hashes remained equal. StageOnly did not run Pester or publish to a gallery.

Build limitation: cached NuGet restore/publish succeeded with NU1900 warnings because vulnerability metadata at api.nuget.org was unavailable in this environment. No package versions were changed; this is not a successful online vulnerability-data check.

Native macOS (T024): no native host is configured; cold .psd1/.psm1 rejection on a real Mac is unrun. The 16 simulated macOS import cases in T014 (both entries, X64/ARM64, stale absent/present, cold/preload) passed with zero downstream probes. Native Linux offline and SQL acceptance remain explicitly unrun after the user's confirmation; cross-publishing/simulation do not satisfy T021/T023.

## Windows SQL acceptance (T022)

Both distributions completed all 75 live scenarios: migration 36, public query 6, archiving 29, Windows audit 4. Source's first sandbox run passed the 71 SQL-only scenarios; its four audit cases could not start because sandbox access to the explicitly configured audit share was denied. Retried only audit outside the sandbox: 4/4 passed. Staged distribution then passed 75/75 outside the sandbox, sequentially on the same explicitly selected resources. No scenarios skipped. Evidence: `.tmp/008-evidence/windows-source-sql.json`, `windows-source-audit.json`, `windows-stage-sql.json` and separate logs. Initial sandbox failures are environmental and retained in the evidence; no SQL/configuration/public behavior changed.

US1 (T008): isolated current-source copy `.tmp/008-us1-b39ddbe7d1ad4abcb738f2c4c3dcadcf/Fast1data.SqlServer` with only the two retained pre-existing bundles passed all 101 loader tests, the three fresh Manifest/Direct/ModelFirst workers and all 30 shared-helper tuples. Packaging 16/16 passed separately. Matrix duration 767 seconds. Frozen public metadata/ownership and the existing 253-test inventory per tuple remain intact. This copy intentionally retained the pre-US2 resolver to validate the packaging increment on native Windows; integrated post-US2 evidence uses the real-build checkout above.

T013 strengthened cause assertions exposed a pre-existing token-fixture issue: Reflection.Emit recomputes PublicKeyToken from the original public key, so SetPublicKeyToken alone did not create an incompatible identity and the synthetic assembly failed later for missing types. The test-only worker now uses a different valid public key and verifies emitted identity, producing the intended incompatible-preload failure. Production loader behavior is unchanged. Initial integrated loader runs each passed 100/101 with only this new assertion failing; corrected worker smoke case passes. Final source/staged loader reruns each passed 101/101; the fifth real stage/import/analyzer pass also succeeded after this fixture correction.

## Integrated native Windows acceptance (T020)

Final real-build source and staged distributions each passed three fresh workers (Manifest, Direct, ModelFirst) with six commands and correct library provenance. Source focused suites: 110/110 passed (16 packaging, 94 simulated runtime); stage focused suites: 94 passed, 16 source-only packaging cases explicitly skipped. Both distributions passed the remaining 11 offline suites: 323 total, 301 passed, 22 skipped (21 Linux audit cases and one existing case-sensitive filesystem case), zero failures. These skips do not establish Linux acceptance.

Corrected loader suites passed 101/101 each from source and stage, including all ten missing/corrupt/type/preload fault cases. Final five-by-six shared-helper matrices each passed all 30 tuples with zero failures or unexpected skips. The earlier interrupted partial runs are not counted as completed acceptance. Each completed matrix must retain 253 tests per tuple; Windows has one existing case-sensitive skip per tuple, for 7,560 passed / 30 expected skipped / zero failures or unexpected skips across 7,590 nested tests.

## Requirements and release gates (T026)

| Requirement | Evidence / status |
|---|---|
| FR-001 | Build/stage allowlists and exact directory assertions; two matching accepted selector cases and all unsupported-fact rejections. Implemented. |
| FR-002 / SC-001 | Controlled packaging failures and 16 green cases; real clean/reused/standalone outputs, required DLLs and 108-file source/stage hash inventories. PASS. |
| FR-003 / SC-003 | Both root entries; 16 macOS stale/cold/preload cases and other unsupported imports; zero lookup/reuse/load/operational/database probes. Simulated acceptance PASS; native macOS supplemental check unavailable. |
| FR-004 | 60 selector cases cover both accepted targets, unknown/macOS and all exposed non-X64 architecture values; OS rejection precedes architecture. PASS (simulated facts). |
| FR-005 / SC-002 | Windows fresh imports, loader faults, frozen metadata/ownership, offline/live SQL and shared-helper checks. Required native Linux source/stage acceptance remains open (T021/T023). |
| FR-006 / SC-004 | Manifest 0.2.0, Windows/Linux tags, immediate-removal notes, README upgrade requirements and reviewed current help/guides agree. PASS. |
| FR-007 | Authorized Principle IV amendment, constitution 2.0.0, module 0.2.0 decision; original ratification and Amendment 1.1.0 retained. PASS. |
| FR-008 | No database/schema/state/configuration/command implementation changes. Retained-host transition guidance preserves state/paths/access; Windows SQL acceptance 75/75 per distribution. Native Linux command acceptance remains open. |

At the end of Windows validation, no release readiness was certified: T021 (native Linux source/stage/offline/import acceptance) and T023 (native Linux source/stage SQL acceptance) require a host the user confirmed is unavailable. They remain unchecked. Native macOS rejection is supplemental and explicitly unrun. StageOnly and substituted native facts do not satisfy these native Linux gates.

Final diff scope is build/stage/runtime selection, metadata/guidance/policy, tests and execution evidence. The dependency project, public implementations/signatures, root/bootstrap ordering, 23-file private inventory, SQL schemas, frozen public snapshot, historical specifications/releases and .vscode tracking are preserved. The existing 0.1.0 release-note text is retained verbatim. Current work remains on dev; nothing was committed or published.

Final loader evidence: `.tmp/008-evidence/windows-source-loaders-final.json` and `windows-stage-loaders-final.json` each report 101 total/passed, zero failed/skipped after the fixture correction. Selected RID, DLL/path, rebuild/fresh-process guidance and distinct underlying causes are preserved. T014's source/stage 94-case simulations remain valid: runtime source and tests are unchanged since those passing runs. Private inventory remains 23 and the public snapshot hash is unchanged.

Analyzer command: `Invoke-ScriptAnalyzer -Path <each of 11 changed/new PowerShell paths> -Severity Warning,Error`, with default settings because no repository settings exist. Exact paths and findings are captured in `.tmp/008-analyzer-final.json` and the final validation-results artifact. Five real `out/publish.ps1 -StageOnly` passes validated package imports and recursive package-wide analyzer checks, including the corrected test worker on the last pass.

## Windows completion record

Native Windows source and stage each passed all 30 final shared-helper tuples. Source duration 836.56 seconds; stage duration 858.79 seconds. Each matrix contains 7,590 nested tests: 7,560 passed, 30 existing case-sensitive-filesystem skips, zero failures and zero unexpected skips. Frozen six-command metadata and defining-module ownership pass across all five loading patterns and six operation orders.

[Structured execution results](validation-results.json) preserve separate source/stage results, all matrix tuples, fresh-worker provenance, analyzer findings, build events, expected skips and environmental limitations. [Bundle inventory](validation-assets.json) retains all 108 file hashes. Local logs remain in `.tmp/008-evidence/`. Partial interrupted runs and the resolved test-fixture/sandbox failures are distinguished from final acceptance.

Completed 24 of 26 tasks. T021 and T023 remain unchecked because native Linux source/stage and SQL acceptance could not run; the user confirmed no Linux host is available. Implementation and available Windows/package/simulation validation are complete, with release readiness explicitly false. No schema/configuration/state/public contract changes and no release publication.

Extension hooks: `.specify/extensions.yml` was absent at pre-execution and final post-execution checks; no hooks were registered or dispatched. Checklists were read-only (requirements.md 16/16 checked). Final diff/metadata review preserves the dependency project, root/model bootstrap ordering, private inventory and original public snapshot. No unrelated files were changed.
