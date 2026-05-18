---
adr: "0022"
title: "Resolve side-effect staging"
type: decision
status: accepted
date: 2026-05-17
sources:
  - docs/decisions/0004-frame-head-abort-reverted.md
  - docs/plans/2026-05-17-009-pipeline-driver-followup-remediation-plan.md
  - docs/proposals/PIPELINE_DRIVER_FOLLOWUP_AUDIT.md
  - docs/proposals/PIPELINE_DRIVER_RESOLUTION_LEDGER.md
---

# ADR-0022: Resolve side-effect staging

## Context

Audit finding F3 flagged that resolve mutates runtime subsystems before commit,
so the old "commit is the side-effect boundary" wording was too broad. A
previous attempt to make frame-head preparation fully pure was reverted in
ADR-0004, because the runtime needs staged access to graph, presentation,
observation, animation, registration, and frame-input state before the tail can
be rendered or cancelled correctly.

The defect was not only the wording. The staging mechanics were spread across
separate draft, checkpoint, commit, and discard calls, making it easy for an
abort path to restore one subsystem but leave residue in another.

## Decision

Resolve remains a staged transaction. The frame head opens a
`FrameHeadTransaction`; commit closes that transaction; abort discards it.

`FrameHeadTransaction` owns the graph draft, runtime registration draft,
presentation portal draft, optional observation draft, animation draft, and the
frame-state/frame-input checkpoints. The renderer commits the transaction
through one `commit()` call and aborts it through one `discard()` call, rather
than coordinating those subsystems with ad-hoc calls in `DefaultRenderer`.

## Consequences

The architecture no longer claims that commit is the only side-effect site.
Frame-head preparation may stage side effects into the transaction, and commit
is the closing boundary that publishes them. Abort totality is guarded by
`ResolvePurityTests.abortLeavesNoResidue`, which compares the observable
runtime subsystem snapshot before and after a prepared head is discarded.

Full resolve purity remains out of scope for this decision. A future attempt to
make the head side-effect-free must replace this transaction explicitly and keep
the abort-totality test intact.
