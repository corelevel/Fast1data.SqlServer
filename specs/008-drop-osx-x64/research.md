# Research: Drop macOS x64 Support

**Date**: 2026-11-20 | **Feature**: [spec.md](spec.md)

Research used two delegated, read-only repository investigations: build/staging/release contracts and runtime/loading/test boundaries. The pre-research constitution gate permits the platform change because the specification explicitly authorizes the compatibility change allowed by Principle IV; adoption must include the policy and release updates described below. No implementation or acceptance tests were performed.

## 1. Build output and stale bundles

**Decision**: Restrict `build/build.ps1` to `win-x64` and `linux-x64`. Remove the obsolete source `Fast1data.SqlServer/lib/osx-x64` directory when present, using an absolute path and checking its exact parent and basename before recursive deletion. Perform this bounded cleanup before the supported publish loop. Preserve per-target publish failures and required-assembly validation. After publishing, assert the exact source RID directory set; unexpected directories fail validation rather than being broadly deleted.

**Rationale**: The existing build replaces only destinations in its RID loop. Removing one loop entry alone leaves its old bundle in a reused checkout. An exact obsolete-directory cleanup also makes the source distribution agree with the new support promise. A failed publish remains a failed build and must not be presented as a valid distribution.

**Alternatives considered**: Deleting all of `lib` unnecessarily discards retained bundles. Editing only the RID list leaves stale macOS assets. Purging historical `build/bin` or `build/obj` output is unnecessary because neither directory is a distribution source.

**Evidence**: `build/build.ps1`; `.gitignore`; `build/SqlClientLoader.csproj`.

## 2. Staged distribution

**Decision**: Restrict the independent `$supportedRids` list in `out/publish.ps1` to the same two targets. Retain its source preflight, contained recreation of `out/Fast1data.SqlServer`, per-RID copying, nested-publish exclusion, assembly checks, and analyzer validation. Add an exact staged RID-set assertion so unexpected directories cannot pass release validation.

**Rationale**: Staging already copies an allowlist rather than the entire source `lib` tree. It therefore excludes old macOS assets even if staging is run without rebuilding a source tree that still contains them. Recreating the staging directory also removes obsolete staged assets.

**Alternatives considered**: Copying the complete source library tree could resurrect unsupported bundles. Depending exclusively on build cleanup would make standalone staging unsafe. Creating a shared runtime-policy file introduces a loader/package boundary for only two lists; focused contract tests can enforce agreement without a new production file.

**Evidence**: `out/publish.ps1`.

## 3. Runtime selection and architecture

**Decision**: Keep `Get-RuntimeIdentifier` parameterless and in its existing file. Recognize only Windows and Linux; require both reported OS architecture and current process architecture to be X64. Reject macOS and other operating systems before any library filesystem lookup, and reject all other reported architecture combinations. Every rejection names x64 Windows (`win-x64`) and x64 Linux (`linux-x64`) as supported alternatives.

**Rationale**: `Import-RequiredLibrary` calls the resolver before its bundle lookup and dependency-error wrapper. Rejection at that boundary remains explicit even with a copied macOS DLL or a compatible assembly preload. Checking process architecture additionally prevents selecting x64 native libraries for a non-x64 PowerShell process. The existing OS check continues to exclude reported ARM64 hosts; this feature does not introduce emulation support.

The API distinguishes the underlying OS architecture from the running process architecture. OS reporting accounts for built-in Windows/macOS emulation, but does not account for QEMU on Linux. The design uses the reported values and does not promise to identify the physical CPU beyond them. Sources: [OSArchitecture](https://learn.microsoft.com/en-us/dotnet/api/system.runtime.interopservices.runtimeinformation.osarchitecture?view=net-10.0), [ProcessArchitecture](https://learn.microsoft.com/en-us/dotnet/api/system.runtime.interopservices.runtimeinformation.processarchitecture?view=net-10.0), [OSArchitecture under emulation](https://learn.microsoft.com/en-us/dotnet/core/compatibility/interop/7.0/osarchitecture-emulation).

**Alternatives considered**: Removing DLLs alone gives misleading dependency errors. Checking only process architecture would widen the current reported-OS acceptance under emulation. Adding public platform overrides or a new private policy module is unnecessary.

**Evidence**: `Fast1data.SqlServer/private/shared/Get-RuntimeIdentifier.ps1`; `Fast1data.SqlServer/private/shared/Import-RequiredLibrary.ps1`; `Fast1data.SqlServer/Fast1data.SqlServer.psm1`.

## 4. Loading boundaries and test isolation

**Decision**: Preserve both public entry points (`.psd1`, `.psm1`), the six exports, bootstrap order, the model's explicit SqlClient-bootstrap prerequisite, and the existing 23-file private inventory. Add `RuntimeSupport.Tests.ps1` and `Packaging.Tests.ps1` with test-only fixtures as needed. Unsupported-platform import tests use fresh child processes and marked disposable distribution copies. In those copies, substitute only the native OS-flag and OS/process-architecture expressions with controlled literals; keep selection, error, loader, and initialization logic intact and validate each expected substitution.

**Rationale**: Native facts are not ordinary Pester-mockable commands, and PowerShell OS variables are read-only. Test-local native-fact substitutions exercise the actual decision and import paths without adding a production test API or mutating global host state. Instrument a later bootstrap/shared-behavior boundary in disposable copies: rejection must occur before it, before bundle access, and with no database-operation attempts. Real native-host checks remain distinct from simulations.

**Alternatives considered**: Mocking the resolver to throw does not test its platform logic. Globally forcing OS variables risks contaminating unrelated tests. Native-only tests cannot cover every unsupported architecture on ordinary development hosts.

**Evidence**: `Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1`; `Fast1data.SqlServer/tests/fixtures/Invoke-ModuleLoaderScenario.ps1`; `Fast1data.SqlServer/private/archiving/ArchivingModel.psm1`.

## 5. Preserve existing contracts

**Decision**: Update only the expected RID set in `tests/fixtures/SharedHelpers.Scenarios.ps1`, require the exact retained directory set, and retain the six-command snapshot in `SharedHelpers.PublicContract.json`. Run loader, shared-helper, query, migration, audit, and archiving regressions on retained platforms as applicable. Keep missing/corrupt supported-library diagnostics and fresh-process recovery instructions.

**Rationale**: The runtime-asset fixture currently requires three bundles. Its command metadata snapshot does not include module version or platform tags, so no blanket snapshot regeneration is needed. Imports alone do not establish native SQL-client behavior; the existing SQL Server acceptance suites supply that evidence. There is no database, configuration, history, checkpoint, or command-format change.

**Alternatives considered**: Updating the entire snapshot could hide unrelated API regressions. Treating package file presence as native Linux execution would overstate verification.

**Evidence**: `Fast1data.SqlServer/tests/fixtures/SharedHelpers.Scenarios.ps1`; `Fast1data.SqlServer/tests/fixtures/Get-SharedHelperPublicContract.ps1`; `README.md` test prerequisites.

## 6. Release and compatibility policy

**Decision**: Plan module release **0.2.0**, advancing from 0.1.0 for this pre-1.0 compatibility change. Update manifest version, current release notes and platform tags, and README requirements/bundles/upgrade guidance together. No independent module versioning policy was found; 0.2.0 is this plan's explicit release decision, not a claim that an existing policy mandates it.

Plan constitution **2.0.0** for the incompatible narrowing of Principle IV's platform promise, following Governance's MAJOR rule for incompatible principle redefinitions. Replace its opening platform sentence with: "The module MUST maintain its documented PowerShell 7.6-or-later Core baseline and x64 Windows and Linux support until an explicit compatibility change is approved." Add an amendment recording the authorized macOS removal, rationale, affected build/loading/metadata contracts, module release 0.2.0, and transition to a retained host. Preserve the original ratification field and historical Amendment 1.1.0; update the last-amended date when the amendment is actually adopted. This planning run does not adopt the amendment or change the module version.

**Rationale**: FR-007 requires both policy reconciliation and an explicit release decision. The specification records authorization to remove macOS; implementation can carry out that authorized reconciliation without a new compatibility-approval question. Constitution and module versions are independent. Guidance must tell macOS users to move execution to a supported host, retain existing database state/history/configuration, preserve portable migration paths, and retain external file/share access and permissions.

**Alternatives considered**: Keeping module 0.1.0 obscures the new support boundary. Module 1.0.0 adds an unrelated stable-release milestone. A warning-only macOS release conflicts with "keep only" and FR-001. A constitution patch/minor understates the incompatible platform-promise change under its stated governance rules.

**Evidence**: `specs/008-drop-osx-x64/spec.md` assumptions and FR-007; `.specify/memory/constitution.md` Principle IV and Governance; `Fast1data.SqlServer/Fast1data.SqlServer.psd1`; `README.md`.

All technical unknowns are resolved. Native-host availability and implementation validation results are execution evidence to collect later, not unresolved design decisions.
