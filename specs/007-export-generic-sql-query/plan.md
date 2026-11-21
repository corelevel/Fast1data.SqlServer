# Implementation Plan: Export Generic SQL Commands

**Branch**: `dev` | **Feature identifier**: `007-export-generic-sql-query` | **Date**: 2026-11-20 | **Spec**: [spec.md](spec.md)

**Input**: `specs/007-export-generic-sql-query/spec.md`

Setup returns the feature identifier as `BRANCH`; the actual Git branch is `dev`. Planning selects feature 007 without switching branches. This revision plans FR-001 through FR-006 of the public-file relocation amendment. The preceding command implementation and validation remain historical; relocation has not been implemented or tested by this planning run.

## Summary

Move the definitions and comment help for `Invoke-Fast1GenericSqlQuery` and `Invoke-Fast1GenericSqlQueryReader` into `public/Invoke-Fast1GenericSqlQuery.ps1` and `public/Invoke-Fast1GenericSqlQueryReader.ps1`. Keep the factory in its existing matching public file. Every new exported command has one canonical source definition with a filename stem matching its function name.

Retain only `Add-GenericSqlParameter` and `Get-GenericSqlCommand` in `private/shared/GenericSqlQuery.ps1`. Keep the three-file shared loader unchanged. Root's existing public-file loop loads the relocated definitions; export its public basenames without special appended query names. `ArchivingModel.psm1` explicitly dot-sources the two canonical public files after loading private support, defining its own local functions without depending on root import. Preserve the manifest's six explicit exports and nested modules' empty exports.

The revised API uses the singular command name Reader while continuing to emit independent row objects. The factory supports standard WhatIf/Confirm with low confirmation impact; WhatIf emits no descriptor. Internal history discovery explicitly disables factory preview/confirmation so outer migration preview remains read-only and can inspect history. No analyzer exception is used.

Preserve the existing private binder, nullable descriptor type, execution bodies, and history delegation. The row command continues to own its reader and command, validate first-result metadata, emit ordered native values, and leave the borrowed connection open. No additional descriptor or history refactor is part of relocation.

## Technical Context

**Language/Version**: PowerShell 7.6+ Core; existing dependency build targets .NET 10. No baseline change.

**Primary Dependencies**: Existing bundled Microsoft.Data.SqlClient 7.1.2, ScriptDom 180.154.0, shared `GenericSqlParam` class, and ordered SQL cleanup helpers. No new package or assembly loader.

**Storage**: Caller-selected SQL Server database; existing `dbo.fast1_migration_history` for migration integration. No schema, history, or configuration migration.

**Testing**: Pester 6+, controlled command/reader doubles, fresh-process import and shared-scope matrices, live SQL Server checks, source/staged module imports, and PSScriptAnalyzer for every modified PowerShell file using project settings when available.

**Target Platform**: Existing x64 Windows, Linux, and macOS bundles (`win-x64`, `linux-x64`, `osx-x64`).

**Project Type**: PowerShell administration module; public surface remains exactly six commands.

**Performance Goals**: Emit each row before reading the next, with application memory proportional to column metadata plus the current row, independent of total row count. Entire individual values, including binary arrays, may be materialized. No throughput or latency target is claimed.

**Constraints**: Already-open borrowed connection; existing provider-default command timeout; no new timeout, transaction, connection-string, or execution-mode parameters. Output only the first tabular result, including an empty first result. Validate names even when empty. Reader then command cleanup on success, error, and pipeline truncation. Preserve primary errors and previously delivered rows. Never expose a live reader. Follow tab-indented multiline PowerShell blocks.

**Scale/Scope**: Relocate two public definitions/help blocks, preserve the third public file, simplify root exports, and extend the archiving model's explicit dependency loading. Update affected layout/loader/ownership tests and documentation. No new dependency, descriptor type, schema, configuration, SQL behavior, or runtime asset change.

## Constitution Check

Constitution 1.1.0: pre-research PASS and post-design PASS for the relocation amendment. These are design gates; implementation acceptance checks remain pending.

| Gate | Pre-research commitment | Post-design evidence |
|---|---|---|
| I. Data integrity and resumability | Do not alter persisted state or completion tracking | History reads preserve stored keys/checksums exactly; no schema or recording changes. |
| II. Deterministic migrations | Preserve identity normalization, order, checksums, force/ignore, and preview | Existing `Get-Executed` delegation remains intact; verify relocated command resolution with history and migration regression suites. |
| III. Explicit database operations | Keep parameters, caller resource ownership, and terminating failures | Shared typed binding, borrowed open connections, no credential-bearing examples/log context; original errors retained with safe cleanup details. SQL remains executable administrator input. |
| IV. Portable PowerShell contracts | Matching public filenames, explicit exports, compatible runtime/dependencies, complete help | Canonical public files are loaded independently into root/model scopes. Root plus manifest expose exactly six commands; nested modules remain private. Source/staged and native-host validation required. |
| V. Verification and visibility | Cover provider-specific behavior beyond mocks | Offline streaming/cleanup tests plus real result-set, null/type, stored-procedure, and migration-history checks are defined in `quickstart.md`. Unrun checks must be recorded. |
| Runtime and governance | No unsupported dependency/schema/baseline change | Existing bundles, descriptor identity, six-command surface, and current version retained. Source organization changes need no schema upgrade or constitution amendment. |
| Development workflow | Analyze all modified PowerShell; resolve new findings | Implementation includes analyzer runs with project configuration if present. This planning run changes Markdown only; no runtime checks are claimed. |

No constitution exception or unresolved design gate remains. Existing baseline migration-input failures and unavailable native hosts are recorded separately from the amendment's required acceptance.

## Project Structure

### Documentation (this feature)

```text
specs/007-export-generic-sql-query/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── tasks.md                         # Existing completed work; amendment tasks pending
└── contracts/
    ├── public-commands.md
    ├── migration-history.md
    └── command-loading.md
```

The existing `tasks.md` records the preceding implementation and still contains the superseded shared-definition design. `$speckit-tasks` must reconcile it and append pending relocation work; this planning invocation does not rewrite or complete implementation tasks.

### Source Code (repository root)

```text
Fast1data.SqlServer/
├── Fast1data.SqlServer.psd1                  # Existing six explicit exports retained
├── Fast1data.SqlServer.psm1                  # Public discovery and basename exports
├── public/
│   ├── Invoke-Fast1GenericSqlQuery.ps1       # Canonical executor definition and help
│   ├── Invoke-Fast1GenericSqlQueryReader.ps1 # Canonical row definition and help
│   └── New-Fast1GenericSqlParam.ps1          # Existing factory retained
├── private/
│   ├── shared/
│   │   ├── Load.ps1                         # Existing shared list retained
│   │   ├── GenericSqlParam.psm1              # Existing type identity retained
│   │   ├── GenericSqlQuery.ps1               # Private binder and command factory only
│   │   └── GenericSqlCleanup.ps1             # Reused cleanup policy
│   ├── archiving/ArchivingModel.psm1        # Explicitly load both public query files
│   └── migration/Get-Executed.ps1           # Existing delegation and ownership retained
└── tests/
    ├── GenericSqlQuery.Tests.ps1             # Layout plus existing query contracts
    ├── GenericSqlQuery.Integration.Tests.ps1 # Existing real provider coverage
    ├── Archiving.Execution.Tests.ps1        # Model-local query regression
    ├── SqlCleanup.Tests.ps1
    ├── Migration*.Tests.ps1
    ├── ModuleLoaders.Tests.ps1
    ├── SharedHelpers.Import.Tests.ps1
    └── fixtures/                            # Export snapshots and scope workers
README.md                                    # Usage/help/validation guidance
Fast1Migration.md                            # History-read behavior
out/publish.ps1                              # Existing StageOnly validation path
```

**Structure Decision**: Public files own public definitions; private shared files own their support functions. Root discovers all public files once. The archiving model loads only the two public query files explicitly in its existing dependency `try` block, immediately after shared support and before operational helpers/classes. Both scopes independently define functions from the same source files. Keep `GenericSqlQuery.ps1` as the private support filename to avoid an unrelated inventory rename. Do not introduce forwarding wrappers, copied definitions, a nested behavior module, or a second class identity. See [contracts/command-loading.md](contracts/command-loading.md).

## Phase 0: Research Outcome

[research.md](research.md) resolves the relocation's loading boundary and validation impact through two delegated read-only repository investigations. Earlier research decisions for result sets, native values, descriptor types, and cleanup remain applicable; only their source-location decision is replaced. No new provider API or external dependency is introduced, and no technical clarification remains.

The existing export snapshot already asserts six commands and must remain unchanged unless a real mismatch is found. Keep eight independently defined functions per consumer (16 ownership observations), but strengthen query ownership checks to require the exact public source paths. The private inventory remains 23 files and the shared loader remains three entries. Account separately for the model's two explicit public dependencies so private coverage counts do not become 25. Recalculate child-process case totals only after adding cases; never loosen skip or ownership checks.

## Phase 1: Design

1. Move both query function/help blocks intact to matching public files. Leave private support functions in the existing shared file and retain the factory's literal class import. Do not add class imports to the shared behavior or moved query scripts; existing consumer imports provide their descriptor identity.
2. Retain root bootstrap and public discovery ordering. Replace the special appended query export names with `$publicScripts.BaseName`. Preserve the manifest's six names, the factory behavior, and root's existing initialization error handling.
3. Add literal `../../public/Invoke-Fast1GenericSqlQuery.ps1` and `../../public/Invoke-Fast1GenericSqlQueryReader.ps1` dot-sources to the model's existing dependency block after shared loading. Resolve paths from `$PSScriptRoot`. Preserve empty model exports and its error-preference restoration; missing, parse-invalid, and runtime-failing query files must terminate initialization. Root's mandatory model load precedes public discovery, so those failures must also reject root initialization; prove this with both-consumer fault tests. Standalone model checks bootstrap SqlClient with the existing designated loader before model import, preserving its current prerequisites.
4. Add AST layout checks for exact public filenames, matching top-level function/help, and no public definitions in private shared files. Extend designated-loader selection with the two public dependencies while retaining complete 23-file private coverage and the unchanged three-entry shared list. Add both-consumer fault cases and exact public `ScriptBlock.File` assertions. Preserve all six-command metadata snapshots and existing defining-session-state checks.
5. Verify model-first/root-first and all five loading patterns by six operation orders, plus archiving execution, query, cleanup, migration, and live provider regressions. Run analyzer on all changed PowerShell and stage with the existing `StageOnly` path; repeat affected staged suites and supported host imports. Record source/staged/live/native results separately.
6. Update README loader/source-location guidance and any affected references, retaining user examples and contracts. Regenerate amendment tasks through `$speckit-tasks` before implementation. This plan completes design only and does not claim test or relocation acceptance.

## Complexity Tracking

No constitution violations require justification. The same two public files are dot-sourced into two existing scopes; no new framework, dependency, duplicate implementation, or persistence model is introduced.
