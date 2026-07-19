if not exists (select 1 from INFORMATION_SCHEMA.ROUTINES where ROUTINE_NAME = 'stp_import_audit_files' and ROUTINE_SCHEMA = 'dbo' and ROUTINE_TYPE = 'PROCEDURE')
begin
	exec sp_executesql N'create procedure dbo.stp_import_audit_files as select ''Fake procedure to be replaced by alter script'''
end
go
alter procedure dbo.stp_import_audit_files
	@file_pattern			nvarchar(260) ,
	@initial_file_name		nvarchar(260),
	@audit_record_offset	bigint
as
set nocount on

declare @max_audit_record_offset bigint
declare @command nvarchar(max)

begin try
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

	if not exists(select 1 from #audit_stg)
	begin
		return
	end

	begin tran

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

	merge	dbo.import_state with(serializable) as t
	using	(
			select	[file_name],
					max_audit_file_offset,
					try_convert(uniqueidentifier, substring([file_name], p.guid_pos, 36)) audit_guid
			from	(
					select	[file_name],
							max(audit_file_offset) max_audit_file_offset
					from	#audit_stg
					group by [file_name]
					) agg
					cross apply
					(
					select patindex('%[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]-%',upper([file_name])) guid_pos
					) p
			) as s
			on t.[file_name] = s.[file_name]
	when matched
		and t.audit_file_offset <> s.max_audit_file_offset
	then update
		set	t.audit_file_offset = s.max_audit_file_offset,
			t.modified_at = sysutcdatetime()
	when not matched by target
	then insert ([file_name], audit_file_offset, audit_guid, modified_at)
		values (s.[file_name], s.max_audit_file_offset, audit_guid, sysutcdatetime());

	commit tran
end try
begin catch
    if @@trancount > 0 rollback transaction
	;throw
end catch
go

if not exists (select 1 from INFORMATION_SCHEMA.ROUTINES where ROUTINE_NAME = 'stp_get_import_state' and ROUTINE_SCHEMA = 'dbo' and ROUTINE_TYPE = 'PROCEDURE')
begin
	exec sp_executesql N'create procedure dbo.stp_get_import_state as select ''Fake procedure to be replaced by alter script'''
end
go
alter procedure dbo.stp_get_import_state
	@audit_guids	guid_array readonly
as
set nocount on

select	max([file_name]) [file_name],
		max(audit_file_offset) audit_file_offset
from	dbo.import_state ist
where exists(select 1 from @audit_guids v where v.[value] = ist.audit_guid)
group by audit_guid
go