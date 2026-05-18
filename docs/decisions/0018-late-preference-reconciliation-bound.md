---
adr: "0018"
title: "Late-preference reconciliation remains bounded and diagnostic"
status: accepted
date: 2026-05-17
sources:
  - docs/plans/2026-05-12-002-late-preference-reconciliation-plan.md
  - docs/plans/2026-05-16-001-pipeline-driver-hardening-plan.md
  - docs/plans/2026-05-17-001-stage-2-name-hidden-stages-plan.md
  - Sources/SwiftTUIRuntime/SwiftTUI.swift
---

# ADR-0018: Late-preference reconciliation remains bounded and diagnostic

## Context

Layout-dependent content can emit preferences only after measure/place realizes
that content. The runtime therefore runs a late-preference reconciliation stage:
apply layout-dependent realizations, reconcile consumers such as toolbar hosts,
and re-run layout if the reconciled tree changes structure or safe area.

That is a bounded fixpoint loop, not a single pass through the advertised
seven-phase pipeline. The current shipped consumer is toolbar hosting for
layout-dependent `.toolbarItem(...)` values.

## Decision

Keep late-preference reconciliation as an explicitly named loop-bearing stage
with a runtime pass budget derived from the current resolved tree.

When the stage still has not converged after the bound, the runtime keeps the
frame non-fatal but no longer commits the stale pre-reconciliation output. It
emits a `latePreference.reconciliationLimitExceeded` warning, applies the
latest reconciled tree, performs one final relayout, and commits that final
reconciled layout.

Do not make bound exhaustion a hard runtime failure in this stage.

## Rationale

The shipped toolbar-host loop still gives the smallest concrete example:

1. Initial layout realizes layout-dependent toolbar items before toolbar chrome
   exists.
2. The first reconciliation absorbs those items and inserts toolbar chrome,
   which changes the available geometry for the hosted content.
3. The relayout realizes geometry-dependent content again under the reserved
   toolbar row; those realized toolbar payloads can differ from the first pass.
4. The next reconciliation absorbs that changed payload, and the final check
   confirms the tree is stable.

That sequence needs four checks in the current fixture, but the runtime no
longer bakes that value into the stage. The budget is `resolved.subtreeNodeCount
+ 1`: every relayout must be justified by a finite node in the current resolved
tree producing changed late-preference consumer output, and the extra pass is
the stability confirmation. If the runtime emits
`latePreference.reconciliationLimitExceeded`, the authored tree has exceeded the
finite per-frame tree budget or formed a late-preference cycle.

A hard failure would turn authored preference depth into a frame-killing runtime
error. That is too aggressive while the only shipped late consumer is toolbar
hosting and while the broader arbitrary-preference dependency graph is not
modeled.

## Consequences

- Stage 3 must compose late-preference reconciliation as a loop-bearing stage,
  not hide it in the frame tail.
- The warning remains author-observable through frame diagnostics and runtime
  issue sinks.
- Deep or cyclic late-preference dependencies render from one final relayout of
  the latest reconciled tree after the bound instead of the older stale
  pre-reconciliation output.
- A future expansion beyond toolbar hosting should revisit this ADR and decide
  whether a stronger dependency-depth solver or hard failure is justified.
