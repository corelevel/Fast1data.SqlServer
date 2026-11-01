# Feature Specification: Explicit Module Loaders and One Shared Loading List

**Feature Branch**: `dev` (existing branch; no branch hook configured)

**Created**: 2026-11-01

**Status**: Draft

**Input**: User description: "Use one shared loading script and explicit module loaders. Maintain the complete shared function list in private/shared/Load.ps1 and dot-source it from both module entry files. Remove recursive private-file discovery and its exclusion list. Explicitly load audit, migration, and the archiving entry function in the root module, and archiving-specific helpers in the archiving model. Remove dependency loading from ordinary function files, including Set-Executed.ps1. Keep assembly initialization separate and visibly first. Module loaders assemble the code; function files contain behavior. Retain two module scopes and two executions of the shared loader."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Maintain the shared function list once (Priority: P1)

As a maintainer, I need one authoritative list of shared functions so that I can see what is shared and update both consuming components without maintaining duplicate lists or following dependencies through behavior files.

**Why this priority**: A single shared list is the central requested improvement; repeating the list only makes dependencies visible without removing duplicate maintenance.

**Independent Test**: Review the shared list and both module loaders, then verify that every listed shared function is available privately to each consumer in a clean session.

**Acceptance Scenarios**:

1. **Given** the root module and archiving model both consume shared functions, **When** a maintainer opens the shared loader, **Then** it contains the complete shared function list and both consumers refer to that same list.
2. **Given** a shared function is added or removed, **When** the maintainer updates the authoritative list, **Then** no matching shared-list edit is required in either consuming module loader.
3. **Given** both consumers are loaded, **When** each resolves logging, query, and cleanup functions, **Then** each has its own private functions and loading one consumer does not replace the other's functions or expose them publicly.

---

### User Story 2 - Understand loading from explicit entry points (Priority: P1)

As a maintainer, I need loading decisions to be visible at the module entry points so that I can understand initialization order and component dependencies without recursive discovery, exclusion rules, or hidden imports in function files.

**Why this priority**: Explicit assembly boundaries make dependency changes reviewable and prevent an unrelated private file from becoming executable merely because it exists in a directory.

**Independent Test**: Trace initialization from each module loader, inventory all intended private functions, and confirm that an unlisted private file is not loaded.

**Acceptance Scenarios**:

1. **Given** a clean root-module import, **When** initialization runs, **Then** the separate assembly initialization stage completes before shared and feature behavior is loaded, and audit, migration, and the archiving entry function are explicitly selected by the root loader.
2. **Given** the archiving model is loaded through its supported entry path, **When** its dependencies are assembled, **Then** it uses the shared loader and explicitly selects its archiving-specific helpers without loading audit or migration behavior.
3. **Given** an ordinary function file, including `Set-Executed.ps1`, **When** a maintainer reviews it, **Then** it contains behavior and no dependency-loading directives; its owning loader supplies required dependencies.
4. **Given** an unlisted private file is present, **When** the root module is imported, **Then** the file is not executed and no recursive discovery or private-file exclusion list is involved.
5. **Given** a required dependency is unavailable or assembly initialization fails, **When** loading is attempted, **Then** the failure identifies the unavailable dependency and the affected operation cannot proceed as though loading succeeded.

---

### User Story 3 - Keep existing operations reliable (Priority: P2)

As an operator, I need audit, migration, and archiving to behave the same after their loading arrangement changes so that existing automation works without invocation changes or session workarounds.

**Why this priority**: The maintenance improvement must preserve the operational contracts and isolation already established for these commands.

**Independent Test**: Run existing import, public-interface, logging, query, cleanup, and representative workflow acceptance coverage against source and packaged distributions in independent clean sessions.

**Acceptance Scenarios**:

1. **Given** either distribution, **When** the root module is imported, **Then** exactly `Invoke-Fast1Audit`, `Invoke-Fast1Migration`, and `Invoke-Fast1Archiving` remain public, with unchanged parameters and no exported private helpers.
2. **Given** supported loading orders and repeated imports, **When** operators invoke the three commands, **Then** shared functions and existing archiving classes remain available, requested verbose messages appear, warnings retain their severity, and caller preferences remain unchanged.
3. **Given** existing success, failure, and retry fixtures, **When** the affected workflows run, **Then** SQL results, error propagation, cleanup, processing order, persisted progress, and recovery match their established expectations.

### Edge Cases

- A shared function omitted from the authoritative list must be detected by dependency coverage rather than supplied accidentally by the caller's session or another component.
- A newly added, unlisted private file must remain inactive even when its name would have matched the previous recursive discovery pattern.
- The same shared loader executes in two module scopes; this must not create public helpers, duplicate operational messages, or replace a consumer's existing functions.
- Archiving class and parameter-type availability must survive the removal of dependency directives from ordinary function files, including dependencies that need to be known before behavior can be used.
- A process with assemblies already initialized must retain supported repeated-import behavior; a process missing a required assembly must report a useful loading error.
- Source and packaged checks must start independently so previously loaded functions or classes cannot conceal missing loading declarations or packaged files.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The complete shared behavior-function list MUST have exactly one authoritative definition in `private/shared/Load.ps1`, including logging, generic SQL cleanup, generic SQL queries, and any other behavior functions retained as shared. Both module entry files MUST dot-source this loader rather than repeat its function list. Acceptance: Story 1, scenarios 1–2.
- **FR-002**: Each consuming module MUST obtain its own private shared functions. The existing two module scopes and two executions of the shared loader MUST be retained without adding public helper exports or replacing the other consumer's functions. Acceptance: Story 1, scenario 3, and Story 3, scenarios 1–2.
- **FR-003**: The root module MUST explicitly select its audit helpers, migration helpers, and archiving entry function. Recursive private-file discovery and its exclusion list MUST be removed. An unlisted private file MUST NOT execute during import. Acceptance: Story 2, scenarios 1 and 4.
- **FR-004**: The archiving model MUST explicitly select its archiving-specific helpers and use the shared loader for shared functions. It MUST NOT assemble audit or migration behavior. Acceptance: Story 2, scenario 2.
- **FR-005**: Dependency assembly MUST belong to module loaders and the shared loader. Ordinary function files, including `Set-Executed.ps1`, MUST contain no dependency-loading directives. Required function and type dependencies MUST remain available through the owning loaders. Acceptance: Story 2, scenario 3, and Story 3, scenario 2.
- **FR-006**: Assembly initialization MUST remain a separate, visibly first runtime loading stage, completed before shared or feature behavior is loaded. Bootstrap dependencies MUST be distinguishable from the shared behavior-function list. Acceptance: Story 2, scenarios 1 and 5.
- **FR-007**: Missing required dependencies and assembly initialization failures MUST surface with actionable dependency context; affected operations MUST NOT continue with incomplete initialization. Acceptance: Story 2, scenario 5.
- **FR-008**: The three existing public commands, their parameters, internal archiving class availability, supported runtime/platform contracts, and source/package behavior MUST remain compatible. Internal helpers MUST remain private. Acceptance: Story 3, scenarios 1–2.
- **FR-009**: Loading changes MUST preserve logging levels and verbosity controls, SQL parameter/result contracts, error propagation, resource cleanup, configuration and schema compatibility, processing order, persisted progress, and retry behavior. Acceptance: Story 3, scenarios 2–3.

### Acceptance Coverage and Dependencies

Review the complete private dependency inventory to account for every existing function: shared behavior, component-specific behavior, bootstrap support, and required type definitions. The user-specified loading structure is a design constraint; planning must resolve type availability without reintroducing hidden dependency loading in ordinary functions.

Use the existing shared-helper isolation feature (`specs/004-isolate-shared-helpers/spec.md`) and regression coverage as the compatibility baseline. Cover clean root-module import, supported archiving-first and root-first loading paths, and supported repeated imports. Check both private function ownership and public exports, and retain the existing audit verbose regression expectation. Validate the affected import and packaging paths in independent sessions. Unsupported class hot reloading is not a new requirement.

Applicable constitution requirements are Principles I–III for preserving durable progress, migration ordering and preview behavior, bounded database operations, cleanup, and error propagation; Principle IV for public, runtime, and platform compatibility; and Principle V for regression evidence and operational visibility. Implementation must validate affected imports and builds, use SQL Server checks where substitutes cannot establish correctness, and apply the project analysis rules to modified PowerShell files. Unavailable checks must be recorded rather than reported as passing.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A maintainer can identify the full shared behavior-function set by reviewing one authoritative list, with zero duplicate lists to keep synchronized.
- **SC-002**: A maintainer can account for 100% of intended private dependencies from the designated loading entry points, with zero dependency-loading directives in ordinary function files and zero unintended executions of unlisted private files.
- **SC-003**: Consumers retain exactly three public operations with zero required changes to invocation parameters, configuration, or persisted operational data.
- **SC-004**: Across the defined source and package acceptance cases, 100% of expected workflow results, progress messages, warnings, failures, cleanup outcomes, and retry outcomes match their existing contracts, with zero loading-order workarounds.

## Assumptions

- This feature refines loading structure on top of the existing shared-helper isolation contract; it does not replace that contract or alter SQL and workflow behavior.
- The user has explicitly chosen a shared loading script and explicit module loaders. Their requested paths and loading responsibilities are requirements; no additional framework or module-architecture redesign is needed.
- The sample shared list illustrates shared behavior rather than an instruction to discard other required helpers. Every existing private function must be accounted for; assembly bootstrap support remains separately identified.
- Existing public-file loading and export mechanics may remain as they are, provided the manifest continues to expose exactly the current three commands. The discovery removal requirement concerns private files.
- Required type definitions, including the existing generic SQL parameter and archiving types, remain compatibility dependencies. Planning must address their availability within the requested loader ownership rule.
- Assembly-first ordering describes runtime initialization; language-required declaration processing must preserve type availability without causing feature behavior to run before assembly initialization.
- Existing test and build infrastructure is available for reuse. Database-dependent checks require an explicitly selected test database and documented prerequisites.
