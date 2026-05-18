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

The Phase 10 independent re-audit found the original remediation incomplete:
although abort totality was centralized, a prepared abortable head still left
live runtime subsystems visibly mutated until `discard()` rolled them back.

The defect was not only the wording. The staging mechanics were spread across
separate draft, checkpoint, commit, and discard calls, making it easy for an
abort path to restore one subsystem but leave residue in another.

## Decision

Resolve remains a staged transaction, but abortable frame-head preparation no
longer leaves the live runtime in the prepared state. The frame head opens a
`FrameHeadTransaction`; that transaction captures both the committed baseline
and the prepared graph/frame-input state, then suspends the live runtime back to
the committed baseline before the prepared head is returned.

`FrameHeadTransaction` owns the graph draft, runtime registration draft,
presentation portal draft, optional observation draft, animation draft, and the
frame-state/frame-input checkpoints. Preview and commit explicitly materialize
the prepared state; preview suspends it again afterward, while commit publishes
it through one `commit()` call. Abort discards the draft-owned state through one
`discard()` call rather than rolling back an observable live mutation.

## Consequences

The architecture no longer claims that head construction is purely functional;
it may use runtime subsystem machinery while building the transaction. The
observable boundary is stricter: after abortable preparation returns, live
runtime subsystem state matches the committed baseline until preview or commit
materializes the draft. Abort totality is guarded by
`ResolvePurityTests.abortLeavesNoResidue`, which compares the observable
runtime subsystem snapshot before preparation, immediately after preparation,
and after the prepared head is discarded.

Full resolve purity remains out of scope for this decision. A future attempt to
make the head side-effect-free must replace this transaction explicitly and keep
the no-observable-residue test intact.
