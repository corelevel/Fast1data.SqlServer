# Discovery Contract

**Feature**: [spec.md](../spec.md) | **Model**: [data-model.md](../data-model.md)

## Existing discovery interface

```powershell
Get-SqlAuditFile -Folder <string> [-Credential <PSCredential>]
```

This remains private to the module and is consumed by `Invoke-Fast1Audit`. The exported command list is unchanged.

| Environment | Accepted request | Credential behavior |
| --- | --- | --- |
| Windows | Local directory or UNC directory, including nested folders and trailing separators | Supplied credentials remain unused; current Windows identity performs enumeration. |
| Linux | UNC server/share and optional nested directory; `smbclient` available | Supplied credential required; null or `PSCredential.Empty` is rejected. |
| Other OS | Unsupported for discovery | Terminating unsupported-platform error. |

Linux validates that the folder identifies a UNC server and share rather than treating an arbitrary local path as a share. Nested directory components and spaces must survive argument construction. No recursive search, wildcard folder expansion, or public transport-selection parameter is added.

## Success and filename acceptance

Each returned `PSCustomObject` has exactly the existing discovery properties:

| Property | Type | Meaning |
| --- | --- | --- |
| `FileName` | `string` | Full path of one valid audit file. |
| `AuditGuid` | `System.Guid` | Parsed identifier from that filename. |

Example: `fast1_audit west_615E3B8A-9980-4739-89DD-B8CA9D93C36E_0_134289496418640003.sqlaudit` identifies GUID `615e3b8a-9980-4739-89dd-b8ca9d93c36e`. In `\\server\share\nested\`, its result path is that root, with trailing separators normalized, followed by one separator and the unchanged basename.

The full-name grammar is defined in [data-model.md](../data-model.md). Empty prefix, bad GUID layout, missing/nonnumeric sequence or ticks, and trailing text are rejected. Unrelated files, directory entries even with valid-looking names, and SMB metadata are ignored. Multiple files with one GUID each produce a result. No order guarantee is introduced. Successful empty and rejected-only listings emit zero objects.

## Failure and secret handling

| Condition | Required behavior |
| --- | --- |
| Invalid request, missing Linux credentials or executable | Actionable terminating error naming the unmet prerequisite. |
| Windows enumeration failure, including failure after yielding entries | Terminating error; no discovered results from the failed listing. |
| Native invocation throws | Sanitized terminating invocation error after credential restoration. |
| Native process exits nonzero | Sanitized terminating listing error with exit code and available safe context, even if output contains valid-looking file rows. |

No supplied password may appear in any emitted stream or terminating error details. Capture native output instead of forwarding it; redact the password before composing diagnostics. Do not retain an unsanitized inner exception in the emitted error record. Passwords never appear in process arguments or result objects.

Linux snapshots both presence and value of process `PASSWD`, temporarily uses it for the child, and restores the exact prior state in `finally`. When it was absent, remove the introduced variable. This applies to successful matches, successful no matches, process failure, and invocation exception. Windows credentials do not change environment state.

## Internal listing seam

```powershell
Get-SqlAuditFileEntry -Folder <string> [-Credential <PSCredential>]
```

This new helper is private and returns `{ Name: string, FullName: string }` file candidates. It owns platform selection and transport interpretation, with no audit grammar or GUID projection. Discovery buffers its complete output before accepting any names.

Windows uses existing literal, nonrecursive, file-only enumeration with terminating errors. Linux uses `smbclient` with separate share, username, static `-c 'ls'`, and optional `-D` argument values. No supplied password is placed in those arguments. Capture the process result, check status before row parsing, and treat every nonzero exit as failure. The native error preference is controlled locally so caller preferences do not alter this contract.

Linux row interpretation must use file attributes and metadata boundaries, rejecting directory attributes and preserving spaces within the basename. The listing helper may understand SMB formatting but must not independently recognize audit names. It must not treat a diagnostic substring as a file row.

## Caller and SQL Server boundary

`Invoke-Fast1Audit` continues to call discovery with the same parameters, group returned GUIDs, and invoke the existing importer. It must acquire no platform-selection, transport, or filename-parsing logic. SQL Server reads audit contents through its existing stored procedure and `sys.fn_get_audit_file` under its own permissions. Discovery credentials authorize only SMB enumeration.

## Required verification evidence

Controlled tests call discovery and control existing enumeration/native-process boundaries, not an invented adapter or only a parser. Use a common filename matrix for both routes and compare accepted basenames/GUID values separately from full-path assertions. Check result property names/types, duplicate-GUID files, metadata, directories, malformed names, nested roots, trailing separators, and empty outcomes.

Failures must produce terminating errors and zero success objects. Test both native error preference settings, missing prerequisites, unsupported OS, and Windows credential non-use. Inspect every stream and error details using recognizable test-only password sentinels. Cross the four credential exit conditions with prior credential state absent and present.

A separate Linux suite must invoke actual `smbclient` against populated, empty/rejected-only, and failing dedicated paths, observing credential state before/after. Controlled tests establish the invocation-exception case; real process tests must establish successful listing, successful no matches, and native failure. Record unavailable environments as unrun rather than passing. See [quickstart.md](../quickstart.md).
