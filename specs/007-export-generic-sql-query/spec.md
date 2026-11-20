# Feature Specification: Export Invoke-Fast1GenericSqlQuery

**Status**: Public command file relocation implemented on 2026-11-20. Full source/staged Windows validation and the subsequent audit reruns are recorded in quickstart.md. The full staged run passed 507 tests with 26 expected skips; four earlier source audit setup failures were resolved after fixture repair. Current Windows query, migration, archiving and audit SQL acceptance plus both public SQL smokes passed. Native Linux/macOS execution remains unverified; full cross-platform release acceptance is not established.

**Input amendment**: Move the new exported functions from `Fast1data.SqlServer/private/shared` to `Fast1data.SqlServer/public`. Each filename must match its function name.

## Purpose

Expose `Invoke-Fast1GenericSqlQuery` as a public command for scalar and non-query execution. Add a separate public command that retrieves query rows through the PowerShell pipeline, plus a public factory for typed SQL parameters. Refactor `Get-Executed` to retrieve migration history through the new row command. Make each new exported command easy for maintainers to locate by placing its definition in a matching file under `Fast1data.SqlServer/public`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Locate each public command by name (Priority: P1)

As a maintainer, I can locate the definition and help for each new exported command in the public directory using its command name as the filename.

**Why this priority**: This is the requested amendment and makes the new commands follow the repository's public command convention.

**Independent Test**: Inspect the three public files listed in FR-001 and confirm that each contains its matching command definition and help, with no duplicate definition remaining in the private shared directory.

**Acceptance Scenarios**:

1. **Given** the two query commands currently defined in the private shared directory, **When** the relocation is complete, **Then** each definition and its help reside in its own matching public file.
2. **Given** the parameter factory already has a matching public file, **When** the amendment is applied, **Then** that file remains its canonical definition.
3. **Given** shared support functions are used by public commands, **When** the command definitions move, **Then** those support functions remain private and are not newly exported.

### User Story 2 - Continue using the existing command contracts (Priority: P1)

As a module user, I can continue running parameter creation, scalar queries, silent non-query execution, row queries, migrations, and archiving after the public command files move.

**Why this priority**: Source organization must preserve the existing user and internal caller contracts.

**Independent Test**: Import both the source and packaged module through their supported entry points, exercise the acceptance checks below, and verify migration-history retrieval and archiving query callers.

**Acceptance Scenarios**:

1. **Given** either supported root import entry point (manifest or direct module file), **When** the module is imported, **Then** all six existing public commands are available and internal helpers remain hidden.
2. **Given** an open caller-owned connection and factory-created parameters, **When** either query command executes, **Then** its inputs, outputs, errors, cleanup, and connection ownership follow the agreed decisions below.
3. **Given** migration-history retrieval or archiving invokes a relocated command, **When** the workflow runs, **Then** command resolution succeeds in its existing module scope and the established results and cleanup behavior are preserved.

### Edge Cases

- A command moved out of the shared directory must remain available to archiving's independently loaded module scope as well as to the root module.
- A duplicate definition left behind in the private shared directory must fail the layout acceptance check, even if root import succeeds.
- A public filename that differs from its defined command name must fail the layout acceptance check, even if an explicit export makes the command callable.
- A packaged distribution must include all three public files and preserve supported imports; source-only success is insufficient.
- Empty results, invalid column names, typed null and binary values, late read failures, early pipeline termination, and cleanup failures retain the outcomes specified below.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Each of the three commands introduced by this feature MUST have its canonical definition and command help in the following public file. The filename stem MUST exactly match the function name.

  | Exported function | Required file |
  | --- | --- |
  | `Invoke-Fast1GenericSqlQuery` | `Fast1data.SqlServer/public/Invoke-Fast1GenericSqlQuery.ps1` |
  | `Invoke-Fast1GenericSqlQueryReader` | `Fast1data.SqlServer/public/Invoke-Fast1GenericSqlQueryReader.ps1` |
  | `New-Fast1GenericSqlParam` | `Fast1data.SqlServer/public/New-Fast1GenericSqlParam.ps1` |

- **FR-002**: The two query command implementations MUST move out of `Fast1data.SqlServer/private/shared/GenericSqlQuery.ps1`. No duplicate or forwarding definition of the three public commands may remain in `private/shared`; shared support functions and the parameter descriptor type MUST remain private.
- **FR-003**: Manifest and direct root module imports, from both source and packaged distributions, MUST expose exactly the existing six public functions: `Invoke-Fast1Audit`, `Invoke-Fast1Migration`, `Invoke-Fast1Archiving`, `Invoke-Fast1GenericSqlQuery`, `Invoke-Fast1GenericSqlQueryReader`, and `New-Fast1GenericSqlParam`. The manifest MUST continue to enumerate public commands explicitly.
- **FR-004**: Relocation MUST preserve all command names, parameters, defaults, help, output, errors, resource ownership, and cleanup behavior described in the agreed decisions and acceptance checks below.
- **FR-005**: Existing internal callers, including `Get-Executed` and archiving's independently loaded module scope, MUST continue to resolve the relocated query commands and preserve their existing behavior.
- **FR-006**: Affected usage documentation MUST identify the public command files consistently. Layout, exports, supported source/packaged imports, query behavior, cleanup, migration, and archiving regression checks MUST verify the amendment before it is marked implemented.

## Agreed decisions

Revision on 2026-11-20: the maintainer chose to revise the API instead of granting
analyzer exceptions and explicitly requested the name `Invoke-Fast1GenericSqlQueryReader`.
It continues to emit materialized row objects and owns its internal reader.
`New-Fast1GenericSqlParam` provides standard `-WhatIf`/`-Confirm`
support for descriptor creation, with low confirmation impact. Normal calls return
one descriptor; WhatIf returns none. Internal read-only history discovery explicitly
disables these factory switches so migration previews can still read history.

- Export the command as `Invoke-Fast1GenericSqlQuery`.
- Preserve `-Scalar`: return the first column of the first result row.
- Preserve the default operation: execute a non-query without emitting the affected-row count.
- Add a separate command for retrieving rows instead of adding a `-Rows` switch to `Invoke-Fast1GenericSqlQuery`.
- Name the row command `Invoke-Fast1GenericSqlQueryReader`. Give it the same `-SqlConn`, `-Query`, `-CommandType`, and `-Parameters` inputs as the existing query command, without an execution-mode switch.
- The row command emits one PowerShell object per row, with properties corresponding to SQL columns.
- Read rows incrementally through an internally managed SQL reader rather than buffering the complete result or returning a live reader to the caller.
- The function is responsible for disposing its reader and command.
- Return only the first tabular result set. Subsequent result sets are not emitted.
- Map SQL `NULL` to PowerShell `$null`; retain native types for other column values, including byte arrays for binary values.
- Reject unnamed columns and case-insensitive duplicate column names before emitting any rows. Require SQL aliases to provide usable names.
- Export `New-Fast1GenericSqlParam` so public callers can construct the existing typed parameter descriptors without importing a private module path.
- Require `-Type` on `New-Fast1GenericSqlParam`; accept optional `-Value`, `-Size`, `-Precision`, and `-Scale`. Omitting `-Value` represents SQL `NULL`.
- Accept valid SQL types including `SqlDbType.BigInt` (enum value zero), while rejecting a genuinely missing type. Correct the existing validation in support of this public contract.
- The caller supplies an already-open `-SqlConn` and remains responsible for its lifetime. The query commands leave it open.
- Reading failures terminate execution. Rows already emitted remain delivered; streaming does not promise all-or-nothing output.
- Dispose owned resources on success, failure, and early pipeline termination.
- Refactor the existing private `Get-Executed` function to use `Invoke-Fast1GenericSqlQueryReader` for migration-history reads.

## Get-Executed integration

- Retain the existing `Get-Executed -ConnStr -Phase` signature and keep the function private.
- `Get-Executed` continues to create, open, and dispose its own connection. It passes that open connection to `Invoke-Fast1GenericSqlQueryReader`, which owns the command and reader.
- Preserve the query against `dbo.fast1_migration_history` and its `phase = @phase` filter.
- Construct the phase descriptor through `New-Fast1GenericSqlParam -Type NVarChar -Size 32 -Value $Phase` and pass it through the row command's `-Parameters` hashtable.
- Stream the row command's output directly, retaining `script_name` and `checksum` as the output properties and emitting nothing when history is empty.
- Preserve persisted script-name spelling, case, and separators exactly. Migration phase evaluation continues to own identity normalization.
- Replace the local command construction, parameter binding, reader loop, and command/reader disposal with delegation to the new row command. Retain connection cleanup and primary-error preservation in `Get-Executed`.

## Public command examples

The caller imports the module and opens `$connection` before these calls, and disposes the connection afterward.

```powershell
$parameters = @{
	Id = New-Fast1GenericSqlParam -Type BigInt -Value 42
}

# Stream objects from the first tabular result set.
Invoke-Fast1GenericSqlQueryReader -SqlConn $connection `
	-Query 'SELECT Id, Name FROM dbo.Example WHERE Id = @Id' `
	-Parameters $parameters |
	Export-Csv -Path './example.csv' -NoTypeInformation

# Preserve scalar execution.
$count = Invoke-Fast1GenericSqlQuery -SqlConn $connection `
	-Query 'SELECT COUNT(*) FROM dbo.Example' -Scalar

# Preserve silent non-query execution.
Invoke-Fast1GenericSqlQuery -SqlConn $connection `
	-Query 'UPDATE dbo.Example SET Name = NULL WHERE Id = @Id' `
	-Parameters $parameters

# A typed SQL NULL parameter.
$nullName = New-Fast1GenericSqlParam -Type NVarChar -Size 100
```

## Acceptance checks

- Each of the three new public commands has its definition and help in the matching public file listed in FR-001, and none retains a definition in `private/shared`.
- Manifest and direct root module imports expose exactly the six public commands in FR-003 for both source and packaged distributions.
- Existing archiving callers resolve the relocated query commands in their independently loaded module scope without a root import prerequisite.
- External callers can create and use a parameter through `New-Fast1GenericSqlParam` without resolving the private class name or importing a private module path.
- Existing scalar and silent non-query callers retain their behavior.
- Row execution handles empty, single-row, and multiple-row results; an empty result emits no objects.
- A command without a tabular result emits no row objects. Only the first tabular result set is emitted when several are returned.
- Row properties retain column names and order, map SQL `NULL` to `$null`, and preserve native non-null value types, including binary arrays as individual property values.
- Empty and case-insensitively duplicate column names fail before rows are emitted, including when the result set is empty.
- The factory maps supported metadata, represents an omitted value as SQL `NULL`, and requires an explicit SQL type.
- Both query commands accept `BigInt`; genuinely missing SQL types remain invalid.
- Reader creation, row reading, and resource cleanup failures follow the existing cleanup error policy and do not dispose the borrowed connection.
- Readers and commands are released on normal completion, failure, and early pipeline termination. Previously emitted rows are retained when a later read fails.
- `Get-Executed` delegates history retrieval to `Invoke-Fast1GenericSqlQueryReader` with the correct query, open connection, and phase parameter (`NVarChar`, size `32`).
- `Get-Executed` preserves empty and populated history output, including exact stored script names and checksums, and continues to support existing migration consumers.
- The row command disposes the history reader and command before `Get-Executed` disposes its connection on success, failure, and early pipeline termination. Cleanup failures preserve the primary operation error under the existing cleanup policy.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Maintainers can locate all three new public command definitions and their help directly by command name, with zero filename mismatches or duplicate definitions.
- **SC-002**: Users can discover and invoke all six existing public commands through every supported source and packaged import entry point, with zero additional internal commands exposed.
- **SC-003**: All acceptance checks for parameter creation, scalar and non-query execution, row retrieval, migration history, archiving, and resource ownership pass after relocation, with zero regressions attributable to the amendment.

## Assumptions

- This amendment updates the current feature, `specs/007-export-generic-sql-query`; it does not create a separate feature or request production changes in this specification step.
- "New exported functions" means the three commands introduced by this feature. The factory already meets the public filename requirement and remains in place.
- Filenames use the exact function spelling and the `.ps1` extension, consistent with existing public commands.
- The existing shared support functions, descriptor type, dependency loading, and independently loaded archiving scope remain dependencies of the relocated commands. No public signature or supported runtime change is requested.
- Constitution principles IV and V apply: retain explicit manifest exports and portable public contracts, update affected help/documentation, and validate affected imports and packaging. Existing data integrity, migration, and database operation guarantees continue to apply.
- Existing plan, research, and completed tasks describe the preceding implementation. Their decisions to retain query definitions in the shared file are superseded by FR-001 and FR-002; planning and task updates are required before implementing this amendment.

## Scope and unchanged defaults for final review

- The new row command uses the existing command timeout behavior. No new connection-string, timeout, or transaction options are introduced by this feature.
- Internal shared helpers remain private; the three public command definitions belong to the public files listed in FR-001.
- Implementation includes public exports, help and usage documentation, the `Get-Executed` refactor, and appropriate query, parameter, cleanup, module-loading, and migration regression verification.

## Prior authorization and amendment readiness

The preceding implementation was authorized on 2026-11-20 when the maintainer replied "Yes, confirm and implement" to the complete contract. The relocation amendment was implemented through T035–T056. Available Windows source/staged offline and SQL evidence, successful audit reruns and remaining native-host limitations are recorded in quickstart.md; implementation completion does not establish full cross-platform release acceptance.
