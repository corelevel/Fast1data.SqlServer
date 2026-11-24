# Data Model: Per-Table Bulk Copy Timeout

**Feature**: `009-add-bulk-copy-timeout` | **Date**: 2026-11-23

## Source-table configuration

Extend the existing `dbo.SourceTable` entity with one field. Its primary key (`SourceTableId`), parent relationship (`TableGroupId` to `dbo.TableGroup`), table identity, batching, activity, copy/purge options and computed working-table names remain unchanged.

| Field | SQL type | Typed model | Default | Meaning |
| --- | --- | --- | --- | --- |
| `BulkCopyTimeout` | `int NOT NULL` | `[int]$BulkCopyTimeout` on `Table`, loaded from metadata | 30 seconds in SQL | Zero: unlimited bulk waiting; positive: bulk timeout in seconds. |

Validation:

- Named default: `DF_SourceTable__BulkCopyTimeout`, expression `30`.
- Named check: `CK_SourceTable__BulkCopyTimeout`, expression `BulkCopyTimeout >= 0`.
- Valid persisted range: 0 through 2,147,483,647 inclusive.
- Omitted insert field receives 30. Explicit null is rejected by `NOT NULL`.
- Negative inserts and updates fail. Failed updates preserve the prior valid value.
- No conversion to milliseconds or a smaller integer type; preserve the stored value.

Each group has multiple source configurations; each configuration owns its timeout independently. The SQL default is the sole configured default for omitted inserts. The typed property has no initializer: normal execution always reads the required metadata column, and private direct construction must explicitly supply a timeout before copying.

## Metadata and execution representation

`dbo.stp_GetSourceTable(@TableGroupId int)` continues returning active configurations for the selected group, with an added non-null Int32 `BulkCopyTimeout` result column. `TableGroup.ReadSourceTables()` retrieves it by name and includes it in the values used to construct the existing `Table` object.

| Copy operation | Reader source | Write target | Timeout owner |
| --- | --- | --- | --- |
| `Table.BulkCopySourcePK()` | Source key query | Configuration database source-key working table | Current `Table.BulkCopyTimeout` |
| `Table.BulkCopyDestinationPK()` | Destination keys matching captured-key pages | Configuration database destination-key working table | Current `Table.BulkCopyTimeout`, on each page's copy |
| `Table.BulkCopyTable()` | Archive-data procedure/reader | Destination archive table | Current `Table.BulkCopyTimeout`, on each batch's copy |

Every newly created copy receives the value before writing. Skipped/no-row stages retain existing behavior. A change to stored configuration takes effect when the workflow loads that configuration; it does not reconfigure a running operation.

No timeout field is added to `TableGroup`, `ProcessState`, or the working tables. Ordinary command timeout remains a separate existing provider/connection concern.

## Installation preparation states

These are deployment states, not new stored entities or runtime state flags:

| State | Storage | Metadata | Permitted next step |
| --- | --- | --- | --- |
| Fresh database | SourceTable absent | Absent/initial setup | Run tables setup, then procedure setup; inserted omitted values become 30. |
| Legacy/unprepared | Existing SourceTable lacks field | Old projection | Stop archiving and manually prepare storage; rerunning tables setup alone leaves it unchanged. |
| Storage prepared | Required field, all old rows 30, default/check present | Old projection | Deploy the updated metadata procedure before running the changed module. |
| Prepared | Valid required field/default/check | Returns configured field | Run changed module using unchanged group selection and progress state. |

Manual preparation must retain all configuration identities, relationships, `ProcessState` rows, working sets, and user data. It is an administrator operation; this feature adds no automatic transition code or migration artifact.

## Failure and progress invariants

- A bulk timeout follows the existing primary error and cleanup path.
- A failed or uncertain write does not authorize a subsequent success checkpoint or completion transition.
- Previously durable effects may remain after failure, as with existing independent copy/checkpoint commits.
- Retry uses existing persisted state, recaptures an unconfirmed key set, and reconciles captured keys against actual destination presence.
- Timeout selection does not alter batching, key selection, archive/purge order, accounting rules, or retry policy.
- Zero removes only the bulk-copy time limit; queries, cancellation, connectivity, and other failures retain existing behavior.
