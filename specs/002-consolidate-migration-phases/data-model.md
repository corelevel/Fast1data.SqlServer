# Data Model: Migration Phase Evaluation

**Scope**: Private in-process values and existing persisted history. No schema or public API additions. See [research.md](research.md) and [contracts/migration-command.md](contracts/migration-command.md).

## Migration phase

| Field | Meaning / validation |
| --- | --- |
| `Phase` | Literal selected JSON property name; do not interpret wildcard characters. |
| `ConfigFile` | Absolute path to existing `migration.json`. Missing configuration terminates evaluation. |
| `PhaseDirectory` | Absolute existing directory for the selected phase. |
| `ConfiguredScripts` | Ordered names from the phase's `scripts` array. An existing empty array is valid; a missing phase is an error. |

A phase owns ordered script decisions. History for other phases is not an input to its matching map.

## Script identity and operator selections

Names from configuration, history, ignore, and force share separator normalization and ordinal case-insensitive matching. Preserve displayed/file-lookup spelling; matching does not imply case-insensitive filesystem lookup. Convert contained rooted names to phase-relative spelling before identity/storage. Preserve relative spelling without general path-alias deduplication.

`IgnoreScripts` and `ForceScripts` are normalized membership sets, not additional scripts. Reject their intersection even if a conflicted name is absent from configuration. Reject configured duplicates under the same identity rules. Unknown nonconflicting selections yield warnings. Unconfigured historical entries never create work.

## Existing execution history entry

| Field | Existing SQL type | Meaning |
| --- | --- | --- |
| `phase` | `nvarchar(32)` | Selected phase, supplied to existing parameterized SQL. |
| `script_name` | `nvarchar(255)` | Original stored key, preserved exactly until a write locates it. |
| `checksum` | `char(64)` | Recorded SHA-256 for successfully recorded execution. |
| `executed_at` | `datetime2(7)` | Database UTC timestamp; default on insert, refreshed on forced update. |

The existing primary key is `(phase, script_name)`. No collation/schema change or history repair is planned. Evaluation creates a normalized matching view while retaining the original name as `HistoryScriptName`. Database equality must not substitute for phase identity rules. A forced update predicates on the original key and writes the evaluated normalized name; values remain parameterized.

## Script decision

| Field | Type | Meaning |
| --- | --- | --- |
| `ScriptName` | string | Normalized phase-relative identity, display name, and intended persisted name. |
| `FullPath` | string | Absolute file location retaining configured filesystem casing. Must be strictly inside the phase directory, even when ignored. |
| `Checksum` | string or null | Current SHA-256 for every non-ignored file; null for ignored entries. |
| `WasExecuted` | bool | Whether supplied phase history matched this identity. |
| `HistoryScriptName` | string or null | Original matched persisted name for update lookup; null when no history matches. |
| `IsForced` | bool | Whether the identity is in the force set. |
| `Action` | `Run` or `Skip` | Eligibility, not evidence of execution. |
| `Reason` | `New`, `Forced`, `Ignored`, `AlreadyExecuted` | Explanation of the decision. |

Decisions preserve configured order. Containment uses full-path resolution and a directory-separator boundary with Windows ordinal case-insensitive and Unix ordinal comparison. Ignored entries need not exist and are never hashed. Force exempts drift rejection only.

| Ignored | Forced | In history | File/checksum condition | Result |
| --- | --- | --- | --- | --- |
| Yes | Yes | Any | Any | Global selection conflict: error before decisions return. |
| Yes | No | Any | Contained; existence/hash irrelevant | `Skip / Ignored`. |
| No | No | No | Contained file; checksum obtained | `Run / New`. |
| No | No | Yes | Current checksum equals recorded checksum | `Skip / AlreadyExecuted`. |
| No | No | Yes | Checksum differs | Error identifying script and expected/current checksums. |
| No | Yes | Any | Contained file; checksum obtained | `Run / Forced`; update if historical, otherwise insert. |

## Phase evaluation

One completed object contains `Phase`, `ConfigFile`, `PhaseDirectory`, `Scripts` (an explicit ordered array of decisions), and `Warnings` (an explicit ordered string array). Empty and single-entry results retain the same shape. Warnings distinguish unknown ignore and force names and identify the selections.

Return this object only after every configured entry passes applicable validation. Failure throws a terminating error; no executable partial result is exposed. The object is an unlocked snapshot of files/history and contains no credentials or completed-execution claims.

## Execution lifecycle owned by the command

`Inputs → Complete evaluation → ShouldProcess → Execute script → Record success → Next eligible script`.

- Validation failure: no script execution or history mutation.
- Preview or declined confirmation: display evaluation; no mutating calls.
- Empty/all-skipped phase: indicate no work; no mutating calls.
- Execution failure: terminate; no history for the failed script; retain previous progress.
- Recording failure after execution: terminate before later scripts; SQL effects may exist without history. Retry may execute the script again, so scripts must be idempotent.
- Successful new/forced-new execution: insert normalized name and checksum once.
- Successful forced historical execution: update the matched original key to normalized name, checksum, and current execution time. Skips never update history.
