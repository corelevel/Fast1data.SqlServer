# Research: Consolidate Migration Phase Validation

**Date**: 2026-10-30 | **Branch**: `dev` | **Specification**: [spec.md](spec.md)

## Scope and research questions

Repository research covered the evaluator boundary, portable identity and containment, whole-phase validation, SQL history updates, preview, and verification prerequisites. Two research agents independently inspected phase rules and execution/history verification. No runtime dependency or database interface is being selected. All technical design questions below are resolved; availability of a test database and other operating systems remains a validation prerequisite, not a design clarification.

## R1. One private phase evaluator

**Decision**: Replace `private/migration/Get-Migration.ps1` with `private/migration/Resolve-MigrationPhase.ps1`. Accept `BasePath`, `Phase`, supplied `History`, `IgnoreScripts`, and `ForceScripts`. Return one completed object containing phase metadata, ordered script decisions, and warnings. Read configuration/files and compute checksums using existing helpers; perform no SQL calls, script execution, history writes, or confirmation prompts.

**Rationale**: The current reader only loads JSON and normalizes configured separators; its caller owns almost all invariants and validates paths/checksums inside the execution loop. A complete result makes the validation boundary observable and prevents a valid early entry from executing before a later error. The existing module loader discovers private scripts recursively.

**Alternatives considered**: Expand the shallow reader while retaining caller validation, which leaves split ownership; introduce a database adapter, injectable operation registry, public phase API, or class hierarchy, which the specification excludes.

**Evidence**: `Fast1data.SqlServer/private/migration/Get-Migration.ps1`, `Fast1data.SqlServer/public/Invoke-Fast1Migration.ps1`, `Fast1data.SqlServer/Fast1data.SqlServer.psm1`.

## R2. Shared identity, literal selection, and order

**Decision**: Select JSON properties by literal property-name lookup and preserve array order. Normalize backslashes to forward slashes for configuration, history, and both selection lists. Use ordinal case-insensitive sets/maps for matching without lowercasing paths used to open files. Reject configured duplicates and ignore/force intersections globally, including intersections absent from configuration; return warnings for other unknown selections.

Use slash-normalized phase-relative configured spelling as both the matching name and recorded name. Keep relative spelling rather than adding dot-segment/path-alias deduplication. For an accepted rooted path within the phase, derive phase-relative spelling using retained `Get-RelativePath` before identity/storage; apply the same conversion to rooted names from the other sources. Resolve filesystem paths separately. These rules keep persisted names consistent with later evaluation without adding general path-alias matching.

**Rationale**: Configuration and SQL history currently normalize in separate readers, while selection normalization occurs in the command. Literal property lookup distinguishes an existing empty phase from a missing property, including bracketed phase names. The specified identity rules are independent of filesystem case sensitivity.

**Alternatives considered**: Host-sensitive script identity, lowercasing actual paths, sorting scripts, wildcard selection, or broad canonical-path deduplication would change specified behavior.

**Evidence**: Current reader, public migration command, `private/migration/Get-Executed.ps1`, and specification FR-002–FR-004 and matching-scope assumptions. Literal property-name behavior was checked locally with bracketed names.

## R3. Containment before exemptions

**Decision**: Resolve a fully qualified phase directory and resolve each configured path against it with rooted-path-aware .NET path operations. Require the resolved script path to start with the phase root plus a directory separator, using ordinal case-insensitive comparison on Windows and ordinal comparison on Linux/macOS. Check containment even for ignored/forced entries. Require every non-ignored path to be an existing file. Use literal filesystem operations throughout, including a narrow change from `Get-FileHash -Path` to `-LiteralPath` inside retained `Get-FileChecksum`.

**Rationale**: A separator boundary rejects sibling directories sharing the root's name prefix and rejects the directory itself. `Join-Path` alone is insufficient to interpret rooted child input; local inspection confirmed this on Windows. Bracketed phase names must not become wildcard file queries. .NET provides a full-path overload with an explicit base directory, and PowerShell exposes literal file hashing. See [Path.GetFullPath](https://learn.microsoft.com/dotnet/api/system.io.path.getfullpath) and [Get-FileHash](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/get-filehash?view=powershell-7.4).

**Alternatives considered**: String-prefix comparison without a separator, lowercasing Unix paths, checking containment only for runnable entries, or adding a symbolic-link resolution policy. The last is explicitly outside scope; this retains lexical full-path containment.

**Evidence**: Existing public command root-prefix logic; `private/shared/Get-FileChecksum.ps1`; `private/shared/Get-RelativePath.ps1`.

## R4. Buffered decisions and checksum behavior

**Decision**: Build all script decisions in memory and return only after complete successful evaluation. Contained ignored entries skip existence/hash checks. All other entries receive SHA-256 checksums. New entries run; unchanged historical entries skip unless forced; changed historical entries fail unless forced. Force still requires containment and file existence. Include identity, expected checksum, and current checksum in drift errors.

**Rationale**: Neither SQL execution nor history mutation may begin with a partially validated phase. Retaining the checksum helper preserves meaningful behavior while moving decision ownership. The result is an evaluation snapshot, not a lock or transaction.

**Alternatives considered**: Lazy pipeline decisions, validation during execution, or reimplementing checksum decisions in preview all permit inconsistent or partial behavior.

## R5. Command coordination and exact history keys

**Decision**: Keep history reads in `Get-Executed`, SQL execution in `Invoke-Migration`, and writes in `Set-Executed`. Move history-name normalization into the phase responsibility and preserve the original stored `script_name` returned by the reader. Carry the matched stored name in each decision. Extend only the existing private writer as needed with a `HistoryScriptName` lookup argument for updates: use that original key in the parameterized predicate and write the evaluated normalized `ScriptName`, checksum, and execution timestamp. Inserts continue using the evaluated name. Do not change schema or public parameters.

The command reads history, obtains the complete evaluation, presents warnings/skips, performs its existing phase-level `ShouldProcess`, then executes and records each eligible script in order. Preview consumes the same result and prints eligible names without calling either mutating helper. Invoke existing execution/writer boundaries with terminating error behavior. Stop after either execution or recording failure.

**Rationale**: Today the history reader discards stored backslashes, and forced updates predicate on configured spelling. A normalized evaluator match can otherwise fail its SQL update with legacy separators or a case-sensitive database collation. The original key and intended recorded name serve different purposes. Successful execution followed by failed recording remains possible and requires idempotent scripts.

**Alternatives considered**: Rely on database collation to implement application identity, rewrite or bulk-repair history during validation, wrap arbitrary migration scripts and history in a new transaction, or replace SQL helpers with an adapter. These change scope or recovery guarantees. No general legacy-history repair or collation change is planned.

**Evidence**: `private/migration/Get-Executed.ps1`, `Set-Executed.ps1`, `Invoke-Migration.ps1`, `schema/migration/tables.sql`, and `Fast1Migration.md`.

## R6. Verification layers and explicit test database

**Decision**: Add `tests/MigrationPhase.Tests.ps1` for the phase interface using real temporary files and supplied history. Load only the evaluator and retained filesystem helpers there so phase rules require no SQL access. Retain `tests/Migration.Tests.ps1` for command orchestration/WhatIf checks and tagged real SQL coverage. Replace shallow-reader tests with phase behavior assertions. Mock existing execution/history boundaries for command tests; retain and extend SQL checks for persistence, timestamps, SQL errors, legacy stored names, and case-sensitive collation.

**User revision after implementation**: T003's connection refactor was reverted. Retain the original local `pester_migration` connection in the test file, without a file-level connection parameter or its added guards. Keep Integration-only SQL setup, nonintegration isolation, and fixture-owned cleanup. The current commands are in quickstart.md.

The original design proposed replacing the hardcoded integration connection with an explicit test-container `ConnectionString` parameter, used only by integration setup, and rejecting a missing database selection. That proposal is superseded by the user revision above. Pester's test-container mechanism remains documented at [New-PesterContainer data](https://pester.dev/docs/usage/data-driven-tests).

**Rationale**: Phase semantics can be established without deployment, but mocks cannot prove SQL collation, real execution failure, or durable history. Current SQL coverage tests new/skip/force idempotency only; failure and stored-name scenarios need expansion. A planned command-level late-invalid case must assert zero executions and zero history writes.

**Alternatives considered**: Keeping only reader-level tests, mocking all database correctness, requiring a database for every phase test, or silently using the existing hardcoded local credentials.

## Planning environment observations

- Windows x64, PowerShell 7.6.9 Core; Pester 6.2.0, PSScriptAnalyzer 1.25.0, and SqlServer 22.4.5.1 are available. These observations do not change the supported PowerShell 7.4 baseline.
- Source manifest validation/import succeeded and exposed the three existing public commands. This does not verify all bundled runtime assets.
- An existing nonintegration migration baseline was attempted during research, but Pester could not create its TestRegistry key under sandbox restrictions. No baseline acceptance tests passed; four framework failures were reported and integration was not run. This is an unavailable baseline, not evidence of a migration regression.
- No explicit SQL test database was selected. SQL integration, Linux, and macOS verification were not run.
- No project PSScriptAnalyzer settings file was found. Static analysis is an implementation gate for changed PowerShell, including tests; this planning workflow changes Markdown only.

All feature acceptance tests and implementation checks remain pending implementation. See [quickstart.md](quickstart.md) for the validation procedure.
