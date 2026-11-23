# Contract: Archiving Bulk Copy Timeout

**Feature**: `009-add-bulk-copy-timeout` | **Status**: Planned

## Administrator configuration

`dbo.SourceTable.BulkCopyTimeout` is a required SQL `int`, measured in seconds, independently configurable per source table.

| Input | Contract |
| --- | --- |
| Omitted on insert | Store 30. |
| `0` | Store zero; disable the bulk-copy time limit. |
| `1` through `2147483647` | Store unchanged; apply as seconds. |
| Negative integer | Reject insert/update with a database check constraint. |
| Explicit `NULL` | Reject insert/update with `NOT NULL`. |

An invalid update leaves the prior value intact. The field/default/check exist on fresh installation. Rerunning `schema/archiving/tables.sql` does not add the field to an existing table.

## Metadata interface

`dbo.stp_GetSourceTable` keeps its `@TableGroupId int` input, existing result fields, and `Active = 1`/group filtering. Add the result field `BulkCopyTimeout` with SQL `int` type and no null values. Consumers must locate it by name; no new ordinal guarantee is introduced.

`TableGroup.ReadSourceTables()` must copy the field unchanged into the typed table model. The model property has no initializer; the database supplies the default for omitted inserts. Private direct construction must explicitly supply a timeout before copying. Missing metadata is an unprepared-installation error; this feature supplies no automatic fallback or schema repair.

## Runtime behavior

Before every `SqlBulkCopy.WriteToServer`, set that object's `BulkCopyTimeout` to the owning table's loaded value in all three operations:

1. Source primary keys to the source-key working table.
2. Destination primary keys to the destination-key working table, including every reconciliation page.
3. Archive data to the destination table, including every archive batch.

Zero must be assigned explicitly. Tables in one group must not inherit one another's values. A skipped stage need not execute. Existing streaming, copy options, mappings, batching, cleanup, error visibility and progress/retry rules continue to apply.

Ordinary `SqlCommand.CommandTimeout` behavior, including the connection string's `Command Timeout` where already applicable, is independent and unchanged. Unlimited bulk waiting does not disable query timeouts or other failures.

## Command compatibility

`Invoke-Fast1Archiving -ConnStr <string> -GroupName <string>` retains its required parameters, public export, common parameters and existing output/error behavior. This setting adds no command parameter or success object. Guide and command help must explain the configuration and installation prerequisites.

## Existing-installation prerequisite

Before running the changed module, the administrator must:

1. Stop active runs and select the intended configuration database using existing administrative controls.
2. Manually add the required integer field, populate **every preexisting row with 30**, establish a default of 30 for future omitted inserts, and add/validate the nonnegative check and non-null requirement.
3. Deploy the updated `dbo.stp_GetSourceTable` after storage is prepared.
4. Verify existing row values, default/check/nullability, and returned metadata before resuming one process per group.

`Fast1Archiving.md` must contain this complete order and explain create-only setup. No migration scripts or automatic table alteration are shipped. Preserve existing configuration and progress; do not reset working sets as an upgrade step. The release must record an explicit module-version decision and corresponding release notes.

## Acceptance evidence

The implementation must produce controlled evidence at all three actual write boundaries and live SQL evidence for defaults, accepted/rejected values, metadata, real waiting/timeout, manual preparation, unchanged query limits, and existing failure/retry behavior. Required scenarios and commands are in [quickstart.md](../quickstart.md); entity invariants are in [data-model.md](../data-model.md).
