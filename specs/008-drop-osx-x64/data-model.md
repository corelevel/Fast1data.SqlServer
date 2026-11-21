# Data Model: Drop macOS x64 Support

**Feature**: [spec.md](spec.md) | **Contract**: [contracts/runtime-support.md](contracts/runtime-support.md)

This feature changes runtime and distribution policy. It adds no database entities, tables, configuration fields, or persisted state formats.

## Runtime target

| Field | Type / allowed value | Validation |
|---|---|---|
| Operating system | Windows or Linux | macOS and all other systems reject before dependency lookup. |
| Reported OS architecture | `Architecture.X64` | Other reported values reject; retain existing OS-architecture restriction. |
| Process architecture | `Architecture.X64` | A non-x64 process cannot select an x64 bundle. |
| Runtime identifier | `win-x64` or `linux-x64` | Derived only from valid native facts; no fallback. |

Relationship: one accepted runtime target selects one bundle directory under the current distribution's `lib`. No target can select `osx-x64`, even when that directory exists or a matching assembly is already loaded. Production native facts come from the PowerShell OS flags and RuntimeInformation; test facts are substituted only in disposable copies.

## Dependency bundle

| Field | Meaning | Invariant |
|---|---|---|
| RID | Target identifier | Exactly one retained RID per bundle directory. |
| Root | `Fast1data.SqlServer/lib/<rid>` | Destination absolute parent and basename validated before recursive cleanup. |
| Required managed libraries | SqlClient and ScriptDom DLLs | Both exist after publishing/copying; runtime retains identity/type validation. |
| Native/resource files | Existing target-specific publish assets | Retained intact for supported targets; no dependency version changes. |

Bundle filesystem state:

1. Before build: supported directories may be absent, old, or accompanied by an obsolete macOS bundle.
2. Build cleanup: remove only the validated obsolete macOS source bundle.
3. Per retained target: publish, check required libraries, replace the contained destination, and check copied libraries.
4. Build success: validate exactly two supported runtime directories, with zero macOS bundles. An unexpected directory or publish/copy failure terminates the build; partially updated assets do not count as release success.

Other arbitrary directories in a distribution `lib` are not valid runtime bundles and must fail exact-set acceptance. Do not broaden cleanup to arbitrary source directories to make that assertion pass.

## Release distribution

| Field | Value / relationship |
|---|---|
| Source | Current module source, selected documentation and required libraries |
| Stage root | Existing `out/Fast1data.SqlServer` |
| Supported RID set | Exactly `{win-x64, linux-x64}` |
| Module version | Planned `0.2.0` |
| Metadata | Windows/Linux tags and immediate macOS-removal release guidance |
| Public API | Existing six commands, signatures and manifest exports |

Staging transition: validate required sources for both targets -> validate exact stage destination -> recreate stage -> copy selected module files and allowlisted bundles -> validate manifest/assets/exact target set -> import/analyze -> optionally run tests. Preflight failure preserves the preceding stage. A later failure must remain an error and cannot certify a release. `-StageOnly` completes staging/analyzer checks only and never claims test acceptance or publication.

## Initialization result

| State | Entry / transition | Observable result |
|---|---|---|
| Native facts read | First required library request | No database access. |
| Unsupported | OS or architecture outside the target contract | Terminating unsupported-platform error with both supported alternatives; no bundle selection. |
| Supported | Valid Windows/Linux x64 facts | Select exactly matching RID. |
| Dependency failure | Selected DLL missing, corrupt, incompatible, or required type unavailable | Existing actionable DLL/RID/path/rebuild/fresh-process diagnostic. |
| Initialized | Required loaders and behavior imports succeed | Existing six public commands; no database mutation merely from import. |

Unsupported-platform errors occur before required-library reuse/lookup. The root may wrap them with existing initialization context while preserving the reason and alternatives. An obsolete directory or warm assembly cannot transition an unsupported host to supported.

## Compatibility record

The planned constitution 2.0.0 amendment records the approved platform narrowing and transition; module 0.2.0 independently identifies the release. No migration-history, audit-offset, archiving-state, checksum, schema, or configuration representation changes. A macOS user moves orchestration to a supported host while preserving database state, portable migration identities and external file/share access. No database-format conversion results from this feature.
