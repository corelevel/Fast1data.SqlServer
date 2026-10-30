---
description: "Implementation tasks for Unify Audit Discovery"
---

# Tasks: Unify Audit Discovery

**Input**: Design documents from `specs/001-unify-audit-discovery/`.
**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/discovery.md`, `quickstart.md`, and `.specify/memory/constitution.md`.
**Tests**: Explicitly required by FR-008, FR-009, and SC-001 through SC-005. Exercise `Get-SqlAuditFile`, not just a parser or a mocked listing helper. Add each story's regression cases before its implementation; confirm newly missing behavior fails while preserving existing passing cases.
**Organization**: Setup, shared test foundations, one phase per user story, then cross-cutting validation. This file schedules implementation; no runtime check is claimed to have passed during task generation.

**Static Analysis Completion Gate**: Constitution Development and Review Workflow items 6–11 apply to every new or modified `.ps1`, `.psm1`, and `.psd1`, including tests and fixtures. Existing implementation and runtime evidence is retained in `quickstart.md`; PowerShell-editing tasks T002–T010, T013–T018, and T021–T026 are reopened pending analyzer evidence for their files. These changes are already implemented; complete the outstanding gate rather than rebuilding them. T031 validates the current files after implementation and T028, before final review T029 and evidence completion T030. Analyzer unavailability must be reported and leaves these tasks pending.

## Format: `[ID] [P?] [Story] Description`

- `[P]` identifies work that can overlap a ready task in a different file, after its prerequisites are complete.
- `[US1]`, `[US2]`, and `[US3]` map to the specification's stories; shared tasks have no story label.
- All paths are relative to the repository root. Preserve existing user edits, especially in `Fast1data.SqlServer/tests/Audit.Tests.ps1`.

## Path Conventions

- Discovery: `Fast1data.SqlServer/private/audit/Get-SqlAuditFile.ps1`.
- New listing seam: `Fast1data.SqlServer/private/audit/Get-SqlAuditFileEntry.ps1`.
- Existing regression suite: `Fast1data.SqlServer/tests/Audit.Tests.ps1`.
- New controlled/native suite: `Fast1data.SqlServer/tests/Audit.Discovery.Tests.ps1`.
- Shared filename fixtures: `Fast1data.SqlServer/tests/Audit.Discovery.Fixtures.ps1`; included in T005/T007 and the static-analysis scope.
- New real-process suite: `Fast1data.SqlServer/tests/Audit.Smb.Tests.ps1`.
- Operator guidance: `Fast1Audit.md`; validation evidence: `specs/001-unify-audit-discovery/quickstart.md`.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the existing module's validation prerequisites and portable regression baseline. No new production dependency or project scaffold is needed.

- [X] T001 Verify x64 PowerShell 7.4+, Pester 5, SqlServer, bundled Microsoft.Data.SqlClient assets, and available Windows/Linux/share environments using the documented setup; record versions and missing prerequisites in `specs/001-unify-audit-discovery/quickstart.md`, follow `README.md` and `build/build.ps1` only when existing runtime assets need building, and use the session-only `001` feature override without changing `.specify/feature.json`.
- [ ] T002 Correct source-path casing to `private/audit` and `schema/audit`, gate only native local-folder discovery cases to Windows, and retain public-command, missing-folder, and SQL text contract checks in `Fast1data.SqlServer/tests/Audit.Tests.ps1`, preserving the user's current changes.

**Checkpoint**: Prerequisites and unavailable environments are known; the existing regression suite remains usable on supported hosts.

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish shared test infrastructure before story implementation. Do not add a generic adapter framework or public testing switches.

- [ ] T003 [P] Create the Pester 5 harness in `Fast1data.SqlServer/tests/Audit.Discovery.Tests.ps1`: load the module, call private discovery through module scope, control only existing `Get-ChildItem`, prerequisite lookup, and `smbclient` boundaries, and isolate/restore simulated platform variables, native preferences, and process environment even when assertions fail; provide a reusable safe stream/error-capture utility for later failure and secret assertions.
- [ ] T004 [P] Create the opt-in `RealSmb` Pester harness in `Fast1data.SqlServer/tests/Audit.Smb.Tests.ps1` accepting `PopulatedFolder`, `EmptyFolder`, `FailureFolder`, and `Credential` as documented container data; require Linux and actual `smbclient`, skip unavailable prerequisites with explicit reasons, invoke discovery without enumeration/process mocks, restore runner environment in cleanup, and never provision or modify arbitrary share contents or store secrets in reports.

**Checkpoint**: Both harnesses are ready. All stories depend on Phase 2. Real checks need dedicated, pre-provisioned fixtures; skipped tests do not establish process behavior.

## Phase 3: User Story 1 - Discover the same audits across supported environments (Priority: P1) - MVP

**Goal**: Keep one filename interpretation and one result projection while Windows and Linux listing implementations return transport-neutral file candidates.

**Independent Test**: Through discovery, compare accepted basenames and GUID values for equivalent Windows records and realistic SMB rows, separately checking platform full paths and exact property types. Every valid file, including repeated GUIDs, remains a separate result; no malformed or directory entry is accepted. Run native Windows fixtures and the populated real SMB case when their environments are available.

### Tests for User Story 1

- [ ] T005 [P] [US1] Add one shared filename matrix exercised through both controlled routes in `Fast1data.SqlServer/tests/Audit.Discovery.Tests.ps1`: valid prefixes with spaces/underscores, mixed-case GUIDs, digit components beyond numeric/date ranges, multiple files per GUID, empty prefixes, malformed GUIDs, missing/nonnumeric components, trailing text, unrelated files, audit-named directories, and SMB headers/status/footer rows; assert exactly `FileName` and GUID-typed `AuditGuid`, root-specific full paths, nested directories and trailing separators, preserving internal filename spaces without requiring output order or extension-case expansion.
- [ ] T006 [US1] Add unmocked Windows `TestDrive` discovery cases in `Fast1data.SqlServer/tests/Audit.Discovery.Tests.ps1` using the same matrix, literal folder names, nonrecursive enumeration, and an audit-named directory; skip these native cases on other hosts and verify supplied Windows credentials remain unused without changing `PASSWD`.
- [ ] T007 [P] [US1] Add populated-share discovery cases to `Fast1data.SqlServer/tests/Audit.Smb.Tests.ps1` using the shared filename categories and a declared expected fixture manifest; compare exact accepted filenames, GUID values/types, and complete UNC paths for nested directory names with spaces and roots with trailing separators, with no listing or process mocks.

### Implementation for User Story 1

- [ ] T008 [P] [US1] Add private `Get-SqlAuditFileEntry` in `Fast1data.SqlServer/private/audit/Get-SqlAuditFileEntry.ps1` with the existing `Folder`/`Credential` parameter types and a Windows branch using literal, nonrecursive, file-only `Get-ChildItem -ErrorAction Stop`; preserve these model constraints verbatim: `Folder` is "Windows local/UNC directory; Linux UNC server/share with optional nested directory. Preserve directory-name spaces. Invalid requests terminate.", candidate `Name` is "Basename from a genuine file entry, with filename spaces preserved. May be an invalid audit name.", and candidate `FullName` is "Full path to that file in the requested directory. Windows uses the enumerated full path; Linux reconstructs the UNC file path."; emit no audit interpretation, credentials, or additional metadata.
- [ ] T009 [US1] Implement Linux listing and row normalization in `Fast1data.SqlServer/private/audit/Get-SqlAuditFileEntry.ps1`: supply share, username, static `-c 'ls'`, and optional `-D` as separate argument values, preserve spaces and nested roots, use the existing temporary `PASSWD` authentication mechanism with `finally` cleanup and no password arguments, capture native output, and identify genuine file rows by attributes/size/timestamp boundaries while rejecting directories and metadata; do not interpret audit names, and preserve the credential constraint "Required and not `PSCredential.Empty` on Linux; unused on Windows. Used only for listing."; exact prior-state restoration and comprehensive sanitization are completed in US3.
- [ ] T010 [US1] Refactor `Fast1data.SqlServer/private/audit/Get-SqlAuditFile.ps1` to call the private listing helper and keep the sole anchored filename rule and sole result projection; preserve the model constraints verbatim: prefix "Nonempty; may contain underscores and spaces.", GUID "Hexadecimal GUID in standard 8-4-4-4-12 layout; either letter case.", sequence "Nonempty digits; no conversion, ordering, or range rule.", ticks "Nonempty digits; no conversion, timestamp validation, or range rule.", extension "Existing lowercase `.sqlaudit` baseline; no new case-support promise.", `FileName` "Candidate's complete full path.", and `AuditGuid` "GUID value extracted by the authoritative filename rule."; cast only the GUID, emit one object per accepted file without sorting/deduplication, and retain the existing caller request contract.
- [X] T011 [P] [US1] Update supported discovery access, Linux `smbclient`/credential prerequisites, the `Credential` parameter table, filename-only discovery semantics, and SQL Server's independent service-account read permission in `Fast1Audit.md`; preserve the single-process audit-directory requirement and existing import/checkpoint guidance.
- [X] T012 [US1] Run the US1 controlled/native Pester cases and populated real SMB case, perform the documented native Windows UNC comparison when a dedicated fixture is supplied, and record SC-001/SC-005 evidence, fixture categories, counts, and any unavailable Windows/UNC/Linux checks in `specs/001-unify-audit-discovery/quickstart.md`; do not treat controlled transport parity as real-process evidence.

**Checkpoint**: The parity increment is demonstrable through discovery. US2 and US3 remain required before feature acceptance; an MVP demonstration does not imply release readiness.

## Phase 4: User Story 2 - Distinguish no files from discovery failure (Priority: P1)

**Goal**: Publish empty success only after a successful complete listing, and propagate request, enumeration, and native process failures without apparent discovery results.

**Independent Test**: Empty, rejected-only, and metadata-only successful listings emit zero objects without error. Inaccessible Windows folders, partial enumeration followed by failure, invalid Linux prerequisites, invocation errors, unsupported platforms, and nonzero SMB exits terminate and emit zero success objects. Real Linux empty and failing paths establish native outcomes separately.

### Tests for User Story 2

- [ ] T013 [P] [US2] Add discovery contract cases in `Fast1data.SqlServer/tests/Audit.Discovery.Tests.ps1` for empty/rejected-only/metadata-only success on both routes, missing/null/empty Linux credentials, malformed UNC server/share roots and local Linux paths, missing `smbclient`, and unsupported OS; require actionable terminating errors for invalid requests, and verify Windows local/UNC requests retain their current credential non-use.
- [ ] T014 [US2] Add controlled inaccessible Windows and partial-enumeration failures, native invocation exceptions, and nonzero exits containing valid-looking file rows in `Fast1data.SqlServer/tests/Audit.Discovery.Tests.ps1`; capture success output externally to the failing pipeline to prove zero emitted results, test both caller `$PSNativeCommandUseErrorActionPreference` settings, and assert the caller preference is unchanged and safe failure context/exit codes remain available.
- [ ] T015 [P] [US2] Add actual empty and rejected-only successful listings plus a known missing/access-denied share-path process failure in `Fast1data.SqlServer/tests/Audit.Smb.Tests.ps1`; reuse `EmptyFolder` with a rejected-only fixture in a separate run, assert terminating native failure with zero discovery objects, and do not substitute malformed request validation for process failure.

### Implementation for User Story 2

- [ ] T016 [P] [US2] Implement actionable platform and request/prerequisite validation in `Fast1data.SqlServer/private/audit/Get-SqlAuditFileEntry.ps1`: retain Windows local/UNC scope, require a genuine Linux UNC server/share, reject missing/null/`PSCredential.Empty` credentials and unavailable `smbclient`, preserve nested names/spaces, terminate on unsupported discovery platforms, and never mutate process credential state during Windows enumeration or failed prerequisite checks.
- [ ] T017 [P] [US2] Buffer the complete helper output before filename projection in `Fast1data.SqlServer/private/audit/Get-SqlAuditFile.ps1` so failure after a yielded candidate cannot publish partial discovery objects; keep successful zero candidates and zero valid names as an empty pipeline, with no success/error sentinel records.
- [ ] T018 [US2] Finish complete-listing failure handling in `Fast1data.SqlServer/private/audit/Get-SqlAuditFileEntry.ps1`: terminate Windows enumeration errors, set `$PSNativeCommandUseErrorActionPreference = $false` locally, capture native output and `$LASTEXITCODE` immediately, reject every nonzero status before row interpretation, and convert invocation exceptions to terminating errors without forwarding raw native streams; retain available safe failure context and the exit code, with comprehensive redaction completed in US3.
- [X] T019 [P] [US2] Document successful no-match behavior, terminating listing/prerequisite failures, supported discovery platforms, and operator recovery steps in `Fast1Audit.md`, distinguishing unreadable folders from folders with nothing to import and retaining SQL Server's separate file-access requirement.
- [X] T020 [US2] Run US2 and earlier discovery/audit regressions plus native Windows empty/failure and real Linux empty/rejected-only/failure checks where available; record SC-002 and SC-004 outcome counts, explicit native-error preference observations, and unavailable environments in `specs/001-unify-audit-discovery/quickstart.md` without marking skipped process checks as passing.

**Checkpoint**: Empty success and failed discovery are observably distinct, including zero partial discovery results on failure. This phase follows US1 because it hardens the same listing and projection implementations.

## Phase 5: User Story 3 - Finish remote discovery without retaining credentials (Priority: P2)

**Goal**: Restore borrowed process credential state exactly and prevent supplied passwords from escaping through any discovery output or error.

**Independent Test**: Cross files found, no files found, nonzero listing exit, and invocation exception with initially absent and pre-existing `PASSWD` (eight controlled cases). Assert temporary child authentication, exact prior presence/value restoration, and no supplied secret in emitted streams, arguments, results, or error details. Observe the three actual process outcomes on Linux with both prior states.

### Tests for User Story 3

- [ ] T021 [P] [US3] Add the eight-case credential lifecycle matrix through discovery in `Fast1data.SqlServer/tests/Audit.Discovery.Tests.ps1`, using distinct supplied/prior test-only sentinels; assert `PASSWD` contains the supplied value during invocation and precisely round-trips its original presence/value after success, no matches, native failure, or invocation exception, and restore the test runner's own environment in `finally`.
- [ ] T022 [US3] Add secret-leak regression cases in `Fast1data.SqlServer/tests/Audit.Discovery.Tests.ps1` with supplied password sentinels embedded in native diagnostics and thrown invocation errors; inspect all six output streams and emitted error messages, details, target objects, and nested exceptions, assert passwords are absent from native arguments/result objects, and retain actionable sanitized failure context without leaking a prior credential value.
- [ ] T023 [P] [US3] Extend the real Linux cases in `Fast1data.SqlServer/tests/Audit.Smb.Tests.ps1` to cross populated, empty/rejected-only, and failing process outcomes with absent/pre-existing `PASSWD`; observe exact restoration after actual `smbclient` execution, scan emitted streams/errors for the supplied secret, retain process mocks only in the separate controlled suite, and leave invocation-exception proof to T021/T022.

### Implementation for User Story 3

- [ ] T024 [US3] Implement exact borrowed-environment restoration in `Fast1data.SqlServer/private/audit/Get-SqlAuditFileEntry.ps1`, preserving these model constraints verbatim: prior presence "Remember whether process `PASSWD` existed before discovery.", prior value "Preserve exactly for restoration; never log it.", and temporary value "Supplied password; only available to the listing operation and its child."; snapshot presence/value before assignment, put assignment and invocation inside the protected region, restore the prior value in `finally` or remove the variable only when previously absent, and cover all four exit conditions without entering this lifecycle on Windows.
- [ ] T025 [US3] Sanitize captured native diagnostics and invocation exceptions before constructing terminating errors in `Fast1data.SqlServer/private/audit/Get-SqlAuditFileEntry.ps1`; redact the supplied password from every exposed diagnostic field, retain no unsanitized inner exception or target object, never forward raw process output, and preserve the useful failure category and native exit code.
- [ ] T026 [US3] Update affected comment-based help in `Fast1data.SqlServer/private/audit/Get-SqlAuditFile.ps1`, `Fast1data.SqlServer/private/audit/Get-SqlAuditFileEntry.ps1`, and `Fast1data.SqlServer/public/Invoke-Fast1Audit.ps1`, and credential guidance in `Fast1Audit.md`, covering Linux prerequisites, cleanup/restoration, empty success versus terminating errors, the serialized process-environment assumption, and independent SQL Server access without changing public command behavior or parameters.
- [X] T027 [US3] Run the complete controlled credential/secret suite and available real Linux lifecycle cases; record SC-003/SC-004 evidence and unrun environments in `specs/001-unify-audit-discovery/quickstart.md`, including all eight controlled outcomes and the actual-process success/empty/failure outcomes with both prior credential states, without recording secret values.

**Checkpoint**: The three story behaviors are independently observable through discovery; missing required platform/process evidence remains explicitly unverified.

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Confirm the focused change preserves module, caller, and database boundaries and leaves an accurate acceptance record.

- [X] T028 Run the full affected Pester discovery and `Fast1data.SqlServer/tests/Audit.Tests.ps1` suites, verify module import through `Fast1data.SqlServer/Fast1data.SqlServer.psd1`, and confirm the existing three public exports and private helper visibility using `Fast1data.SqlServer/Fast1data.SqlServer.psm1`; record passed/failed/skipped counts and import prerequisites in `specs/001-unify-audit-discovery/quickstart.md`, treating missing runtime dependencies as unrun checks rather than discovery failures or passes.
- [ ] T031 Validate every new or modified PowerShell file using `Invoke-ScriptAnalyzer`, including source, public-command, test, and fixture scripts. Use the project's PSScriptAnalyzer configuration when available and record the selected configuration. Resolve all newly introduced errors and warnings; report unrelated pre-existing findings with supporting baseline evidence. Do not disable or suppress rules solely to bypass validation. Record analyzer version, file scope, results, remediation, and any inability to run in `specs/001-unify-audit-discovery/quickstart.md`. Unavailable or failed execution must not be reported as successful validation and leaves the gate pending. Re-run analysis for remediated files and affected Pester checks if behavior changes; restore completed status to reopened PowerShell-editing tasks only when their file-level gate is satisfied.
- [ ] T029 Review `Fast1data.SqlServer/private/audit/Get-SqlAuditFile.ps1`, `Fast1data.SqlServer/private/audit/Get-SqlAuditFileEntry.ps1`, `Fast1data.SqlServer/public/Invoke-Fast1Audit.ps1`, `Fast1data.SqlServer/private/audit/Import-SqlAuditFile.ps1`, and `Fast1Audit.md` together against FR-001 through FR-010 and the constitution; confirm one filename rule/projection, one nonrecursive enumeration/process per call, no new caller transport responsibilities, no SQL/checkpoint/schema/manifest/runtime changes, no new abstraction/dependency, and no secret-bearing examples, and record findings in `specs/001-unify-audit-discovery/quickstart.md`.
- [ ] T030 Complete the validation record in `specs/001-unify-audit-discovery/quickstart.md` by following every applicable command/scenario, replacing planning-only implementation status, mapping SC-001 through SC-005 to observed evidence, and recording date, OS/runtime, Pester/smbclient versions, worktree context, fixture categories, results, and credential observations; keep unavailable Windows UNC or Linux/share checks explicitly unrun, do not claim feature acceptance while required evidence is missing, and block release on unresolved material audit-integrity risks.

## Dependencies & Execution Order

### Phase Dependencies

```text
Phase 1: T001 -> T002
                 |
Phase 2:      T003 || T004
                 |
Phase 3:       US1 (P1) -- parity MVP
                 |
Phase 4:       US2 (P1) -- empty/failure distinction
                 |
Phase 5:       US3 (P2) -- credential restoration and sanitization
                 |
Phase 6:     T028 -> T031 -> T029 -> T030
```

- Phase 2 blocks story implementation. T003 and T004 can run together after Phase 1.
- Reopened PowerShell-editing tasks have their implementation in place and await the T031 completion gate; their unchecked status does not require repeating implementation or block T031. For future edits, validate each changed PowerShell file before completing its task. T029 and T030 wait for recorded static-analysis compliance; no additional production-code task may be marked complete solely because Pester or parsing passes.
- US1 owns initial listing/projection implementation; US2 depends on it and US3 hardens that same native invocation path. Serialize these implementation phases because they edit the same source files. Each story has its own discovery-interface acceptance criteria and can be validated at its checkpoint.
- Story test additions can be prepared after their harness exists, but edits to the same test file must be serialized. Do not run tests against a concurrently changing module.
- Dedicated native environments are dependencies of runtime evidence, not reasons to invent a substitute transport. Continue available implementation/controlled validation while recording unavailable checks; full acceptance still requires the specified evidence.
- Documentation tasks that name the same file must also be serialized across stories. The `[P]` marker never overrides an explicit dependency or shared-file conflict.

### Within Each User Story

- US1: T005 precedes T006; T007 can overlap T005/T006. After test definitions are ready, execute T008 -> T009 -> T010; T011 can overlap these implementations. T012 validates the combined result.
- US2: T013 precedes T014; T015 can overlap them. After test definitions are ready, T016, T017, and T019 can run together; T018 follows T016 and T020 waits for all US2 work.
- US3: T021 precedes T022; T023 can overlap them. After test definitions are ready, execute T024 -> T025 -> T026 -> T027. Source/help tasks are sequential because they share files.
- Keep regression cases that establish missing behavior ahead of their fixes. Native/real scenarios run only on their actual platforms.

### Parallel Opportunities

- Foundation: T003 (controlled harness) and T004 (real harness).
- US1: T005/T006 (controlled/native cases) alongside T007 (real populated case); T008-T010 alongside T011 (operator guidance).
- US2: T013/T014 alongside T015; then T016 (listing validation), T017 (projection buffering), and T019 (operator guidance), followed by T018.
- US3: T021/T022 (controlled credentials/secrets) alongside T023 (real lifecycle cases). Credential implementation and affected help share files and run sequentially.
- These are execution opportunities for later implementation, not instructions to launch agents during task generation.

## Parallel Example: User Story 1

```text
After T003/T004:
  T005: Shared parity matrix in Audit.Discovery.Tests.ps1
  T007: Populated real-share cases in Audit.Smb.Tests.ps1
After US1 test definitions:
  T008: Windows candidate helper in Get-SqlAuditFileEntry.ps1
  T011: Operator access guidance in Fast1Audit.md
```

## Parallel Example: User Story 2

```text
After US1 and US2 test definitions:
  T016: Platform/request validation in Get-SqlAuditFileEntry.ps1
  T017: Complete-listing buffering in Get-SqlAuditFile.ps1
  T019: Empty/failure recovery guidance in Fast1Audit.md
Then T018 completes native failure handling; T020 validates all paths.
```

## Parallel Example: User Story 3

```text
After US2:
  T021: Controlled eight-case matrix in Audit.Discovery.Tests.ps1
  T023: Actual-process state observations in Audit.Smb.Tests.ps1
Then T022 extends the controlled suite; T024/T025 implement the fixes.
```

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Setup and Foundational tasks (T001-T004).
2. Complete US1 (T005-T012) and demonstrate equivalent accepted files through discovery.
3. Validate parity, exact paths/types, file-only behavior, and repeated GUIDs. Record native/real checks that could not run.
4. Treat this as the first reviewable increment. US2 is also P1 and US3 covers required credential safety; finish both and cross-cutting validation before accepting the full feature.

### Incremental Delivery

1. Foundation: portable existing tests plus controlled and real-process harnesses.
2. US1: single filename rule/projection and two private listing routes.
3. US2: complete-listing buffering, explicit empty success, terminating request/process failures.
4. US3: exact credential restoration and secret-safe errors across all exit conditions.
5. Final validation: module import/export checks, PowerShell Static Analysis through T031, existing caller/SQL contract review, actual Windows and Linux evidence, and an accurate acceptance record.

## Notes

- The new helper is loaded by the existing recursive private loader; no loader or public export change is planned.
- Sequence/ticks remain naming strings. No timestamp validation, sorting, deduplication, recursive search, new transport, or new platform is introduced.
- SQL Server integration is outside this discovery-only change; preserve existing SQL text regression coverage and independent service permissions.
- Implementation changes are present; completion of affected tasks remains pending required static analysis through T031. Available runtime evidence is recorded in quickstart.md; required Windows UNC and real Linux SMB checks remain unverified, so feature acceptance is pending.



