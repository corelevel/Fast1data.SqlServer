/*
CREATE TABLE [dbo].[tmp]
(
	event_time				datetime2(7) not null,
	action_id				varchar(4) not null,
	class_type				varchar(2) not null,
	session_server_principal_name sysname null,
	database_principal_name	sysname null,
	server_principal_name	sysname null,
	server_instance_name	sysname not null,
	[database_name]			sysname null,
	[schema_name]			sysname null,
	[object_name]			sysname null,
	[statement]				nvarchar(4000) null,
	client_ip				nvarchar(128) null,
	[host_name]				nvarchar(128) null,
	application_name		nvarchar(128) null
)
GO
*/



--declare @file_pattern nvarchar(260) = 'G:\MSSQL12.MAIN\MSSQL\Audit\*'


/*
drop table ignored_statement
drop table ignored_server_principal_name
drop table ignored_database_name
drop table ignored_action_id_class_type


truncate table dbo.ignored_statement
insert	ignored_statement
select	'PRPSQLMAIN\MAIN', 'open symmetric key%'

truncate table dbo.ignored_server_principal_name
insert	dbo.ignored_server_principal_name
select	'PRPSQLMAIN\MAIN', 'NT SERVICE%'

truncate table dbo.ignored_database_name
insert	dbo.ignored_database_name
select	'PRPSQLMAIN\MAIN', 'master'

truncate table dbo.ignored_action_type_id
insert	dbo.ignored_action_type_id
select	'PRPSQLBI\BI', 'OP', 'SK'
union all
select	'PRPSQLBI\BI', 'AS', 'CR'

select * from dbo.ignored_statement
select * from dbo.ignored_server_principal_name
select * from dbo.ignored_database_name
*/

declare @file_pattern nvarchar(260) = 'C:\Temp\*'
declare @initial_file_name nvarchar(260) --= 'N:\MSSQL12.BI\MSSQL\Audit\NewAudit_2F7C46A4-9994-449C-9DB2-576A2186EBAE_0_134287422524160000.sqlaudit'
declare @audit_record_offset bigint --= 434176
declare @command nvarchar(max)

drop table #audit_stg
create table #audit_stg
(
	event_time				datetime2(7) not null,
	action_id				varchar(4) not null,
	class_type				varchar(2) not null,
	session_server_principal_name	sysname null,
	database_principal_name			sysname null,
	server_principal_name	sysname null,
	server_instance_name	sysname not null,
	[database_name]			sysname null,
	[schema_name]			sysname null,
	[object_name]			sysname null,
	[statement]				nvarchar(4000) null,
	client_ip				nvarchar(128) null,
	[host_name]				nvarchar(128) null,
	application_name		nvarchar(128) null,
	[file_name]				nvarchar(260) not null,
	audit_file_offset		bigint not null
)

set @command = '
insert	#audit_stg
(
	event_time,
	action_id,
	class_type,
	session_server_principal_name,
	database_principal_name,
	server_principal_name,
	server_instance_name,
	[database_name],
	[schema_name],
	[object_name],
	[statement],
	client_ip,
	[host_name],
	application_name,
	[file_name],
	audit_file_offset
)
select	event_time,
		action_id,
		class_type,
		session_server_principal_name,
		database_principal_name,
		server_principal_name,
		server_instance_name,
		[database_name],
		[schema_name],
		[object_name],
		[statement],' +
		case when convert(int, serverproperty('ProductMajorVersion')) >= 14 then '
		client_ip,
		[host_name],
		application_name,'
		else '
		null client_ip,
		null [host_name],
		null application_name,'
		end + '
		[file_name],
		audit_file_offset
from	sys.fn_get_audit_file(@file_pattern, @initial_file_name, @audit_record_offset) af
where not exists(select 1 from dbo.ignored_statement i where i.server_instance_name = af.server_instance_name and af.[statement] like i.[statement])
	and not exists(select 1 from dbo.ignored_server_principal_name i where i.server_instance_name = af.server_instance_name and af.server_principal_name like i.server_principal_name)
	and not exists(select 1 from dbo.ignored_database_name i where i.server_instance_name = af.server_instance_name and af.[database_name] like i.[database_name])
	and not exists(select 1 from dbo.ignored_action_id_class_type i where i.server_instance_name = af.server_instance_name and i.action_id = af.action_id and i.class_type = af.class_type)'

exec sp_executesql @command,
	N'@file_pattern nvarchar(260),
	@initial_file_name nvarchar(260),
	@audit_record_offset bigint',
	@file_pattern = @file_pattern,
	@initial_file_name = @initial_file_name,
	@audit_record_offset = @audit_record_offset

insert	dbo.easy_audit
(
	event_time,
	action_id,
	class_type,
	session_server_principal_name,
	database_principal_name,
	server_principal_name,
	server_instance_name,
	[database_name],
	[schema_name],
	[object_name],
	[statement],
	client_ip,
	[host_name],
	application_name,
	audit_guid
)
select	event_time,
		action_id,
		class_type,
		session_server_principal_name,
		case when database_principal_name = '' then null else database_principal_name end database_principal_name,
		case when server_principal_name = '' then null else server_principal_name end server_principal_name,
		server_instance_name,
		case when [database_name] = '' then null else [database_name] end [database_name],
		case when [schema_name] = '' then null else [schema_name] end [schema_name],
		case when [object_name] = '' then null else [object_name] end [object_name],
		case when [statement] = '' then null else [statement] end [statement],
		case when client_ip = '' then null else client_ip end client_ip,
		case when [host_name] = '' then null else [host_name] end [host_name],
		case when application_name = '' then null else application_name end application_name,
		try_convert(uniqueidentifier, substring([file_name], p.guid_pos, 36)) audit_guid
from	#audit_stg
		cross apply
		(
		select patindex('%[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]-%',upper([file_name])) guid_pos
		) p
select * from import_state

select	max([file_name]),
		max(audit_file_offset)
from	dbo.import_state
group by audit_guid

select * from easy_audit

declare @audit_guids	guid_array

insert @audit_guids
values ('e0ebc0ef-1b59-4e1e-ac4c-036d4082a88e'),
 ('111110ef-1b59-4e1e-ac4c-036d4082a88e')

exec stp_get_import_state @audit_guids = @audit_guids
/*
set nocount on
go
truncate table easy_audit
drop table #audit_file

select	event_time,
		action_id,
		class_type,
		session_server_principal_name,
		database_principal_name,
		server_principal_name,
		server_instance_name,
		[database_name],
		[schema_name],
		[object_name],
		[statement],
		client_ip,
		[host_name],
		application_name,
		[file_name],
		audit_file_offset
--		,*
into	#audit_file
from	sys.fn_get_audit_file(
    'C:\Temp\*',
    DEFAULT,
    DEFAULT
)

select * from #audit_file

select max([file_name]) from #audit_file


SELECT t.[file_name],
       TRY_CONVERT(uniqueidentifier,
           SUBSTRING(t.[file_name], p.GuidPos, 36)) AS AuditGuid
FROM #audit_file t
CROSS APPLY (
    SELECT PATINDEX('%[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]-%',
        UPPER(t.[file_name])
    ) AS GuidPos
) AS p
*/