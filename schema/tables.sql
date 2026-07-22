create table dbo.ignored_statement
(
	server_instance_name	sysname not null,
	[statement]				nvarchar(322) not null
)
go
alter table dbo.ignored_statement add constraint pk_ignored_statement primary key clustered (server_instance_name, [statement])
go

create table dbo.ignored_server_principal_name
(
	server_instance_name	sysname not null,
	server_principal_name	sysname not null
)
go
alter table dbo.ignored_server_principal_name add constraint pk_ignored_server_principal_name primary key clustered (server_instance_name, server_principal_name)
go

create table dbo.ignored_database_name
(
	server_instance_name	sysname not null,
	[database_name]			sysname not null
)
go
alter table ignored_database_name add constraint pk_ignored_database_name primary key clustered (server_instance_name, [database_name])
go

create table dbo.ignored_action_id_class_type
(
	server_instance_name	sysname not null,
	action_id				varchar(4) not null,
	class_type				varchar(2) not null
)
go
alter table dbo.ignored_action_id_class_type add constraint pk_ignored_action_id_class_type primary key clustered (server_instance_name, action_id, class_type)
go

create table dbo.easy_audit
(
	easy_audit_id			bigint identity(1, 1),
	event_time				datetime2(7) not null,
	action_id				varchar(4) not null,
	class_type				varchar(2) not null,
	session_server_principal_name	sysname null,
	database_principal_name	sysname null,
	server_principal_name	sysname null,
	server_instance_name	sysname not null,
	[database_name]			sysname null,
	[schema_name]			sysname null,
	[object_name]			sysname null,
	[statement]				nvarchar(4000) null,
	client_ip				nvarchar(128) null,
	[host_name]				nvarchar(128) null,
	application_name		nvarchar(128) null,
	audit_guid				uniqueidentifier not null
)
go
alter table dbo.easy_audit add constraint pk_easy_audit primary key nonclustered (easy_audit_id)
go
create clustered index ixc_easy_audit__event_time on dbo.easy_audit (event_time)
with (sort_in_tempdb = on, online = on, data_compression = page)
go

drop table dbo.import_state
go
create table dbo.import_state
(
	import_state_id		int identity(1, 1),
	[file_name]			nvarchar(260) not null,
    audit_record_offset	bigint not null,
	audit_guid			uniqueidentifier not null,
    modified_at			datetime2(7) not null
)
alter table dbo.import_state add constraint pk_import_state primary key nonclustered (import_state_id)
with (data_compression = page)
go

create type guid_array as table 
(
	[value] uniqueidentifier not null
)
go
