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
with a documented runtime bound of four relayout passes.

When the stage still has not converged after the bound, the runtime keeps the
existing behavior: emit a `latePreference.reconciliationLimitExceeded` warning
and commit the last fully laid-out tree with the latest realized
layout-dependent content.

Do not make bound exhaustion a hard runtime failure in this stage. Do not derive
the bound from a preference graph yet.

## Rationale

Four relayout passes are the existing shipped behavior from the toolbar
reconciliation tranche. Keeping that value preserves compatibility while making
the policy visible in code.

A hard failure would turn authored preference depth into a frame-killing runtime
error. That is too aggressive while the only shipped late consumer is toolbar
hosting and while the broader arbitrary-preference dependency graph is not
modeled.

A derived bound is the better long-term shape, but it needs evidence from more
than one late-preference consumer. Until `overlayPreferenceValue`,
`backgroundPreferenceValue`, or another structural consumer enters this stage,
the runtime cannot honestly claim a dependency-depth solver.

## Consequences

- Stage 3 must compose late-preference reconciliation as a loop-bearing stage,
  not hide it in the frame tail.
- The warning remains author-observable through frame diagnostics and runtime
  issue sinks.
- Deep or cyclic late-preference dependencies can still render with stale final
  consumer output after the bound. That is an explicit degradation policy, not
  an accidental silent path.
- A future expansion beyond toolbar hosting should revisit this ADR and decide
  whether a graph-derived bound or a stronger diagnostic is justified.
