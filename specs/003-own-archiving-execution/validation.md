# Own Archiving Execution — Validation

Validated 2026-10-30 on x64 Windows, PowerShell 7.6.9 Core. All available acceptance checks passed. Required SQL durability and FK evidence was obtained; Linux/macOS execution remains unverified.

## Environment and isolation

Pester 6.2.0, PSScriptAnalyzer 1.25.0, SqlServer 22.4.5.1, bundled Microsoft.Data.SqlClient product version 7.1.1; SQL Server 17.0.5015.4. The module remains version 0.0.4 with PowerShell 7.6 Core, the existing explicit exports, dependencies and Windows/Linux/macOS runtime declarations. No schema or stored-procedure file changed.

The user authorized disposable databases on the supplied test server. TCP connectivity succeeded; CREATE DATABASE succeeded after the login permission update. Registered targets were `fast1_003_de0c09ecbf3a_config`, `fast1_003_de0c09ecbf3a_source`, and `fast1_003_de0c09ecbf3a_destination`. Connections were supplied through Pester container data; no fallback targets were used. Credentials and full connection strings are omitted from this record.

Schema deployment was tables.sql then sprocs.sql, only in the configuration target. Unique fixture names bounded configuration rows, working tables, triggers, child FKs and source/destination objects. Observations below used fresh connections outside execution transactions and preceded fixture teardown. No transaction spanned effects and checkpoints. Private substitutions for partial writes/FK actions still performed real SQL before the selected failure.

Final teardown verified zero remaining configuration fixture rows and zero source/destination fixture tables, then dropped exactly the three registered disposable databases. A fresh master-database query confirmed all three were removed.

## Results

| Check | Passed | Failed | Skipped / unverified |
| --- | ---: | ---: | --- |
| SQL-independent ArchivingExecution.Tests.ps1 | 28 | 0 | 0 |
| Explicitly targeted Archiving.Tests.ps1 | 29 | 0 | 0 |
| Audit.Tests.Common.ps1 | 3 | 0 | 0 |
| Audit.Tests.Windows.ps1 | 7 | 0 | 0 |
| Audit.Tests.Linux.ps1 | 0 | 0 | 21: requires Linux |
| Migration.Tests.ps1, including disposable SQL integration | 47 | 0 | 1: requires case-sensitive database collation |
| Migration.Tests.Phase.ps1 | 33 | 0 | 1: requires case-sensitive Unix filesystem |
| PSScriptAnalyzer, seven changed feature PowerShell files | Clean | 0 findings | No rules suppressed; no repository settings found |
| Fresh-process manifest and direct .psm1 imports | Both passed | 0 | Linux/macOS hosts unavailable; WSL is not installed |

Total: **147 tests passed, 0 failed, 23 conditional skips**. Skips are not evidence of Linux or case-sensitive behavior. Class changes were tested in fresh pwsh processes. Pester's unused TestRegistry was disabled after its default temporary registry setup was rejected in the restricted Windows environment.

Analyzer coverage: ArchivingModel.psm1, Invoke-ArchivingProcess.ps1, Metadata.psm1, GenericSqlQuery.ps1, public Invoke-Fast1Archiving.ps1, Archiving.Tests.ps1 and ArchivingExecution.Tests.ps1. SQL provider types were loaded before analysis. Tab indentation and multiline control-flow blocks were retained. New analyzer warnings were corrected without suppression.

## Durable batch and checkpoint evidence

For five-key fixtures, initial source keys were `{1,2,3,4,5}`. Captured working rows were independently observed as positions 1–5 paired with those keys and initially false skip flags. `A` and `P` below mean persisted position / recorded count, not physical row counts. `∅` denotes an empty key set.

| Fixture / failure | Independently observed after failure | Retry result |
| --- | --- | --- |
| `pester_1ebabf604311`: retained data-copy interruption, process 144/table 127 | Source `{1..5}`, destination `{1,2,3}`; A=2/2; working keys `{1..5}` retained; archive/overall incomplete | Source ∅, destination `{1..5}`; recorded archive count 4, purge count 5; complete; no duplicate PKs |
| `pester_a4846eef5d76`: retained delete interruption, process 145/table 128 | Source `{3,4,5}`, destination `{1..5}`; A=6/5, P=2/2; archive complete, overall incomplete; working keys retained | Source ∅, destination `{1..5}`; recorded purge count 5; complete |
| `pester_aec48620cd7d`: post-copy checkpoint rejection, process 113/table 101 | Destination `{1,2}` durable with A=0/0; source and working keys `{1..5}`; no completion | Changed eligibility excludes a committed key and newly eligible key 99 is added. Retry destination `{1..5}`, source `{99}`; A=6/3, P=6/5; complete; working tables removed |
| `pester_9114af2b5452`: post-delete checkpoint rejection, process 114/table 102 | Source `{3,4,5}` with P=0/0; destination `{1..5}`; archive complete; purge/overall incomplete; working keys retained | Retry revisits absent keys 1/2. Destination `{1..5}`, source `{99}`; recorded purge count 3; complete; working tables removed |

The changed-eligibility copy case reproduced a duplicate-key failure before captured-key reconciliation was implemented, then passed with the correction. Recorded counts intentionally lag independently committed effects after checkpoint rejection.

## Transition and retained-set evidence

| Rejected transition / fixture | State after failure | Recovery |
| --- | --- | --- |
| Maximum position: `pester_92aba5289ccc`, process 115 | KeyMaxValue and KeyCopyDate absent; source `{1..5}`, destination ∅; working set retained | Fresh capture, complete copy/purge; destination `{1..5}` |
| Capture date: `pester_45710b330a8a`, process 116 | Maximum 5, unconfirmed capture; source `{1..5}`, destination ∅ | Recreated capture; complete |
| Archive complete: `pester_28b0c962f3bf`, process 117 | A=6/5, destination `{1..5}`, source `{1..5}`; no purge; working set retained | Persisted-truth retry; complete |
| Purge complete: `pester_be8bd5d5522e`, process 118 | Source ∅, destination `{1..5}`, P=6/5; no overall completion; working set retained | Retry records required transitions; complete |
| Overall complete: `pester_43ee0c8874ac`, process 119 | Source ∅, destination `{1..5}`, both phases complete; overall absent; working set retained | Retry confirms overall completion, then removes working tables |

Each successful transition retry retained its process identity. Final destination keys were unique and complete; required working tables were removed only after confirmed overall completion. Controlled tests additionally committed an archive-complete write then lost its response: execution stopped, and a fresh owner reloaded the committed marker instead of repeating copy work.

Partial source capture wrote two actual keys and failed before KeyCopyDate; retry recreated the set and archived all five. Composite fixture `pester_3105ca6a97f0` captured 1,105 `(nvarchar(12), decimal(12,2))` keys with nonsequential values. KeyCopyBatchSize was 5,000, so reconciliation had to cross the 1,000-key parameter-page bound. Two hundred copies committed before checkpoint rejection. Eligibility then changed and outside key 99999 was inserted. A retry wrote a real partial destination snapshot and failed; persisted archive position remained zero and recovery tables remained. The next retry rebuilt the snapshot and finished with all 1,105 expected unique pairs, zero missing expected pairs, no outside destination key, and only outside key 99999 remaining in source. AlwaysRunCheck was enabled.

Multi-table fixture `pester_8d29d8156558` retained earlier completed process 135 while a later table's copy failed. Retry preserved that completion and finished the later table with five unique destination keys. No checkpoint was manually repaired.

## Source FK evidence

Each fixture used two inbound source child constraints, named `FK_archiving_test_<suffix>_a` and `_b`. Constraint b began disabled. Process IDs differed from SourceTableIds. Observations were scoped to those exact names in source sys.foreign_keys before fixture cleanup.

| Fixture suffix / fault | Observed enabled/trusted state and retained progress |
| --- | --- |
| `0a47c31406d6`: delete failure, process 121/table 108 | Both enabled/untrusted; source `{1..5}`; P=0/0; no purge/overall completion |
| `c440f4940398`: post-delete checkpoint failure, process 123/table 109 | Both enabled/untrusted; source `{3,4,5}`; P=0/0; no purge/overall completion |
| `d068ef954b00`: failure after first actual disable, process 125/table 110 | Entire registered scope restored, including b; both enabled/untrusted; no purge/overall completion |
| `e6f5dcbf83cd`: restore a fails after successful deletes, process 127/table 111 | a disabled/untrusted, b enabled/untrusted; source ∅, P=6/5; restoration failure primary; no purge/overall completion |
| `bccd3ad30863`: restore a fails after checkpoint failure, process 129/table 112 | a disabled/untrusted, b enabled/untrusted; source `{3,4,5}`, P=0/0; checkpoint error primary with actionable restore-a context; no purge/overall completion |
| `5790243b1a88`: DisableFK off | Zero toggle calls; delete rejected by FK; a remains enabled/trusted, b remains disabled/untrusted |

All failing processes retained their working keys. Removing injections and retrying without editing progress completed the enabled-FK fixtures; both constraints were independently observed enabled/untrusted after retry. Successful enabling did not validate or repair historical child rows.

## Controlled ownership and compatibility

Source-open failure released source and configuration handles. Destination-open failure released destination, source and configuration handles, including the failed-open allocation. Readers/commands were released before subsequent connection reuse. The actual streaming batch method was exercised with private resource substitutions: reader release preceded checkpoint writes; bulk/reader disposal errors did not prevent command or connection release.

Operation errors retained the original exception reference and stack. Ordered sanitized contexts covered logging, independent connection failures, reader/command/bulk failures and nested cleanup entries. Cleanup-only errors terminated. Late drop/disposal failure did not erase committed completion. Partial disabling restored the registered scope before connection release and blocked success when restoration failed. Single-use owners rejected a second execution.

Compatibility passed for archive-only, purge-only, combined, inactive, both-disabled, empty groups, unknown groups and empty captured sets; computed/rowversion exclusion, missing-column creation and missing destination schema/table creation were retained. Controlled traversal preserved supplied preparation/archive order, group copy-before-purge, configured PurgeOrder, batch sizes, delays and purge-only reconciliation triggers. No new ordering guarantee was added.

Both fresh imports exposed `Invoke-Fast1Archiving [-ConnStr] <string> [-GroupName] <string> [[-LogFile] <string>] [<CommonParameters>]`. Mandatory string parameters, optional LogFile, three manifest exports and no-success-object behavior passed. Caller inspection found only inert construction and one Execute request, with no state/checkpoint/FK/disposal coordination.

Test target guards rejected missing inputs, system databases, overlapping targets, configuration/source instance mismatches and a uniquely registered preexisting target mismatch. Procedure modify_date was unchanged during mismatch rejection, demonstrating rejection before schema deployment. A read-only guard check also succeeded before archiving schema existed.

## Requirement coverage and limits

| Requirements / criteria | Evidence |
| --- | --- |
| FR-001,015 / SC-005 | Thin caller, same request, actual owned preparation/batch/transition loops, single-use lifetime |
| FR-002,014 / SC-006 | Contract/import, all modes, supplied traversal, purge order, schema/column compatibility |
| FR-003,006,007 / SC-001,006 | Retained copy/delete, changed eligibility, composite bound, partial capture/snapshot, earlier-table completion |
| FR-004,005 / SC-001,002 | Independent post-effect checkpoint failures, every transition rejection, committed-write/lost-response test, recorded-count assertions |
| FR-008,011 / SC-003,004 | Both partial opens, independent resource failures, primary reference/stack, nested sanitized contexts, cleanup-only and late failures |
| FR-009,010 / SC-003,004 | Real FK enabled/trusted observations, partial disabling, independent failed/successful restores, DisableFK-off zero toggles |
| FR-012,013 / all SC | Retained and added tests, fresh SQL observers, safe fixture identities, truthful platform/skip reporting |

No material integrity failure or missing required SQL evidence remains from the available checks. Linux/macOS imports/execution and the two skipped case-sensitive behaviors are explicitly unverified. Hard termination/server outage restoration success and exactly-once counts are not guaranteed. No coverage percentage is claimed; coverage is tied to the acceptance scenarios above.

Extension hooks: `.specify/extensions.yml` was absent before and after implementation; no hooks were registered to execute.
