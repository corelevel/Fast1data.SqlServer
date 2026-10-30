## PowerShell Formatting
- Follow *PSScriptAnalyzer* formatting conventions with these overrides:
	- Always use multiline blocks for control-flow statements, including if, else, elseif, switch, foreach, for, while, and try/catch/finally.
	- Place the opening brace { on the same line as the statement.
	- Place the closing brace } on its own line, aligned with the statement.
	- Indent the block body with one tab.
	- Never use single-line control-flow blocks, even when the body contains only one statement.
	- Correct:
	```pwsh
	if (-not $IsLinux) {
		throw 'Unsupported operating system. Audit discovery supports Windows and Linux.'
	}
	```
	- Incorrect:
	```pwsh
	if (-not $IsLinux) { throw 'Unsupported operating system. Audit discovery supports Windows and Linux.' }
	```