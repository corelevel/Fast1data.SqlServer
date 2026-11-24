# Fast1 Audit

[Back to the module README](README.md)

Fast1 Audit imports [SQL Server Audit](https://learn.microsoft.com/en-us/sql/relational-databases/security/auditing/sql-server-audit-database-engine) (`.sqlaudit`) files into a SQL Server database. It stores the last processed file and file offset so later runs resume instead of rereading the complete audit history.

## Requirements

- SQL Server with SQL Server Audit enabled
- A target database, such as `fast1_audit`
- Read access to the directory containing the `.sqlaudit` files
- SQL login permissions to execute the Fast1 Audit stored procedures and read audit data (see [Database setup](#database-setup))

The audit path is used by two processes:

- PowerShell scans it to discover audit files
- The SQL Server service reads it through `sys.fn_get_audit_file`

For a remote SQL Server, use a UNC path accessible to both the PowerShell user and the SQL Server service account.

Discovery supports Windows local/UNC directories using the current Windows identity, and Linux UNC shares using `smbclient` installed in PATH and a supplied `PSCredential`. Linux roots may include nested directories and spaces. Credentials supplied on Windows are unused. Discovery inspects filenames only; SQL Server reads audit contents independently under its service account. Discovery credentials do not grant SQL Server file access.

A successful listing with no valid audit filenames returns no files. An unreadable directory, invalid Linux request, missing `smbclient`, or failed listing terminates discovery before any files are offered for import. Check the folder/share path, PowerShell identity or Linux listing credentials, network access, and executable installation before retrying. A native failure includes its exit code and available diagnostic context. Resolve SQL Server service-account read permissions separately if discovery succeeds but importing fails. Audit discovery is unsupported on other operating systems.

Note: **only one process should import a given audit directory at a time.**

Linux discovery temporarily supplies the SMB password through process `PASSWD`, then restores its previous presence and value after success, no matches, process failure, or invocation failure. Passwords are excluded from process arguments and redacted from listing errors. Serialize discovery calls within a host process because they borrow process environment state. Supply credentials interactively with `Get-Credential` or from an approved secret store; keep passwords out of scripts and logs.

## Database setup

Create the target database, connect to it, and execute these scripts in order:

1. [`schema/audit/tables.sql`](Fast1data.SqlServer/schema/audit/tables.sql)
2. [`schema/audit/sprocs.sql`](Fast1data.SqlServer/schema/audit/sprocs.sql)

The module login needs permission to execute:

- `dbo.stp_get_import_state`
- `dbo.stp_import_audit_files`

The module's database user also needs `EXECUTE` and `REFERENCES` on the table type `dbo.guid_array`, or equivalent permissions on its schema or database, because `dbo.stp_get_import_state` receives a table-valued parameter of that type. Procedure execution permissions alone do not grant these type permissions. See Microsoft's [table-valued parameter permissions reference](https://learn.microsoft.com/en-us/sql/relational-databases/tables/use-table-valued-parameters-database-engine#permissions).

The importer calls `sys.fn_get_audit_file` through dynamic SQL. In addition to procedure execution permissions, the module login needs the following server-level permission on the SQL Server instance used for importing:

- SQL Server 2019 (15.x) and earlier: `CONTROL SERVER`
- SQL Server 2022 (16.x) and later: `VIEW SERVER SECURITY AUDIT`

See Microsoft's [`sys.fn_get_audit_file` permissions reference](https://learn.microsoft.com/en-us/sql/relational-databases/system-functions/sys-fn-get-audit-file-transact-sql#permissions).

The SQL Server service account must independently have read access to the audit files. SQL login permissions and procedure execution permissions do not grant service-account file access.

### Parameters

| Parameter    | Required | Description                                     |
| ------------ | -------- | ----------------------------------------------- |
| `ConnStr`    | Yes      | Connection string for the target database       |
| `Folder`     | Yes      | Existing directory containing `.sqlaudit` files |
| `Credential` | On Linux | SMB listing credentials; unused on Windows      |

Detailed command help is also available:

```powershell
Get-Help Invoke-Fast1Audit -Full
```

## Import behavior

For each unique audit GUID discovered in the directory, the module:

1. Retrieves the last saved filename and offset
2. Calls `sys.fn_get_audit_file` through `dbo.stp_import_audit_files`
3. Applies the configured ignore rules
4. Inserts accepted records into `dbo.fast1_audit`
5. Updates the checkpoint in `dbo.import_state`

The checkpoint advances for every processed record, including ignored records. This prevents ignored records at the end of a file from being read repeatedly.

With `-Verbose`, progress resembles:

```text
3 audit file(s) found in the folder
1 unique audit GUID(s) found
150 audit records processed
142 audit records imported
```

Progress messages use the verbose stream; warnings use the warning stream. Use PowerShell stream redirection if you need to save output to a file.

## Ignore rules

These tables control which records are excluded:

- `dbo.ignored_statement`
- `dbo.ignored_server_principal_name`
- `dbo.ignored_database_name`
- `dbo.ignored_action_id_class_type`

Entries are scoped by `server_instance_name`. Statement, principal, and database values use SQL `LIKE`, so wildcard patterns such as `%text%` are supported.

Example:

```sql
insert dbo.ignored_database_name
(
	server_instance_name,
	database_name
)
values
(
	'SQL01',
	'tempdb'
);
```

## Usage

- An example server audit and audit specification is available in [`example/audit/audit-00.sql`](example/audit/audit-00.sql)
- Review its destination path, audit actions, retention settings, and failure behavior before running it. Creating server audits requires suitable SQL Server permissions
- Run
```powershell
$connectionString = @'
Data Source=<server>;
Initial Catalog=fast1_audit;
Encrypt=True;
TrustServerCertificate=False;
Integrated Security=True;
Application Name=Fast1data.SqlServer;
'@

Invoke-Fast1Audit `
	-ConnStr $connectionString `
	-Folder '\\audit-server\sql-audit' `
	-Verbose
```
- Imported audit data will be in the `dbo.fast1_audit` table

The connection example validates the server certificate. Configure SQL Server with a certificate trusted by the client and use a server name matching that certificate. See Microsoft's [`TrustServerCertificate` reference](https://learn.microsoft.com/en-us/dotnet/api/microsoft.data.sqlclient.sqlconnectionstringbuilder.trustservercertificate).

## Linux tests

Run the self-contained tests from the repository root in PowerShell 7 with Pester 5 or later:

```powershell
Invoke-Pester -Path ./Fast1data.SqlServer/tests/Audit.Linux.Tests.ps1 -Output Detailed
```

These tests call `Invoke-Fast1Audit` with a temporary executable standing in for
`smbclient`. They cover Linux credentials, UNC validation, filename filtering,
multiple audit GUIDs, empty listings, failed listings, password redaction, and
restoration of the process environment. No SMB share or SQL Server is needed.
Successful discovery stops at an intentionally invalid SQL connection string;
these tests do not verify imported database records. They skip on other operating
systems. Do not run environment-changing tests concurrently in one PowerShell process.

## Live integration tests

The live suites are
[`Audit.Integration.Linux.Tests.ps1`](Fast1data.SqlServer/tests/Audit.Integration.Linux.Tests.ps1)
and [`Audit.Integration.Windows.Tests.ps1`](Fast1data.SqlServer/tests/Audit.Integration.Windows.Tests.ps1).
They check initial imports, checkpoint reuse without duplicate records, and
checkpoint advancement when all records are ignored. They run automatically when
selected on their corresponding operating system and skip on other operating systems.

Set the required environment variables in the PowerShell session before running
Pester:

| Environment variable | Value | Required on |
| --- | --- | --- |
| `FAST1_TEST_AUDIT_SQL_CONN_STR` | SQL Server connection string for a disposable test instance | Windows and Linux |
| `FAST1_TEST_AUDIT_FOLDER` | Folder containing closed audit files | Windows and Linux |
| `FAST1_TEST_AUDIT_SMB_USER` | SMB user name | Linux |
| `FAST1_TEST_AUDIT_SMB_PASSWORD` | SMB user password | Linux |

Windows discovery uses the current Windows identity, independently of the SQL
login. Linux uses the SMB credentials and requires a backslash UNC folder.
For remote Windows SQL Server instances, use a UNC path; a local path must refer
to the same files on both hosts. Missing or blank required configuration fails
setup. Supply credentials locally or through your CI secret store.

Each suite reads expected record counts and audit GUIDs directly from
`sys.fn_get_audit_file` before running the importer. It compares the imported
records against that source baseline.

Prepare these prerequisites:

- On Linux, install `smbclient` in PATH. Build the module's bundled SQL client as described in the [README](README.md).
- Supply real, closed `.sqlaudit` files in the configured folder. Keep its contents unchanged during the run; do not use an active audit output directory. Prefer multiple files for one GUID and at least two distinct audit GUIDs. Empty files with audit-shaped names are insufficient.
- The SQL login needs permission to create/drop a database, deploy the audit schema, and read audit data through `sys.fn_get_audit_file`. The SQL Server service must independently have read access to the audit folder. The Linux SMB account or current Windows user needs permission to list that folder.

Each suite creates a uniquely named `fast1_audit_test_*` database, installs the
repository's audit schema, and drops that database in `AfterAll`, including after
assertion failures. It does not use an existing `pester_audit` database. An
interrupted PowerShell process may leave its test database behind. The share is
read-only to the tests. Missing prerequisites or connection failures fail the run.

Run from the repository root in PowerShell:

```powershell
$env:FAST1_TEST_AUDIT_SQL_CONN_STR = 'Server=YOUR_TEST_SERVER;Initial Catalog=master;Integrated Security=True;Encrypt=True'
$env:FAST1_TEST_AUDIT_FOLDER = '\\YOUR_TEST_SERVER\audit\closed'

# Linux only; supply the password through your local or CI secret store.
$env:FAST1_TEST_AUDIT_SMB_USER = 'DOMAIN\audit-reader'
$env:FAST1_TEST_AUDIT_SMB_PASSWORD = '<SMB password>'

Invoke-Pester -Path ./Fast1data.SqlServer/tests/Audit.Integration.Linux.Tests.ps1 -Output Detailed
```

Use the SQL authentication and encryption options required by your test
environment. On Windows, run `Audit.Integration.Windows.Tests.ps1` instead;
the SMB variables are not required.

To run all audit suites without accessing live services, exclude the integration tag:

```powershell
Invoke-Pester -Path ./Fast1data.SqlServer/tests/Audit*.Tests.ps1 -ExcludeTag Integration -Output Detailed
```
