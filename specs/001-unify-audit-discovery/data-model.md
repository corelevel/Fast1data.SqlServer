# Data Model: Unify Audit Discovery

**Feature**: [spec.md](spec.md) | **Contract**: [contracts/discovery.md](contracts/discovery.md)

All records are transient PowerShell values. No database schema, persisted checkpoint, or new public type is introduced.

## Discovery request

| Field | Type | Rules |
| --- | --- | --- |
| `Folder` | `string`, mandatory | Windows local/UNC directory; Linux UNC server/share with optional nested directory. Preserve directory-name spaces. Invalid requests terminate. |
| `Credential` | optional `PSCredential` | Required and not `PSCredential.Empty` on Linux; unused on Windows. Used only for listing. |

One request produces one complete listing outcome. Discovery credentials have no relationship to SQL Server's content-reading permissions.

## Listing candidate (private seam)

| Field | Type | Rules |
| --- | --- | --- |
| `Name` | `string` | Basename from a genuine file entry, with filename spaces preserved. May be an invalid audit name. |
| `FullName` | `string` | Full path to that file in the requested directory. Windows uses the enumerated full path; Linux reconstructs the UNC file path. |

`Get-SqlAuditFileEntry` emits only files. Directories, status text, headers, and footer metadata never become candidates. Attributes and native output remain helper implementation details; they do not become result fields. Candidates contain no GUID interpretation or credentials.

## Audit filename interpretation

| Component | Rules |
| --- | --- |
| Audit-name prefix | Nonempty; may contain underscores and spaces. |
| Audit GUID | Hexadecimal GUID in standard 8-4-4-4-12 layout; either letter case. |
| Sequence | Nonempty digits; no conversion, ordering, or range rule. |
| Ticks | Nonempty digits; no conversion, timestamp validation, or range rule. |
| Extension | Existing lowercase `.sqlaudit` baseline; no new case-support promise. |

The whole basename must fit `prefix_GUID_sequence_ticks.sqlaudit`. The single authoritative anchored expression remains in `Get-SqlAuditFile`; transport helpers do not repeat it. A malformed name is a rejected candidate, not a listing failure.

## Discovered audit file (existing result)

| Field | Type | Rules |
| --- | --- | --- |
| `FileName` | `string` | Candidate's complete full path. |
| `AuditGuid` | `System.Guid` | GUID value extracted by the authoritative filename rule. |

Each accepted candidate produces one result. Distinct files with the same GUID remain distinct; the GUID is a grouping attribute, not a unique file key. Discovery imposes no output order. No audit records, prefix/sequence/ticks fields, credentials, or transport metadata are exposed.

## Listing outcome and transitions

| State | Transition | Observable outcome |
| --- | --- | --- |
| Request bound | Validate platform/path/prerequisites | Continue, or terminate with actionable error. |
| Listing in progress | Windows enumeration or Linux process invocation | Buffer output; publish no discovery results yet. |
| Listing successful | Normalize file rows, then apply shared filename rule | Zero or more existing result objects. |
| Listing failed | Enumeration error, invocation exception, or nonzero native exit | Sanitized terminating error; zero discovery results. |

Successful zero candidates or zero accepted names both produce an empty pipeline. Failure is never represented by an empty-success sentinel.

## Borrowed credential state

| State field | Rules |
| --- | --- |
| Prior presence | Remember whether process `PASSWD` existed before discovery. |
| Prior value | Preserve exactly for restoration; never log it. |
| Temporary value | Supplied password; only available to the listing operation and its child. |

Lifecycle: capture prior state -> enter protected region -> assign temporary password -> invoke/capture -> restore prior state in `finally` -> return candidates or throw sanitized error. Both initially absent and initially present states must round-trip for files found, no files found, process failure, and invocation exception. Windows never enters this lifecycle. This is scoped cleanup, not a guarantee of erasing managed-memory password copies.
