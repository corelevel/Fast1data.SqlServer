# Implementation Plan: Remove the SqlServer Module Dependency

**Branch**: `dev` | **Feature identifier**: `006-remove-sqlserver-dependency` | **Date**: 2026-11-19 | **Spec**: [spec.md](spec.md)

**Input**: `specs/006-remove-sqlserver-dependency/spec.md`

Setup returned `006-remove-sqlserver-dependency` as `BRANCH`; Git reports `dev`. Planning does not create or switch branches.

## Summary

Replace `Invoke-Sqlcmd` with whole-script validation using `TSql160Parser` and ordered execution of original batch text. Under the latest FR-016 addition, `Invoke-Migration -ConnStr -Script` opens its own connection and creates its own command; `Set-Executed -SqlCmd` retains borrowed history resources. Keep the public interface, phase evaluation, checksums, confirmation, and history schema. This refresh changes requirements/design only; production implementation remains separate.

The public command opens history resources only after evaluation and confirmation and forwards its original connection string to the executor. Each validated executable file uses an executor-owned connection and command under ambient suppression, with timeout `0`, final transaction validation, and disposal of command then connection then suppression scope before history. History keeps its own unchanged command/timeout/transaction. The earlier clone/rebinding/restoration mechanism is superseded. Dependency delivery uses the existing build, explicit root bootstrap, and generic `Import-RequiredLibrary` from FR-014; the SqlServer PowerShell prerequisite remains removed.

## Technical Context

**Language/Version**: PowerShell 7.6+ Core; dependency build targets `net10.0`. Earlier host/runtime observations are recorded in `validation.md`; this refresh does not repeat runtime acceptance.

**Primary Dependencies**: User-edited project references Microsoft.Data.SqlClient 7.1.2, Microsoft.SqlServer.TransactSql.ScriptDom 180.154.0, System.Security.Cryptography.Pkcs 11.0.0. Preserve these edits; validate the complete dependency graph during implementation. Explicit parser: `TSql160Parser`, regardless of newer package parser types. Remove the SqlServer PowerShell prerequisite.

**Storage**: Existing SQL Server `dbo.fast1_migration_history` and filesystem scripts/configuration. No schema or configuration migration.

**Testing**: Pester 6+, fresh-process source/package imports, native runtime smoke tests, explicitly selected SQL Server integration target, and PSScriptAnalyzer. Previously observed tool versions are recorded in `validation.md`. No repository analyzer settings were found in the prior review; use project settings if present during implementation.

**Target Platform**: Existing x64 Windows, Linux, macOS: `win-x64`, `linux-x64`, `osx-x64`. Preserve audit's separate Windows/Linux discovery restriction.

**Project Type**: PowerShell administration module with three public commands.

**Performance Goals**: No performance claim. Read and parse a complete script once per attempt; execute each nonempty batch once, perform one read-only final transaction-count check per executable file, and write history once per successful script. Zero-batch files open no execution connection.

**Constraints**: Executor takes original `ConnStr`, owns its per-file connection/command, uses script timeout `0`, and suppresses ambient transactions on its owned path. History borrows its original command/connection/settings/transaction. No executor borrowing/cloning/restoration, public interface change, or implicit phase transaction. Invalid/zero-batch/preview work opens no execution resources. Final transaction and cleanup failures prevent history/later work. Preserve source spans, primary errors, secret-free context, and tab-indented multiline PowerShell formatting.

**Scale/Scope**: Two private helper signatures, executor-owned per-file connections with authentication/session isolation, public history-resource ownership, one parameterized assembly bootstrap replacing the separate SqlClient/ScriptDom loaders, manifest/dependency delivery, migration and loader tests, and affected guides/help. `Get-Executed` keeps its read-only connection-string contract. Audit/archiving behavior and public parameter sets remain unchanged.

## Constitution Check

Pre-research: PASS for documentation-only design. Post-design adoption gate resolved on
2026-11-19: maintainer explicitly approved the exact amendment below, constitution
1.1.0, and module 0.1.0. The constitution amendment is applied. Implementation validation
remains separate; see [validation.md](validation.md) for actual results and limitations.

| Gate | Pre-research commitment | Post-design evidence required |
|---|---|---|
| I. Durable completion | Record only completed scripts; preserve retries | History follows all batches, final transaction validation, and successful owned command/connection/scope cleanup. All operation failures stop later work. |
| II. Deterministic migrations | Preserve phase evaluation, identity, order, SHA-256, force/ignore, preview | Retain phase regressions. Parse each script before its first batch. Clear stale command parameters. |
| III. Explicit operations | Parameterize history; preserve primary errors | Public owner owns history resources; executor owns its command/connection/scope, initializes from original ConnStr, and uses ordered cleanup without borrowing history resources. |
| IV. Portable contracts | Preserve runtimes/public API; deliver the parser | Both assemblies per RID, explicit root bootstrap, source/staged and native host checks. |
| V. Verification | Require success, failure, retry and SQL evidence | Follow `quickstart.md`; unrun checks remain unverified and material integrity risks block release. |
| Runtime stack/governance | Use the approved stack and release decision | PASS: constitution 1.1.0 is applied and module 0.1.0 is approved; the existing approval is recorded in `validation.md`. |
| Development workflow | Analyze every changed PowerShell file | Use project settings if present, resolve new findings without suppression, report unavailable checks. Planning changes only Markdown. |

### Adopted amendment and release decision

The first Database and Runtime Constraints bullet now reads:

> PowerShell orchestration, Microsoft.Data.SqlClient, Microsoft.SqlServer.TransactSql.ScriptDom, and versioned SQL setup scripts form the supported implementation stack. Required client and parser assemblies MUST be bundled for each supported runtime and initialized through designated loaders; a separate SqlServer PowerShell module installation is not required.

Rationale: the requested parser/direct execution replace migration's only `Invoke-Sqlcmd` use. Affected contracts: installation, script syntax, private signatures, and loader/build validation. Transition: rebuild all RID bundles, update manifest/help/guides, reject unsupported SQLCMD before execution, and retain idempotent retry guidance. Existing history needs no upgrade.

Approved constitution `1.1.0` for the materially changed stack and added delivery guidance;
original ratification text retained, Last Amended 2026-11-19. Approved module release:
`0.1.0` from `0.0.5`, with SQLCMD authoring incompatibilities and private helper changes
called out. Approval is recorded in [validation.md](validation.md).

## Project Structure

### Documentation (this feature)

```text
specs/006-remove-sqlserver-dependency/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── contracts/migration-execution.md
├── contracts/required-library.md
├── contracts/script-session.md
├── quickstart.md
├── validation.md
├── tasks.md
└── checklists/requirements.md
```

The existing `tasks.md` and `validation.md` retain implementation status and historical evidence. This planning refresh does not regenerate tasks or change their completion markers.

### Source Code (repository root)

```text
.specify/memory/constitution.md                 # Applied stack amendment
build/{SqlClientLoader.csproj,build.ps1}        # Preserve edits; validate assets
out/publish.ps1                               # Source and staged asset checks
Fast1data.SqlServer/
├── Fast1data.SqlServer.{psd1,psm1}             # Prerequisite removal/bootstrap
├── public/Invoke-Fast1Migration.ps1            # Resource owner
├── private/
│   ├── shared/
│   │   ├── Import-RequiredLibrary.ps1         # FR-014: replaces both specific loaders
│   │   └── GenericSqlCleanup.ps1              # Existing cleanup reused
│   └── migration/
│       ├── Invoke-Migration.ps1
│       ├── Set-Executed.ps1
│       ├── Get-Executed.ps1
│       └── Resolve-MigrationPhase.ps1
├── lib/{win-x64,linux-x64,osx-x64}/
└── tests/
    ├── Migration{,.Phase,.Command,.Execution,.Preflight,.Integration}.Tests.ps1
    ├── ModuleLoaders.Tests.ps1
    ├── SharedHelpers.Import.Tests.ps1
    ├── SqlCleanup.Tests.ps1
    └── fixtures/
README.md
Fast1Migration.md
```

**Structure Decision**: Keep established boundaries. FR-014 supersedes the dedicated ScriptDom bootstrap design: define `Import-RequiredLibrary` once under `private/shared/`, and invoke it explicitly for SqlClient and ScriptDom before dependent behavior loads. Replace the two library-specific loader files and update all bootstrap consumers, inventories, and fixtures together. Optional required-type names retain parser compatibility checks without hardcoding library identities into the generic function. No dependency loading inside migration behavior and no new execution framework.

## Phase 0: Research Outcome

[research.md](research.md) records parser and generic-loader research and historical FR-015 clone/restoration probes. Two delegated read-only investigations for this refresh checked execution ownership and loader/build integration against current code, tasks, and recorded evidence. FR-016 supersedes executor borrowing/cloning/restoration: target/authentication/options come directly from original ConnStr, and execution resources are internally owned. Ambient suppression, pooled isolation, transaction completion, and cleanup remain defined by [contracts/script-session.md](contracts/script-session.md). This artifact update runs no implementation or acceptance checks.

Resolve malformed-input handling before the zero-batch return: explicitly reject null/empty/whitespace strings, then use `SqlConnectionStringBuilder` for local syntax/keyword/typed-value validation without allocating a connection or command. Preserve the original string for execution rather than round-tripping the builder. This does not establish authentication, reachability, or all provider option compatibility; remaining construction/open failures belong to the executable path. No technical clarification remains.

Current code already implements FR-014 and the prior clone-based isolation work. `validation.md` records their source/staged/offline evidence and explicit live/native limitations. The replacement ConnStr executor and its tests/help remain pending T056-T058; historical checks do not establish FR-016 acceptance.

### Spec review outcome

| Requirement area | Review finding and design resolution |
|---|---|
| FR-002/FR-003/FR-005/FR-009/FR-015/FR-016; SC-005/SC-008/SC-009 | Latest input supersedes the borrowed executor command: open a connection from ConnStr and create an owned command per executable file; history retains SqlCmd. |
| FR-015/FR-016 authentication/target | Forward the original ConnStr rather than reading an opened history connection. Connection-string target/options/authentication determine script initialization; cloning credential/token objects and selecting history's current database are no longer required. |
| FR-006/FR-007; Principles I/III | Batch success alone is insufficient if an unfinished transaction rolls back or cleanup fails. Check @@TRANCOUNT, require owned command/connection/scope cleanup before history, and preserve the first error. |
| FR-010/FR-015; SC-004/SC-008 | Validate before allocating script resources. Preview, invalid, and zero-batch paths open no script connection. Pooling may reuse physical sessions; require observable state isolation rather than unique SPIDs across files. |
| FR-001/FR-004/FR-008/FR-011/FR-012/FR-013/FR-014 | Retain whole-file parsing, unsupported-syntax rejection, parameterized history, deterministic phase validation, bundled dependencies, generic bootstrap, existing exports, and documentation/retry obligations. |

The latest requirement updates the spec with FR-016. T056-T058 track interface/caller/test/help changes; existing completed task markers and prior implementation evidence retain their historical scope.

## Phase 1: Design and Validation

1. Retain the applied constitution 1.1.0 amendment and approved module 0.1.0 release decision. Re-evaluate implementation against the active constitution; no new governance approval is needed for this design.
2. Preserve edited package references and the implemented `Import-RequiredLibrary -DllName [-RequiredTypeName]` contract. Retain per-call selected-distribution/RID asset and identity checks, exact compatible-preload reuse, required-type validation, cold-load provenance, no success output, and actionable dependency failures. Bootstrap SqlClient then ScriptDom before behavior. Current root/fixture consumers and parameter-aware traces use the generic function; the private inventory is 23. T041-T043/T051/T053 are checked with recorded source/staged/offline evidence, including the third bundled `Microsoft.SqlServer.Server.dll`, intact repeat reuse, and warm/cold faults. Rerun affected loader/build/staged validation after the executor change; outstanding native/live acceptance remains explicit.
3. Under FR-016 require mandatory string -ConnStr and existing -Script in Invoke-Migration. Reject blank input and locally validate connection-string syntax/keywords/typed values before reading/validating the whole script and before a zero-batch return. Allocate no execution SQL resources for rejected or zero-batch files. For executable files initialize/open a new connection directly from the original supplied string under ambient suppression, create an owned command with timeout 0, execute original parser spans, and validate final @@TRANCOUNT. Always attempt owned command, connection, then scope disposal using the existing ordered generic cleanup support; preserve the primary error and prohibit history on cleanup-only failure. Do not borrow, clone, rebind, or restore caller resources. T056-T058 track this unimplemented interface change.
4. Require `-SqlCmd` in `Set-Executed`, retaining all other arguments. Clear parameters, set text and typed parameters on that command, then execute once. Preserve insert/update SQL, UTC timestamps, and missing-forced-key failure. Remove its hidden connection and generic-query allocation path.
5. Retain history read and phase evaluation before confirmation. For confirmed eligible work the public command owns history resources, forwards its original ConnStr to Invoke-Migration, then calls Set-Executed -SqlCmd only after executor success. History retains its timeout without script/history switching. Preserve separate ownership, ordered cleanup, safe errors, and no implicit phase transaction.
6. Cover parser/preflight, ConnStr-only invocation, original-string forwarding, owned command/connection/scope allocation and failure cleanup, timeout 0, and history's unchanged command/transaction contract. Use explicit-target SQL for configured target/authentication, session isolation, transaction completion, committed-effects/retry, and history correctness. Replace old clone/binding/restoration/assigned-executor-transaction tests with coverage of the new interface; preserve prior evidence as historical.
7. Retain the existing explicit `FAST1_TEST_SQL_CONNECTION_STRING` integration opt-in without hardcoded credential defaults. Keep unique disposable databases and case-sensitive legacy-key coverage. Update loader inventories, bootstrap tracing, and provenance assertions.
8. Update affected manifest notes, public/private help, README, migration and release guidance together. Document dialect/quoted-identifier behavior, unsupported preprocessing, ConnStr-only executor ownership, history transaction support, ambient suppression, complete explicit transactions, partial commits, and retry. Remove superseded executor-command borrowing/transaction-rejection/cloning/restoration and public timeout-switching claims. Validate with [quickstart.md](quickstart.md). Current execution order is T056 (regressions) -> T057 (executor/caller implementation) -> T058 (guidance and fresh validation). T033/T038/T039/T052 retain applicable SQL/full-release/native obligations; their obsolete cloning/external credential-property expectations are superseded by FR-016. Serialize overlapping tests, staging, and evidence updates.

See [data-model.md](data-model.md), [contracts/migration-execution.md](contracts/migration-execution.md), [contracts/script-session.md](contracts/script-session.md), and [contracts/required-library.md](contracts/required-library.md) for the detailed lifecycle and contracts.

### Post-design constitution review

PASS for updated design: FR-016 derives execution target/authentication from original ConnStr and assigns command/connection/scope ownership to the executor. History retains its borrowed command and transaction contract. Ambient suppression, final transaction validation, and unconditional owned cleanup preserve completion integrity. Generic bootstrap, three public exports, approved stack governance, and platform contracts remain. T056-T058 track implementation and new-interface acceptance; actual SQL/native limitations remain in validation.md. This update changes feature artifacts only.

Historical planning validation counts describe earlier refreshes only. This workflow refreshes the plan, research, model, contracts, and quickstart and checks local links, requirement coverage, embedded PowerShell syntax/formatting, and unresolved placeholders. Specification, tasks/checkmarks, constitution, implementation evidence, and production PowerShell retain their contents. No runtime/analyzer pass is claimed. Extension hooks are checked again before completion.

Planning verification for this refresh: seven design artifacts, 38 local links, 11 PowerShell examples parsed without execution, and all 16 functional requirement IDs covered; no broken link, parse error, space-indented example, or unresolved template marker was found. These are documentation checks only. `.specify/extensions.yml` is absent at the pre-plan and post-plan checks, so no registered hooks are dispatched.

## Complexity Tracking

No constitution violation or exception remains in the design. One generic function replaces two library-specific implementations within the existing bootstrap boundary; no additional framework or public API is introduced.
