# Implementation Plan: Export Generic SQL Commands

**Branch**: `dev` | **Feature identifier**: `007-export-generic-sql-query` | **Date**: 2026-11-20 | **Spec**: [spec.md](spec.md)

**Input**: `specs/007-export-generic-sql-query/spec.md`

Setup returns the feature identifier as `BRANCH`; the actual Git branch is `dev`. Planning selected feature 007 without switching branches. The maintainer subsequently confirmed implementation; see spec.md for the satisfied gate and the 2026-11-20 API revision.

## Summary

Expose the existing scalar/silent non-query command, add `Invoke-Fast1GenericSqlQueryReader` for incremental row output, and add `New-Fast1GenericSqlParam` so callers need no private class import. Keep query implementations in the independently loaded shared behavior file and explicitly export only the requested functions from the root module and manifest. Add the factory under `public/`.

The revised API uses the singular command name Reader while continuing to emit independent row objects. The factory supports standard WhatIf/Confirm with low confirmation impact; WhatIf emits no descriptor. Internal history discovery explicitly disables factory preview/confirmation so outer migration preview remains read-only and can inspect history. No analyzer exception is used.

Reuse one private parameter-binding helper for both query commands, distinguish an omitted SQL type from `BigInt` using a nullable descriptor type, and retain existing execution defaults. The row command owns its reader and command, validates first-result column metadata before reading, emits ordered objects with native values and SQL-null conversion, and leaves the supplied connection open. Refactor `Get-Executed` to delegate row retrieval while retaining its owned connection and exact stored history keys.

## Technical Context

**Language/Version**: PowerShell 7.6+ Core; existing dependency build targets .NET 10. No baseline change.

**Primary Dependencies**: Existing bundled Microsoft.Data.SqlClient 7.1.2, ScriptDom 180.154.0, shared `GenericSqlParam` class, and ordered SQL cleanup helpers. No new package or assembly loader.

**Storage**: Caller-selected SQL Server database; existing `dbo.fast1_migration_history` for migration integration. No schema, history, or configuration migration.

**Testing**: Pester 6+, controlled command/reader doubles, fresh-process import and shared-scope matrices, live SQL Server checks, source/staged module imports, and PSScriptAnalyzer for every modified PowerShell file using project settings when available.

**Target Platform**: Existing x64 Windows, Linux, and macOS bundles (`win-x64`, `linux-x64`, `osx-x64`).

**Project Type**: PowerShell administration module; public function surface grows from three commands to six.

**Performance Goals**: Emit each row before reading the next, with application memory proportional to column metadata plus the current row, independent of total row count. Entire individual values, including binary arrays, may be materialized. No throughput or latency target is claimed.

**Constraints**: Already-open borrowed connection; existing provider-default command timeout; no new timeout, transaction, connection-string, or execution-mode parameters. Output only the first tabular result, including an empty first result. Validate names even when empty. Reader then command cleanup on success, error, and pipeline truncation. Preserve primary errors and previously delivered rows. Never expose a live reader. Follow tab-indented multiline PowerShell blocks.

**Scale/Scope**: Three public commands, one shared binding path, one private history consumer, explicit exports, help/README/migration guidance, and affected query/cleanup/import/migration verification. Existing audit, archiving, migration order/checksums/force/preview, runtime assets, and dependency versions retain their contracts.

## Constitution Check

Constitution 1.1.0: pre-research PASS and post-design PASS. These are design gates; implementation acceptance checks remain pending.

| Gate | Pre-research commitment | Post-design evidence |
|---|---|---|
| I. Data integrity and resumability | Do not alter persisted state or completion tracking | History reads preserve stored keys/checksums exactly; no schema or recording changes. |
| II. Deterministic migrations | Preserve identity normalization, order, checksums, force/ignore, and preview | Only `Get-Executed` retrieval is delegated; phase and command regression suites remain required. |
| III. Explicit database operations | Keep parameters, caller resource ownership, and terminating failures | Shared typed binding, borrowed open connections, no credential-bearing examples/log context; original errors retained with safe cleanup details. SQL remains executable administrator input. |
| IV. Portable PowerShell contracts | Explicit exports, compatible runtime/dependencies, complete help | Root plus manifest expose exactly six commands; nested modules remain private. Source/staged and native-host import validation required. |
| V. Verification and visibility | Cover provider-specific behavior beyond mocks | Offline streaming/cleanup tests plus real result-set, null/type, stored-procedure, and migration-history checks are defined in `quickstart.md`. Unrun checks must be recorded. |
| Runtime and governance | No unsupported dependency/schema/baseline change | Existing bundles/loaders reused. Additive public surface and private nullable field change documented; update current 0.1.0 release notes without inventing a new release approval. |
| Development workflow | Analyze all modified PowerShell; resolve new findings | Implementation includes analyzer runs with project configuration if present. This planning run changes Markdown and feature-selection state only. |

No constitution exception or amendment is required. The spec's pre-implementation confirmation is separate from these design gates.

## Project Structure

### Documentation (this feature)

```text
specs/007-export-generic-sql-query/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
└── contracts/
    ├── public-commands.md
    └── migration-history.md
```

`tasks.md` belongs to the subsequent task-generation workflow and is not created here.

### Source Code (repository root)

```text
Fast1data.SqlServer/
├── Fast1data.SqlServer.psd1                  # Explicit exports and release notes
├── Fast1data.SqlServer.psm1                  # Export loaded shared query functions
├── public/New-Fast1GenericSqlParam.ps1            # New public descriptor factory
├── private/
│   ├── shared/
│   │   ├── Load.ps1                         # Existing shared list retained
│   │   ├── GenericSqlParam.psm1              # Nullable Type; no exported commands
│   │   ├── GenericSqlQuery.ps1               # Query modes, rows, private binder
│   │   └── GenericSqlCleanup.ps1             # Reused cleanup policy
│   └── migration/Get-Executed.ps1            # Delegate rows; own connection
└── tests/
    ├── GenericSqlQuery.Tests.ps1             # Planned focused contract coverage
    ├── GenericSqlQuery.Integration.Tests.ps1 # Planned live provider coverage
    ├── SqlCleanup.Tests.ps1
    ├── Migration*.Tests.ps1
    ├── ModuleLoaders.Tests.ps1
    ├── SharedHelpers.Import.Tests.ps1
    └── fixtures/                            # Export snapshots and scope workers
README.md                                    # Usage/help/validation guidance
Fast1Migration.md                            # History-read behavior
out/publish.ps1                              # Existing StageOnly validation path
```

**Structure Decision**: Keep both query functions in `private/shared/GenericSqlQuery.ps1`, already loaded independently into root and archiving model scopes. Extract parameter validation/binding into one private helper in that file. Root exports the two query functions in addition to commands discovered under `public/`; the manifest enumerates all six. The factory belongs to root `public/` and returns the existing descriptor class. Do not introduce forwarding wrappers, a new nested behavior module, or a second class identity.

## Phase 0: Research Outcome

[research.md](research.md) resolves result-set selection, native-value preservation, nullable type handling, shared export boundaries, cleanup, and validation strategy using repository inspection, delegated read-only research, primary provider documentation, and small PowerShell behavior probes. No technical clarification remains.

The existing fixed export snapshot and shared-helper ownership tests deliberately assert three commands. Implementation must revise them to six while preserving the exact metadata of the original three; recalculate affected child-process expected totals only when test counts change. Keep checking that nested modules export nothing and source/staged functions belong to the selected distribution.

## Phase 1: Design

1. Change only descriptor `Type` to nullable `SqlDbType`; omitted type is null and explicit zero is valid. Factory requires `-Type` and copies `Value`, `Size`, `Precision`, and `Scale` without requiring callers to resolve the private class. Preserve omitted/null value as SQL NULL at binding time.
2. Share command parameter validation/binding across existing query modes and the row command. Retain named keys without an `@` prefix, native values, positive metadata forwarding, and silent helper behavior. The new factory accepts nonnegative Size; zero/omitted metadata retain provider defaults. MAX size and explicit zero-scale control are not added. Use direct value assignment with separate null handling to preserve binary arrays. Existing scalar/non-query execution and timeout behavior remain unchanged.
3. Execute a reader without `CloseConnection`; skip non-tabular results only until a result with columns is found. Validate names once with an ordinal case-insensitive set before `Read()`. Build a fresh ordered object per row by direct ordinal `GetValue()` assignment, replacing only `DBNull` with null. Never collect all rows or advance beyond the first tabular result, even if it has no rows.
4. Wrap owned reader/command in the existing operation-error/finally pattern. Release reader before command and never the borrowed connection. Stream directly through `Get-Executed`, which builds the phase descriptor via the public factory and retains only connection cleanup. A later read failure leaves prior rows delivered; disposal may wait for pending server results and does not promise cancellation of later SQL statements.
5. Update public help, README examples and help listing, migration history guidance, manifest release notes, export snapshot, scope inventories, fresh-process totals where affected, and relevant failure assertions together. Explain SQL aliases, first-result semantics, SQL NULL, streaming/partial output, metadata limits, and connection lifetime.
6. Complete the validation guide during implementation, recording source/staged/native and live SQL outcomes separately. This plan does not execute production tests or establish feature acceptance.

## Complexity Tracking

None. One private binding helper removes duplication between the two query commands; no new framework, dependency, or persistence model is introduced.
