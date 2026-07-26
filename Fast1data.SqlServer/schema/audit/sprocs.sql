if not exists (select 1 from INFORMATION_SCHEMA.ROUTINES where ROUTINE_NAME = 'stp_import_audit_files' and ROUTINE_SCHEMA = 'dbo' and ROUTINE_TYPE = 'PROCEDURE')
begin
	exec sp_executesql N'create procedure dbo.stp_import_audit_files as select ''Fake procedure to be replaced by alter script'''
end
go
alter procedure dbo.stp_import_audit_files
	@file_pattern		nvarchar(260),
	@initial_file_name	nvarchar(260) = null,
	@audit_file_offset	bigint = null
as
set nocount on
set xact_abort on

declare @command nvarchar(max)
declare @row_processed int = 0, @rows_imported int = 0

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
	from	sys.fn_get_audit_file(@file_pattern, @initial_file_name, @audit_file_offset) af'

	exec sp_executesql @command,
		N'@file_pattern nvarchar(260),
		@initial_file_name nvarchar(260),
		@audit_file_offset bigint',
		@file_pattern = @file_pattern,
		@initial_file_name = @initial_file_name,
		@audit_file_offset = @audit_file_offset

	select	@row_processed = count(*)
	from	#audit_stg

	if @row_processed = 0
	begin
		select 0 row_processed, 0 rows_imported
		return
	end

	begin tran

	insert	dbo.fast1_audit
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
	select	stg.event_time,
			stg.action_id,
			stg.class_type,
			stg.session_server_principal_name,
			case when stg.database_principal_name = '' then null else stg.database_principal_name end database_principal_name,
			case when stg.server_principal_name = '' then null else stg.server_principal_name end server_principal_name,
			stg.server_instance_name,
			case when stg.[database_name] = '' then null else stg.[database_name] end [database_name],
			case when stg.[schema_name] = '' then null else stg.[schema_name] end [schema_name],
			case when stg.[object_name] = '' then null else stg.[object_name] end [object_name],
			case when stg.[statement] = '' then null else stg.[statement] end [statement],
			case when stg.client_ip = '' then null else stg.client_ip end client_ip,
			case when stg.[host_name] = '' then null else stg.[host_name] end [host_name],
			case when stg.application_name = '' then null else stg.application_name end application_name,
			try_convert(uniqueidentifier, substring(stg.[file_name], p.guid_pos, 36)) audit_guid
	from	#audit_stg stg
			cross apply
			(
			select patindex('%[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]-%',upper(stg.[file_name])) guid_pos
			) p
	where not exists(select 1 from dbo.ignored_statement i where i.server_instance_name = stg.server_instance_name and stg.[statement] like i.[statement])
		and not exists(select 1 from dbo.ignored_server_principal_name i where i.server_instance_name = stg.server_instance_name and stg.server_principal_name like i.server_principal_name)
		and not exists(select 1 from dbo.ignored_database_name i where i.server_instance_name = stg.server_instance_name and stg.[database_name] like i.[database_name])
		and not exists(select 1 from dbo.ignored_action_id_class_type i where i.server_instance_name = stg.server_instance_name and i.action_id = stg.action_id and i.class_type = stg.class_type)

	set @rows_imported = @@rowcount

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

	select @row_processed row_processed, @rows_imported rows_imported
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

select	ist.audit_guid,
		ist.[file_name],
		ist.audit_file_offset
from	(
		select	ist_.audit_guid,
				max(ist_.[file_name]) [file_name]
		from	dbo.import_state ist_
		where exists(select 1 from @audit_guids v where v.[value] = ist_.audit_guid)
		group by ist_.audit_guid
		) agg
		join dbo.import_state ist
		on ist.[file_name] = agg.[file_name]
go
