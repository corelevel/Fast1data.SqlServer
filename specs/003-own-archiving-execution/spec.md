# Feature Specification: Own Archiving Execution

**Feature Branch**: `dev` (existing branch; no branch hook configured)

**Created**: 2026-10-30

**Status**: Draft

**Input**: User description: "The caller coordinates batch effects, mutable ProcessState, separate checkpoint writes and foreign-key restoration. Purge errors bypass re-enabling; a TableGroup constructor can fail after opening a connection before the caller can assign and dispose it. Deepen execution so ordering, progress and acquired resources are owned together. Retain copy/delete interruption fixtures; add checkpoint-write failure, partial connection-open failure and DisableFK-enabled purge failure, with real SQL durability checks. Effects span connections and consolidation does not make them atomic. Preserve working sets, processing order, incomplete state and documented constraint-trust behavior. Preserve the original error and handle cleanup failure. Absorb exposed ProcessState sequencing into execution; deleting it or splitting the large file alone is insufficient."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Resume from actual batch effects (Priority: P1)

As an archiving operator, I need interrupted execution to recover from saved progress and actual completed work, including when saving progress fails after a successful batch, so retry does not skip unfinished records or duplicate archived keys.

**Why this priority**: Progress that gets ahead of effects can silently lose data. Assuming checkpoint failure rolled back a successful batch can make recovery unsafe.

**Independent Test**: Invoke the same execution interface against dedicated SQL Server fixtures, interrupt copying, deleting or checkpoint writing, inspect durable rows and progress through independent connections, remove the interruption, and retry the same group.

**Acceptance Scenarios**:

1. **Given** a later copy batch fails, **When** execution stops, **Then** prior committed copies and saved progress remain, unfinished work is not marked complete, and retry reconciles destination records and completes without duplicate archived keys.
2. **Given** a later delete batch fails, **When** execution stops, **Then** earlier committed deletions remain, progress does not claim the failed batch completed, and retry finishes the original working set.
3. **Given** a copy batch commits and its following checkpoint write fails, **When** the failure reaches the caller, **Then** copied rows remain durable, saved progress can lag those rows, required working tables and incomplete state remain, and retry reconciles actual copies without duplicating keys or skipping unfinished records.
4. **Given** a delete batch commits and its following checkpoint write fails, **When** the failure reaches the caller, **Then** deleted rows remain absent, saved progress can lag that deletion, and retry safely revisits the original working set, including already absent rows, without deleting records outside it.
5. **Given** phase or overall completion recording fails, **When** execution stops and is retried, **Then** no later work proceeds on an unconfirmed transition, required recovery information remains available, and retry uses persisted state and actual effects rather than assuming rollback or completion.

---

### User Story 2 - Recover resources and constraints on failure (Priority: P1)

As an archiving operator, I need opened resources released and temporarily disabled foreign keys re-enabled when execution fails, with the original error still identifiable, so a failed run does not silently leave an unsafe or unexplained operating state.

**Why this priority**: Resources can be acquired before initialization finishes, and purge exceptions currently bypass constraint restoration. Cleanup can also fail and obscure the original cause.

**Independent Test**: Fail initialization after an earlier connection opens, fail purging with foreign-key disabling enabled, and separately fail cleanup. Observe release attempts, constraint status, retained recovery state and the returned error through the same execution interface.

**Acceptance Scenarios**:

1. **Given** the configuration connection opens but opening the source connection fails, **When** initialization exits, **Then** all acquired resources are released without the caller receiving a successfully initialized group, and the opening failure remains primary.
2. **Given** configuration and source connections open but opening the destination connection fails, **When** initialization exits, **Then** both earlier connections and other acquired resources are released and the destination-opening failure remains identifiable.
3. **Given** foreign keys were disabled for purge and a delete or checkpoint operation fails, **When** execution unwinds, **Then** restoration is attempted before its required resources are released, successful restoration leaves affected keys enabled under the existing trust policy, and unfinished state and required working tables remain available for retry.
4. **Given** disabling fails after changing some foreign keys, **When** execution unwinds, **Then** restoration is attempted for constraints this invocation may have changed and the disabling error remains primary.
5. **Given** an operation fails and restoration or disposal also fails, **When** execution exits, **Then** the original error remains primary, each cleanup failure is exposed with actionable context, and remaining independent cleanup actions are still attempted.
6. **Given** processing succeeds but required cleanup fails, **When** execution exits, **Then** the caller receives a failure identifying the cleanup action; failed restoration prevents newly recording purge or overall completion for the affected process.
7. **Given** foreign-key disabling is off, **When** processing succeeds or fails, **Then** execution performs no purge-related constraint toggles.

---

### User Story 3 - Invoke execution without coordinating its internals (Priority: P2)

As a maintainer of an archiving caller, I need to request a configured group execution without coordinating batches, progress writes, constraint restoration or resource disposal, so callers cannot accidentally omit required ordering rules.

**Why this priority**: A single execution contract reduces caller mistakes and makes success and failure behavior testable together.

**Independent Test**: Exercise successful and failed group runs through one execution interface. Review its caller to confirm it supplies inputs and handles outcomes without driving execution through mutable progress or separate batch and cleanup calls.

**Acceptance Scenarios**:

1. **Given** archive-only, purge-only, combined and disabled tables, **When** their group executes, **Then** existing selection, skipping, table traversal, group copy-before-purge ordering, configured purge order, batch settings, delays and destination reconciliation rules are preserved.
2. **Given** a working set was durably captured for an incomplete process, **When** source eligibility changes and execution retries, **Then** the captured working set is resumed rather than replaced with a fresh selection.
3. **Given** an unknown group, an empty group or an empty working set, **When** execution is requested, **Then** existing error or no-work behavior is retained and acquired resources are released.
4. **Given** a caller supplies only the existing connection, group and optional logging inputs, **When** execution succeeds or fails, **Then** execution owns all required state transitions and cleanup, without the caller reading or changing process progress to drive execution.

### Edge Cases

- A copy partially succeeds before throwing, or commits before its checkpoint fails; neither implies committed copies disappeared.
- A delete commits before its checkpoint fails; retry encounters absent rows and must preserve existing recorded-count semantics rather than invent missing counts.
- A progress callback reports activity before durability is established; activity alone is not evidence of committed progress.
- Key capture or its completion checkpoint fails; partial key capture must not be treated as a completed working set.
- Archiving completes but purge fails; archive completion can remain recorded while overall processing remains incomplete.
- Restoration fails because a connection is unusable or permission is denied; the action and potentially affected constraints must remain identifiable.
- Re-enabled foreign keys remain untrusted; enabled status does not imply validated historical rows or repaired integrity.
- One resource fails disposal while others still require cleanup; remaining independent cleanup attempts must proceed.
- One table completes before another fails; completed work is retained and the failing process keeps required recovery information.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Execution MUST own initialization, selection, batch effects, progress transitions, completion, constraint restoration and acquired resource cleanup behind one execution boundary. Its caller MUST NOT drive these actions by inspecting or mutating process state or separately writing checkpoints.
- **FR-002**: Execution MUST preserve existing active-table selection, disabled-table skipping, supplied table traversal, group copy-before-purge ordering and configured purge ordering. Archive-only, purge-only and combined behavior, batch sizes, delays, destination preparation and reconciliation choices MUST remain compatible.
- **FR-003**: Retry MUST preserve the captured working set and incomplete persisted process after successful key capture. Execution MUST retain the distinction between incomplete key capture and a completed working set, including existing recovery behavior for interrupted key capture.
- **FR-004**: Saved batch progress MUST follow successful batch effects and MUST NOT advance past unfinished work. Phase and overall completion MUST follow required work and successful preceding progress transitions. A failed required transition MUST stop subsequent processing and surface to the caller.
- **FR-005**: Execution and recovery guidance MUST account for independently committed copy, purge and checkpoint effects across connections. Checkpoint failure MUST NOT be treated as rollback of prior effects. Consolidation MUST NOT claim atomic execution or introduce a distributed-transaction requirement.
- **FR-006**: After interrupted copying or a failed post-copy checkpoint, retry MUST reconcile destination keys against the retained working set before continuing, avoiding duplicate archived keys and skipped unfinished records. After interrupted deleting or a failed post-delete checkpoint, retry MUST safely revisit retained ranges, tolerate absent records and restrict deletion to the original working set. Existing recorded-row-count semantics MUST be preserved, and their limitations after effects commit without checkpoints MUST be documented.
- **FR-007**: Failed processing MUST retain incomplete state and working tables needed for recovery; resource cleanup MUST NOT discard them. Successful execution MUST preserve the existing lifecycle for completion records and working-table removal.
- **FR-008**: Execution MUST own disposable resources from acquisition, including initialization before a group can be returned. Success, no-work returns and failure MUST attempt release of every acquired resource. One cleanup failure MUST NOT prevent remaining independent cleanup attempts.
- **FR-009**: With foreign-key disabling enabled, execution MUST attempt re-enabling on every exit after disabling begins, including partial disabling, delete failure and checkpoint failure, before releasing required resources. Failed restoration MUST be reported and MUST prevent newly recording purge or overall success for the affected process.
- **FR-010**: Constraint handling MUST preserve its existing scope and documented trust behavior: re-enabling does not require validating historical rows or making constraints trusted. With disabling off, execution MUST perform no purge-related constraint toggles. Guidance MUST identify affected source constraints and retain the documented possibility of untrusted constraints and invalid existing data.
- **FR-011**: If an operation and cleanup both fail, the original operation error MUST remain primary and identifiable. Every encountered cleanup failure MUST be exposed as a secondary failure identifying the action and affected group, table or resource without exposing secrets. Cleanup failure without a prior operation failure MUST cause the invocation to fail.
- **FR-012**: Existing copy-batch and delete-batch interruption fixtures MUST be retained. Acceptance coverage MUST add checkpoint-write failures after committed copy and delete effects, both partial connection-open failures, and purge failure with foreign-key disabling enabled. Coverage MUST also establish partial-disabling recovery, cleanup failure with and without an earlier operation error, and remaining cleanup attempts after cleanup failure. Tests MUST cross the same execution interface without caller coordination of mutable progress.
- **FR-013**: Real SQL Server checks in explicitly selected test databases MUST establish durability and constraint behavior. Independent observations MUST inspect source/destination keys, persisted checkpoints and completion markers, retained working sets, and constraint enabled/trusted status after failure and retry. Controlled failure tests MAY establish cleanup attempts and error precedence; mocks alone MUST NOT establish SQL durability. Unavailable checks MUST be reported as unverified.
- **FR-014**: The public command and parameters, existing configuration and persisted-state formats, supported runtime/platform contract, primary-key prerequisite, same-instance configuration/source requirement and single-process-per-group restriction MUST remain compatible. Affected operator guidance MUST explain recovery and cleanup behavior without revealing credentials.
- **FR-015**: Acceptance MUST demonstrate that caller-level mutable progress and checkpoint sequencing have been absorbed into execution. Removing a process-state type while spreading persistence details among callers, or merely splitting a large file, MUST NOT satisfy this requirement. Internal representation remains a planning decision.

### Key Entities *(include if feature involves data)*

- **Table group execution**: One invocation for a configured group, its table order, resources, outcome and failures.
- **Table work configuration**: Existing source/destination identities, archive/purge choices, selection, ordering, batch settings, delays and reconciliation settings.
- **Captured working set**: Persisted selected primary keys and batch positions, retained across retries after successful key capture.
- **Process progress**: Key-capture status, batch positions, recorded totals and completion markers; these may lag independently committed effects after failure.
- **Constraint cleanup obligation**: Constraints the invocation may have disabled and must attempt to re-enable under the existing trust policy.
- **Execution failure**: The primary processing or cleanup error, accompanying secondary failures and recovery context.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All retained copy/delete interruption cases and both new post-effect checkpoint-failure cases resume to the expected final record set, with zero duplicate archived keys, zero skipped unfinished selected records and zero deletions outside the captured working set.
- **SC-002**: In every tested processing failure, saved progress never claims unfinished batch work and the affected process is not newly marked complete; independently observed committed effects remain visible despite checkpoint failure.
- **SC-003**: Both partial connection-open cases attempt cleanup of every acquired resource. Every tested exit after constraint disabling begins attempts restoration; successful restoration leaves affected constraints enabled under the documented trust policy.
- **SC-004**: In every combined operation/cleanup failure case, the operator can identify the original cause and each cleanup failure. Every cleanup-only failure is returned as a failure, with zero false success reports.
- **SC-005**: One execution request suffices for all success and failure acceptance cases, with zero caller-managed progress mutations, separate checkpoint writes, constraint-restoration calls or resource-disposal ordering rules.
- **SC-006**: All compatibility cases for archive-only, purge-only, combined operations, no work, captured working sets, processing order and existing incomplete state retain their expected outcomes. All required durability and constraint-status checks have real persisted-state evidence before release.

## Assumptions

- Scope is existing archiving execution. This feature adds no concurrency, cancellation, selection rules, automatic integrity repair, new persistence formats or atomic cross-connection execution. Retaining or removing an internal process-state representation is a planning choice; caller sequencing must be absorbed either way.
- Retry uses the same group with stable configuration and no concurrent process for that group. Operators retain incomplete state and required working tables and correct the failure cause before retrying.
- Preserving order means current table traversal and configured purge ordering. This feature does not add ordering guarantees for otherwise unordered tables or tied purge-order values.
- Cleanup uses best-effort attempts on failure. Hard termination or an unavailable server can prevent restoration; the guarantee is observable attempts and actionable errors, not successful restoration when the server cannot accept it.
- Existing totals describe recorded processing under current recovery semantics. Effects committed without checkpoints can leave totals behind actual effects; missing counts cannot always be reconstructed, and exactly-once counting is not promised.
- Verification requires dedicated SQL Server test databases and permissions for setup, inspection, controlled failure injection and cleanup. Production databases are not implicit test targets.
- Applicable constitution requirements are data integrity/resumability (I), explicit database operations (III), public/runtime compatibility (IV), and real SQL verification with truthful reporting (V), plus database prerequisites and recovery documentation. Later PowerShell changes require the prescribed PSScriptAnalyzer validation.
