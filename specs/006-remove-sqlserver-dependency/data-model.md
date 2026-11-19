# Data Model: Migration Batch Execution

**Feature**: [spec.md](spec.md) | **Contract**: [contracts/migration-execution.md](contracts/migration-execution.md)

This feature adds transient execution and dependency-initialization state. It changes neither the history schema nor migration configuration. Fields below describe behavior and do not require new persisted classes or tables.

## Required library request and initialization

| Field | Source / validation |
|---|---|
| `DllName` | Caller-supplied single managed DLL filename; restrictions in [contracts/required-library.md](contracts/required-library.md) |
| `RequiredTypeName` | Optional fully qualified, case-sensitive type names; all must resolve from the chosen assembly |
| `DistributionRoot` | Derived from the defining loader; never inferred from the working directory or source fallback |
| `RuntimeIdentifier` | Existing runtime resolver: `win-x64`, `linux-x64`, or `osx-x64` |
| `ExpectedPath` | Absolute selected-distribution `lib/<rid>/<DllName>`; literal file in that bundle |
| `ExpectedIdentity` | Managed file metadata; simple name matches filename stem |
| `Assembly` | Compatible preloaded instance or assembly loaded from `ExpectedPath` |
| `ActualIdentity` | Name, version, culture, public-key token; must match `ExpectedIdentity` |
| `LoadDisposition` | Transient `Reused` or `Loaded`; internal observation, no success output |
| `Diagnostics` | Requested DLL, RID/path when available, rebuild guidance, and preserved underlying exception |

One root bootstrap makes two requests through the same function: SqlClient with `SqlConnection`, followed by ScriptDom with `TSql160Parser`. A request may require multiple types, all from its chosen assembly. Other bundled managed DLLs use the same contract without adding a loader or name-list entry.

```text
Validate arguments -> Resolve selected distribution/RID/path
  -> Validate bundled file and managed identity on every call
       -> Matching loaded assembly: verify exact identity, reuse instance
       -> No matching loaded assembly: load expected path, verify identity/location
       -> Verify every required type -> Ready, no output
  -> Any failure: terminate initialization before usable public exports
```

Missing/corrupt selected assets fail even when a matching assembly is already loaded. A compatible preload may originate elsewhere, provided the selected asset remains valid; cold loads require selected-bundle provenance. Failure does not unload process-wide assemblies or create a reusable success cache. Recheck the bundle and types on subsequent calls; restart the process after correcting an incompatible load. No dependency state is persisted to SQL or disk.

## Migration script

| Field | Source / rule |
|---|---|
| `FullPath` | Existing phase evaluation; literal contained file path |
| `ScriptName` | Existing normalized phase-relative identity with `/` separators |
| `Phase` | Literal configured phase name |
| `Checksum` | Existing SHA-256 over file bytes, represented by 64 characters |
| `HistoryScriptName` | Exact stored key retained for a forced update |
| `IsForced`, `WasExecuted` | Existing evaluation flags; update only when both are true |
| `SourceText` | Complete file contents read for this attempt; transient |
| `Batches` | Ordered parser batches with statements; zero or more |
| `ParseDiagnostics` | Original script coordinates and parser error identifiers; fatal if nonempty |

Identity, ignore/force conflicts, lexical containment, file existence, and checksum drift retain existing pre-execution validation. Source parsing is an execution-time validation of each selected script; preview retains existing phase reads/reports and does not promise SQL syntax validation. File/history validation remains a snapshot without locking or a new race-prevention guarantee.

## Migration batch

| Field | Meaning / validation |
|---|---|
| `Ordinal` | One-based executable-batch order within the script |
| `StartOffset`, `FragmentLength` | Valid in-range span from ScriptDom into the original source |
| `StartLine`, `StartColumn` | Original source coordinates for diagnostics |
| `Statements` | Parser AST statements; empty collection means no database execution |
| `CommandText` | Original substring; excludes separator tokens and preserves statement text |

A script has zero or more executable batches. Batches use one executor-owned command and session for that file and execute sequentially once. Empty/comment-only scripts are successful zero-batch executions, open no script connection, and remain eligible for one completion record. A parser error or unsupported construct anywhere prevents all batches and script connection creation for that file.

## History resources and owned script execution context

| Field | Ownership / rule |
|---|---|
| `ConnStr` | Original caller-supplied string; forwarded unchanged to the executor, never included in contextual diagnostics |
| `ConnectionStringValidation` | Nonblank check and local SqlConnectionStringBuilder syntax/keyword/typed-value validation before zero-batch return; no execution connection/command or authentication probe |
| `SqlCmd` | Caller/public-owned history command supplied only to Set-Executed |
| `HistoryConnection` | Existing open connection used only for history, not borrowed by the executor |
| `ExecutionConnection` | New target SqlConnection initialized from ConnStr and opened/disposed inside Invoke-Migration for one executable file |
| `ExecutionCommand` | Executor-created command reused across all file batches and final transaction check; disposed before its connection |
| `TargetServer`, `TargetDatabase` | Target configured by ConnStr, including its configured/default catalog behavior; no history-current-database snapshot |
| `AuthenticationConfiguration` | Connection-string authentication/options supplied by caller; no clone of external credential/token objects |
| `SuppressionScope` | Owned ambient suppression through script open/execution/SQL cleanup; disposed to restore ambient context |
| `CommandTimeout` | Execution command uses 0; history command retains its supplied value without switching |
| `Transaction` | History writer preserves its assigned transaction; executor has no borrowed-command transaction input |
| `CommandType` | Text for each operation |
| `CommandText`, `Parameters` | Operation-specific; clear stale parameters before use |
| `PrimaryError` | First terminating operation failure, preserved across all owned cleanup attempts |
| `FinalTransactionCount` | SELECT @@TRANCOUNT after executable batches on their owned command/session; must be zero |

The public command owns history resources after confirmation. The executor separately owns its connection, command, and suppression scope and receives only ConnStr and Script. It does not clone, rebind, restore, or dispose history resources. Get-Executed owns its existing independent read resources. Empty/rejected files allocate no execution SQL resources. Local connection-string validation does not replace the original string or establish login/reachability; remaining provider construction/open validation applies to executable files.

All batches and final transaction validation in one file share its owned session. History and later files receive none of that session's state; pooled physical sessions may be reused after reset. Script ambient suppression and history transaction support remain unchanged. See [contracts/script-session.md](contracts/script-session.md). FR-016 supersedes the intermediate borrowed-command FR-015 model.

## Execution history entry

Existing `dbo.fast1_migration_history`:

| Column | SQL type | Rule |
|---|---|---|
| `phase` | `nvarchar(32)` | Composite primary key with script name |
| `script_name` | `nvarchar(255)` | Normalized current name; forced lookup uses original persisted key |
| `checksum` | `char(64)` | Successful script's SHA-256 |
| `executed_at` | `datetime2(7)` | Database `sysutcdatetime()` default on insert; refreshed on forced update |

One record denotes completion of the whole script. All values remain typed SQL parameters. A forced update matching no original key terminates. Failed batches, outstanding explicit transactions, failed completion checks, and owned-cleanup failures never invoke history writing and leave any previous successful row unchanged. A failed history statement must not be reported as completion.

## State transitions

```text
Read history -> Evaluate entire phase
  -> Invalid / preview / declined / no eligible work: no execution resources
  -> Confirmed: public owner opens history resources
       -> Invoke-Migration with original ConnStr and Script
            -> Validate nonblank ConnStr and local syntax/keywords/typed values
            -> Read/preflight/parse/validate all spans
            -> Failure: no execution resources/history/later script
            -> Zero batches: succeed without execution allocation
            -> Executable batches: suppress ambient -> create/open connection from ConnStr
                 -> Create owned command with timeout 0
                 -> Execute batches 1 ... N -> Require final @@TRANCOUNT = 0
                 -> Dispose command -> connection -> suppression scope on all exits
                 -> Any failure: preserve primary error; no history/next file
       -> Success: Set-Executed with public-owned history SqlCmd
       -> Dispose public-owned history command then connection on every exit
```

Cleanup attempts every owned command, connection, and suppression-scope disposal even when an earlier attempt fails. Attach later failures to the primary error; when no operation failed, the first cleanup failure becomes primary after all attempts. There is no borrowed executor command to restore. Neither execution nor history introduces an implicit phase transaction: authors must finish explicit script transactions, and prior commits can survive failure, so retries require idempotent scripts.
