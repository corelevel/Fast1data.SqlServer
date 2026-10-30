# Research: Unify Audit Discovery

**Date**: 2026-10-28 | **Feature**: [spec.md](spec.md)

## Evidence and scope

Reviewed `Get-SqlAuditFile.ps1`, `Invoke-Fast1Audit.ps1`, `Import-SqlAuditFile.ps1`, the module loader and manifest, `Audit.Tests.ps1`, `Fast1Audit.md`, and the active constitution. Two research agents investigated the discovery boundary and SMB/process verification. Findings below are design decisions, not implementation or runtime verification results.

## 1. Keep discovery and add one private listing seam

**Decision**: Retain `Get-SqlAuditFile -Folder [-Credential]`. Add `Get-SqlAuditFileEntry` in `Fast1data.SqlServer/private/audit/Get-SqlAuditFileEntry.ps1`. This private helper selects the platform, validates listing prerequisites, executes the existing transport, and returns file candidates with `Name` and `FullName`. Discovery applies the filename rule and produces existing result objects.

**Rationale**: The two existing listing routes justify the seam. `Invoke-Fast1Audit` already consumes discovery results and groups their GUIDs; the importer independently builds the SQL file pattern. The loader already discovers private scripts recursively, so no loader or export change is needed.

**Alternatives considered**: Generic filesystem interfaces, selectable adapters, a public parser, and moving listing into the importer add unnecessary contracts. Keeping both filename parsers retains the inconsistency risk.

## 2. One filename rule, one result projection

**Decision**: Keep the existing anchored audit-name/GUID/sequence/ticks grammar in `Get-SqlAuditFile` only. Interpret sequence and ticks as digit strings. Cast only the GUID. Return one `{ FileName, AuditGuid }` object per valid candidate without sorting or deduplication. Use the existing lowercase-extension baseline.

**Rationale**: Prefix underscores and spaces are already allowed by the grammar. Numeric conversion or timestamp validation could reject previously accepted files. Windows supplies its enumerated full path; Linux supplies the complete UNC path reconstructed from the requested root.

**Alternatives considered**: Splitting names on underscores breaks prefixes. GUID grouping belongs to the existing caller. Additional date, range, or ordering rules exceed the spec.

## 3. Normalize listing records before filename interpretation

**Decision**: Windows retains nonrecursive `Get-ChildItem -LiteralPath -File -ErrorAction Stop`. Linux uses nonrecursive `smbclient` command `ls`, with the share and optional `-D` directory supplied as separate arguments. Parse complete listing rows using their attributes, size, and timestamp boundary, preserving filename spaces and rejecting directories and non-row text. Neither route interprets audit filename components.

**Rationale**: Samba's client implementation defaults an omitted listing mask to `*` and propagates listing errors. A restrictive audit wildcard can therefore turn a no-match case into a process failure; this is an inference from the implementation, not an observed SMB run. Enumerating first avoids treating nonzero status as an empty result. The documented `-g` option applies to service enumeration with `-L`, not a structured file listing contract. The Windows cmdlet supports literal file enumeration. Sources: [Samba client source](https://raw.githubusercontent.com/samba-team/samba/master/source3/client/client.c), [smbclient manual](https://www.samba.org/samba/docs/current/man-html/smbclient.1.html), [Get-ChildItem reference](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-childitem?view=powershell-7.4).

**Alternatives considered**: Retaining `ls *.sqlaudit` and translating selected nonzero statuses to success risks concealing access failures. Splitting rows on whitespace loses spaces. Matching only a `.sqlaudit` substring can accept directory names or diagnostic text.

## 4. Complete enumeration before publishing results

**Decision**: Buffer the helper result before discovery projects any objects. Capture remote output and `$LASTEXITCODE` immediately after invocation, and reject every nonzero exit before interpreting rows. Locally set `$PSNativeCommandUseErrorActionPreference = $false` in the invocation helper so explicit exit handling works under either caller preference. Catch invocation exceptions and emit a sanitized terminating error.

**Rationale**: A failed listing must not expose apparent results or look empty. A local preference keeps error handling consistent without changing caller state. Microsoft documents the native-command preference and its scope in [about_Preference_Variables](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_preference_variables?view=powershell-7.4#psnativecommanduseerroractionpreference).

**Alternatives considered**: Streaming candidates permits partial output before an enumeration failure. Depending on inherited preferences produces inconsistent failure paths. Ignoring native exit status hides unprocessed audits.

## 5. Borrow process credentials and restore them exactly

**Decision**: Keep the existing `PASSWD` transport. Capture prior presence and value before assignment; restore that state in `finally`, removing the variable only when previously absent. The protected region surrounds assignment and invocation. Sanitize supplied passwords in captured diagnostics and exception messages before emitting new error records; do not attach an unsanitized original exception or forward native output to user streams. Never include passwords in process arguments.

**Rationale**: The current unconditional removal destroys a previous value. Samba supports environment authentication; PowerShell process environment values are inherited by child processes. See [smbclient authentication options](https://www.samba.org/samba/docs/current/man-html/smbclient.1.html) and [about_Environment_Variables](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_environment_variables?view=powershell-7.4). This design retains the existing single-operation process-state mechanism; concurrent credential-scoped discovery is outside scope.

**Alternatives considered**: Password arguments expose secrets. Credential files add a new secret lifecycle. Replacing native invocation with a new process wrapper is unnecessary for this focused change. Removing `PASSWD` unconditionally violates restoration requirements.

## 6. Verify at discovery and real process boundaries

**Decision**: Add controlled Pester coverage through `Get-SqlAuditFile`, mocking existing enumeration/process commands rather than the new listing helper. Use isolated module-scope platform state where required and restore it after each case. Add a separately tagged Linux SMB suite that calls the actual executable against dedicated populated, empty, and failing share paths. Cross the four credential exit conditions with absent and pre-existing `PASSWD`. Include sentinel-secret diagnostic and invocation-exception cases.

**Rationale**: The current two discovery tests cover only Windows local folders. Their source path casing also conflicts with Linux; normalize affected test paths and gate local-folder scenarios appropriately while preserving existing module and SQL text contract checks. Shared fixtures establish repeatable parity; actual SMB runs establish process behavior. Existing tests use Pester 5 constructs, so use Pester 5 for planned validation rather than the installed Pester 3.4.

**Alternatives considered**: Parser-only tests do not verify discovery. Mocking the entire helper bypasses transport interpretation. A memory-backed adapter cannot establish native invocation behavior. Requiring SQL Server for filename discovery adds an unrelated prerequisite.

## 7. Keep database access independent

**Decision**: Update `Fast1Audit.md` and affected help to explain Linux `smbclient`, supplied credentials, terminating listing errors, and the independent SQL Server service read permission. Preserve importer logic, schemas, checkpoints, manifest exports, dependencies, and the module-wide runtime/platform baseline.

**Rationale**: Discovery finds names; `sys.fn_get_audit_file` reads contents under SQL Server's own permissions. Nothing in this change grants those permissions.

**Alternatives considered**: Passing discovery credentials into import or redesigning SQL file access expands scope and changes security and database contracts.

## Resolution and verification status

All technical design questions are resolved above. Real SMB listing format, successful empty enumeration, argument handling, exit propagation, and credential restoration remain required implementation validation, not open design choices.

Planning host observations: Windows, PowerShell 7.6.6, Pester 3.4.0 available; Pester 5, the SqlServer module, bundled SQL client runtime assets, and `smbclient` were not found. No Linux/share/test-credential environment was supplied. No Pester, SMB, or SQL Server verification ran during planning. Unavailable runtime checks must remain explicitly unrun until the documented prerequisites are provided.
