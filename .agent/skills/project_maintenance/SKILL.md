---
name: Project Maintenance
description: Guidelines for maintaining project documentation (GOTCHAS.md, CHANGELOG.md).
---

# Project Maintenance

This skill ensures the project documentation stays alive and useful.

## 1. `GOTCHAS.md` (Living Knowledge Base)

**Location**: Root of the repository (`/GOTCHAS.md`).

**Purpose**:
To document tricky, non-obvious, or painful details about the codebase that are easily forgotten. This usually means things that `grep` won't tell you.

**When to Update**:
*   Whenever you spend more than 10 minutes debugging a weird issue.
*   When you discover an undocumented dependency between two components.
*   When you implement a workaround for a framework bug.
*   When you define a specific business rule (e.g., "Grades dropped in 12/2 are strictly ignored").

**Structure**:
Keep it grouped by topic (e.g., `# Grade Calculation`, `# UI`, `# Firestore`). Use concise bullet points.

## 2. `CHANGELOG.md` (History)

**Location**: Root of the repository (`/CHANGELOG.md`).

**Purpose**:
To keep a human-readable history of what has changed in the project.

**Format**:
Follow [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format.
*   Newest version at the top.
*   Global `[Unreleased]` section at the top for current work.
*   Subsections: `### Added`, `### Changed`, `### Deprecated`, `### Removed`, `### Fixed`.

**Instruction**:
*   **AFTER** completing a feature or fix (in `VERIFICATION` mode or before notifying the user), append a line to the `[Unreleased]` section of `CHANGELOG.md`.

## 3. Workflow Integration
When finishing a task:
1.  Did I solve a weird bug? -> Update `GOTCHAS.md`.
2.  Did I add a feature? -> Update `CHANGELOG.md`.
