# Data Model: Own Archiving Execution

Existing SQL schema remains unchanged. Execution/cleanup structures below are private runtime data, not new tables or public configuration. See [contract](contracts/archiving-execution.md).

## Table group execution

| Field | Meaning / invariant |
| --- | --- |
| Inputs | Existing connection string, group name, optional log path; no secrets in diagnostics. |
| Configuration | Existing group ID, source/destination identities and DisableFK. |
| Tables | Active rows in supplied traversal; purge view sorted by PurgeOrder. |
| Resources | Every allocated connection/reader/command/bulk-copy handle registered before use. |
| Failures | Original operation ErrorRecord, or first cleanup-only error, plus ordered cleanup contexts. |
| Lifetime | Created → initializing → preparation/archive → purge → releasing → succeeded/failed; no-work exits also release. |

One invocation owns many table executions/resources. Constructor is inert and execution single-use. Failure stops processing and enters cleanup; earlier table completion remains durable. Retry creates a fresh owner and reloads SQL state.

## Table work configuration

Existing dbo.SourceTable fields remain: SourceTableId/TableGroupId, schema/table, Active, KeyQuery, Archive/Purge, PurgeOrder, key/data/purge batch sizes, DelayInterval, AlwaysRunCheck and computed working/position/flag names. Metadata remains runtime data. Each table belongs to one group and has historical process records; preserve latest-incomplete lookup.

KeyQuery remains executable administrator input. New metadata predicates use parameters; DDL identifiers require validation/quoting. Inactive tables are excluded and both-disabled skipped. PK/same-instance prerequisites remain.

## Captured working set

| Field | Storage / rule |
| --- | --- |
| Source working identity | Existing configuration database dbo source working-table name. |
| Position | int identity used for batching; not a numeric source PK value. |
| Actual PK columns | Original selected keys, including composite keys. |
| Skip flag | Existing bit marking destination matches. |
| Destination snapshot | Existing rebuildable destination-key working table, populated from actual destination presence of captured PKs independent of current eligibility. |
| Confirmation | ProcessState.KeyCopyDate establishes completed capture. |

Missing confirmation retains recreate/recapture behavior. Maximum position precedes confirmation. Confirmed capture survives eligibility changes and recoverable failures; cleanup never drops required tables. Normal removal follows overall completion; failed removal returns failure and may leave completed-process tables.

## Process progress

Retain ProcessState internally; hide caller access/mutation. SQL fields/null semantics stay compatible:

| Fields | Meaning / validation |
| --- | --- |
| ProcessStateId, SourceTableId, CreateDate, ModifyDate | Existing identity, relationship and timestamps. |
| KeyMaxValue, KeyCopyDate | Maximum captured position and confirmed capture; empty confirmed set has maximum zero. |
| LastArchivedKey, RowsArchived, ArchiveCompleteDate | Archive position, recorded count and phase marker. |
| LastPurgedKey, RowsPurged, PurgeCompleteDate | Purge position, recorded affected count and phase marker. |
| CompleteDate | Marker following all enabled phases and required restoration. |
| IncompleteProcess | Runtime loaded-incomplete flag; retain reconciliation/reset role. |
| Candidate position / batch activity | Reset per attempt; accept after effect/checkpoint success. Callbacks alone are not durability. |

| Transition | Preconditions | Failure/recovery |
| --- | --- | --- |
| Create/load | Enabled table prepared | Stop before effects on failure. |
| Capture → maximum → capture date | Each prior operation/write succeeds | Failed confirmation blocks phases; missing capture date retains recapture. |
| Reconcile | Existing incomplete/AlwaysRunCheck rule | Page retained keys, query actual destination presence, snapshot matches, flag and confirm safe position; partial snapshot failure stops and retry rebuilds it. |
| Copy → checkpoint | Successful batch, reader released before checkpoint reuse | Effects can survive failure; reload/reconcile retained keys. |
| Archive complete | All required archive checkpoints confirmed | Failed marker blocks following work; archive-only then follows overall lifecycle. |
| Delete → checkpoint | Retained set/range; FK obligations registered where enabled | Absent rows tolerated; no outside-set deletion or fabricated counts. |
| Restore → purge complete → overall complete | Every required preceding transition succeeds | Failed restore/write blocks new later markers/removal. |
| Remove working tables | Overall completion confirmed | Drop failure returned; committed markers not undone. |

Successfully examined empty ranges may advance. Failed batches cannot advance progress. Checkpoints may lag effects or commit before response loss; fresh recovery reads persisted truth. Totals retain recorded-processing limitations without exactly-once counting/rollback promises. Combined processes can retain archive completion while purge/overall remains incomplete. Later disposal failure can fail invocation after durable completion.

## Constraint cleanup obligation

Fields: group/table/process identity; source database, child schema/table, distinct FK name; registered/disable-attempted/restore-attempted/restored-or-failed status; nonvalidating restoration policy. Scope is inbound source FKs referencing the configured source table, including initially disabled entries within the existing enable scope.

Register the entire list before first disable. Partial failure retains all possibly affected entries for independent restoration before connection release. NOCHECK disables; WITH NOCHECK CHECK enables without establishing trust. DisableFK off creates no toggle obligation. Records are in memory; hard termination may require operator inspection.

## Resource and failure records

Resource fields: action/role, handle, acquired/release-attempted/released-or-failed status. Dependencies require short-lived readers/bulk-copy before connection release and restoration before releasing its connections. Failed release cannot prevent independent attempts.

Expose cleanup entries at Exception.Data['Fast1Archiving.CleanupFailures']: Action, GroupName, optional SourceTable/ProcessStateId, ResourceRole or source constraint identity, ErrorType and sanitized Message. Preserve operation ErrorRecord primary; absent one, promote first cleanup failure. Merge nested contexts. No connection strings, credentials or sensitive SQL; no persisted failure schema/new public success object.
