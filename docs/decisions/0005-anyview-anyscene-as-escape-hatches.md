---
adr: "0005"
title: "AnyView and AnyScene as escape hatches, not defaults"
status: accepted
date: 2026-04-29
refined: 2026-05-04
sources:
  - docs/PUBLIC_SURFACE_POLICY.md
  - docs/PUBLIC_API_INVENTORY.md
  - AGENTS.md
  - docs/proposals/TYPE_ERASURE_DEFERRAL_PLAN.md
  - docs/proposals/TERMINAL_EMBEDDING.md
  - docs/plans/2026-05-04-001-terminal-embedding-plan.md
---

# ADR-0005: AnyView and AnyScene as escape hatches, not defaults

## Context

`AnyView` and `AnyScene` are SwiftUI-shaped type-erasure containers.
They make it easy to:

- store heterogeneous children in a `[AnyView]` array,
- return different concrete types from a builder branch under a single
  signature,
- defer authored content for later evaluation.

They also make it easy to *lose* the structural identity that the
framework's state, lifecycle, and reuse machinery depends on. SwiftUI's
own runtime treats `AnyView` as a hint that identity has been collapsed
— behavior that's defensible in SwiftUI but expensive in SwiftTUI's
incremental-paint pipeline, where dropped reuse triggers full repaints.

Earlier authoring patterns in the package leaned on `AnyView` and
`[AnyView]` storage for builder-flexibility convenience. Those patterns
were reachable to consumers, were the default example in some early
docs, and made it easy to write code that silently disabled
identity-keyed state and measurement-cache reuse.

## Decision

`AnyView` and `AnyScene` remain on the public surface as **escape
hatches**, not as default authoring shapes. The package's public API
guards against turning them into defaults:

- Public `View` is body-only. It does not inherit any low-level
  resolver protocol, and there is no public `[AnyView]` initializer.
- Public builder-taking APIs accept typed `@ViewBuilder` /
  `@SceneBuilder` closures, never `[AnyView]` / `[AnyScene]`.
- Internal `AnyView` storage is acceptable only for heterogeneous
  child storage, deferred authored-content capture, or local branch
  unification when concrete types genuinely diverge.
- Authored content captured for later evaluation goes through
  `scopedAnyView(...)`, not plain `AnyView(...)`, so dynamic-property
  scope and identity-bound state continue to behave correctly.
- New stored `AnyView`, `[AnyView]`, or closure-returning-`AnyView`
  members carry a nearby `AnyView policy:` comment explaining why
  typed storage is not practical in that file.

The same rules apply to `AnyScene`: typed `@SceneBuilder` and generic
`WindowGroup<Content>` storage are the defaults; `AnyScene` is the
narrow erasure escape for availability unification or compatibility
seams.

## Status

Accepted. Enforced through the `Scripts/check_public_surface_policies.sh`
pre-commit hook, the
[PUBLIC_SURFACE_POLICY.md](../PUBLIC_SURFACE_POLICY.md) review
checklist, and the
[TYPE_ERASURE_DEFERRAL_PLAN.md](../proposals/TYPE_ERASURE_DEFERRAL_PLAN.md)
remaining-work tracker.

## Consequences

**Enabled:**

- Identity-keyed state survives most authored patterns by default.
  Authors don't have to know about `AnyView` to keep `@State` working.
- Measurement cache and resolve-reuse stay effective because the
  structural type tree is preserved through ordinary authoring.
- A new `AnyView` site is treated as a design decision in review, not
  as a convenience refactor — the comment requirement makes the cost
  visible.

**Foreclosed:**

- The "stuff a heterogeneous array of views into a parent" pattern is
  not the default authoring path. Typed `@ViewBuilder` closures are.
- Public APIs that historically exposed `[AnyView]` builder closures or
  `AnyView`-returning factories are not reintroduced as compatibility
  shims.
- Adding a new public erasure seam requires explicit ADR-level
  consideration, not just a one-line shim.

**Discipline imposed:**

- Reviewers reject erasure-as-convenience refactors even when they
  shrink the diff.
- Internal lowering protocols (`ViewNode`, `ResolvableView`) stay
  package-only; the migration to remove them remains tracked in the
  type-erasure deferral plan.

The bet: authored apps that lean on typed builders write less code
that silently disables runtime correctness, and SwiftTUI's
incremental-rendering invariants stay intact across ordinary edits.

## What this ADR does not decide (refined 2026-05-04)

Two related questions are deliberately *out of scope* here, surfaced by
the terminal-embedding planning discussion:

1. **Identity-preserving erasure as a mechanism.** The framework
   provides none today. `AnyView` is structurally erasing — identity
   does not flow through it, lifecycle metadata bound below is at
   risk, and the resolve phase treats it as a leaf. This is a missing
   capability, not a deliberate stance. It has not bitten hard enough
   yet to motivate the substrate work.

2. **Whether this ADR holds if that capability is added.** It does.
   `AnyView` would remain a smell signal regardless: typed views stay
   preferred for compile-time clarity, refactor safety, and
   legibility — concerns inherited from SwiftUI culture and
   independent of the runtime's identity story. But future
   load-bearing surfaces — particularly an in-process plugin system
   wanting third-party `View`s to participate in the host's lifecycle
   — would need identity-preserving erasure. That work should propose
   a *separate* mechanism distinct from `AnyView` (e.g.
   `IdentityPreservingErasure<Subtree>`). As a side effect, the
   substrate would let `AnyView` lose its identity-loss bug class
   without changing its public role.

The pseudo-symmetry: the substrate work an ambitious plugin system
needs is structurally the same work that would make `AnyView`
non-broken. See
[plans/2026-05-04-001-terminal-embedding-plan.md](../plans/2026-05-04-001-terminal-embedding-plan.md)
"Future Stages (Speculative)" for the long-form discussion and the
conditions under which the substrate becomes worth scheduling.
