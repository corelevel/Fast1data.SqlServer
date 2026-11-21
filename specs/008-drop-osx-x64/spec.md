# Feature Specification: Drop macOS x64 Support

**Feature Branch**: `dev` (existing branch; no branch-creation hook configured)

**Created**: 2026-11-20

**Status**: Draft

**Input**: User description: "deprecate 'osx-x64'. keep only 'win-x64' and 'linux-x64'"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Obtain a release for the supported platforms (Priority: P1)

As a maintainer, I can build and distribute a release that supports only x64 Windows and x64 Linux, so the published platform promise matches the platforms maintained by the project.

**Why this priority**: Restricting the supported targets is the requested compatibility change and determines what users receive.

**Independent Test**: Produce a release from both a clean workspace and a workspace containing an old macOS bundle. Confirm that the resulting distribution's platform bundles are exactly `win-x64` and `linux-x64`, then verify existing command acceptance on both platforms.

**Acceptance Scenarios**:

1. **Given** a clean workspace, **When** the maintainer builds the release, **Then** dependency bundles are produced for `win-x64` and `linux-x64` only.
2. **Given** a workspace or staging directory containing an old `osx-x64` bundle, **When** a new distribution is prepared, **Then** that obsolete platform bundle is excluded.
3. **Given** either supported platform, **When** a user installs the release and loads the module through a supported entry point, **Then** dependencies load and existing public commands remain available with their current contracts.
4. **Given** an existing installation's database state, migration history, and configuration, **When** execution moves to a supported host using this release, **Then** existing contracts remain valid without a database-format migration caused by platform removal.

---

### User Story 2 - Receive a clear unsupported-platform result (Priority: P1)

As a user attempting to run the new release on macOS, I receive a clear explanation that the platform is unsupported and that x64 Windows and x64 Linux are the supported choices.

**Why this priority**: Removing a bundle without changing platform acceptance would leave users with misleading missing-dependency failures.

**Independent Test**: Attempt module initialization on macOS, including with a leftover macOS bundle, and verify an unsupported-platform error before database work begins.

**Acceptance Scenarios**:

1. **Given** an x64 macOS host, **When** module initialization selects platform dependencies, **Then** initialization fails with an unsupported-platform message identifying x64 Windows and x64 Linux as supported.
2. **Given** a macOS host with an old `osx-x64` bundle present, **When** initialization is attempted, **Then** the presence of that bundle does not enable macOS support.
3. **Given** an operating system or processor architecture outside the supported targets, **When** initialization is attempted, **Then** it rejects the platform without falling back to another platform's bundle or starting database operations.

---

### User Story 3 - Understand the compatibility change before upgrading (Priority: P2)

As an existing user, I can determine which platforms the new release supports and understand how removal affects a macOS installation before upgrading.

**Why this priority**: Current documentation and package metadata advertise macOS support, so users need consistent support statements and upgrade guidance.

**Independent Test**: Review current installation guidance, package platform metadata, release notes, and compatibility policy for agreement on supported platforms and the macOS transition.

**Acceptance Scenarios**:

1. **Given** current installation requirements or package metadata, **When** a user checks supported platforms, **Then** only x64 Windows and x64 Linux are advertised as supported.
2. **Given** a macOS user considering an upgrade, **When** they read release notes and upgrade guidance, **Then** they learn that this release removes macOS support and requires moving execution to a supported host.
3. **Given** the existing compatibility policy, **When** the change is prepared for release, **Then** the policy records the authorized platform change and the release records an explicit version decision for this breaking change.

### Edge Cases

- Reused build or staging directories contain an obsolete macOS bundle: new distributions still contain only the two supported platform bundles.
- An old macOS bundle is copied into a new installation: platform validation still rejects macOS.
- An unsupported architecture, including ARM64, is used: the change introduces no additional supported target or fallback.
- Required dependencies are missing on a supported host: the user receives an actionable dependency error rather than an unsupported-platform error.
- Historical specifications or earlier releases mention macOS: they remain historical records; current support claims and new distributions reflect the new scope.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Supported runtime targets MUST be exactly `win-x64` and `linux-x64`; `osx-x64` MUST be removed from active support in the release delivering this feature.
- **FR-002**: Release builds MUST produce platform dependency bundles only for the two supported targets. New distributions MUST exclude obsolete macOS bundles, including when prepared from reused build or staging directories.
- **FR-003**: Module initialization MUST reject macOS even when an old macOS bundle is present, report that the platform is unsupported, and identify x64 Windows and x64 Linux as alternatives before starting database operations.
- **FR-004**: Unsupported operating systems and architectures MUST remain rejected without selecting another platform's bundle.
- **FR-005**: Both supported targets MUST retain dependency loading and existing public command contracts through all supported module entry points. Missing dependencies on a supported target MUST retain actionable dependency diagnostics.
- **FR-006**: Current installation requirements, platform metadata, and release notes MUST consistently advertise only x64 Windows and x64 Linux. Upgrade guidance MUST explicitly describe macOS removal and moving execution to a supported host.
- **FR-007**: The project compatibility policy MUST reflect this explicitly authorized platform change. Release preparation MUST document the breaking compatibility change and an explicit module release-version decision.
- **FR-008**: Existing database state, migration history, configuration formats, and command behavior on supported platforms MUST remain compatible; moving execution to a supported host MUST NOT require a database-format migration because of platform removal.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Every new distribution, from either a clean or reused workspace, contains exactly two supported platform bundles and zero macOS platform bundles.
- **SC-002**: Users on both supported platforms can load the module and complete all existing command acceptance scenarios with no contract regressions attributable to platform removal.
- **SC-003**: Every unsupported-platform acceptance scenario ends with explicit platform rejection and zero database operations; macOS rejection identifies both supported alternatives.
- **SC-004**: All current support statements in installation guidance, package metadata, release notes, and compatibility policy agree on the same two supported platforms, and upgrade guidance explains macOS removal.

## Assumptions

- "Deprecate" together with "keep only" means removal of active support in the release delivering this feature, without an intermediate warning-only release.
- The request authorizes the explicit compatibility change allowed by constitution Principle IV. Implementation must reconcile that principle's current macOS wording, document the amendment and transition, and record its version impact under Governance; this specification does not amend the constitution itself.
- The current PowerShell baseline, public command surface, and database contracts remain in force. No additional operating systems or architectures are introduced.
- Dependencies include the existing build and distribution workflows, platform selection, module entry points, and published platform descriptions. Verification must cover packaging and loading on both retained platforms under constitution Principle V and the Development and Review Workflow.
- Historical specifications and previously published releases need not be rewritten or withdrawn. Obsolete bundles must be excluded from new distributions; deleting users' existing installations is outside scope.
- The exact release number will be recorded during release planning using project versioning policy; this specification does not assign a new number.
