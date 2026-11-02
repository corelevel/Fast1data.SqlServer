# Feature Specification: Consolidate Migration Phase Validation

**Feature Branch**: `dev` (existing branch; no branch hook configured)

**Created**: 2026-10-30

**Status**: Draft

**Input**: User description: "Get-Migration is shallow while phase invariants live in its caller, interleaved with execution; configuration names and history names are normalized in different places. Concentrate phase interpretation and validation inside one module, leaving execution and history recording coordinated by the command. Keep existing file and SQL implementations; this is an in-process seam, not a reason to invent another database adapter or design a new interface yet. Remove the shallow phase-reader module, retain meaningful checksum and execution behavior, share validation with preview, and exercise phase-level behavior. Retain SQL execution/history tests and WhatIf checks. Preserve idempotent-script guidance: successful execution can still precede failed history recording."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Interpret a phase consistently (Priority: P1)

As a migration operator, I need configuration, history, and ignore/force selections to identify scripts consistently, so spelling and path separators do not change which scripts run.

**Why this priority**: Inconsistent script identity can cause unintended reruns or bypass checksum comparisons.

**Independent Test**: Evaluate a selected phase with ordered nested scripts, supplied history, and operator selections through the phase interface. Compare identities, order, and run/skip decisions without executing scripts or recording history.

**Acceptance Scenarios**:

1. **Given** several phases and a selected phase with scripts deliberately not in alphabetical order, **When** it is evaluated, **Then** only the literal named phase is selected and its script order is preserved.
2. **Given** a configured nested script and history differing only in letter case or slash direction, **When** checksums match, **Then** they identify the same script and it is skipped as already executed.
3. **Given** ignore and force names differing in case or slash direction from configuration, **When** the phase is evaluated, **Then** ignored scripts are skipped and forced scripts remain eligible in configured order.
4. **Given** configured names differing only in case or slash direction, **When** the phase is evaluated, **Then** duplicate names are rejected and identified.
5. **Given** a name in both ignore and force selections under the matching rules, **When** the phase is evaluated, **Then** the conflict is rejected, even if the name is absent from configuration.
6. **Given** unmatched ignore or force names without a conflict, **When** the phase is evaluated, **Then** warnings identify those names and no extra work is added.

---

### User Story 2 - Detect phase problems before applying changes (Priority: P1)

As a migration operator, I need the entire selected phase checked before any script runs, so a known configuration, path, or checksum problem cannot leave earlier scripts applied.

**Why this priority**: Validation interleaved with execution can turn an avoidable validation error into a partial deployment.

**Independent Test**: Evaluate phases with a valid first script followed by an invalid entry or checksum drift. Verify rejection before any execution or history recording.

**Acceptance Scenarios**:

1. **Given** missing configuration, a missing selected phase, or a missing phase directory, **When** migration is requested, **Then** an actionable error identifies the missing input before any script or history mutation.
2. **Given** a valid first script followed by a duplicate, ignore/force conflict, escaping path, missing non-ignored file, or unforced checksum mismatch, **When** migration is requested, **Then** the entire phase is rejected before any script executes or history is written.
3. **Given** a configured path resolving outside the phase directory, including a sibling directory sharing its name prefix, **When** evaluated, **Then** it is rejected even if the external file exists or the entry is ignored or forced.
4. **Given** an executed script with unchanged content, **When** evaluated, **Then** it is skipped unless forced; a changed executed script without force fails with its identity and expected and current checksums.
5. **Given** an explicitly forced script with changed content, **When** evaluated, **Then** it is eligible to run while containment and file-existence checks still apply.
6. **Given** an ignored script with a missing file or changed content, **When** evaluated, **Then** it is skipped without existence or checksum errors, provided its configured path remains within the phase directory.

---

### User Story 3 - Preview the same decisions used for execution (Priority: P2)

As a migration operator, I need preview to apply the same rules as execution, so I can inspect a deployment without changing the target.

**Why this priority**: Preview is useful only when its decisions and validation failures agree with execution against the same inputs.

**Independent Test**: Compare preview and execution requests against unchanged files and history. Compare ordered eligible scripts, skips, warnings, and errors, and observe preview side effects.

**Acceptance Scenarios**:

1. **Given** new, unchanged executed, ignored, and forced scripts, **When** `-WhatIf` preview is requested, **Then** eligible scripts and order agree with execution for identical inputs, with zero script executions and history writes.
2. **Given** an invalid phase from Stories 1 or 2, **When** preview is requested, **Then** it reports the same validation failure as execution without script or history mutations.
3. **Given** an empty phase or no eligible scripts, **When** preview or execution is requested, **Then** it succeeds with a nothing-to-run indication and no script or history mutations.

---

### User Story 4 - Preserve truthful history across failures (Priority: P2)

As a migration operator, I need successful executions recorded in order and failures surfaced, so I can recover without history claiming work that failed.

**Why this priority**: Consolidating validation must preserve execution and recovery guarantees.

**Independent Test**: Retain verification against existing database behavior for new, skipped, forced, execution-failure, and history-failure cases. Observe executed scripts and persisted records.

**Acceptance Scenarios**:

1. **Given** a valid phase with new scripts, **When** execution succeeds, **Then** eligible scripts run in configured order and each success is followed by its history record using a normalized phase-relative name and checksum.
2. **Given** a forced script already in history, **When** it succeeds, **Then** its history checksum and execution time are updated; a forced script without history receives a new entry.
3. **Given** a script execution failure, **When** it occurs, **Then** the command terminates without recording that script or running later scripts, and earlier completed history remains intact.
4. **Given** successful execution followed by history-recording failure, **When** it occurs, **Then** the command terminates before later scripts, surfaces the recording failure, and does not claim rollback. Guidance continues to require idempotent scripts because retry may execute it again.

### Edge Cases

- Phase names containing wildcard characters are treated literally; wildcard selection is not introduced.
- An empty script list in an existing phase is distinct from a missing phase.
- Case-insensitive script identity does not promise case-insensitive file lookup on a case-sensitive filesystem; configured paths must locate actual files.
- Duplicate and conflicting selections are checked after separator normalization and case-insensitive matching, including nested paths.
- Unknown selections warn; an unknown name in both selection lists still fails as a conflict.
- Parent traversal, absolute paths outside the phase, the phase directory itself, and sibling paths with a common prefix cannot qualify as contained script files.
- Ignored entries skip file-existence and checksum checks but remain subject to containment.
- A late invalid entry prevents all execution, including earlier valid entries.
- History entries absent from configuration do not add executable work.
- Force allows a new script and does not require prior history.
- Validation is not a transaction or a lock against subsequent file or history changes.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Phase interpretation and validation MUST have one authoritative responsibility covering ordered configuration, script identity, ignore/force decisions, containment, and checksum drift. Given phase files, history, and selections, callers MUST obtain validated run/skip decisions without reimplementing those rules. Evaluation MUST NOT execute scripts or write history.
- **FR-002**: Evaluation MUST select the phase by literal name, preserve configured script order, reject a missing phase, and accept an existing empty script list as no work. Missing configuration and phase directories MUST produce actionable errors.
- **FR-003**: Configuration, history, ignore, and force names MUST share case-insensitive matching with backslashes normalized to forward slashes. Recorded names MUST be normalized phase-relative names consistent with those decisions. Actual file lookup MUST respect host filesystem case rules.
- **FR-004**: Evaluation MUST reject configured duplicates and ignore/force intersections under FR-003 matching rules, including conflicting names absent from configuration. Unknown selections without conflicts MUST warn and MUST NOT add work.
- **FR-005**: Every configured path MUST resolve within the selected phase directory under the host's path-comparison rules. Escaping paths MUST be rejected, including ignored and forced entries. Every non-ignored script MUST exist as a file; ignored entries need not exist and MUST NOT undergo checksum validation.
- **FR-006**: Evaluation MUST obtain SHA-256 checksums for non-ignored files and compare them with matching history. Unchanged executed scripts MUST be skipped unless forced. Changed executed scripts MUST be rejected unless explicitly forced. Force MUST NOT bypass containment or existence validation. New and forced scripts MUST retain configured order.
- **FR-007**: The complete selected phase MUST pass applicable validation before its first script executes or history mutation occurs. A later validation error MUST prevent earlier execution. Errors MUST identify the phase or script and violated rule; checksum mismatches MUST include expected and current checksums.
- **FR-008**: Preview and execution MUST share interpretation and validation for identical inputs. `-WhatIf` MUST permit required history reads and validation, report eligible scripts in order, and execute zero scripts and write zero history entries. Valid phases with no eligible scripts MUST indicate no work without mutation.
- **FR-009**: The command MUST continue coordinating each eligible script's execution and subsequent history recording. Successful new scripts MUST be inserted; successful forced reruns MUST update existing history with current checksum and execution time. Skipped scripts MUST NOT change history.
- **FR-010**: Execution and history-recording failures MUST terminate the command before later scripts. Failed scripts MUST NOT be recorded as successful. Earlier work MUST NOT be represented as rolled back. Guidance MUST retain the idempotent-script requirement and explain the successful-execution/failed-history retry case.
- **FR-011**: Verification MUST exercise ordered scripts, case and separator matching across all name sources, duplicates, ignore/force conflicts, unknown selections, containment, existence, and checksum drift through the phase interface. A late-invalid-entry case MUST establish zero execution and history writes before validation completes.
- **FR-012**: Verification MUST retain SQL execution/history coverage and command-level `-WhatIf` checks for new, skipped, forced, execution-failure, and history-failure behavior. Real SQL Server checks MUST remain where controlled substitutes cannot establish database correctness. Unavailable checks MUST be recorded as unrun.

### Key Entities *(include if feature involves data)*

- **Migration phase**: A selected named group of ordered script references and its script directory.
- **Script identity**: A phase-relative name compared consistently across configuration, history, and selections, independent of letter case and slash direction.
- **Execution history entry**: A phase, script identity, checksum, and execution time representing recorded successful execution.
- **Operator selections**: Ignore and force names modifying eligibility without adding configured scripts.
- **Phase evaluation**: Ordered run/skip decisions with resolved file locations, applicable checksums, history status, and warnings, or a validation failure. It represents no completed execution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In 100% of acceptance cases covering selection, order, case, and separators, operators obtain expected identities and run/skip decisions with zero extra or reordered scripts.
- **SC-002**: Every invalid-phase case in Stories 1 and 2 fails before any execution or history write, including a valid first script followed by an invalid later entry.
- **SC-003**: Every preview/execution pair with identical inputs agrees on eligible scripts, order, warnings, and validation failures; every preview performs zero script executions and history mutations.
- **SC-004**: Every outcome in Story 4 preserves truthful progress: zero failed scripts recorded as successful, zero later scripts run after failure, and exactly one recorded entry per successfully recorded new or forced script identity.
- **SC-005**: Every phase-rule acceptance case can be assessed without performing a deployment, while retained database verification establishes execution/history outcomes. Reports distinguish passed, failed, and unavailable checks without counting unavailable checks as passes.

## Assumptions

- This is a focused responsibility change within migration processing. Public parameters, configuration format, history schema, supported platforms, and runtime requirements remain compatible. Audit and archiving are outside scope.
- The user-supplied design constraint is an in-process seam: phase interpretation and validation concentrate together, replacing the separate shallow `Get-Migration` reader. The command coordinates execution and history. Existing file and SQL implementations and meaningful checksum/execution helpers are retained. A new database adapter, generic interface framework, public phase API, or dependency is outside scope; internal signatures belong in planning.
- Complete validation before execution is intentional and strengthens current behavior, where late path/checksum errors can follow earlier execution. It provides no atomic execution, automatic rollback, concurrency control, or protection against later input changes.
- Ignoring continues to skip existence and checksum checks. Containment applies even to ignored entries to satisfy the constitution's requirement to reject paths outside the selected phase before execution.
- Matching scope is separator normalization and case-insensitive identity. No new filesystem case-resolution, symbolic-link policy, history repair, path-alias deduplication, or phase-ordering mechanism is introduced. The command processes the selected phase in configured script order.
- Prerequisites remain phase files, access to existing migration history, and permission to execute scripts. Real integration verification requires an explicitly selected test database and documented setup and permissions, as described in [Fast1Migration.md](../../Fast1Migration.md).
- Applicable constitution principles are II (deterministic migrations, matching, validation, preview, idempotency), III (bounded operations and terminating failures), IV (portable contracts), and V (regression verification and recovery guidance). Principle I's completed-work semantics also apply to truthful progress during partial failure.
- Constitution Development and Review Workflow items 6–11 apply during implementation: modified PowerShell files, including tests, require `Invoke-ScriptAnalyzer` with project configuration where available. Resolve new findings, report unrelated existing findings and analyzer unavailability, and do not suppress rules solely to bypass validation.
