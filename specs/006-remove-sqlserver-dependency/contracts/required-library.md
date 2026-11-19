# Required Library Initialization Contract

**Feature**: [../spec.md](../spec.md) | **Execution contract**: [migration-execution.md](migration-execution.md)

This private contract implements FR-014 and SC-007. It supersedes the separate `Import-SqlClientLib` and `Import-ScriptDomLib` designs. It does not add a public export.

The working tree already implements this contract under T041-T043/T051/T053, with recorded source/staged/offline results in [../validation.md](../validation.md). Retain that implementation during FR-016 work and rerun affected acceptance; outstanding native/live checks remain distinct from recorded loader results.

## Function and arguments

`Import-RequiredLibrary -DllName <string> [-RequiredTypeName <string[]>]`

The definition lives in `Fast1data.SqlServer/private/shared/Import-RequiredLibrary.ps1`. It returns no success-stream output and throws on failure.

| Argument | Validation and meaning |
|---|---|
| `DllName` | Mandatory, nonempty single filename with a nonempty stem and case-insensitive `.dll` extension. Reject rooted/drive-qualified paths, `/`, `\`, `:`, wildcard syntax, directory components, and invalid filename characters. No library-name allowlist. |
| `RequiredTypeName` | Optional collection of nonempty fully qualified type names. Every supplied name must resolve, case-sensitively, from the selected assembly. Omitting it requests identity/load validation without an additional type check. |

## Resolution, compatibility, and reuse

1. Validate arguments before loading an assembly. Use the existing `Get-RuntimeIdentifier`; retain its unsupported-platform failures.
2. Derive the distribution root from the defining loader's `$PSScriptRoot`, independent of the current directory, module search paths, or source checkout. Compute the absolute `lib/<rid>/<DllName>` path and verify its parent is the selected RID bundle. Do not accept an alternate search root.
3. Require a literal file at that path and inspect managed metadata with `AssemblyName.GetAssemblyName`. Its simple name must match the requested filename stem, case-insensitively. This prevents another managed DLL renamed to the requested filename from satisfying initialization.
4. Inspect assemblies already in the process by the expected simple name. Reuse a compatible instance only when name, version, culture, and public-key token match the selected asset's identity. A same-name incompatible preload terminates initialization; do not try another assembly copy or change load contexts to conceal the conflict. No automatic version roll-forward is promised.
5. If none is loaded, load the selected absolute path through `Assembly.LoadFrom`. Validate the resulting identity and cold-load location; a resolved entry assembly outside the selected bundle is a failure. No custom source/global probing or assembly resolver is introduced. Transitive dependencies continue through the existing .NET binding mechanism and are validated by import/execution acceptance.
6. For a new or reused assembly, validate every required type using `Assembly.GetType`. A missing type or dependency exception is fatal. Complete without output only after all checks succeed.

Bundle presence and metadata are checked on every invocation, including reuse. A compatible assembly preloaded from another location may be reused when the selected bundle remains valid; this is explicit reuse, not a fallback search. A missing/corrupt selected package asset must still fail in a warm process. Current fixtures enforce intact-bundle reuse and separate warm missing/corrupt failures. Cold-source/staged provenance checks remain separate from compatible-preload tests.

These rules establish metadata and requested-type compatibility; they do not promise binary integrity attestation or that every transitive/native operation works without runtime validation.

## Bootstrap consumers

Root bootstrap dot-sources the generic definition once after `Get-RuntimeIdentifier`, then calls it in the existing dependency order:

| DLL | Required type | Purpose |
|---|---|---|
| `Microsoft.Data.SqlClient.dll` | `Microsoft.Data.SqlClient.SqlConnection` | Database client before typed behavior |
| `Microsoft.SqlServer.TransactSql.ScriptDom.dll` | `Microsoft.SqlServer.TransactSql.ScriptDom.TSql160Parser` | Required migration parser before migration behavior |

The specific loader implementations have been removed. Keep `private/shared/Load.ps1` limited to shared behavior. Retain the migrated bootstrap calls in `tests/fixtures/Invoke-ModuleLoaderScenario.ps1`, `Invoke-SharedHelperScenario.ps1`, `Import-SharedHelperDependency.ps1`, assertions in `SharedHelpers.Scenarios.ps1`, and parameter-aware generic tracing and ownership/fault checks in `ModuleLoaders.Tests.ps1`. The actual private inventory is 23 files; update the complete inventory if future implementation changes it.

`Microsoft.SqlServer.Server.dll`, with required type `Microsoft.SqlServer.Server.SqlFunctionAttribute`, is the existing bundled third-library acceptance case. It needs no new production bootstrap call or package reference.

## Failure behavior

Missing, unreadable, corrupt, wrong-identity, incompatible-preload, and required-type failures terminate with DLL name, RID, expected bundle path, and `build/build.ps1` rebuild guidance. Preserve the underlying exception as the cause. Invalid arguments identify the rejected argument; unsupported runtimes retain the runtime resolver's actionable error when no RID/path can be selected. Do not copy secrets or arbitrary dependency exception text into added context.

Root initialization preserves its terminating error scope, stage diagnostics, and preference restoration. Dependency failure prevents usable partial public exports. Assembly loads are process-wide and are not rolled back after failure; a fresh process is required after replacing a faulty/incompatible dependency.

## Acceptance

Run the matrix in [../quickstart.md](../quickstart.md) against source and staged distributions. It covers both primary DLLs, a third managed DLL, no success output, repeated reuse, required types for both paths, argument containment, wrong identities, incompatible preloads, cold and warm bundle faults, provenance, bootstrap order, and unchanged exports. Earlier library-specific loader results do not establish this contract.
