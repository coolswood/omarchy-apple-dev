
## Review and merge rule (2026-10-10)

The human owners do not review or merge pull requests. Agents do. Another agent or a review bot reviews a PR, the author fixes the findings, and the PR is merged when it is clean and CI is green.

- Never write or report a PR as blocked on an owner's review or merge.
- Only an explicit per-PR hold stands. A hold is named in the PR itself.
- A PR that needs a review: ask another agent or use the review bots, fix the findings, then merge when green.

## Owner standing rules (all repos, since 2026-11-09)

- **Orchestrator mode**: the main agent session orchestrates; multi-step work (exploration, code changes, tests, scripts, triage) runs in background subagents (Agent tool, `run_in_background: true`), so the owner can keep talking to the session. Independent tasks run in parallel. Relay results faithfully when completion notifications arrive; never fabricate pending results. Direct execution only for micro-operations (a single read/command).
- **Business logic over code**: default answers to the level of business logic and decisions — what changes for the system/users/data, which alternatives exist, their consequences. Code snippets are illustration, not substance. Technical choices (library, format, command) — decide yourself; surface only what changes business meaning.
