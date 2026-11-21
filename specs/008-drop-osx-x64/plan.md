# Implementation Plan: Drop macOS x64 Support

**Branch**: `dev` | **Feature identifier**: `008-drop-osx-x64` | **Date**: 2026-11-20 | **Spec**: [spec.md](spec.md)

**Input**: `specs/008-drop-osx-x64/spec.md`

Setup returned `008-drop-osx-x64` as `BRANCH` from the selected feature directory. The actual Git branch remains `dev`, as recorded by the specification. No branch switch is needed.

## Summary

Support exactly `win-x64` and `linux-x64`. Remove macOS from the dependency build and staging allowlists, clean only the obsolete source bundle using contained path checks, and preserve the staging script's recreation/filtering behavior. Reject macOS and every other unsupported reported OS/architecture combination before selecting a dependency bundle, including when stale macOS assets exist. Preserve the six public commands, supported-host dependency diagnostics, PowerShell/dependency baselines, and database/configuration contracts.

Deliver module 0.2.0 with consistent manifest tags, release notes, README requirements and macOS upgrade guidance. Reconcile the authorized compatibility change in constitution 2.0.0 during implementation. Validate clean/reused distributions, platform rejection, both root entry points, shared/model imports, and existing command acceptance on native Windows and Linux x64.

## Technical Context

**Language/Version**: PowerShell 7.6+ Core; existing dependency project targets .NET 10 (`net10.0`).

**Primary Dependencies**: Bundled Microsoft.Data.SqlClient 7.1.2 and Microsoft.SqlServer.TransactSql.ScriptDom 180.154.0, with existing native/resource dependencies. No dependency additions or upgrades.

**Storage**: Source/staged runtime bundles on disk; existing selected SQL Server databases, history, audit checkpoints, and archiving state are unaffected. No database upgrade.

**Testing**: Pester 6+, fresh PowerShell processes, isolated disposable distribution copies, real build and `out/publish.ps1 -StageOnly`, existing command/SQL integration suites, and PSScriptAnalyzer on all modified PowerShell files with repository settings if available.

**Target Platform**: x64 Windows and x64 Linux only; both reported OS and process architecture must be X64. macOS, ARM64, x86, other operating systems, and fallback to another bundle are unsupported.

**Project Type**: PowerShell SQL Server administration module with dependency build and release staging scripts.

**Performance Goals**: No new numerical target. Platform validation is local and precedes dependency loading and database work; existing command performance and streaming behavior remain unchanged.

**Constraints**: Keep the resolver parameterless, the existing private inventory and loader ordering, six explicit manifest exports, current command signatures, and provider failure diagnostics. Bound recursive cleanup to validated absolute source/stage paths. Follow tab-indented multiline PowerShell blocks. Do not publish a release during validation. RuntimeInformation reports architecture on a best-effort basis; no new physical-host/emulation detection is introduced.

**Scale/Scope**: Two production RID lists, one existing resolver, one manifest, README, constitution, and focused runtime/package tests plus the existing runtime-asset fixture. No schema, SQL execution, checkpoint, configuration, or command implementation changes.

## Constitution Check

Active constitution: **1.1.0**. Pre-research gate **PASS**: Principle IV explicitly permits an approved compatibility change, and the feature specification records that authorization. Post-design gate **PASS** for planning, with the authorized policy/version reconciliation explicitly included in implementation. Passing these design gates does not mean release verification has run.

| Gate | Pre-research commitment | Post-design evidence / release obligation |
|---|---|---|
| I. Data integrity and resumability | Preserve durable progress and retry behavior | No persisted state or operational algorithms change. Host-transition guidance retains existing state and external access requirements. |
| II. Deterministic migrations | Preserve checksums, order, history, and preview | No migration code/schema edits; existing regression and live acceptance remain required on retained platforms. |
| III. Explicit database operations | Reject unsupported hosts before database operations | Resolver fails before bundle lookup and operational loading; isolated rejection tests assert no downstream/database attempts. Examples use local environment secrets only. |
| IV. Portable PowerShell contracts | Apply the explicit authorization to remove macOS | Exact two-target build/staging/runtime contract; unchanged Core 7.6+ baseline, dependencies, six exports and signatures; current help/metadata/docs reviewed together. |
| V. Verification and visibility | Match packaging/import/command validation to risk | Clean/stale bundle tests, both imports, retained dependency diagnostics, source/staged native Windows/Linux acceptance, explicit unavailable-check reporting. |
| Build/runtime constraints | Bundle required client/parser assemblies per retained RID | Both DLLs and native/resources retained; stale source cleanup and staging allowlist prevent macOS redistribution. |
| Governance and breaking compatibility | Record version decision, policy text, impact, and transition | Module 0.2.0; constitution 2.0.0 with Principle IV text and amendment specified in research. Adopt during implementation before release, retaining original ratification and historical amendments. |
| Development workflow | Analyze every modified PowerShell file | Use project analyzer settings if present; resolve new findings and report unrelated baseline findings. This planning invocation changes Markdown only. |

No constitution exception is requested. Release readiness requires the policy amendment and validation evidence; neither is claimed by this design run.

## Project Structure

### Documentation (this feature)

```text
specs/008-drop-osx-x64/
├── spec.md
├── checklists/requirements.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── runtime-support.md
└── tasks.md                         # Future speckit-tasks output
```

### Source Code (repository root)

```text
build/
├── build.ps1                        # Two targets and obsolete source bundle cleanup
└── SqlClientLoader.csproj            # Existing framework/packages retained
out/
├── publish.ps1                      # Two-target allowlist and exact staged-set check
└── Fast1data.SqlServer/              # Generated staged distribution
Fast1data.SqlServer/
├── Fast1data.SqlServer.psd1           # 0.2.0, platform tags and release notes
├── Fast1data.SqlServer.psm1           # Existing bootstrap/exports retained
├── private/shared/
│   ├── Get-RuntimeIdentifier.ps1      # Existing resolver, no new production helper
│   └── Import-RequiredLibrary.ps1     # Existing loader boundary/diagnostics retained
├── lib/                             # Generated: win-x64/ and linux-x64/ only
├── public/                          # Six existing public command files
└── tests/
    ├── RuntimeSupport.Tests.ps1      # Planned native-fact matrix and rejection imports
    ├── Packaging.Tests.ps1           # Planned isolated build/staging acceptance
    ├── ModuleLoaders.Tests.ps1       # Existing import/dependency/contract coverage
    ├── SharedHelpers.Import.Tests.ps1
    └── fixtures/
        ├── SharedHelpers.Scenarios.ps1 # Replace three-RID expectation only
        ├── SharedHelpers.PublicContract.json # Preserve command snapshot
        └── Invoke-ModuleLoaderScenario.ps1   # Reuse isolated-copy pattern
README.md                            # Current requirements and host transition
.specify/memory/constitution.md       # Authorized compatibility amendment
```

**Structure Decision**: Edit existing build, staging, resolver and metadata boundaries. New tests and test fixtures belong under the current tests directory; do not add a production runtime-policy module, public platform override, or private helper. Keep historical specs/releases unchanged.

## Phase 0: Research Outcome

[research.md](research.md) resolves output cleanup, staging isolation, OS/process architecture checks, unsupported-host test isolation, retained loader contracts, and version/policy choices. The source build leaves removed targets behind today; staging already recreates its output and copies an explicit allowlist. The resolver executes before dependency lookup, so that is the correct rejection boundary. All technical unknowns are resolved.

## Phase 1: Design

1. Restrict the two RID lists. Before publishing dependencies, validate the absolute obsolete `lib/osx-x64` path against the exact source library root and basename, then remove only that directory if present. Preserve required-assembly assertions and per-RID errors, and assert the exact source RID directory set after publishing. Unexpected directories fail validation instead of expanding cleanup. Do not delete build caches or users' installations.
2. Preserve release source validation and contained stage recreation; copy only the two retained bundles. Validate their exact directory set and required DLLs after staging. Missing retained assets fail preflight; an old macOS source/stage directory must never re-enter the package.
3. In the existing resolver, reject unsupported OS first with supported alternatives; for Windows/Linux require X64 OS and process architecture before returning the corresponding RID. Keep resolver errors outside the loader's dependency wrapper. Existing supported-host missing/corrupt/preload diagnostics remain intact.
4. Add meaningful runtime and packaging regressions. Platform fixtures change only native fact reads in marked disposable copies and validate substitutions. Exercise both root entry points with stale macOS bundles absent/present, incompatible architecture cases, and preload cases. Assert rejection before bundle/operational loading with no database attempts. Packaging tests execute scripts against isolated roots with controlled external publishing where appropriate; verify clean/reused output and failure paths, not just list text.
5. Update the shared-helper fixture's bundle expectation to exactly two targets, preserving its command metadata snapshot, ownership checks, and five-by-six import/operation matrix. Run existing source/staged regressions and native Windows/Linux acceptance described in quickstart. Cross-published files are packaging evidence, not native execution evidence.
6. Implement module 0.2.0 metadata and upgrade guidance alongside constitution 2.0.0. Apply the Principle IV sentence and amendment in research; retain ratification and old amendments. Review current help/support claims, and change any discovered current macOS promise. Previous specifications and historical notes remain historical.

Entity and state invariants are in [data-model.md](data-model.md); the externally visible platform/package/import/upgrade contract is in [contracts/runtime-support.md](contracts/runtime-support.md). [quickstart.md](quickstart.md) defines validation commands and evidence requirements. This invocation ends after design and does not generate tasks or implement the feature.

## Complexity Tracking

No constitution violations require justification. No new production abstraction, dependency, persistence model, public parameter, or operating system is introduced.
