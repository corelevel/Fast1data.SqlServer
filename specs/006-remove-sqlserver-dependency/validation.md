# Implementation validation: Remove the SqlServer module dependency

Evidence date: 2026-11-19 (Europe/Bucharest). Feature: `006-remove-sqlserver-dependency`.

Task IDs before the "Current implementation run" section refer to the previous task sequence. Current IDs refer to [tasks.md](tasks.md); its "Previous task ID mapping" relates carried-forward obligations to the current checklist. Earlier results and completion counts retain their historical scope.

## Baseline (T001)

- Branch: `dev`; repository root: `C:\Dev\Fast1data.SqlServer`.
- Initial Git status: modified `build/SqlClientLoader.csproj`; untracked `specs/006-remove-sqlserver-dependency/`. These pre-existing changes are preserved.
- Dependency project inspected without modification: target `net10.0`, Microsoft.Data.SqlClient `7.1.2`, Microsoft.SqlServer.TransactSql.ScriptDom `180.154.0`, System.Security.Cryptography.Pkcs `11.0.0`. Package references alone do not establish restore, delivery, or runtime compatibility.
- Host: Windows 10.0.26300, x64; PowerShell Core 7.6.10; runtime .NET 10.0.15; selected .NET SDK 11.0.100.
- Available validation tools: Pester 6.2.0; PSScriptAnalyzer 1.25.0. No project analyzer settings found.
- SqlServer 22.4.5.1 is discoverable on this host. Cold acceptance will require isolated module paths so this installation cannot satisfy imports.
- `FAST1_TEST_MIGRATION_SQL_CONN_STR` is absent. No SQL integration suite has been run; no implicit database target is authorized by this record.
- Requirements checklist: 16 total, 16 checked, 0 unchecked; PASS. Checklist markers were not changed.
- No `.specify/extensions.yml` exists; no pre-implementation hooks are registered.
- Git ignore rules already cover generated build outputs, module dependency bundles, staged distribution, and universal temporary/editor artifacts. `.vscode/` remains available for VS Code Tasks. No Docker, Node, Terraform, Helm, ESLint, or Prettier setup was detected.

## Adoption decision (T002)

Maintainer explicitly selected “Approve amendment and both proposed versions” on
2026-11-19. Approved constitution: `1.1.0`; approved module release: `0.1.0`.
Applied the exact stack amendment to the constitution, retaining its original
ratification text and using 2026-11-19 as the amendment date.

Concrete proposal in `plan.md`: constitution `1.1.0`, module `0.1.0`, replacing the first Database and Runtime Constraints bullet with:

> PowerShell orchestration, Microsoft.Data.SqlClient, Microsoft.SqlServer.TransactSql.ScriptDom, and versioned SQL setup scripts form the supported implementation stack. Required client and parser assemblies MUST be bundled for each supported runtime and initialized through designated loaders; a separate SqlServer PowerShell module installation is not required.

Rationale: replace migration's Invoke-Sqlcmd dependency with the requested parser and direct execution. Contracts affected: installation, script syntax, private helper signatures, dependency loading/building. Transition: rebuild every supported RID bundle, update manifest/help/guides, reject unsupported SQLCMD syntax before effects, retain idempotent retry requirements. No history schema upgrade is required. Original constitution ratification text was retained; approved versions and adoption date are recorded above.

## Migration identity inspection (T003)

Read `Resolve-MigrationPhase.ps1` and `Migration.Phase.Tests.ps1`. Existing contract to preserve:

| Field | Contract |
|---|---|
| FullPath | Existing phase evaluation; literal contained file path |
| ScriptName | Existing normalized phase-relative identity with `/` separators |
| Phase | Literal configured phase name |
| Checksum | Existing SHA-256 over file bytes, represented by 64 characters |
| HistoryScriptName | Exact stored key retained for a forced update |
| IsForced, WasExecuted | Existing evaluation flags; update only when both are true |

Keep containment, duplicate/conflict, checksum, case/separator, ignore/force, warning, and ordering regressions. No configuration or schema migration.

## Build and dependency evidence

`build/build.ps1` completed successfully for all three RIDs using SDK 11.0.100 and
the preserved `net10.0` project. The first sandbox attempt was blocked by .NET
first-run profile writes; the approved escalated build succeeded. Both published
and copied bundles now require both primary assemblies before accepting output.
Cleanup resolves and validates the exact library target before recursive removal.

Inspected each published `SqlClientLoader.deps.json` and the final restore graph:
SqlClient **7.1.2**, ScriptDom **180.154.0**, Pkcs **11.0.0** in every target.
These are resolved package versions, not merely project references.

| RID | Runtime target | Resolved libraries (including project) | Recursively copied files |
|---|---|---:|---:|
| win-x64 | .NETCoreApp v10.0 / win-x64 | 27 | 56 |
| linux-x64 | .NETCoreApp v10.0 / linux-x64 | 26 | 54 |
| osx-x64 | .NETCoreApp v10.0 / osx-x64 | 26 | 54 |

Both primary DLLs exist in all source and staged RID folders. Compared every
source dependency file to its staged counterpart by SHA-256: zero mismatches.
The recursive copy retains transitive, native and satellite resource output.
Cross-publishing does not establish Linux/macOS native execution or live SQL compatibility.

## Regression execution evidence

- Before implementation, the new loader inventory check failed because root did
  not select ScriptDom; the 21 new execution/preflight tests failed against the old
  `ConnStr` signature. The private command suite then exposed six failures against
  the old history helper. These were actual contract failures, separate from tool
  availability failures.
- Source loader suite: **51 passed, 0 failed**. Workers use fresh processes with
  `PSModulePath` restricted to PowerShell's built-in modules and verify SqlServer is
  not discoverable. Source root/manifest imports retain exactly the three public
  exports. Trace checks put parser bootstrap before migration behavior. Tests cover
  compatible preloads/repeated loader calls, missing/corrupt/incompatible parser
  assets, required parser type, actionable RID/path/rebuild diagnostics, and absence
  of usable public commands after initialization failure.
- Execution/preflight: **21 passed**. Real provider objects with intercepted
  execution verify original batch text/order, no empty calls, whole-file rejection,
  reserved substitutions in every lexical context, harmless quoted/commented
  directive mentions, source coordinates, safe contextual messages and causes.
  Intercepted execution is not SQL/session/transaction acceptance.
- Private command contracts: **10 passed**; public migration orchestration:
  **41 passed**; cleanup suite: **32 passed**. These cover typed signatures,
  invalid/closed connections, typed parameters, script/history reuse, timeout
  selection/restoration, original database restoration, ordered completion/failure,
  and command-then-connection cleanup with primary-error preservation.
- Additional final confirmation/no-work assertions: **4 passed**, 37 other tests
  intentionally not selected in that focused rerun. Declined confirmation traps
  any mutation-resource allocation; empty/ignored/historical phases explicitly
  assert zero mutation connection/command construction.
- Full source offline suite: **279 total, 257 passed, 22 skipped, 0 failed** in
  **637.95 seconds**. Skips are 21 Linux audit cases on Windows and one
  case-sensitive filesystem case. All **30** shared-helper loading/operation
  scenarios passed. Their nested suites contain **4,290 total, 4,260 passed,
  30 expected filesystem skips, 0 failed**; these nested counts are separate
  from the 279 top-level cases and must not be added as distinct top-level tests.
- Migration integration suite: **20 skipped, 0 executed, 0 failed** because
  `FAST1_TEST_MIGRATION_SQL_CONN_STR` is absent. Its discovery/skip behavior is
  verified; no live SQL result is claimed. Added real SQL cases cover session/temp
  objects, batch-scoped definitions, explicit quoting, no earlier effects on later
  parse/preflight failure, partial commits/retry, empty files, USE restoration,
  shared transaction/timeout/command reuse and rollback, forced history and real
  owner cleanup. They remain unexecuted until an explicit target is supplied.

The first Pester attempt encountered blocked registry setup; subsequent suites
disable `TestRegistry` because these tests do not use registry fixtures. No
test-registry failure is counted as an expected feature regression or a pass.

## Staged distribution and native host evidence

`out/publish.ps1 -StageOnly` stages the same package and runs its analyzer while
explicitly reporting that tests were not run and release validation is incomplete.
This optional mode was added to permit package review without invoking unrelated
integration suites against their embedded targets. The default full-test path is
retained; it was not run because its separate live resources are unconfigured.
Source assets are validated before replacing the stage; both primary assemblies
are required in every staged RID. No external publication was performed.

Fresh Windows x64 process with SqlServer absent imported
`C:\Dev\Fast1data.SqlServer\out\Fast1data.SqlServer\Fast1data.SqlServer.psd1`:

- Version: **0.1.0**.
- Exports: **Invoke-Fast1Archiving, Invoke-Fast1Audit, Invoke-Fast1Migration**.
- SqlClient assembly: `out/Fast1data.SqlServer/lib/win-x64/Microsoft.Data.SqlClient.dll`.
- Parser assembly: `out/Fast1data.SqlServer/lib/win-x64/Microsoft.SqlServer.TransactSql.ScriptDom.dll`.

Affected staged loader/migration/phase/command/execution/preflight/cleanup suites:
**189 total, 188 passed, 1 expected Windows filesystem skip, 0 failed** in 121 seconds.
Cold fault workers assert selected-distribution provenance without source/global
fallback. The staged package passed recursive PSScriptAnalyzer validation. Final
metadata/no-allocation guard refinements were copied to stage and analyzed again;
they do not change executable module behavior.

Final review also required zero-batch files to clear stale command text/parameters
and select Text mode without executing SQL. Those four cases now assert this
explicitly. Lexical errors retain safe structured diagnostics on their cause, like
parse errors. The final source execution/preflight/command rerun passed **31/31**;
the final staged execution/preflight/command/public-migration rerun passed **72/72**.
Changed files were analyzed again without new findings and copied to the stage.
The transaction fixture explicitly selects XACT_ABORT OFF so its failure/rollback
checks do not depend on a login's ambient setting; it remains unexecuted live.

The final package comparison identified concurrent source edits that moved the
root's bootstrap statements and changed SqlClient's library path to portable slash
spelling. Both edits were preserved. Added an initial runtime-bootstrap stage label
so a missing runtime helper cannot mask the original error under StrictMode.
Revalidated the final source and staged loader suites: **51/51 passed in each**.
The final all-file source/staged module comparison reports **zero mismatches**.

| Host | Source/staged cold imports | Live migration workflow |
|---|---|---|
| Windows x64 / PS 7.6.10 / .NET 10.0.15 | Passed with bundled win-x64 assets and SqlServer absent | Unavailable: no selected test target |
| Linux x64 | Native host not available; cross-publish only | Not run |
| macOS x64 | Native host not available; cross-publish only | Not run |

Audit's separate Windows/Linux discovery restriction remains unchanged. No native
Linux/macOS or public live success/failure/retry acceptance is claimed.

## Analyzer and formatting evidence

PSScriptAnalyzer **1.25.0** analyzed all **22** modified/new PowerShell files after
loading built dependencies. No project settings file exists. Result: **zero new
errors/warnings**; **11 existing PSAvoidUsingWriteHost warnings** in `out/publish.ps1`.
Analyzing the HEAD version independently confirms the same 11 existing warnings.
No new suppression or expanded type-warning filter was added. Recursive staged
module analysis passed with no reported findings.

PowerShell AST validation found zero syntax errors or single-line control-flow
blocks across changed files. New blocks use tabs and same-line opening braces.
`git diff --check` passed after removing a trailing blank line. `.vscode/` is not
ignored. Final metadata/guard refinements were separately analyzed with zero findings.

## Acceptance evidence map

Results for the original shared-connection execution model below are historical.
FR-015 changes FR-002/FR-003/FR-005/FR-009 and SC-005 ownership/isolation
expectations; their affected cases require revalidation under T044-T046.

| Requirement | Planned evidence | Result |
|---|---|---|
| FR-001 | Cold source/staged imports without SqlServer; no Invoke-Sqlcmd execution | Windows import/export checks pass; live public SQL pending |
| FR-002 | Typed helper signatures; timeout/transaction/connection preservation | Offline contracts pass; live settings/transaction checks skipped |
| FR-003 | Invalid-resource guards; caller reuse after success/failure | Offline guards/reuse pass; live reuse skipped |
| FR-004 | Whole-file TSql160 parsing; later syntax failure prevents effects | Offline parser/zero-command checks pass; live zero-effects skipped |
| FR-005 | Source spans, batch order, empty scripts, session continuity | Offline text/order/empty-file checks pass; live session checks skipped |
| FR-006 | Read/parse/runtime/history failure stops; safe diagnostics and causes | Offline failure/cause/cleanup tests pass; live provider outcomes skipped |
| FR-007 | Exact-once insert/forced update; failed attempt retains history | Offline ordering/keys preserved; persisted SQL history checks skipped |
| FR-008 | Typed parameters; script/history/next-script command reuse | Offline typed parameter/reuse checks pass; live transaction reuse skipped |
| FR-009 | Confirmed public ownership; ordered cleanup and primary errors | Offline owner cleanup passes; real provider cleanup cases skipped |
| FR-010 | Phase/path/checksum/force/ignore/reporting/preview regressions | Offline source/staged regressions pass; Windows case-sensitive filesystem check skipped |
| FR-011 | Restore graph; both assemblies per RID; loader fault/native acceptance | Build/graph/all bundles/stage/Windows faults pass; native Linux/macOS pending |
| FR-012 | Manifest/help/install/authoring/release contract review | Reviewed together; approved 0.1.0 notes and private signature/SQLCMD/retry guidance applied |
| FR-014 | Shared parameterized loader for both primary DLLs and another managed DLL; reuse/types/faults/source-stage provenance | Added requirement only; implementation and validation pending T041-T043 |
| FR-015 | Executor-owned per-file target connection; session isolation, target/authentication, restoration, split cleanup, assigned-transaction rejection | Added requirement only; implementation and validation pending T044-T046 |
| FR-013 | Unsupported directives/counts/substitutions before effects | Offline complete-file rejection passes; live zero-effects checks skipped |
| SC-001 | Public workflow with SqlServer absent and unchanged parameters | Cold imports/public metadata pass; representative live workflow pending |
| SC-002 | All batch boundary and session cases execute exactly once | Offline batch interception passes; real SQL/session acceptance pending |
| SC-003 | Failures produce no successful completion or later script | Offline control flow passes; persisted history/runtime SQL acceptance pending |
| SC-004 | Preview/declined confirmation retain reports with zero mutations | Offline preview/declined/no-work tests pass; live preview skipped |
| SC-005 | Borrowed settings/resources retained; public owned cleanup | Offline settings/ownership/cleanup pass; real provider acceptance pending |
| SC-006 | Documented clean setup, multi-batch migration, failure and retry | Instructions/build/imports verified; operator SQL exercise pending |
| SC-007 | Both primary libraries and another bundled library use one loading implementation | Not implemented or tested; pending T041-T043 |
| SC-008 | Within-file batch continuity, script/history and between-file session isolation; no connection opens for rejected/empty files | Not implemented or tested; pending T044-T046 |

## Execution and release limitations

- The T002 adoption gate is resolved by explicit maintainer approval; implementation may proceed.
- Dependency restore/build/package graph, Windows source/staged imports, and staged offline regressions passed as detailed above.
- Full source offline suite and all 30 shared-helper scenarios passed as detailed above.
- SQL success/failure/retry/session/transaction/history acceptance: not run; explicit disposable test target is missing.
- Changed-file and staged analyzer checks completed; only the 11 unchanged release-script warnings remain.
- Distribution staging completed. Default full release-suite checks remain unrun: audit requires immutable accessible audit files and reviewed SQL/SMB settings; archiving requires reviewed disposable SQL databases and its configured server. Their embedded targets were not contacted.
- Native Windows imports/offline execution passed. Native Linux/macOS execution is unavailable on this host; no remote hosts were selected.
- No release acceptance or external publication is claimed. Material data integrity requirements remain unverified.

## Task and hook closure

**37/46 tasks completed after the FR-014 and FR-015 additions** (original scope: 37/40).
T041-T043 remain pending parameterized-loader work; T044-T046 add pending separate-script-connection work. T033 remains open for the explicit-target SQL acceptance
portion; its offline suites pass. T038 remains open for the default complete
release-suite and public live success/failure/retry workflow; package staging,
provenance, dependency hashes, analyzer and affected staged offline suites pass.
T039 remains open for native Linux/macOS and representative live acceptance on all
supported hosts. These tasks have not been marked complete from skipped tests.
T024 explicitly permits recording unavailable SQL checks; its offline cases and
the integration opt-in/skip behavior are recorded above.

Post-implementation hook check: `.specify/extensions.yml` is absent. No mandatory
or optional after-implementation hooks are registered. No hook dispatch was needed.

## Additional requirement: parameterized DLL loader (2026-11-19)

The maintainer requested one new parameterized loading function for SqlClient,
ScriptDom, and other required DLLs. FR-014, Story 4, and SC-007 capture this addition.
The plan, research decision, private dependency contract, quickstart, quality
checklist, and pending T041-T043 now specify `Import-RequiredLibrary -DllName`
with optional required-type validation, replacing both specific loaders.

This update changes feature artifacts only. The existing source still uses
`Import-SqlClientLib` and `Import-ScriptDomLib`. No implementation tests were run
for the new requirement. Earlier build/import/analyzer/test results above remain
evidence for their original scope and do not establish FR-014 or SC-007 completion.

## Additional requirement: separate script connection (2026-11-19)

The maintainer requires `Invoke-Migration` to create and use a separate target
connection. FR-015, Story 5, and SC-008 capture this addition and supersede the
executor's previous no-allocation/shared-connection contract. The typed `-SqlCmd`
input remains; each executable script uses one executor-owned target connection,
then restores the supplied command's original connection and disposes its own.
History continues on the original connection. Assigned caller transactions are
rejected by the executor without alteration; the history writer retains support.

Updated the spec, plan, data model, migration contract, research decision,
quickstart, quality review, and tasks T044-T046. This update changes artifacts
only. No production code, test execution, analyzer pass, or SQL authentication/
session-isolation acceptance is claimed for FR-015. Existing shared-session and
database-restoration results do not establish the revised ownership behavior.

## Implementation follow-ups and convergence — 2026-11-19

This section supersedes the earlier pending-implementation statements for FR-014
and FR-015. Historical results above remain scoped to their original design.
Constitution 1.1.0 and module 0.1.0 remain the approved versions; no new adoption
gate or release publication was introduced.

### Implemented behavior

- `Import-RequiredLibrary -DllName [-RequiredTypeName]` replaces both specific
  loaders. Every invocation checks the selected RID asset and managed identity,
  then requires exact name/version/culture/public-key-token compatibility and all
  case-sensitive requested types. Cold loads retain selected-bundle provenance;
  compatible preloads cannot conceal missing/corrupt assets. Bootstrap and fixtures
  explicitly require SqlConnection and TSql160Parser. The private inventory is 23
  files and public exports remain unchanged. Microsoft.SqlServer.Server.dll proves
  extension to another managed dependency without a library allowlist.
- `Invoke-Migration` rejects assigned caller transactions, validates all source
  before allocation, clones the original provider connection through ICloneable,
  suppresses ambient enlistment and selects the captured current database. It uses
  the supplied command/timeout for all file batches and a final `SELECT @@TRANCOUNT`.
  A failed/nonzero check prevents completion. Invalid/zero-batch scripts create no
  execution connection or suppression scope and run no final query.
- Original-command restoration is guarded separately from connection/scope
  disposal. Both owned disposals are attempted after restoration failure; the
  earliest error remains primary and later safe cleanup metadata is attached.
  Cleanup-only failure also prevents history and later scripts. The public owner
  keeps history on its original connection and no longer restores its database
  after script `USE`. Set-Executed retains assigned-transaction support.
- Manifest release notes, README, migration guidance, quickstart, and public/private
  help describe ownership, authentication, ambient suppression, pooling, explicit
  transactions, completion barriers and idempotent retry after committed effects.

### Regression and static evidence

Host: Windows x64, PowerShell 7.6.10, .NET 10.0.15, Pester 6.2.0,
PSScriptAnalyzer 1.25.0. Package references and already built RID bundles were
preserved; this follow-up changes no package graph and did not repeat restore/build.
All three named managed libraries remain present in all three source RID bundles.

- Tests preceded the new lifecycle/loader implementation. Initial regression runs
  failed for missing lifecycle seams (18 cases) and the absent generic loader (30
  cases). These are implementation failures, distinct from the first sandboxed
  Pester attempt's denied temporary-registry access. Subsequent runners disable the
  unused TestRegistry fixture through Pester's supported configuration.
- Loader plus command regression checkpoint: **95 passed, zero failed** (80 loader,
  15 command). Fresh workers cover source root/manifest, absent SqlServer module,
  all three libraries, compatible external preloads, repeated intact-bundle reuse,
  warm missing/corrupt assets, wrong file identity, version/culture/token preload
  conflicts, missing types, invalid paths/filenames, bootstrap order and exports.
- Executor checkpoint: **18 passed**. Combined with preflight/public/cleanup
  regressions, the first affected run passed 138/139; its sole failure incorrectly
  required reference identity for cloned SqlCredential. The corrected configuration
  assertions passed in the 95-test checkpoint. This is synthetic configuration
  evidence, not a live login or opened/password-redaction result.
- Cleanup coverage includes every combination of batch/restoration/connection-
  disposal/scope-disposal failure (16 cases), earliest-error retention, both disposal
  attempts, cleanup-only termination and caller-resource preservation. Public
  orchestration rejects completion/next-file work after transaction, restoration,
  disposal, execution or history failure.
- Additional direct smoke: omitted required types and multiple required types
  both emit zero objects; wrongly cased required types terminate as expected.
- Changed-file analysis: **21 PowerShell files**, zero new errors/warnings, zero
  parse/control-block/brace/tab findings. The **11 PSAvoidUsingWriteHost warnings**
  in out/publish.ps1 also occur when analyzing its HEAD baseline. No suppressions or
  type-warning filters were added. No project analyzer settings file exists.
- The first full-suite attempt exposed a stale shared-helper expected count (143).
  A direct worker passed **161 with one expected skip, zero failures**, total 162;
  both guards now require 162. The repeated failing-count run was stopped and is
  not passing acceptance evidence.
- Final source offline suite: **343 total, 321 passed, 22 expected skips, zero
  failures**, 12 files in **659.04 seconds**. The skips are 21 Linux audit cases on
  Windows and one case-sensitive filesystem case. All **30** shared-helper import
  scenarios passed: **4,860 nested checks, 4,830 passed, 30 expected filesystem
  skips, zero failures** (162 checks per worker).
- `out/publish.ps1 -StageOnly` successfully staged module **0.1.0** and passed
  recursive package analysis. It explicitly reported that tests were not run by
  staging and release validation remains incomplete. A separate fresh-process run
  then passed affected staged loader/migration/phase/cleanup suites: **253 total,
  252 passed, one expected filesystem skip, zero failures**, seven files in
  **125.22 seconds**. The full source shared-helper matrix was not repeated in the
  staged affected run. No gallery publication occurred.
- Cold source root/manifest and staged root/manifest imports were run as four
  separate processes with SqlServer absent from discovery. Each exposes exactly
  Invoke-Fast1Audit, Invoke-Fast1Migration and Invoke-Fast1Archiving. Both primary
  assembly locations match the selected distribution's lib/win-x64 directory.
  Roots: `C:\Dev\Fast1data.SqlServer\Fast1data.SqlServer` and
  `C:\Dev\Fast1data.SqlServer\out\Fast1data.SqlServer`. Staged hashes match source
  for all nine named-library/RID combinations; retired loaders are absent.
- Migration integration opt-in: **34 skipped, zero executed, zero failed** because
  FAST1_TEST_MIGRATION_SQL_CONN_STR is absent. The suite now includes pooled isolation,
  current-database selection, password redaction/SqlCredential, ambient rollback
  independence, explicit transaction completion, failed forced history, and real
  provider execution with narrow completion/restoration/disposal failure injection.

### Current acceptance map

| Requirement | Current evidence and remaining boundary |
|---|---|
| FR-001 | Three exports, no SqlServer/Invoke-Sqlcmd dependency; clean loader workers pass; live public workflow pending |
| FR-002 | Typed command, timeout preservation and executor transaction rejection pass offline; history transaction live checks unrun |
| FR-003 | Connection restoration, caller preservation and invalid-state guards pass offline; real open-session acceptance unrun |
| FR-004 | Whole-file TSql160 parser/preflight regressions pass; live zero-effects evidence unrun |
| FR-005 | Original source/order, shared per-file command/connection interception pass; real session/definition effects unrun |
| FR-006 | Primary failures, stopping and safe context/cleanup pass offline; live provider effects unrun |
| FR-007 | Transaction/restoration/cleanup completion barrier and stop ordering pass offline; persisted history/retry unrun |
| FR-008 | Parameter metadata, stale-state replacement and command reuse pass offline; live history unrun |
| FR-009 | Split ownership and public confirmation/timeout/cleanup coverage pass offline; real owner cleanup unrun |
| FR-010 | Existing deterministic phase, preview, validation and reporting suites retained; full source result below |
| FR-011 | All RID assets present and Windows loader faults/provenance pass; source/staged results below; Linux/macOS native execution unrun |
| FR-012 | Manifest/help/README/migration/quickstart refreshed together at approved 0.1.0; operator live exercise pending |
| FR-013 | Complete unsupported syntax rejection before allocation passes offline; live zero-effects checks unrun |
| FR-014 | Generic loader's three-library, identity/reuse/type/fault/containment/bootstrap matrix passes; staged result below |
| FR-015 | Clone configuration, target selection, suppression, restoration, cleanup and no-allocation guards pass offline; authentication and pooled SQL behavior unverified |
| SC-001 | Clean imports/public metadata pass; representative public SQL workflow unverified |
| SC-002 | Batch interception passes; real SQL/session acceptance unverified |
| SC-003 | Offline failure/completion barriers pass; durable effects/history/retry unverified |
| SC-004 | Offline preview/declined/no-work guards pass; live preview unverified |
| SC-005 | Offline timeout/ownership/restoration/cleanup checks pass; live provider behavior unverified |
| SC-006 | Updated setup/recovery instructions reviewed; operator SQL exercise unverified |
| SC-007 | Three generic library loads and defined source fault/reuse/type cases pass; staged result below |
| SC-008 | Separate per-file connections and ambient lifecycle pass with intercepted I/O; real pooled isolation/continuity unverified |

US4 source acceptance is established by the loader matrix. US5 implementation and
offline lifecycle coverage are present; **live acceptance is not established**.
SQL-password redaction, SqlCredential, access tokens, token callbacks and integrated
authentication have **zero live evidence** on this host. Synthetic clone tests for
all five modes cannot establish authentication. Token/callback and integrated modes
require deployment-specific provisioning; T052 remains open for live acceptance.
The unconfigured SQL suite never contacted a target. No unrelated audit/archiving
integration targets were contacted. Native Linux/macOS hosts remain unavailable.

### Task and hook closure

**51/55 tasks checked.** This follow-up completed T041-T051 and T053-T055. Code,
offline regressions, selected-distribution imports, staging, analysis, formatting,
documentation and evidence recording are complete for those tasks; their live/native
acceptance boundaries remain explicit above. The original completed markers retain
their historical scope.

Four tasks remain unchecked:

- **T033**: actual SQL command/history/transaction/failure/retry acceptance requires
  FAST1_TEST_MIGRATION_SQL_CONN_STR. All affected offline suites pass.
- **T038**: full default release-suite acceptance and public live workflow require
  the separate reviewed migration/audit/archiving resources. StageOnly and the
  separate affected staged suites are not complete release validation.
- **T039**: native Linux/macOS execution and representative SQL acceptance on every
  supported host remain unavailable. Windows cold source/staged imports pass.
- **T052**: live pooling, current-target/password-redaction/authentication, ambient
  suppression and isolation acceptance remains unverified. Relevant disposable SQL
  cases were added, but all 34 live cases skipped. Deployment token/callback and
  integrated modes require provisioned environments; none were inferred or contacted.

No skipped SQL/native checks have been counted as passing. Release acceptance is
incomplete because material database/session integrity behavior remains unverified.
`git diff --check` passes; `.vscode/` was not added to ignore rules. Checklist
markers and preserved package-reference edits were not changed.

Final post-execution hook check: `.specify/extensions.yml` is absent. There are no
registered mandatory or optional after-implementation hooks to dispatch.

## Additional requirement: connection-string executor input — 2026-11-19

The maintainer clarified that the request to accept a connection string and open
the connection inside `Invoke-Migration` is an additional requirement, not an
implementation request. Added FR-016, Story 6, SC-009, and pending T056-T058.
The executor's required interface is now `Invoke-Migration -ConnStr -Script`;
it owns both script command and connection. `Set-Executed -SqlCmd` remains unchanged.

This supersedes executor command borrowing, authentication cloning, current-history-
database selection, command rebinding/restoration, and assigned-command-transaction
rejection. Keep whole-file parsing, same-session batches, per-file/history isolation,
ambient suppression, timeout 0, final transaction validation, safe failure context,
and cleanup completion barriers. The public caller forwards its original string;
history command settings need no script/history timeout switching.

Updated the specification, plan, model, migration/session contracts, research
supersession notes, quickstart expectations, quality review, and pending tasks.
Production code, tests, and prior checkbox states are unchanged. No Pester,
analyzer, SQL, build, or staging checks were executed for this requirement update.
Prior implementation evidence establishes only the earlier interfaces, not FR-016.

| Current affected criteria | Required evidence | Status |
|---|---|---|
| FR-002/FR-003/FR-005/FR-009/FR-015/FR-016 | ConnStr-only executor, original-string forwarding, target/options/authentication, owned SQL resources, unchanged history borrowing, failure cleanup | Pending T056-T058 |
| SC-005/SC-008/SC-009 | Independent script/history resources, within-file continuity, between-file isolation, no caller-created executor resources, every owned disposal attempted | Pending T056-T058 |

Current task status after the addition: **51/58 historically completed, 7 open**.
Existing T033/T038/T039/T052 remain open under their applicable live/release/native
obligations; T056-T058 add the replacement interface implementation and validation.
Connection-string authentication acceptance replaces obsolete cloning of external
credential/token properties; unrun applicable SQL/native checks remain unverified.

## Current implementation run — 2026-11-19 (regenerated T001–T042)

Baseline: Windows x64; PowerShell 7.6.10 Core; .NET 10.0.15; dotnet SDK 11.0.100; Pester 6.2.0; PSScriptAnalyzer 1.25.0.
Constitution 1.1.0 and module 0.1.0 already approved; no additional adoption gate.
Preserve existing edits and net10.0 / SqlClient 7.1.2 / ScriptDom 180.154.0 / Pkcs 11.0.0 references.
Current IDs refer to [tasks.md](tasks.md); its "Previous task ID mapping" covers carried-forward obligations from the previous sequence. Historical clone/restoration evidence does not establish FR-016.
FAST1_TEST_MIGRATION_SQL_CONN_STR is absent. No SQL target selected or contacted. No native Linux/macOS host is available. Live/authentication/full-release/native checks remain unrun.

Initial working tree:

```text
 M .specify/memory/constitution.md
 M Fast1Migration.md
 M Fast1data.SqlServer/Fast1data.SqlServer.psd1
 M Fast1data.SqlServer/Fast1data.SqlServer.psm1
 M Fast1data.SqlServer/private/migration/Invoke-Migration.ps1
 M Fast1data.SqlServer/private/migration/Set-Executed.ps1
 D Fast1data.SqlServer/private/shared/Import-SqlClientLib.ps1
 M Fast1data.SqlServer/public/Invoke-Fast1Migration.ps1
 M Fast1data.SqlServer/tests/Migration.Integration.Tests.ps1
 M Fast1data.SqlServer/tests/Migration.Tests.ps1
 M Fast1data.SqlServer/tests/ModuleLoaders.Tests.ps1
 M Fast1data.SqlServer/tests/SharedHelpers.Import.Tests.ps1
 M Fast1data.SqlServer/tests/SqlCleanup.Tests.ps1
 M Fast1data.SqlServer/tests/fixtures/Import-SharedHelperDependency.ps1
 M Fast1data.SqlServer/tests/fixtures/Invoke-ModuleLoaderScenario.ps1
 M Fast1data.SqlServer/tests/fixtures/Invoke-SharedHelperScenario.ps1
 M Fast1data.SqlServer/tests/fixtures/SharedHelpers.Scenarios.ps1
 M README.md
 M build/SqlClientLoader.csproj
 M build/build.ps1
 M out/publish.ps1
?? Fast1data.SqlServer/private/shared/Import-RequiredLibrary.ps1
?? Fast1data.SqlServer/tests/Migration.Command.Tests.ps1
?? Fast1data.SqlServer/tests/Migration.Execution.Tests.ps1
?? Fast1data.SqlServer/tests/Migration.Preflight.Tests.ps1
?? Fast1data.SqlServer/tests/fixtures/Get-MigrationTestCommand.ps1
?? specs/006-remove-sqlserver-dependency/

```

Bundle readiness (existing assets, no package changes requiring rebuild):
- win-x64: 56 files; Microsoft.Data.SqlClient, Version=7.0.0.0, Culture=neutral, PublicKeyToken=23ec7fc2d6eaa4a5; Microsoft.SqlServer.TransactSql.ScriptDom, Version=18.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91; System.Security.Cryptography.Pkcs, Version=11.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a
- linux-x64: 54 files; Microsoft.Data.SqlClient, Version=7.0.0.0, Culture=neutral, PublicKeyToken=23ec7fc2d6eaa4a5; Microsoft.SqlServer.TransactSql.ScriptDom, Version=18.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91; System.Security.Cryptography.Pkcs, Version=11.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a
- osx-x64: 54 files; Microsoft.Data.SqlClient, Version=7.0.0.0, Culture=neutral, PublicKeyToken=23ec7fc2d6eaa4a5; Microsoft.SqlServer.TransactSql.ScriptDom, Version=18.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91; System.Security.Cryptography.Pkcs, Version=11.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a

T002 identity review: Resolve-MigrationPhase and its existing phase regressions preserve FullPath as a literal contained path; ScriptName as normalized phase-relative identity using /; Phase as literal configured name; Checksum as 64-character SHA-256 over bytes; HistoryScriptName as the exact stored forced-update key; IsForced/WasExecuted as flags whose conjunction selects updates. Retain containment, casing/separators, duplicate/conflict, drift, ignore/force, order and reporting coverage. Runtime regression verification follows.
Ignore setup: Git repository; existing .gitignore covers build/bin, build/obj, bundles, staged output and temporary/editor artifacts. No Node/Docker/Terraform/Helm project detected; no additional ignore files needed. .vscode remains tracked. Checklist requirements.md: 16/16 checked; untouched.

### Current progress: T001–T028, T030–T031, T034–T036

- Setup/foundation: retained all starting edits, governance, references and available RID assets. Reviewed build/publish source-first primary-DLL guards, recursive copies and contained cleanup; no demonstrated production loader/build gap requires rebuilding or replacement. Existing transitive/native/resource counts are 56 Windows and 54 each Linux/macOS. Metadata is readiness evidence only, not native execution.
- T005–T007: retained no-SqlServer source import/export/bootstrap/provenance and fault coverage. The initial affected checkpoint passed all 80 existing loader cases plus 34 phase regressions (one filesystem skip in the affected set). Six additional optional/multiple/case-sensitive type cases are being run in the final matrix. No usable partial exports or migration Invoke-Sqlcmd execution is allowed.
- T008–T012: adapted input/history/public tests before implementation. Initial red run: 64 tests, 48 passed, 16 failed as expected for the changed interface/forwarding plus one obsolete shared-command expectation. ConnStr is mandatory string, blank/malformed syntax/unknown keywords/typed values fail locally even with empty files, and original text is forwarded unchanged. No caller connection/command is required. The public owner retains history timeout and passes only history SqlCmd to Set-Executed.
- T013–T022: retained original parser slices, order, lexical/preprocessing rejection, full-file parsing and all-span guards. Replaced clone/binding seams with connection/command construction seams. Execution owns command at timeout 0, connection and ambient suppression; batches and final transaction check share command/session. Disposal is command, connection, scope and every attempt completes before success. Lifecycle tests cover suppression/construction/open/command/batch/postflight failures, ambient restoration, and all 16 batch/command/connection/scope-failure combinations with safe first-error retention. Offline observations do not prove provider session/authentication behavior. Invalid span handling is code-reviewed; a real ScriptDom-generated out-of-range span was not induced.
- T023–T028: history writer retained without further production edits; typed metadata, command/connection lifetime/settings, stale parameter replacement, forced lookup and cause preservation verified. Public orchestration retains phase evaluation/confirmation, success-history-next ordering and failure/retry guards. Get-Executed and history schema unchanged.
- Targeted green checkpoint after stale test cleanup: **142 passed, zero failed/skipped**, across command/execution/preflight/public/cleanup suites. An earlier broad intermediate run had 249 passes, 6 failures and one skip: five obsolete borrowed/empty-command assertions and one empty collection assertion under StrictMode; corrected without changing successful production behavior.
- Adapted all live executor cases to ConnStr; retained public/history success/failure/retry, case-sensitive legacy keys, timestamps and forced updates. Added configured/default catalog despite changed history database, original SQL-password input despite history redaction, pooled original-string options, command disposal in real-provider cleanup injection, and retry after cleanup failure. Removed external SqlCredential cloning and executor assigned-transaction rejection assertions, which no longer apply. **34 SQL cases skipped, zero executed**, because explicit FAST1_TEST_MIGRATION_SQL_CONN_STR is absent; no target was contacted. SQL-auth, integrated/other connection-string authentication, pooling/ambient, transaction rollback/retry and durable effects are unverified, so T033 remains open.
- T030–T031: private inventory remains 23 files; ownership fixture names Get-MigrationScriptCommand in place of removed Invoke-MigrationCommandBinding. Removed obsolete clone fixture after all consumers migrated. Generic loader/bootstrap implementation retained.
- T034–T036: executor/public help, manifest 0.1.0 release notes, README, migration guide and quickstart now describe original ConnStr, owned timeout 0 command/connection/scope, separate borrowed history transactions, no timeout switching, no login for zero-batch files, ambient suppression, complete explicit transactions, cleanup barriers and idempotent retry. Current task IDs refer to the current checklist; previous IDs are distinguished by the mapping in tasks.md.
- Initial changed-file analysis: **21 PowerShell files, zero parse/format violations, 11 existing PSAvoidUsingWriteHost warnings in out/publish.ps1, no other warnings/errors**. No settings file exists. Follow-up analysis of final test edits remains pending before T037 closure. No new suppression/filter was introduced.

Tasks that allow unavailable SQL outcomes/gaps (T017/T022/T028) record that limitation here; their checkmarks do not establish live acceptance. T033/T040/T041 remain separate unfulfilled release obligations.

T029 source loader suite now passes with six added cold/reuse optional/multiple/case-sensitive type checks (86 loader cases total). T037 final changed-file analysis repeated after fixture cleanup and final assertions: 21 files, zero parse/format violations, the same 11 existing publish.ps1 Write-Host warnings and no other warnings/errors. Source root and manifest cold imports each passed in a fresh process with SqlServer undiscoverable, exactly three exports, and both assembly paths under the source lib/win-x64 bundle.

Additional dependency readiness: all source bundle files match the existing corresponding build/bin/Release/net10.0/<rid>/publish output by relative path and SHA-256 (56/54/54 files; zero differences). Each RID has 26 resource DLLs; Windows includes its native SNI asset. SqlClient product version is 7.1.2+b1dd9db72cd9e6eb9fc83ca308558e73b57dd449. Existing dependency graph and binaries were reused; no fresh restore/build or Linux/macOS/native SQL execution is claimed.

Full release prerequisites reviewed separately: migration needs its explicit environment opt-in and disposable database creation permissions; Windows audit needs a reviewed SQL target plus closed immutable audit files readable by both Windows identity and SQL Server; Linux audit additionally needs smbclient, explicit SMB credentials/share access and the native host; archiving creates disposable config/source/destination databases on reviewed test resources. The unrelated suites contain embedded sample targets and are not configured by the migration variable. None were contacted. Default publish/full integration and staged SQL remain unrun (T040); no gallery publication is requested or performed. T041 has Windows offline import evidence only, with Windows SQL and native Linux/macOS acceptance still unavailable.

T032/T038 source closure: 352 total, 330 passed, 22 expected skips, zero failed across 12 offline files in 00:10:57.6994126. Includes 86 loader tests and all 30 shared-helper workers (4,860 nested checks; 4,830 passed, 30 expected filesystem skips, zero failed). Source integration suites were excluded. Final command/preflight/fixture assertions are included in this run. Stage validation follows.

### Final source/staged verification (current IDs)

- Source offline: **352 total, 330 passed, 22 expected skips, zero failed**, 12 files, duration 00:10:57.6994126. Excluded all Integration suites. Skips are 21 Linux audit cases on Windows and one case-sensitive filesystem case.
- Staged affected offline: **262 total, 261 passed, 1 expected filesystem skip, zero failed**, 7 loader/migration/phase/cleanup files, duration 00:04:23.2982075. All 30 staged shared-helper scenarios ran separately as the same fresh-process workers, three independent processes at a time; each root/tuple/exit/count/failure/skip assertion and distinct 30-tuple coverage were checked. Their nested counts follow; they are separate from this top-level Pester count.
- Shared-helper nested results (not added to top-level Pester counts):
- source: 30 workers, 4860 nested checks; 4830 passed, 30 expected filesystem skips, zero failed.
- staged: 30 workers, 4860 nested checks; 4830 passed, 30 expected filesystem skips, zero failed.
- out/publish.ps1 -StageOnly staged approved version 0.1.0 and passed recursive package analysis; it explicitly reported that tests were not run by staging and release validation remains incomplete. Separate staged offline execution supplies the counts above. No full-release or gallery publication claim.
- Fresh source and staged root/manifest imports passed separately with SqlServer undiscoverable; exactly Invoke-Fast1Archiving, Invoke-Fast1Audit, Invoke-Fast1Migration exported. Both primary assemblies resolve to the selected distribution's lib/win-x64. Fresh signature inspection verifies mandatory string ConnStr/Script and no executor SqlCmd, with typed history SqlCmd retained. Noninteractive omission of ConnStr or Script is rejected by parameter binding before any body execution.
- Both primary assemblies, third-library and Pkcs metadata are valid for all staged RIDs. All 56/54/54 staged bundle files match source SHA-256 by relative path, including native/resource/transitive output. This is packaging evidence; only Windows import executed natively. No fresh build was necessary because source bundles match existing per-RID build output exactly.
- Final analysis/formatting: 21 changed/new PowerShell files, zero new warnings/errors, zero parse/control-block/brace/tab findings. The 11 PSAvoidUsingWriteHost warnings in publish.ps1 were independently reproduced against HEAD. No analyzer settings exist; no new suppression or warning filter. The subsequent live-retry wrapper adjustment was analyzed separately with zero findings.
- Live SQL: 34 skipped, zero executed; no explicit target selected. Provisioned connection-string authentication (SQL password/integrated/other), pooling/session/target effects, transaction rollback and persisted completion/failure/retry remain unverified. Native Linux/macOS hosts are unavailable; Windows live SQL is also unverified. Missing acceptance remains a release blocker under constitution V.

### Current FR/SC/story evidence map (supersedes historical interface claims)

| Requirement | Current evidence | Remaining acceptance |
|---|---|---|
| FR-001 | Source/staged clean imports, removed prerequisite, unchanged three exports | Representative public SQL workflow |
| FR-002 | Mandatory ConnStr executor; typed borrowed history command, invalid state and metadata tests | Real history transaction reuse/rollback |
| FR-003 | Executor owns command/connection; borrowed history lifetime preserved offline | Live provider ownership |
| FR-004 | Whole-file TSql160 lexical/parse rejection, later errors before allocation | Live zero-effects proof |
| FR-005 | Original slices, definitions, mixed GO, shared command/session observations, empty files | Live once-only/state/definition effects |
| FR-006 | Safe stage/batch/source context and preserved causes; later work stops | Live partial effects/history failure/retry |
| FR-007 | Executor completion/postflight/cleanup barriers precede one history call | Durable new/forced/empty history and failed-rerun timestamps |
| FR-008 | NVarChar(255)/NVarChar(32)/Char(64), stale parameter/text replacement, history reuse | Actual parameterized writes/forced legacy keys |
| FR-009 | Original-string forwarding, history timeout preserved, ordered owner cleanup | Live owner cleanup/provider behavior |
| FR-010 | Phase/path/checksum/force/ignore/order/reporting/preview/declined confirmation suites pass | Live preview/no-work checks |
| FR-011 | Preserved package graph/bundles, source/staged primary/transitive/native/resource checks, Windows imports | Native Linux/macOS and live native paths |
| FR-012 | Approved 0.1.0 notes, private/public help, README, migration guide and quickstart updated | Operator live exercise |
| FR-013 | SQLCMD/shell/utility/counts and reserved substitutions rejected before allocation | Live zero-effects proof |
| FR-014 | Generic three-library loader, cold/reuse/identity/types/filename/fault/provenance/bootstrap suites | Native Linux/macOS execution |
| FR-015 | Separate owned per-file lifecycle, suppression through SQL disposal, final transaction check, no allocation for invalid/zero batches | Real pooling/authentication/ambient/transaction/session isolation |
| FR-016 | ConnStr-only direct calls, local validation, original forwarding, timeout 0 and every owned cleanup attempt | Live original-string configured/default target/authentication |
| SC-001 | Clean imports/public metadata source and staged pass | Public SQL workflow |
| SC-002 | Offline batch order/text/state observations pass | SQL batch/session effects |
| SC-003 | Failure, cleanup barriers and stop/retry orchestration pass offline | Persisted effects/history/retry |
| SC-004 | Preview/declined/no-work offline guards pass | Live absence of effects |
| SC-005 | History settings/ownership and ordered executor/public cleanup pass offline | Real provider transactions/lifetimes |
| SC-006 | Setup/recovery guidance reconciled | Operator migration/failure/retry exercise |
| SC-007 | Three-library generic loader and all defined source/staged cases pass | Native cross-platform acceptance |
| SC-008 | No allocation for rejected/zero batches; shared per-file owned session and ambient restoration pass offline | Real pooled isolation/continuity |
| SC-009 | Direct ConnStr/Script invocation, original options and all ownership/failure stages pass offline | Live target/authentication |

| Story | Current status |
|---|---|
| US1 dependency removal | Source/staged import and packaging verified; public live migration pending T033/T040/T041 |
| US2 faithful batches | Offline boundary/preflight tests pass; direct live SQL acceptance pending T033 |
| US3 history separation/completion | Borrowed history/public ordering/cleanup pass offline; persisted history/retry pending T033 |
| US4 generic loading | Source/staged full loader/shared-helper matrix verified; native acceptance pending T041 |
| US5 isolated sessions | Owned lifecycle/completion/ambient/cleanup verified offline; real SQL sessions/transactions pending T033/T041 |
| US6 direct ConnStr | Interface, validation, forwarding and owned cleanup verified offline; original-string authentication/target pending T033/T041 |

Current task closure: **39/42 completed**, with T033/T040/T041 left unchecked for explicit SQL/full-release/native resources. T017/T022/T028 permit recording unavailable SQL evidence; those checkmarks are not live acceptance. Previous 51/58 counts and clone/restoration results remain historical. Checklist markers, package versions, public parameters/exports, history schema and .vscode tracking were preserved.

Final extension-hook check: .specify/extensions.yml is absent; no registered before/after implementation hooks to dispatch. Git diff whitespace check passes. Implementation/offline/staged tasks are complete; release acceptance remains incomplete until the three environment-dependent tasks are executed.
