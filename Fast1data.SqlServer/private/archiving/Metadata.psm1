class TableColumn {
	[string]$Name
	[string]$DataType
	[string]$Collation
	[bool]$Computed
	[bool]$Nullable
}

class IndexColumn {
	[int]$Id
	[string]$Name
	[string]$Order
}

class Index {
	[string]$Name
	[bool]$Unique
}
