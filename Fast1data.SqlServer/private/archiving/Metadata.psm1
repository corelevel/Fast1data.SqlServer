class TableColumn {
	[string]$Name
	[string]$DataType
	[string]$SqlType
	[int]$SqlSize
	[byte]$SqlPrecision
	[byte]$SqlScale
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
