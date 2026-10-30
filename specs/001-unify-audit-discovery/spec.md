# Feature Specification: Unify Audit Discovery

**Feature Branch**: `dev` (existing branch; no branch hook configured)

**Created**: 2026-10-28

**Status**: Draft

**Input**: User description: "Keep one interpretation of audit filenames and place Windows and Linux execution behind an internal seam. The existing Get-ChildItem and smbclient adapters justify this separation; no generic filesystem abstraction is needed. Retain and deepen discovery so its caller does not inherit transport complexity. Exercise equivalent listings, malformed names, SMB failure, empty results, and credential cleanup through the discovery interface. Keep real SMB verification for process behavior. SQL Server still reads files independently."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Discover the same audits across supported environments (Priority: P1)

As an audit operator, I need equivalent directory contents to identify the same audit files and audit identifiers on Windows and Linux, so changing the discovery environment does not change which audits are offered for import.

**Why this priority**: Discovery determines which audits reach the importer. Inconsistent filename rules can silently omit audits.

**Independent Test**: Request discovery through its existing interface for equivalent Windows and Linux listings containing valid and malformed names, and compare accepted filenames and audit identifiers after accounting for the different folder roots. Check full paths separately for each environment.

**Acceptance Scenarios**:

1. **Given** equivalent supported folders containing valid audit filenames, **When** discovery runs in each environment, **Then** each valid file produces one result with its full path and the same audit identifier in both environments.
2. **Given** valid names with audit-name prefixes containing underscores or spaces and identifiers containing uppercase or lowercase hexadecimal letters, **When** discovery runs, **Then** each name is accepted and its identifier is extracted correctly in both environments.
3. **Given** a listing containing valid files, unrelated files, directories, and malformed audit names, **When** discovery runs, **Then** only valid audit files are returned and malformed entries do not prevent valid files from being returned.
4. **Given** several valid files for one audit identifier and files for other identifiers, **When** discovery runs, **Then** every valid file is returned individually with its corresponding identifier.

---

### User Story 2 - Distinguish no files from discovery failure (Priority: P1)

As an audit operator, I need discovery to distinguish a successfully inspected folder with no matching files from a folder that could not be inspected, so I can decide whether there is nothing to import or an access problem to resolve.

**Why this priority**: Reporting a failed listing as an empty folder could conceal unprocessed audit data.

**Independent Test**: Request discovery for empty and entirely malformed listings, inaccessible Windows folders, and failed remote listings. Verify returned results or terminating errors through the discovery interface.

**Acceptance Scenarios**:

1. **Given** an accessible folder with no audit files, **When** discovery completes successfully, **Then** it returns no results without an error.
2. **Given** an accessible folder containing only malformed audit names or unrelated entries, **When** discovery completes successfully, **Then** it returns no results without an error.
3. **Given** an inaccessible Windows folder, **When** discovery is requested, **Then** it raises a terminating error identifying the listing failure.
4. **Given** a remote listing that fails, including a nonzero process exit with output resembling valid file entries, **When** discovery is requested, **Then** it raises a terminating error and does not present those entries as successful discovery results.
5. **Given** a Linux request with missing or empty credentials, an invalid share path, or an unavailable remote-listing prerequisite, **When** discovery is requested, **Then** it raises a terminating error identifying the unmet requirement without exposing secrets.
6. **Given** an operating system outside the existing discovery support, **When** discovery is requested, **Then** it reports that discovery is unsupported.

---

### User Story 3 - Finish remote discovery without retaining credentials (Priority: P2)

As an audit operator, I need credentials used for remote discovery to remain confined to that operation, so later work in the same process does not inherit its secrets.

**Why this priority**: Both successful and failed discovery can otherwise leave sensitive state behind in a long-running import process.

**Independent Test**: Invoke discovery with remote credentials under success, empty-result, remote-failure, and process-invocation-exception conditions. Observe credential state before and after the call and inspect emitted output and errors for the supplied secret.

**Acceptance Scenarios**:

1. **Given** no pre-existing temporary credential state, **When** remote discovery succeeds, returns no files, or fails, **Then** credentials introduced for that operation are no longer present after it ends.
2. **Given** pre-existing process credential state, **When** remote discovery ends successfully or exceptionally, **Then** that prior state is restored without retaining the credentials supplied for discovery.
3. **Given** a remote listing process that cannot start or throws during invocation, **When** discovery unwinds, **Then** temporary credentials are cleaned up and the failure reaches the caller.
4. **Given** credentials containing a recognizable test secret, **When** discovery emits results, diagnostics, or errors, **Then** none contain that secret.

### Edge Cases

- Empty listings and listings consisting only of headers, status text, or unrelated files yield no audit results after a successful listing.
- Names with an empty audit prefix, malformed identifier, missing component, nonnumeric sequence or ticks, or extra trailing text are ignored.
- Prefixes containing underscores or spaces do not shift identification of the identifier, sequence, and ticks components.
- Remote listing indentation and metadata are distinguished from the filename; whitespace within a valid filename is preserved.
- Folder roots with trailing separators and nested share directories produce complete file paths without losing the filename or directory components.
- A directory whose name resembles a valid audit filename is not returned as a file.
- Listing failures remain failures even when their diagnostic output contains a plausible audit filename.
- Credential cleanup applies to normal completion, no matches, unsuccessful process exit, and an exception while invoking the process.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Discovery MUST apply one authoritative interpretation of audit filenames to both supported listing routes. A valid name consists of a nonempty audit-name prefix, an underscore, an identifier in the standard 8-4-4-4-12 hexadecimal GUID format, an underscore, a nonempty digit-only sequence, an underscore, a nonempty digit-only ticks component, and the `.sqlaudit` extension. Prefixes may contain underscores and spaces; GUID hexadecimal letters may use either case. Sequence and ticks are naming components, not additional ordering or date-validation rules.
- **FR-002**: Discovery MUST return one result per valid file, preserving the existing `FileName` full-path and `AuditGuid` GUID-value contract. Files sharing an identifier MUST remain separate results. Callers MUST NOT need to parse filenames or interpret operating-system listing output. No result-order guarantee is introduced.
- **FR-003**: Discovery MUST ignore malformed names, unrelated entries, directory entries, and remote listing metadata while continuing to return other valid files from a successful listing.
- **FR-004**: Discovery MUST preserve the existing supported access scope: local and UNC folders on Windows, and UNC share folders with nonempty supplied credentials on Linux. Credentials supplied to discovery on Windows MUST retain their existing unused behavior. Invalid requests, unavailable prerequisites, and unsupported operating systems MUST produce actionable terminating errors.
- **FR-005**: Discovery MUST return no results for a successful listing with no valid audit files, including an empty folder or a folder containing only rejected entries.
- **FR-006**: Discovery MUST surface enumeration and remote process failures as terminating errors. Failed remote listings MUST NOT return apparent audit results or be treated as successful empty listings; available failure context MUST be reported without revealing secrets.
- **FR-007**: Discovery MUST remove temporary credentials it introduces and restore any prior process credential state on every exit path, including process invocation exceptions. Results, logs, and errors MUST NOT reveal supplied passwords.
- **FR-008**: Verification MUST exercise the existing discovery interface for equivalent listings, malformed names, empty results, prerequisite and listing failures, and credential cleanup across both supported routes. Isolated checks of filename interpretation alone are insufficient evidence of discovery behavior.
- **FR-009**: Verification MUST retain real remote-share checks on Linux using the actual listing process to establish process invocation, listing interpretation, failure propagation, and credential cleanup. Controlled listings may establish repeatable rule parity, but an invented in-memory adapter MUST NOT substitute for real process verification. Unavailable environment checks MUST be recorded as unrun.
- **FR-010**: Discovery MUST remain responsible for listing and interpreting audit filenames so its caller does not acquire platform or transport handling. SQL Server MUST continue to read audit contents independently using its own access permissions; discovery credentials MUST NOT be presented as granting SQL Server file access.

### Key Entities *(include if feature involves data)*

- **Discovery request**: A folder and, for Linux remote access, credentials authorizing the listing. It does not authorize SQL Server to read file contents.
- **Audit filename**: A filename encoding an audit-name prefix, audit identifier, sequence, and ticks. The identifier groups files belonging to the same audit.
- **Discovered audit file**: A valid file represented by its full path and audit identifier; it contains no audit records or credentials.
- **Listing outcome**: Successful enumeration with zero or more valid files, or a failure that must reach the caller distinctly from an empty result.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For 100% of cases in the equivalent-listing verification set covering Story 1 and the filename edge cases, operators obtain the same accepted filenames and audit identifiers across both supported environments, with correct full paths for each root and zero malformed entries accepted.
- **SC-002**: Every empty-result and failure scenario in User Story 2 produces the specified distinct outcome; zero failed remote listings are reported as successful discovery results.
- **SC-003**: Across all four credential exit conditions (files found, no files found, listing failure, and invocation exception), zero supplied secrets remain in temporary process state or emitted output, and pre-existing credential state is restored in every case.
- **SC-004**: Every acceptance scenario is verified through the discovery interface, and a real remote-share verification run records at least one successful listing, one empty result, and one listing failure, including credential-state observations. Any unavailable run remains explicitly unverified.
- **SC-005**: Existing audit callers continue to discover files using the same request and result contract, with zero added caller responsibilities for platform selection, listing interpretation, or audit filename parsing.

## Assumptions

- This is a focused improvement of discovery, not a change to audit importing, checkpoints, database schemas, or file-content access. Sorting, recursive search, new filename formats, new platforms, and new transports are outside scope.
- The two existing listing mechanisms, Get-ChildItem on Windows and smbclient on Linux, are the evidence for the requested internal separation. A generic filesystem framework, public adapter-selection option, or new dependency is outside scope; detailed internal design belongs in planning.
- Compatibility is assessed against the existing filename grammar and discovery interface. Lowercase `.sqlaudit` names form the parity baseline; expanding extension-case support is outside scope.
- Removing duplicated filename interpretation is a locality requirement. Retaining discovery is a responsibility boundary: deleting it would move transport handling into the audit importer.
- Real remote verification requires a Linux environment, the existing remote-listing prerequisite, a reachable SMB share, and explicitly supplied test credentials. Test secrets must not be committed. Repeatable controlled checks supplement this environment rather than replace it.
- SQL Server service access to the audit folder remains an independent prerequisite, as documented in [Fast1Audit.md](../../Fast1Audit.md).
- Applicable constitution requirements are I (preserve audit integrity and resumability by avoiding silent discovery omissions), III (surface failures and keep secrets out of logs), IV (preserve existing command contracts and platform scope), and V (validate behavior at the appropriate boundary and record unrun environment checks). The discovery-specific Windows/Linux limit remains explicit; this feature does not change the module-wide runtime baseline.
- Development and Review Workflow items 6–11 also apply: all new or modified PowerShell files (`.ps1`, `.psm1`, and `.psd1`), including tests and fixtures, MUST receive `Invoke-ScriptAnalyzer` validation before their tasks are complete. Use the project's PSScriptAnalyzer configuration when available, resolve all newly introduced errors and warnings, and report unrelated pre-existing findings. Rules MUST NOT be disabled or suppressed solely to bypass validation. Analyzer unavailability or execution failure MUST be explicitly reported without claiming successful validation.
