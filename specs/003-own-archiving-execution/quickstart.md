# Validation Guide: Own Archiving Execution

The controlled suite performs no SQL setup or real connection opens. The integration suite creates three disposable databases; excluding an Integration tag does not make that file SQL independent because its global setup creates databases and deploys SQL objects.

## Prerequisites

PowerShell 7.6+ Core on supported x64 hosts, verified compatible Pester, PSScriptAnalyzer, SqlServer and bundled SqlClient assets. If assets are absent, use existing build/build.ps1 with .NET 10 SDK. No dependency upgrade.

Select the test server and credentials in the test file. The login must be allowed to create and drop databases, deploy the archiving schema, and perform the source, destination, constraint and failure-injection operations exercised by the tests. All three test databases use the same instance. Production execution compares actual configuration/source server identities and accepts aliases of the same instance. Use stable configuration, PKs and one process per group.

`Archiving.Integration.Tests.ps1` defines one connection string containing Data Source, User ID and Password in its `BeforeAll` block. The checked-in settings use `pester-srv`, login `pester` and password `pester`. Setup generates unique configuration/source/destination database names for each run, creates the databases, and deploys `schema/archiving/tables.sql` then `sprocs.sql` into the configuration database. Each test registers unique fixture identities; per-test teardown removes injections and fixture objects. Suite teardown attempts to drop every successfully created database, including after partial setup failure, and reports cleanup failure after attempting the remaining databases. Database connections have pooling disabled so teardown can release the test databases.

## Commands

From repository root, after configuring the server and credentials in the test file:

```powershell
Import-Module ./Fast1data.SqlServer/Fast1data.SqlServer.psd1 -Force
Get-Command Invoke-Fast1Archiving -Syntax
Get-Help Invoke-Fast1Archiving -Full
$controlled = New-PesterConfiguration
$controlled.Run.Path = './Fast1data.SqlServer/tests/Archiving.Execution.Tests.ps1'
$controlled.Run.PassThru = $true
$controlled.TestRegistry.Enabled = $false
$controlled.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $controlled

$sql = New-PesterConfiguration
$sql.Run.Path = './Fast1data.SqlServer/tests/Archiving.Integration.Tests.ps1'
$sql.Run.PassThru = $true
$sql.TestRegistry.Enabled = $false
$sql.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $sql
```

Run in fresh `pwsh -NoProfile` processes after class changes. Pester 6.2.0 was used here; disabling its unused TestRegistry prevents temporary registry-key access in restricted Windows sessions. No Pester container inputs are required; the public command signature is unchanged.

Fresh-process import checks (run each separately):

```powershell
pwsh -NoProfile -Command { Import-Module ./Fast1data.SqlServer/Fast1data.SqlServer.psd1 -Force; Get-Command Invoke-Fast1Archiving -Syntax }
pwsh -NoProfile -Command { Import-Module ./Fast1data.SqlServer/Fast1data.SqlServer.psm1 -Force; Get-Command Invoke-Fast1Archiving -Syntax }
```

## SQL evidence protocol

Observe through fresh connections independent of execution handles/transactions. Before failure record expected captured PKs; after failure/retry inspect source/destination key sets, ProcessState positions/counts/phase/overall markers, retained source working positions/keys/flags and table existence. Inspect source sys.foreign_keys.is_disabled/is_not_trusted scoped to exact fixture constraints. Keep safe evidence before teardown.

For each interruption invoke the same execution request, inspect committed truth after it throws, remove only the interruption and retry same group without editing state. No whole-fixture rollback transaction: it obscures independent durability. See [data-model.md](data-model.md) and [contract](contracts/archiving-execution.md).

| Scenario | Required setup and observations |
| --- | --- |
| Compatibility | Archive/purge/combined, inactive/both-disabled, unknown/empty group and empty set; retain special/missing-column fixtures. Preserve keys, settings, order, markers and no-work behavior. |
| Retained copy interruption | Preserve fixture with earlier committed batch; earlier copies/checkpoint survive; retry has no duplicate/missing key. Retain recorded-count assertions. |
| Retained delete interruption | Preserve trigger fixture; earlier deletions durable, failed range incomplete; retry finishes captured set, outside keys untouched. |
| Post-copy checkpoint failure | Scoped test-only ProcessState trigger/procedure wrapper rejects advancing checkpoint after real copy. Durable keys/lagging state/tables observed; retry reconciles. |
| Post-delete checkpoint failure | Reject advancing purge checkpoint after real delete without a transaction spanning both. Absent keys/lagging state observed; retry tolerates absence, preserves outside keys, invents no counts. |
| Transition failures | Separately fail maximum, capture-date, archive/purge/overall-complete writes. Block later work/markers/removal; retain needed state; remove fault and retry from persisted truth. |
| Set stability | Change eligibility/add outside rows after confirmed capture and committed-copy/checkpoint failure, including a destination row excluded by current eligibility. Same captured set remains; destination presence still reconciles without duplicate/skipped keys; outside rows never purged. Include composite PKs and enough keys to cross the reconciliation parameter/page bound. |
| Capture interruption | Fail capture/confirmation before KeyCopyDate persists; partial keys not a completed set; existing recreation retained. |
| DisableFK failure | Inbound source FKs; delete and separately checkpoint failure with DisableFK enabled. Restore before release; enabled/trusted bits inspected; purge/overall incomplete. Use unequal table/process IDs. |
| Partial disabling | Multiple FKs, failure after one real disable. Entire possible scope restored/attempted; original error primary; inspect all FKs. |
| Restore failure | Fail one restore, permit another, with/without prior error. Independent attempts continue; no new purge/overall success; identify primary/secondary contexts. |
| Earlier table completed | Later table fails; earlier durable completion retained and failing process/set preserved. |

Checkpoint triggers target the uniquely registered table's process and specific transition; independent observer connections prove the preceding effect already committed. FK action substitutions run real DDL and fail only the selected disable/restore action. Partial capture/snapshot substitutions write actual keys before throwing. No fixture-wide transaction spans effects and checkpoints. Keep batch and checkpoint interruption fixtures distinct. Mocks cannot establish SQL durability/trust.

## Controlled ownership/error cases

Cross same execution request using narrow private resource/SQL seams; no public injection flags. Assert order and every attempted cleanup:

- Source open fails after configuration opens: dispose acquired handles, including allocated failed-open connection; opening error remains primary.
- Destination open fails after configuration/source open: release both earlier connections, destination allocation and transient objects.
- Partial disable throws: restore before required connection release. DisableFK off produces zero toggles.
- Operation plus restore/dispose/logging failures: preserve original ErrorRecord and all contexts while continuing independent attempts.
- Cleanup-only failure terminates. Failed restoration blocks new completion; later drop/disposal failure does not erase completion.
- No-work/success/batch failure/parameter setup failure/multiple disposal failures attempt release of every acquired reader/command/bulk-copy/connection.
- Review caller for zero progress mutation/separate checkpoint/FK/disposal sequencing. Verify traversal, copy-before-purge, PurgeOrder, batches/delays.

## Static checks and reporting

Run Invoke-ScriptAnalyzer on every changed .ps1/.psm1/.psd1 including tests, with repository settings when available. Resolve new warnings/errors without suppressing rules. Run affected shared-helper/audit/migration regressions if shared SQL cleanup changes. Verify import/exports and platform compatibility; unavailable hosts reported explicitly.

Report safe fixture IDs, runtime/runner versions, passed/failed/skipped/unverified checks separately. Observe execution cleanup before teardown. An unavailable test server or insufficient database provisioning permissions leaves SQL checks **unverified** and blocks release until required evidence exists.

See [validation.md](validation.md) for executed results, safe fixture evidence and platform limitations. Preserve the original error and inspect cleanup contexts before fixture teardown; successful teardown cannot prove execution itself restored constraints.
