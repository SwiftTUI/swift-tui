# Architecture Decision Records

This directory holds short, dated, durable records of the architectural
decisions that shape TerminalUI. Each ADR captures the context, the
decision, and the consequences in 200–400 words.

ADRs are not specs and not proposals. They are post-decision artifacts.
Their job is to make the project's accumulated wisdom legible at a glance
to a new contributor or a returning reviewer.

## Numbering

ADRs are numbered by adoption order, padded to four digits:

```
0001-swiftui-shaped-not-bubbletea-shaped.md
0002-seven-phase-pipeline-not-collapsed.md
0003-action-scopes-not-global-hotkeys.md
0004-frame-head-abort-reverted.md
```

Numbers are never reused, even when an ADR is superseded. Gaps in
numbering are fine — they mean an ADR is planned but not yet written.

## Frontmatter

```yaml
---
adr: "0001"
title: "SwiftUI-shaped, not Bubble Tea-shaped"
status: accepted
date: 2026-04-29
sources:
  - docs/VISION.md
  - docs/TERMINAL_NATIVE_DOCTRINE.md
---
```

Status values:

- `proposed` — under discussion; not yet binding.
- `accepted` — adopted by the project. The default.
- `superseded` — replaced by a later ADR. The body must link to the
  successor.
- `reverted` — adopted, then backed out. The body must capture the
  post-mortem.

`sources` is optional; list the canonical docs the ADR draws from so a
reader can pull deeper context.

## Body shape

ADRs use this skeleton:

```markdown
# ADR-NNNN: Title

## Context
What was the situation? What forces were at play?

## Decision
What did we pick? What were the alternatives?

## Status
accepted / superseded / reverted, plus a date.

## Consequences
What is enabled by this decision? What is foreclosed?
What new follow-ups does it imply?
```

Keep the body tight. If a section needs more than ~150 words, consider
whether it belongs in a design essay (`docs/<TOPIC>.md`) and let the ADR
link to it.

## How an ADR comes into being

1. A non-trivial design decision lands or is about to land.
2. The author drafts the ADR and lands it as part of (or just after) the
   PR that implements the decision.
3. Reviewers verify the ADR matches the change.
4. The ADR ships and is treated as durable. Future PRs that contradict it
   either supersede it (with an explicit link) or revert it.

A decision worth implementing is usually worth recording. If it isn't,
that's a signal the decision wasn't load-bearing.

## See also

- [VISION.md](../VISION.md) — the philosophy the ADRs descend from
- [PUBLIC_SURFACE_POLICY.md](../PUBLIC_SURFACE_POLICY.md) — the policy
  framework ADRs participate in
- [TESTING_AND_FIXTURE_POLICY.md](../TESTING_AND_FIXTURE_POLICY.md) — the
  testing rules ADRs are held to when they introduce new behavior
