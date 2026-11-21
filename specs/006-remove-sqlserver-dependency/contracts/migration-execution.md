# Migration Execution and Dependency Contracts

**Feature**: [../spec.md](../spec.md) | **Model**: [../data-model.md](../data-model.md)

## Public interface

`Invoke-Fast1Migration -ConnStr <string> -BasePath <string> -Phase <string> [-IgnoreScripts <string[]>] [-ForceScripts <string[]>] [-WhatIf] [-Confirm]`

Parameter names/types, confirmation support, configuration, three manifest exports, phase identity, warnings, verbose messages, and history schema remain compatible. The public owner validates history/files/configuration before confirmation and opens mutation resources only inside the confirmed eligible-work path. Preview can still read history; it executes no batches, writes no history, and creates no mutation command solely for unperformed work.

The public owner passes its original `ConnStr` directly to each executor invocation and lends only its history command to `Set-Executed`. The executor selects timeout `0` on its own command, preserving unbounded script execution. History retains its existing timeout without script/history timeout switching. No public parameter is added.

## Private script executor

`Invoke-Migration -ConnStr <string> -Script <string>`

The complete connection-creation algorithm and failure ordering are in [script-session.md](script-session.md).

- Both parameters are mandatory. FR-016 replaces the former `-SqlCmd` input with `-ConnStr`; no caller-created command or open connection is required.
- Reject missing/blank connection strings, then locally validate syntax/keywords/typed values using `SqlConnectionStringBuilder`, including for zero-batch files. Allocate no connection or command for this validation and preserve the original string for execution. Local validation does not establish login, reachability, or all provider option combinations; executable-path construction/open failures also terminate without SQL batches/history or secrets in added context. Authentication and target selection come from the supplied string, not an opened history connection.
- Read the complete script. Preflight all unsupported syntax and parse all source using `TSql160Parser($true)` before any execution. File read, lexical, unsupported-construct, and parse errors terminate.
- After successful validation, create the target connection directly from `ConnStr`, open it under the existing owned ambient-suppression scope, and create an executor-owned command with timeout `0`. No cloning, history-database snapshot, command borrowing, rebinding, or restoration is required. Do not allocate/open execution resources for zero-batch or rejected files and never fall back to history resources.
- Follow parser batch order and source spans. Execute each statement-bearing batch once on the same owned command/session using the original substring; use text mode and clear parameters for each operation. Send no empty command or row/result output.
- Every executable file gets its own logical connection lifecycle. Batches share that session; history and later files receive none of its session state. Provider pooling may reuse reset physical sessions. Explicit script transactions remain the author's responsibility; the executor has no caller-command transaction input.
- After executable batches, use the owned command for read-only `SELECT @@TRANCOUNT`; require zero outstanding transactions. Success requires the check and successful disposal of owned command, connection, and suppression scope in that order. Attempt every disposal even after failures, preserve the primary error, and write no history inside this helper. Zero-batch files need none of these resources or queries.

## Private history writer

`Set-Executed -SqlCmd <Microsoft.Data.SqlClient.SqlCommand> -ScriptName <string> -Phase <string> -Checksum <string> -ForceScript <bool> [-HistoryScriptName <string>]`

- `-SqlCmd` replaces mandatory `-ConnStr`; other private arguments and default `HistoryScriptName = ScriptName` remain.
- Require an existing open connection and preserve the supplied command's connection, timeout, and optional assigned transaction. Unlike the executor, this helper borrows all SQL resources and creates no separate connection.
- Replace text/parameters and use the existing insert or forced update statement. Bind `@script_name` and `@history_script_name` as NVarChar(255), `@phase` as NVarChar(32), and `@checksum` as Char(64). Values must never be interpolated into SQL.
- Insert new completion once. Forced reruns locate the original stored key and update normalized name, checksum, and database UTC time. A missing forced key is a terminating error.
- Do not allocate commands/connections, call a generic query path that allocates another command, introduce transactions, or dispose supplied resources. `Get-Executed` retains its current contract.

## Supported script language

Support ordinary T-SQL accepted by the requested TSql160 parser with initial quoted identifiers enabled, and standalone case-insensitive `GO` separators recognized by that parser. Preserve separator-like text in literals/comments, multiline constructs, batch-scoped definitions, temporary objects and session settings across batches. Explicit quoting/settings must remain compatible with parser validation and server semantics; no dialect negotiation is introduced.

Reject counted separators including `GO 1` and `GO 3`, SQLCMD directives (`:r`, `:setvar`, `:connect`, etc.), shell/utility directives, and `$(Name)` substitutions before executing any batch in the script. Substitution spelling is reserved even inside a SQL literal, identifier, or comment. A colon/directive-looking string inside a T-SQL literal/comment is otherwise ordinary text. Do not silently ignore, expand, or partially execute unsupported constructs.

Scripts remain executable administrator inputs and must be independently idempotent. Session continuity is guaranteed within each file's separate connection; script session state must not reach history or another file. A script's `USE` changes only its execution connection, so history stays on the original target without needing to restore its database. Authors must finish explicit transactions within the file; the executor rejects a nonzero final transaction count and never automatically commits them. No automatic phase transaction or rollback guarantee is added.

## Failure and completion

| Failure | Required result |
|---|---|
| Missing/corrupt parser dependency | Initialization terminates with dependency/RID/path and rebuild guidance |
| Missing/blank/malformed executor connection string | Terminate without script effects, history writes, or contextual secret disclosure |
| Missing/closed history command connection | History writer terminates before SQL, no replacement/open attempt |
| Separate script connection initialization/open failure | Terminate with safe operation context; attempt owned cleanup; no fallback or completion write |
| Owned execution command creation failure | No batches/history; attempt disposal of connection and suppression scope |
| Read/preflight/parse failure | No batch from that script; no successful history write; source location when available |
| Batch runtime failure | Stop remaining batches/scripts; no completion write; retain earlier committed effects |
| History failure after successful SQL | Stop before next script; report failure; SQL may already be committed |
| Failed forced execution | Leave previous successful row unchanged |
| Nonzero final transaction count or failed transaction check | Terminate without history/next script; dispose script resources without automatically committing |
| Cleanup failure with primary error | Attempt remaining cleanup and preserve primary error with attached cleanup details |
| Cleanup failure alone | Terminate after attempting all owned resources |

FR-016 supersedes the intermediate borrowed-command/clone design while retaining FR-015 session isolation. Use the original caller-supplied connection string to preserve its target/authentication/options; direct provider credential/token/callback properties are outside this input contract. Live authentication, pooling, ambient suppression, transaction completion, and command/connection/scope cleanup require validation under this new interface. Cleanup-only failure prevents history recording.

Diagnostics identify script and operation, one-based batch ordinal/source start for runtime failures, and original line/column for parse/preflight failures. Preserve the underlying error/exception as the cause. Context messages must not include connection strings, credentials, full SQL source, or parameter values. Do not wrap a provider exception in a message that copies its potentially sensitive text; keep the cause available programmatically.

## Assembly and distribution interface

- The complete FR-014 algorithm, compatibility policy, and fixture migration are in [required-library.md](required-library.md).
- Private loader: `Import-RequiredLibrary -DllName <string> [-RequiredTypeName <string[]>]`. `DllName` is a mandatory bundled managed DLL filename; resolve it within the selected distribution's current `lib/<rid>/` directory without a hardcoded library-name list or source/global fallback. Keep the function private and produce no success-stream output.
- Use the same function for `Microsoft.Data.SqlClient.dll`, `Microsoft.SqlServer.TransactSql.ScriptDom.dll`, and further bundled managed dependencies. The generic implementation already replaces `Import-SqlClientLib` and `Import-ScriptDomLib` and their bootstrap/fixture calls; retain it. Ordinary behavior files remain free of assembly loading.
- Validate the selected bundle file and its managed identity before loading or reusing an assembly. Reuse requires matching name, version, culture, and public-key token; validate all supplied `RequiredTypeName` values for both paths. SqlClient callers specify `Microsoft.Data.SqlClient.SqlConnection`; ScriptDom callers specify `Microsoft.SqlServer.TransactSql.ScriptDom.TSql160Parser`. Missing/corrupt/incompatible dependencies terminate with requested dependency, RID, expected bundle path, and rebuild guidance, preserving the underlying cause. A preload cannot conceal a missing/corrupt selected asset; cold loads must resolve from the selected bundle.
- Supported baseline stays PowerShell 7.6+ Core, .NET 10 dependency build, and x64 Windows/Linux/macOS.
- Deliver `Microsoft.Data.SqlClient.dll`, `Microsoft.SqlServer.TransactSql.ScriptDom.dll`, and required dependency/native/resource output in each existing `lib/<rid>/` folder. Validate both primary assemblies before accepting source and staged packages.
- Root explicitly initializes ScriptDom before migration behavior. Ordinary helpers do not import modules or load assemblies. Repeated initialization may reuse a compatible loaded assembly only when the required parser type is available.
- A fresh supported environment imports source root/manifest and staged manifest without SqlServer installed/discoverable. Exactly the existing three commands are exported. Faults do not leave usable partial operations.
- Public help, README, migration guidance, and release notes explain bundled dependencies, supported/unsupported syntax, private signature changes, partial commits, and idempotent recovery. Historical feature artifacts need not be rewritten.

## Acceptance mapping

| Requirements | Evidence |
|---|---|
| FR-001, FR-011, FR-012 | Cold source/package import without SqlServer; native RID checks; asset faults; manifest/help/docs review |
| FR-002, FR-003, FR-008, FR-009 | History command identity/settings/transaction preservation; original-string forwarding; independent executor command/connection ownership and cleanup |
| FR-004, FR-005, FR-013 | Boundary/quoted text/definitions/empty scripts; whole-file parse and unsupported preflight before effects |
| FR-006, FR-007 | Live later-batch and history failures, forced legacy-key updates, unchanged failed-rerun row, idempotent retry |
| FR-010 | Existing phase/path/checksum/force/ignore/preview/confirmation suites plus live execution order |
| FR-014 | One parameterized loader for both primary DLLs and another bundled managed DLL; repeated loads, required types, missing/corrupt/incompatible faults, source/staged provenance, unchanged bootstrap order and exports |
| FR-015, FR-016 | ConnStr-only invocation; malformed input rejected even for empty files without execution allocation; original target/authentication/options; separate script/history sessions; within-file continuity and between-file isolation; owned resource failures/cleanup; no opens for rejected/empty files |
