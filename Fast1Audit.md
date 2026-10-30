# Fast1 Audit

[Back to the module README](README.md)

Fast1 Audit imports [SQL Server Audit](https://learn.microsoft.com/en-us/sql/relational-databases/security/auditing/sql-server-audit-database-engine) (`.sqlaudit`) files into a SQL Server database. It stores the last processed file and file offset so later runs resume instead of rereading the complete audit history.

## Requirements

- SQL Server with SQL Server Audit enabled
- A target database, such as `fast1_audit`
- Read access to the directory containing the `.sqlaudit` files
- Permission to execute the Fast1 Audit stored procedures

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

SQL Server must also be able to read the audit files through `sys.fn_get_audit_file`.

### Parameters

| Parameter    | Required | Description                                     |
| ------------ | -------- | ----------------------------------------------- |
| `ConnStr`    | Yes      | Cconnection string for the target database      |
| `Folder`     | Yes      | Existing directory containing `.sqlaudit` files |
| `LogFile`    | No       | File to which progress messages are appended    |
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

When `-LogFile` is supplied, the same messages are appended to that file.

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
TrustServerCertificate=True;
Integrated Security=True;
Application Name=Fast1data.SqlServer;
'@

Invoke-Fast1Audit `
	-ConnStr $connectionString `
	-Folder '\\audit-server\sql-audit' `
	-LogFile '.\fast1-audit.log' `
	-Verbose
```
- Imported audit data will be in the `dbo.fast1_audit` table
