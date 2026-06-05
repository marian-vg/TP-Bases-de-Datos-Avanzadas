---
name: commit-per-feature
description: Create an atomic Conventional Commit after completing and verifying a feature in this repository. Use when a feature, simulation scenario, report, documentation block, or other independently reviewable change is complete on the dev/simulacion branch.
---

# Commit Per Feature

Create one atomic commit after each independently reviewable feature.

## Workflow

1. Confirm the feature is complete and run its relevant verification.
2. Inspect `git status --short` and keep unrelated user changes out of the commit.
3. Choose a Conventional Commit message that describes only this feature.
4. Invoke `scripts/commit_feature.ps1` with the message and every intended path explicitly.
5. Confirm the resulting commit with `git show --stat --oneline HEAD`.

## Guardrails

- Commit only on the exact branch `dev/simulacion`.
- Never use `git add .` or broad directory staging when a smaller path list is possible.
- Never include already-staged or unrelated changes.
- Never push automatically.
- Stop if verification fails, the worktree contains ambiguous changes, or the feature is not independently reviewable.

## Usage

```powershell
& .agents/skills/commit-per-feature/scripts/commit_feature.ps1 `
  -Message "feat(simulation): add transactional assertion harness" `
  -Paths @("simulacion/lib/harness.sql", "simulacion/00_run_all.sql")
```
