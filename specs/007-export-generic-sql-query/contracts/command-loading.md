# Command Source and Loading Contract

**Feature**: [../spec.md](../spec.md) | **Public behavior**: [public-commands.md](public-commands.md)

## Source ownership

Each of the three new exported commands has one canonical definition and complete comment help in `Fast1data.SqlServer/public/<FunctionName>.ps1`. The function name and filename stem match exactly. No duplicate or forwarding definitions remain under `private/shared`.

`private/shared/GenericSqlQuery.ps1` retains private `Add-GenericSqlParameter` and `Get-GenericSqlCommand`. The descriptor type remains in its existing private class module; the factory keeps its existing literal class import. No class import is added to the moved query scripts or shared behavior.

## Initialization order

| Consumer | Loading sequence | Export boundary |
| --- | --- | --- |
| Root module | Existing class/runtime bootstrap; existing shared, audit/migration, and archiving loading; existing public-file loop loads all public definitions | Export public file basenames only; manifest retains the six explicit public names |
| Archiving model | Existing class imports; existing shared loader; explicitly dot-source `../../public/Invoke-Fast1GenericSqlQuery.ps1` and `../../public/Invoke-Fast1GenericSqlQueryReader.ps1`; remaining model dependencies and declarations | Empty function and alias exports remain unchanged |

Model public paths are literal dot-sources anchored to its `$PSScriptRoot`, inside the existing dependency `try` block immediately after shared support. The model does not enumerate the whole public directory or load the factory. A standalone model import works before root import and retains its existing dependency prerequisites.

The shared loader remains cleanup, private query support, then logging: exactly three entries. It does not load the public query files. Root does not load those files separately from its public-file loop. Each consumer creates its own function instances from the same canonical source, preserving local private helper resolution and module SessionState identity.

## Initialization failures

Missing, parse-invalid, and runtime-failing required query files terminate standalone model initialization through its existing error boundary and restore the prior error preference. Root's mandatory archiving model load occurs before public discovery, so these query dependency failures must also terminate root initialization before public exports succeed. Fault-injection checks must prove both paths; do not rely on public enumeration alone to detect an absent file.

Retain existing actionable stage/path error context and original inner errors. Do not add connection strings or parameter values to messages. Import from an unrelated working directory must resolve only the selected distribution's files.

## Required verification

- AST inspection: each expected public file defines its matching function and help; none of those public definitions exists under `private/shared`.
- Exact source provenance: root/model query functions point to the matching public `ScriptBlock.File` under the selected distribution, while Module and SessionState identities remain independently owned.
- Dependency inventory: all 23 private files remain accounted for; separately verify the model's two explicit public references without including them in the private count. Keep the three-entry shared loader assertion.
- Failure coverage: both public query files, both consumers, and missing/parse/runtime failures must reject initialization.
- Export coverage: exactly six root exports for manifest/direct imports; empty nested exports; unchanged public parameter metadata snapshot.
- Distribution coverage: source and staged imports, standalone model-first loading, existing five loading patterns by six operation orders, and available supported native hosts. Recalculate case totals only for actual added tests.

No new module, wrapper, duplicated implementation, dependency, or generic loading framework is introduced.
