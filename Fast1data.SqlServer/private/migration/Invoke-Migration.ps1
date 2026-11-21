<#
.SYNOPSIS
Validates a complete migration file and executes its original T-SQL batches.

.DESCRIPTION
Uses the bundled TSql160Parser with quoted identifiers initially enabled. Reads and
validates the whole file before allocating execution resources. Rejects SQLCMD
directives, counted GO and reserved substitutions. Rejected and zero-batch files
allocate no execution resources. Zero-batch files do not validate ConnStr beyond
mandatory parameter binding.

For an executable file, suppresses ambient transactions, creates/opens a connection
from the original ConnStr, and creates an owned command with timeout 0. Runs original
batch slices once on that session and requires final @@TRANCOUNT = 0. Always attempts
command, connection, then suppression-scope disposal before returning success.
Cleanup failure prevents history. History uses separate borrowed resources through
Set-Executed; this executor never receives or modifies them.

Temporary objects and settings survive GO within a file. Pooling may reuse reset
physical sessions between files. Authors must finish explicit SQL transactions;
there is no automatic commit. Committed work can survive runtime/history/cleanup
failure, so scripts must be idempotent. Context excludes secrets and SQL source;
underlying exceptions remain available programmatically.

.PARAMETER ConnStr
Original target connection string. Mandatory and forwarded unchanged to a new
owned connection for executable files. Empty files do not validate its contents.
Authentication and configured/default catalog come from
this string. No caller-created connection, command or external token object is needed.
.PARAMETER Script
Literal path of the complete migration file to read and validate before execution.
#>
function Invoke-Migration {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$ConnStr,

		[Parameter(Mandatory)]
		[string]$Script
	)

	try {
		$path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Script)
		$source = [System.IO.File]::ReadAllText($path)
	}
	catch {
		throw [System.IO.IOException]::new("Migration '$Script': read failed.", $_.Exception)
	}

	# A substitution spelling is reserved in every lexical context, including comments.
	$substitution = [regex]::Match($source, '\$\([^\r\n)]+\)')
	if ($substitution.Success) {
		$prefixLines = [regex]::Split($source.Substring(0, $substitution.Index), '\r\n|\r|\n')
		$line = $prefixLines.Count
		$column = $prefixLines[-1].Length + 1
		throw [System.IO.InvalidDataException]::new(
			"Migration '$Script': unsupported substitution at line $line, column $column.",
			[System.FormatException]::new('Reserved SQLCMD substitution syntax.')
		)
	}

	$parser = [Microsoft.SqlServer.TransactSql.ScriptDom.TSql160Parser]::new($true)
	$reader = [System.IO.StringReader]::new($source)
	try {
		$lexicalErrors = $null
		$tokens = $parser.GetTokenStream($reader, [ref]$lexicalErrors)
	}
	finally {
		$reader.Dispose()
	}
	if ($lexicalErrors.Count -gt 0) {
		$diagnostic = $lexicalErrors[0]
		$cause = [System.FormatException]::new('ScriptDom rejected script tokenization.')
		$cause.Data['ParseDiagnostics'] = @($lexicalErrors | Select-Object Number, Line, Column, Offset)
		throw [System.IO.InvalidDataException]::new(
			"Migration '$Script': lexical error $($diagnostic.Number) at line $($diagnostic.Line), column $($diagnostic.Column).",
			$cause
		)
	}
	for ($index = 0; $index -lt $tokens.Count; $index++) {
		$token = $tokens[$index]
		if ($token.TokenType -in @('WhiteSpace', 'SingleLineComment', 'MultilineComment', 'EndOfFile')) {
			continue
		}
		$linePrefix = $source.Substring($token.Offset - $token.Column + 1, $token.Column - 1)
		if (-not [string]::IsNullOrWhiteSpace($linePrefix)) {
			continue
		}
		$unsupported = $null
		if ($token.TokenType -eq 'Colon' -or
			($token.TokenType -eq 'Bang' -and $source.Substring($token.Offset).StartsWith('!!')) -or
			$token.Text -in @('QUIT', 'EXIT', 'RESET', 'ED', 'LIST')) {
			$unsupported = 'directive'
		}
		if ($token.TokenType -eq 'Go') {
			for ($next = $index + 1; $next -lt $tokens.Count; $next++) {
				$following = $tokens[$next]
				if ($following.Line -ne $token.Line) {
					break
				}
				if ($following.TokenType -in @('WhiteSpace', 'SingleLineComment', 'MultilineComment')) {
					continue
				}
				if ($following.TokenType -eq 'Integer') {
					$unsupported = 'counted GO'
				}
				break
			}
		}
		if ($null -ne $unsupported) {
			throw [System.IO.InvalidDataException]::new(
				"Migration '$Script': unsupported $unsupported at line $($token.Line), column $($token.Column).",
				[System.FormatException]::new('Unsupported SQLCMD construct.')
			)
		}
	}

	$reader = [System.IO.StringReader]::new($source)
	try {
		$parseErrors = $null
		$parsed = $parser.Parse($reader, [ref]$parseErrors)
	}
	finally {
		$reader.Dispose()
	}
	if ($parseErrors.Count -gt 0) {
		$diagnostic = $parseErrors[0]
		$cause = [System.FormatException]::new('ScriptDom rejected the complete migration file.')
		$cause.Data['ParseDiagnostics'] = @($parseErrors | Select-Object Number, Line, Column, Offset)
		throw [System.IO.InvalidDataException]::new(
			"Migration '$Script': parse error $($diagnostic.Number) at line $($diagnostic.Line), column $($diagnostic.Column).",
			$cause
		)
	}
	# Validate every span before mutation, even if an unexpected parser result occurs.
	$batches = @($parsed.Batches | Where-Object { $_.Statements.Count -gt 0 })
	foreach ($batch in $batches) {
		if ($batch.StartOffset -lt 0 -or $batch.FragmentLength -le 0 -or
			$batch.StartOffset -gt $source.Length - $batch.FragmentLength) {
			throw "Migration '$Script': parser returned an invalid batch source span."
		}
	}
	if ($batches.Count -eq 0) {
		return
	}
	$executionCommand = $null
	$executionConnection = $null
	$suppressionScope = $null
	$operationError = $null
	$stage = 'ambient suppression'
	try {
		$suppressionScope = Get-MigrationSuppressionScope
		$stage = 'script connection construction'
		$executionConnection = Get-MigrationScriptConnection -ConnStr $ConnStr
		$stage = 'script connection open'
		$executionConnection.Open()
		$stage = 'execution command creation'
		$executionCommand = Get-MigrationScriptCommand -Connection $executionConnection
		$executionCommand.CommandTimeout = 0
		$ordinal = 0
		foreach ($batch in $batches) {
			$ordinal++
			$stage = "batch $ordinal at line $($batch.StartLine), column $($batch.StartColumn)"
			$executionCommand.Parameters.Clear()
			$executionCommand.CommandType = [System.Data.CommandType]::Text
			$executionCommand.CommandText = $source.Substring($batch.StartOffset, $batch.FragmentLength)
			$null = $executionCommand.ExecuteNonQuery()
		}
		$stage = 'transaction completion validation'
		$executionCommand.Parameters.Clear()
		$executionCommand.CommandType = [System.Data.CommandType]::Text
		$executionCommand.CommandText = 'SELECT @@TRANCOUNT;'
		$transactionCount = $executionCommand.ExecuteScalar()
		if ($null -eq $transactionCount -or $transactionCount -is [System.DBNull] -or [int]$transactionCount -ne 0) {
			throw [System.InvalidOperationException]::new('The script must complete all explicit transactions before returning.')
		}
	}
	catch {
		try {
			throw [System.InvalidOperationException]::new("Migration '$Script': $stage failed.", $_.Exception)
		}
		catch {
			$operationError = $_
		}
	}
	finally {
		try {
			Close-GenericSqlResource -Resources ([ordered]@{ ExecutionCommand = $executionCommand; ExecutionConnection = $executionConnection; SuppressionScope = $suppressionScope }) `
				-PrimaryError $operationError -Context @{ Script = $Script }
		}
		catch {
			# Cleanup-only failures also prohibit completion; keep provider text out of context.
			try {
				throw [System.InvalidOperationException]::new("Migration '$Script': execution resource cleanup failed.", $_.Exception)
			}
			catch {
				$operationError = $_
			}
		}
	}
	if ($null -ne $operationError) {
		$PSCmdlet.ThrowTerminatingError($operationError)
	}
}

# Narrow lifecycle seams allow failure injection without replacing the provider contract.
function Get-MigrationScriptConnection {
	param ([string]$ConnStr)
	[Microsoft.Data.SqlClient.SqlConnection]::new($ConnStr)
}

function Get-MigrationScriptCommand {
	param ([Microsoft.Data.SqlClient.SqlConnection]$Connection)
	$Connection.CreateCommand()
}

function Get-MigrationSuppressionScope {
	[System.Transactions.TransactionScope]::new([System.Transactions.TransactionScopeOption]::Suppress)
}
