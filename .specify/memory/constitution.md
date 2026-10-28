# Fast1data.SqlServer Constitution

## Core Principles

### I. Data Integrity and Resumability

Audit imports and archiving MUST preserve durable progress so interrupted work can resume
without silently skipping unfinished records. Checkpoints MUST represent completed work;
audit offsets MUST also advance across intentionally ignored records. Changes to batching,
copying, purging, or checkpoint storage MUST account for interruption and retry behavior.
Archiving MUST preserve configured working sets and processing order. Single-process
requirements for an audit directory or table group MUST remain documented unless concurrent
execution is explicitly implemented and verified. These rules protect data across partial failures.

### II. Deterministic Migrations

Migrations MUST follow configured phase and script order and validate SHA-256 checksums
against execution history. Changed executed scripts MUST be rejected unless explicitly forced.
Validation MUST reject duplicate entries, ignore/force conflicts, and paths outside the selected
phase directory before executing scripts. Script matching MUST preserve documented case and
path-separator behavior. Migration guidance MUST require idempotent scripts because execution
can succeed before history recording fails. `-WhatIf` MUST preview migration changes without
executing scripts or writing history.

### III. Explicit Database Operations

Database mutations MUST be bounded by selected configuration and documented permissions.
SQL values MUST use parameters where supported; dynamic identifiers MUST be validated and
quoted for their SQL context. Migration files and configured SQL queries MUST be documented
as executable administrator inputs. Purging and foreign-key disabling MUST remain explicit
configuration choices with documented integrity implications. Failures MUST surface to callers;
migration SQL failures MUST terminate execution. Credentials and connection strings containing
secrets MUST NOT appear in committed examples or operational logs.

### IV. Portable PowerShell Contracts

The module MUST maintain its documented PowerShell 7.4-or-later Core baseline and x64 Windows,
Linux, and macOS support until an explicit compatibility change is approved. Public commands
MUST be explicitly exported through the manifest. Changes to parameters, configuration formats,
SQL schemas, dependencies, or runtime requirements MUST update affected manifest entries, help,
and documentation. Paths MUST respect documented portable migration conventions. New
dependencies MUST have a stated purpose and a documented build or installation path.

### V. Verification and Operational Visibility

Behavior changes MUST receive validation appropriate to their risk. Changes affecting SQL
execution, persisted progress, checksums, copying, or purging MUST include regression coverage
for relevant success, failure, and retry cases. SQL-specific behavior MUST be verified against
SQL Server when mocks cannot establish correctness. Progress and warnings MUST expose
actionable processing state without leaking secrets. Documentation MUST describe prerequisites,
setup order, limitations, and recovery behavior affected by a change.

## Database and Runtime Constraints

- PowerShell orchestration, Microsoft.Data.SqlClient, the SqlServer module, and versioned SQL
  setup scripts form the supported implementation stack.
- Database object changes MUST account for existing installations and persisted migration,
  audit, and archiving state. Required upgrade steps MUST be documented.
- Archiving MUST retain its documented primary-key requirement and the requirement that the
  configuration database reside on the source SQL Server instance unless a verified design
  explicitly changes those constraints.
- Tests that create, alter, or delete database objects MUST use an explicitly selected test
  database. Test setup and required permissions MUST be documented.
- Build and packaging changes MUST preserve declared runtime assets or explicitly document
  and version a change in supported platforms.

## Development and Review Workflow

1. Define affected commands, configuration, database objects, compatibility implications,
   and failure behavior before implementation. Spec Kit artifacts, when used, MUST identify
   applicable constitution requirements.
2. Keep changes focused on the stated problem. Added abstractions and dependencies MUST have
   a concrete justification tied to that problem.
3. Run affected Pester coverage and required SQL Server integration checks. Module-loading,
   dependency, or packaging changes MUST also validate the affected import or build path.
4. Record validation results and unavailable environment checks. Unrun checks MUST NOT be
   reported as passing; unresolved material data-integrity risks MUST block release.
5. Review code, schemas, help, and examples together for contract consistency and constitution
   compliance before merging. Breaking changes MUST include upgrade guidance and an explicit
   release-version decision.

## Governance

This constitution governs project design, implementation, and review. Conflicting guidance MUST
be reconciled with it or addressed through an explicit amendment before adoption. Each change
review MUST check applicable principles. Proposed exceptions MUST record rationale, impact,
and a remediation plan and MUST receive maintainer approval.

Amendments MUST describe proposed text, rationale, affected contracts, and transition steps.
Maintainers MUST approve amendments before adoption. Constitution versions use semantic
versioning: MAJOR for incompatible principle removals or redefinitions, MINOR for new principles
or materially expanded guidance, and PATCH for non-semantic clarifications. Constitution and
module versions are independent. Amendments MUST retain the original ratification date and
update the last-amended date when content changes. Dependent workflows MUST read the active
constitution at runtime; their templates are outside this amendment's scope.

**Version**: 1.0.0 | **Ratified**: 2026-10-28: maintainer must confirm adoption date | **Last Amended**: 2026-10-28
