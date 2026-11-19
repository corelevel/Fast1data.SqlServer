# Research: Remove the SqlServer Module Dependency

**Date**: 2026-11-19 | **Feature**: [spec.md](spec.md)

Original research combined repository inspection, delegated investigations, official documentation/source, and a read-only local parser probe. Subsequent research covered FR-014 generic loading and the earlier FR-015 clone-based executor, including offline cloning probes. This planning refresh uses two delegated read-only investigations to reconcile current code/tasks/evidence with FR-016 and resolve local connection-string validation. [validation.md](validation.md) records implemented generic-loader and earlier executor results plus their live/native limits. Historical clone/restoration results do not establish the pending ConnStr interface.

## 1. Parse the whole script and execute original batches

**Decision**: Construct `Microsoft.SqlServer.TransactSql.ScriptDom.TSql160Parser` with initial quoted identifiers enabled. Parse the complete file through a disposed `StringReader`; treat every parse error as fatal even if a partial AST is returned. Enumerate `TSqlScript.Batches` in source order, skipping batches with no statements. Execute `source.Substring(batch.StartOffset, batch.FragmentLength)` rather than regenerating SQL. Use original parser line/column and a one-based executable-batch ordinal in diagnostics.

**Rationale**: Parser-defined spans retain multiline statements, definitions, internal comments, and quoted separator text. Full parsing prevents a syntax error in a later batch from allowing earlier batches to run. Original slices preserve execution semantics and allow mapping a provider's batch-relative line back to the file. Comments outside a statement-bearing fragment need not be sent to SQL Server.

**Alternatives considered**: Regex splitting misidentifies quoted/commented separators; splitting statements breaks batch-scoped definitions; AST generation unnecessarily reformats source; execution while incrementally parsing permits partial mutation on later syntax errors.

**Sources**: [Parse API](https://learn.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.transactsql.scriptdom.tsqlparser.parse?view=sql-transactsql-161), [TSqlBatch spans and statements](https://learn.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.transactsql.scriptdom.tsqlbatch?view=sql-transactsql-161), [parser constructor](https://learn.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.transactsql.scriptdom.tsql160parser.-ctor?view=sql-transactsql-161).

**Boundary**: This is the TSql160 dialect with initial `QUOTED_IDENTIFIER ON`. The [official grammar](https://github.com/microsoft/SqlScriptDOM/blob/main/SqlScriptDom/Parser/TSql/TSql160.g) resets parsing mode at `GO`; it does not model arbitrary database session settings. Execute original text so accepted SQL retains server semantics. Cover explicit `SET QUOTED_IDENTIFIER` across batches in live tests, document that scripts must parse under the selected dialect, and do not promise additional dialects or server-setting discovery.

## 2. Reject unsupported preprocessing before any batch

**Decision**: Perform a complete preflight before execution in addition to parsing. Use lexical context and original coordinates to identify line-leading SQLCMD directives/utility commands outside T-SQL strings and comments, and counts following genuine `GO` separator tokens. Reject substitution forms `$(Name)` wherever present, including SQL string/identifier/comment contents; these spellings are reserved unsupported authoring syntax. Do not expand variables, include files, repeat batches, or invoke utilities. Return an unsupported-construct diagnostic with location before considering executable batches.

**Rationale**: A local probe shows `SELECT '$(Name)';` has zero parse errors: ordinary parsing cannot reject variable substitution inside a SQL string. `GO 3` produces a parse error and partial AST; the partial AST must never execute. Directive detection must preserve lexical context so `':r file.sql'` and comments mentioning directives remain ordinary SQL text. Substitution syntax is reserved even in otherwise valid text to prevent accidental execution of unexpanded inputs. Tokenization errors also prohibit execution; a directive diagnostic should identify the construct rather than expose source text.

**Alternatives considered**: Relying on parser errors misses substitutions; raw line matching falsely rejects directives inside multiline literals/comments; supporting partial SQLCMD behavior creates an undocumented preprocessing language. The preflight is a project design inferred from source/token APIs, not a built-in ScriptDom guarantee.

**Sources**: [ScriptDom token kinds](https://learn.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.transactsql.scriptdom.tsqltokentype?view=sql-transactsql-161), [GO and repeat counts](https://learn.microsoft.com/en-us/sql/t-sql/language-elements/sql-server-utilities-statements-go), [SQLCMD commands](https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-commands).

## 3. Separate executor and history input/ownership (FR-016)

**Current decision (2026-11-19)**: Invoke-Migration takes ConnStr and Script and creates/opens/disposes its own connection and command. Set-Executed alone retains SqlCmd and borrowed connection/timeout/transaction semantics. Read/preflight/parse the whole file before allocating script resources; zero-batch files allocate none. Target/authentication/options come from the original supplied string, not an opened history connection or cloned credential/token properties.

**Supersession**: The latest user requirement replaces executor command borrowing, cloning, temporary rebinding/restoration, and assigned-command-transaction rejection. Preserve same-session batches, ambient suppression, unbounded script timeout, final transaction validation, history isolation, and cleanup/error barriers. This decision adds no new provider factual claim or runtime evidence. T056-T058 remain pending.

**Validation decision**: Explicitly reject null/empty/whitespace ConnStr, then locally validate syntax, keywords, and typed values with `SqlConnectionStringBuilder` before the zero-batch return. Do not reconstruct the execution string from the builder. Empty files cannot bypass malformed-input validation, and validation creates no execution connection/command. This does not establish login, reachability, or all provider option combinations; executable files still handle constructor/open failures. Preserve provider causes without copying their messages into diagnostic context.

**Rationale**: Local validation resolves the apparent conflict between rejecting malformed input and allocating no SQL execution resources for zero-batch/rejected files. The existing public caller already uses the builder; no dependency or public interface is added.

**Alternatives considered**: Skipping validation for empty files accepts malformed inputs; opening a connection solely to validate them violates zero-resource behavior; round-tripping the builder unnecessarily replaces the original string.

**Sources**: [SqlClient 7.1.2 builder implementation](https://github.com/dotnet/SqlClient/blob/v7.1.2/src/Microsoft.Data.SqlClient/src/Microsoft/Data/SqlClient/SqlConnectionStringBuilder.cs), [connection constructor validation](https://learn.microsoft.com/en-us/dotnet/api/microsoft.data.sqlclient.sqlconnection.-ctor?view=sqlclient-dotnet-7.1). Applying local validation before the empty-file return is a project design choice, not proof that the target accepts the connection.

## 4. Keep public validation, completion and recovery semantics

**Current decision (FR-016)**: Keep history read/phase evaluation before confirmation. Public ownership covers history only; forward original ConnStr to each executor, which owns its connection/command/suppression scope. Select timeout 0 inside the executor; leave history timeout unchanged. History follows successful batches, final transaction check, and ordered command/connection/scope cleanup. Use existing cleanup and preserve the primary error.

**Rationale**: Temporary objects and session settings survive `GO` within a script's dedicated session. Script `USE` and settings cannot redirect or change history because that connection is never used to execute batches. This supersedes the previous public database-restoration workaround. Phase validation/preview, forced keys, normalized names, SHA-256, UTC timestamps, and idempotent retry semantics remain unchanged. ConnStr-only target/authentication, owned-command/connection/scope cleanup, and public integration acceptance are pending T056-T058 and applicable live/native obligations; prior interfaces do not establish them.

**Alternatives considered**: One connection per batch loses session state. A new phase-wide transaction changes committed-work/retry behavior. Persisting a cross-file session contract adds an unsupported guarantee. Retrying automatically can repeat committed effects.

**Timeout policy (FR-016)**: Retain unbounded script execution by selecting CommandTimeout 0 on the newly owned execution command. Set-Executed preserves its supplied history timeout. The old public script/history timeout switching is superseded. No public timeout parameter is added.

**Recovery**: SQL and history remain separate completion steps. Earlier batches may have committed when a later one fails; history itself can fail after successful SQL. Scripts remain administrator inputs and must be idempotent. Scripts controlling transactions are responsible for their explicit transaction lifecycle; the runner adds no implicit transaction.

## 5. Supply ScriptDom through the existing loaders and packages

**Decision (updated for FR-014, 2026-11-19)**: Preserve the user's `net10.0` project and package edits (SqlClient 7.1.2, ScriptDom 180.154.0, Pkcs 11.0.0). Validate the entire resolved graph. The existing `dotnet publish` loop and recursive library copy already deliver dependency output for all three RIDs. Add required SqlClient and ScriptDom asset assertions in build and source/staged release validation. Replace the separate SqlClient and ScriptDom loader implementations with `private/shared/Import-RequiredLibrary.ps1`, accepting a DLL filename and optional required-type names. Explicit bootstrap calls select each library before dependent behavior. Remove `SqlServer` from manifest prerequisites.

**Rationale**: ScriptDom delivery uses the existing package project and root bootstrap. The implemented generic function centralizes runtime selection, assembly reuse, type validation, and actionable failure handling while allowing callers to initialize only the library they need. Check requested types for both reused and newly loaded assemblies. Missing/corrupt/incompatible assemblies must fail with dependency/RID/path context and rebuild guidance; ordinary behavior files remain free of dependency-loading side effects. FR-014 now has recorded source/staged/offline evidence; native/live limits remain in `validation.md`.

**Alternatives considered**: Relying on another installed module to preload ScriptDom recreates the removed prerequisite. Manifest assembly loading lacks the current RID selection/bootstrap controls. Loading the parser inside `Invoke-Migration` breaks established loader ownership.

**Sources**: [ScriptDom 180.154.0](https://www.nuget.org/packages/Microsoft.SqlServer.TransactSql.ScriptDom/180.154.0), [SqlClient 7.1.2](https://www.nuget.org/packages/Microsoft.Data.SqlClient/7.1.2), [Pkcs 11.0.0](https://www.nuget.org/packages/System.Security.Cryptography.Pkcs/11.0.0), [dotnet publish](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-publish), [module manifest prerequisites](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_module_manifests).

## 6. Verification boundaries and governance

**Decision**: Retain offline phase/preview tests and public resource-owner coverage, and verify real command identity/settings/session/history against an explicitly selected SQL Server. The migration integration suite now uses `FAST1_TEST_SQL_CONNECTION_STRING` and skips when absent; it creates/drops uniquely named disposable databases. Keep case-sensitive history coverage. Native host execution is required in addition to cross-publishing. Actual results and unavailable checks remain in `validation.md`.

**Rationale**: Mocks do not establish provider/session behavior. Current loader tests assert the actual 23-file private inventory and parameter-aware generic bootstrap tracing, fresh-process faults, and assembly provenance. Retain these regressions. The default `out/publish.ps1` runs every integration suite; its existing `-StageOnly` option stages/analyzes without claiming release-suite completion. Exclude `*.Integration.*` filenames for the documented offline run. Do not expand existing analyzer suppressions to bypass new findings.

**Alternatives considered**: All-mock SQL acceptance, treating cross-build as runtime proof, and treating a bundled DLL's presence as working dependency delivery provide insufficient evidence.

**Governance decision**: Use the already applied constitution 1.1.0 and approved module 0.1.0 release decision recorded in `validation.md`. The previous adoption gate is resolved. This refresh changes planning Markdown only and does not amend governance, production code, task completion, or historical test evidence.

## 7. Generic library input, bundle validation, and reuse

**Decision**: Adopt the precise algorithm in [contracts/required-library.md](contracts/required-library.md). Accept a DLL filename rather than a path; resolve the defining loader's selected distribution and current RID. Validate the selected file and inspect its managed identity before reuse or load. Require the identity's simple name to match the filename stem. A compatible loaded assembly must match the selected asset's name, version, culture, and public-key token and provide all caller-requested types. Reject conflicting same-name preloads rather than loading another copy. A cold load must resolve to the selected bundle. Produce no success output.

**Rationale**: The generic name parameter must not permit path escape or accidentally accept a renamed unrelated managed DLL. Inspecting bundle metadata on each call prevents a compatible preload from hiding missing/corrupt selected-package assets. Required types validate the actual chosen assembly on both paths. Exact identity matching is the chosen project compatibility policy, not a .NET guarantee of behavioral equivalence. No package-version upgrade or automatic roll-forward is introduced.

**Alternatives considered**: A library-name allowlist prevents the requested extension to other managed DLLs. Reuse based only on a simple name can hide version/type conflicts. Returning before bundle validation preserves the old rename-after-load fixture but permits broken packages to appear usable in a warm process. Searching source/global locations or introducing a custom load context changes existing bootstrap ownership without a demonstrated need. Restoring separate wrappers leaves duplicated loading entry points.

**Sources**: [.NET file identity inspection](https://learn.microsoft.com/en-us/dotnet/api/system.reflection.assemblyname.getassemblyname?view=net-10.0), [load from a selected path](https://learn.microsoft.com/en-us/dotnet/api/system.reflection.assembly.loadfrom?view=net-10.0), [type lookup on an assembly](https://learn.microsoft.com/en-us/dotnet/api/system.reflection.assembly.gettype?view=net-10.0). The validation order, exact identity policy, filename restrictions, and no-fallback rule are project design decisions using these APIs.

## 8. Generic loader integration and verification

**Decision**: Replace both specific loader files with `Import-RequiredLibrary.ps1`; root defines it once and explicitly calls it for SqlClient then ScriptDom before behavior. Callers supply `SqlConnection` and `TSql160Parser` as required types. Migrate all fixture bootstrap calls, inventory ownership assertions, root-private-function assertions, and trace instrumentation. Validate `Microsoft.SqlServer.Server.dll` with `Microsoft.SqlServer.Server.SqlFunctionAttribute` as the third existing bundled managed library, without adding a production initialization call.

**Rationale**: Repository inspection found library-specific calls in the root module and the module-loader/shared-helper fixtures. Bare-call tracing cannot distinguish parameterized calls until updated. The third DLL already exists in the RID output and demonstrates extensibility without another package. Its required type was confirmed by the delegated read-only reflection probe. Selected-distribution provenance remains tied to the defining loader, independent of the working directory.

**Alternatives considered**: Checking only the two known names would not prove FR-014 extensibility. Keeping the old rename-after-load reuse success case contradicts selected-bundle validation; replace it with intact-bundle identity reuse and separate warm missing/corrupt failures. Cold fault tests alone cannot establish warm validation. Old library-specific test counts cannot substitute for generic-loader acceptance.

**Validation design**: Use fresh source/staged processes and marked disposable copies for faults. Exercise both primary DLLs and the third DLL, repeated identity reuse without output, required-type success/failure on new and reused assemblies, invalid filenames, wrong managed identity, incompatible preloads, cold/warm bundle faults, and unchanged bootstrap order/exports. See `quickstart.md` for runnable smoke commands and the full matrix. T041-T043/T051/T053 are checked with recorded results in `validation.md`; preserve that implementation and rerun affected regressions after FR-016 changes.

## 9. Historical clone research (superseded by FR-016)

The following decisions, sources, and probes describe the prior borrowed-command interface only. They do not impose cloning, current-history-database selection, credential/token copying, or command-restoration requirements on the new ConnStr interface.

**Decision**: After validating the original command, rejecting an assigned transaction, and validating every batch span, return for zero-batch scripts. Otherwise capture the original connection/current database and create a closed copy through `([System.ICloneable]$originalConnection).Clone()`. Keep the clone's connection string unchanged. Open it inside an executor-owned `TransactionScope` with `TransactionScopeOption.Suppress`; keep that scope through execution and connection cleanup, then dispose it before returning. If needed, call `ChangeDatabase` on the opened clone with the captured current database before binding the borrowed command. Never fall back to the original connection if initialization fails.

**Rationale**: Version-pinned SqlClient 7.1.2 source copies its private connection configuration, credentials, access token, token callback, and SSPI provider into a closed clone. The original open connection reports its current database, while the clone starts from its configured catalog. These provider facts support cloning plus post-open database selection. They do not prove a login will succeed or a token is still valid. [Provider clone/copy/database implementation](https://github.com/dotnet/SqlClient/blob/v7.1.2/src/Microsoft.Data.SqlClient/src/Microsoft/Data/SqlClient/SqlConnection.cs)

An opened connection's public connection-string getter can omit security information; reconstructing from it can lose reusable credentials. Do not set `Persist Security Info=True`, extract private fields, or reassign a redacted string. [Connection-string security behavior](https://learn.microsoft.com/en-us/dotnet/api/microsoft.data.sqlclient.sqlconnection.connectionstring?view=sqlclient-dotnet-7.1)

Opening a connection can automatically enlist in the ambient transaction. Suppression keeps script execution independent without changing cloned authentication options or the history writer's transaction contract. This is the chosen project policy for satisfying per-file isolation, not a new transaction spanning the phase. [SqlClient ambient enlistment](https://learn.microsoft.com/en-us/sql/connect/ado-net/distributed-transactions?view=sql-server-ver17), [Suppress scope behavior](https://learn.microsoft.com/en-us/dotnet/api/system.transactions.transactionscopeoption?view=net-10.0)

**Alternatives considered**: Constructing from `original.ConnectionString` can lose credentials/tokens. Rewriting the clone through a connection-string builder can reintroduce the same problem. Sharing the original session violates FR-015. Clearing or moving the caller's transaction violates ownership. Rejecting every ambient scope would unnecessarily restrict callers; suppress only the executor-owned path. One new command per file violates the supplied-command requirement.

**Offline evidence**: The bundled Windows assembly reports ProductVersion `7.1.2+b1dd9db72cd9e6eb9fc83ca308558e73b57dd449`. Delegated synthetic probes confirmed direct PowerShell clone invocation, a distinct closed object, SQL-password option preservation, copied `SqlCredential`, access-token preservation, and token-callback delegate reuse. The probes opened zero SQL connections and printed no credentials. Source inspection establishes private-option copying; an opened/redacted SQL-password login and each deployed authentication mode still require environment-specific live validation.

**Pooling decision**: Preserve provider pooling. A new logical connection per file does not require a unique physical connection or SPID across successive files. Verify script/history separation while both are open, within-file continuity, and reset database/temporary-object/session-setting state across files. Durable database effects intentionally persist; the isolation promise concerns session state. [SqlClient pooling and reuse](https://learn.microsoft.com/en-us/sql/connect/ado-net/sql-server-connection-pooling?view=sql-server-ver17)

## 10. Historical completion design (ownership superseded by FR-016)

Retain final transaction validation, ambient suppression, primary-error preservation, and successful cleanup as completion barriers. Replace borrowed-command restoration below with disposal of the executor's own command, then connection, then scope. The former restoration tests are historical; T056-T058 define current acceptance.

**Decision**: After all executable batches succeed, reuse the same command for one read-only `SELECT @@TRANCOUNT` check. A nonzero count or failed check terminates the file without history. Require scripts to finish their explicit transactions; never commit an unfinished transaction on their behalf. Then restore the original command connection, dispose the execution connection, and dispose the suppression scope. Only complete cleanup permits the public owner to write history.

**Rationale**: Closing/disposing a connection can roll back pending transactions. Recording success after that rollback would misrepresent completed work. The final check enforces the spec's explicit-transaction authoring responsibility and the constitution's completed-work rule. It adds no implicit transaction or automatic rollback guarantee for already committed batches. [Connection close/disposal transaction behavior](https://learn.microsoft.com/en-us/dotnet/api/microsoft.data.sqlclient.sqlconnection.close?view=sqlclient-dotnet-7.1), [transaction-count semantics](https://learn.microsoft.com/en-us/sql/t-sql/functions/trancount-transact-sql?view=sql-server-ver17)

**Failure policy**: Capture the first operation error. Attempt command restoration in its own guarded step; if it fails, attach it to that error or make restoration the primary error when no earlier failure exists. Always attempt execution-connection disposal even when restoration fails, followed by suppression-scope disposal. Use `Add-GenericSqlCleanupFailure` for restoration metadata and `Close-GenericSqlResource` for owned disposals with the current primary error. If cleanup alone fails, propagate it after attempting all owned cleanup. Do not dispose the borrowed command or original connection. A restoration failure cannot be reported as restored/reusable success; terminate without history or later scripts and preserve its details for the caller.

**Alternatives considered**: Assuming batch success is sufficient can record work rolled back during disposal. Automatically committing author transactions changes script meaning. Performing restoration unguarded in `finally` can mask the SQL error and skip connection disposal. The existing disposal helper alone cannot restore a command reference. Requiring different SPIDs for every file tests physical pooling behavior rather than the specified isolation.

**Validation design**: Extend T044-T046 coverage for target selection after the original connection changes database, authentication configurations, ambient suppression/restoration, cloning/open/target-selection/binding failures, a final unfinished transaction and failed postflight check, restoration-only/disposal-only failures, and combined execution/restoration/disposal failures. Assert zero history/next-file execution for each executor failure. Keep current task checkboxes and prior results historical; this research does not execute migration SQL.

## Planning observations

- Git branch is `dev`; setup selects feature directory `006-remove-sqlserver-dependency`.
- The pre-existing edited `build/SqlClientLoader.csproj` remains untouched.
- Original ScriptDom probe: a quoted `GO` creates no false boundary; comments/empty batches produce no executable AST batch; `GO 3` fails at its count; quoted substitution parses successfully; a cross-batch `SET QUOTED_IDENTIFIER OFF` example parses successfully. This refresh did not repeat those probes.
- Prior host inspection found PowerShell 7.6.10, .NET 10.0.15, Pester 6.2.0, PSScriptAnalyzer 1.25.0. This review performed no dependency restore/build, Pester run, SQL connection open/mutation, or cross-platform validation.
- Current repository inspection confirms the executor/caller/tests still use the earlier SqlCmd/clone/restoration interface; FR-016 remains pending T056-T058. The generic loader and earlier isolation work are implemented with recorded evidence, not new results from this refresh.
- No technical clarification or governance adoption gate remains. ConnStr executor implementation/acceptance, applicable live authentication/SQL evidence, and outstanding release/native-platform checks remain obligations, not unknown design choices.
