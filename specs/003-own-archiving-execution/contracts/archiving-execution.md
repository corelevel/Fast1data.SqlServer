# Archiving Execution Contract

## Existing public command

```powershell
Invoke-Fast1Archiving -ConnStr <string> -GroupName <string>
```

Preserve mandatory string/common parameters, manifest export and PowerShell 7.6 Core/x64 Windows/Linux/macOS support. Configuration/source share an instance; source PKs and one process per group remain required. Configuration, procedure signatures, progress fields and working names remain compatible. No new success object, public executor, fault-injection parameter or transaction option.

## Private execution request

```powershell
Invoke-ArchivingProcess -ConnStr <string> -GroupName <string>
```

Public forwarding and acceptance tests use this same request. It constructs an inert TableGroup and requests Execute. Callers supply inputs and handle outcome; they never acquire/dispose the group, drive progress, write checkpoints or restore constraints. Private model fields/methods are not a caller coordination protocol.

## Outcomes and ordering

- Unknown group terminates with identifying error. Empty group, disabled tables and empty sets retain existing no-work/logging/completion behavior and release resources.
- Active rows retain supplied preparation/archive traversal, group copy-before-purge and PurgeOrder sorting. Preserve batch settings, delays, destination preparation and reconciliation.
- Confirmed transitions precede completion. Successful restoration precedes new purge/overall markers. Normal working-table removal follows overall completion.
- Invocation succeeds only with required cleanup success. Later drop/disposal failure is returned without erasing committed completion.

## Failure and retry

Effects/checkpoints commit independently; failure never promises rollback. Stop later processing, attempt cleanup and retain incomplete state/required working tables. Uncertain transition responses cannot authorize continuing; fresh execution reloads persisted truth.

Retry same group with stable configuration, corrected cause and no concurrent invocation. Confirmed captured keys remain authoritative. Reconcile actual destination presence against retained captured keys independently of current eligibility before resumed copy; revisit retained purge ranges and tolerate absent rows. Missing capture confirmation retains recapture behavior. Recorded totals can lag effects and are not exactly-once counts.

## Constraints

DisableFK remains explicit group configuration. Capture/register inbound source child FKs referencing the configured source table before disabling. Attempt restoration on every exit after disabling begins, including partial failure and checkpoint failure, before connection release. Attempt each independently. WITH NOCHECK CHECK preserves enabled/untrusted policy; invalid existing rows are not repaired. Disabling off means no purge-related toggles.

Failed restoration prevents new purge/overall success and identifies source database/child table/FK. Server outage or hard termination can prevent cleanup success; operator inspection remains necessary.

## Errors and diagnostics

Preserve original operation ErrorRecord/exception and cause/stack as primary. Merge cleanup failures into Exception.Data['Fast1Archiving.CleanupFailures']: Action, GroupName, optional SourceTable/ProcessStateId, ResourceRole or source constraint identity, ErrorType and safe Message. Do not obscure the primary with unconditional aggregate exceptions.

If processing succeeded, first cleanup failure becomes primary and terminates invocation; remaining cleanup still runs. Logging follows the same precedence. Added contexts/logs never contain credentials, connection strings or sensitive SQL. Caller has no additional cleanup protocol.

## Acceptance evidence

All tests cross this request. Controlled seams establish attempts/error precedence; independent real SQL connections to explicitly selected test databases establish durability and enabled/trusted status. See [quickstart.md](../quickstart.md) and [data-model.md](../data-model.md).
