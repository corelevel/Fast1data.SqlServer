# Runtime Support Contract

**Feature**: [../spec.md](../spec.md) | **Planned release**: 0.2.0

## Supported targets (FR-001, FR-004)

| OS | Reported OS architecture | Process architecture | Result |
|---|---|---|---|
| Windows | X64 | X64 | `win-x64` |
| Linux | X64 | X64 | `linux-x64` |
| macOS | Any | Any | Unsupported platform |
| Any other OS | Any | Any | Unsupported platform |
| Windows/Linux | Any non-X64 | Any | Unsupported architecture |
| Windows/Linux | X64 | Any non-X64 | Unsupported architecture |

There is no architecture/OS fallback, platform override, or emulation support added by this feature. Architecture restrictions use RuntimeInformation's reported facts, with the reporting limitations documented in [research](../research.md#3-runtime-selection-and-architecture).

## Build and package (FR-002)

- Successful dependency builds publish only `win-x64` and `linux-x64`, retaining SqlClient, ScriptDom, and their required native/resource dependencies.
- A reused build removes the contained obsolete source `lib/osx-x64` directory. Historical build caches are outside the distribution contract.
- Staging preflight requires only the two retained targets. Successful staging contains exactly their two `lib` directories, even when source or previous stage includes an obsolete macOS bundle.
- Staging copies an allowlist and recreates the validated stage directory. It never copies all source RID directories indiscriminately.
- Missing required assets, failed publishes/copies, unexpected source/staged RID directories, manifest/import failure, or analyzer failure cannot yield a successful release result.
- Source preflight precedes stage removal. Recursive cleanup is limited to checked absolute destinations within the intended source/stage root.
- `out/publish.ps1 -StageOnly` does not execute Pester or publish to a gallery. Platform/command acceptance requires separate evidence.

## Public initialization and failure (FR-003, FR-005)

Both `Fast1data.SqlServer.psd1` and direct `Fast1data.SqlServer.psm1` imports follow the same platform gate before bundle lookup, required-assembly reuse/loading, operational behavior loading, or database operations. The parameter descriptor declaration can still load before that gate; it performs no database work.

On unsupported hosts, import terminates with an unsupported OS/platform or architecture reason and identifies **x64 Windows (`win-x64`) and x64 Linux (`linux-x64`)** as supported alternatives. Exact prose is not fixed; existing root initialization context may wrap it. It must not misleadingly report a missing macOS dependency or suggest rebuilding macOS support. Existing macOS bundle files and preloaded compatible assemblies do not change rejection.

On supported hosts, the existing loader validates the selected dependency on every call. Missing/corrupt assets and incompatible preloads retain DLL name, selected RID, expected path, rebuild instructions (`build/build.ps1`), fresh-process guidance, and underlying failure information. Dependency failure must remain distinct from platform rejection.

Supported imports continue exporting exactly:

- `Invoke-Fast1Audit`
- `Invoke-Fast1Migration`
- `Invoke-Fast1Archiving`
- `Invoke-Fast1GenericSqlQuery`
- `Invoke-Fast1GenericSqlQueryReader`
- `New-Fast1GenericSqlParam`

Parameters, output, ownership, preview/confirmation, timeout, configuration, SQL semantics, and explicit manifest exports remain unchanged. Model-first checks continue to bootstrap SqlClient through the designated resolver/loader before importing classes; this feature does not create a new standalone public model entry point.

## Metadata, policy, and transition (FR-006, FR-007, FR-008)

The manifest declares module 0.2.0 and advertises Windows/Linux only. README current requirements and bundle list agree. Release notes explicitly state immediate macOS support removal, unsupported ARM64/other platforms, and moving execution to x64 Windows or Linux. Current help is reviewed for conflicting support statements; historical specifications and old release entries remain historical.

The authorized compatibility amendment updates Principle IV and records constitution 2.0.0 with rationale, contract impact and transition as specified in research. Preserve original ratification and historical amendments; record actual adoption date. No change to the PowerShell 7.6+ Core baseline or dependency versions is part of this release.

Existing SQL Server database state, migration history/checksums, audit checkpoints, archiving state and configuration formats remain compatible. Host moves must preserve portable migration paths and make configured file/share locations and credentials available to the new host. No database-format migration is required by macOS removal. Users' existing macOS installations and historical releases are not deleted.

## Acceptance evidence

Use [../quickstart.md](../quickstart.md). Record simulated platform coverage, native host execution, build/stage checks, analyzer and SQL acceptance separately. Absence of a native Linux or SQL test environment is an unrun check, never a pass. New distributions require exact target-set verification; supported-host acceptance is required on both retained native platforms before release.
