create server audit [easy_audit_00]
to file (filepath = 'C:\Temp\', maxsize = 1024 MB, max_files = 4, reserve_disk_space = off)
with (queue_delay = 1000, on_failure = continue)
go
alter server audit [easy_audit_00] with (state = on)
go

create server audit specification [easy_audit_spec_00]
for server audit [easy_audit_00]
add (audit_change_group),
add (database_change_group),

add (database_object_change_group),
add (database_object_ownership_change_group),
add (database_object_permission_change_group),

add (database_ownership_change_group),
add (database_permission_change_group),
add (database_principal_change_group),
add (database_role_member_change_group),

add (schema_object_change_group),
add (schema_object_ownership_change_group),
add (schema_object_permission_change_group),

add (server_object_change_group),
add (server_object_ownership_change_group),
add (server_object_permission_change_group),

add (server_permission_change_group),
add (server_principal_change_group),

add (server_role_member_change_group),

add (dbcc_group)
with (state = on)
go