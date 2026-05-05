---
adr: "0005"
title: "AnyView and AnyScene as escape hatches, not defaults"
status: accepted
date: 2026-04-29
refined: 2026-05-05
sources:
  - docs/PUBLIC_SURFACE_POLICY.md
  - docs/ANYVIEW_INTERNALS.md
  - docs/PUBLIC_API_INVENTORY.md
  - AGENTS.md
  - docs/proposals/TYPE_ERASURE_DEFERRAL_PLAN.md
  - docs/proposals/TERMINAL_EMBEDDING.md
  - docs/plans/2026-05-04-001-terminal-embedding-plan.md
  - docs/plans/2026-05-05-001-resilient-anyview-plan.md
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

## Runtime refinement (refined 2026-05-05)

`AnyView` is now resilient enough to behave like a real type-erased
view boundary in the retained graph without changing its role as an
escape hatch.

This is a SwiftTUI contract, not a claim that SwiftUI's private
`AnyView` runtime has the same behavior. SwiftTUI intentionally exposes
different trade-offs: an inspectable retained graph, terminal
incremental-paint reuse, package-owned lifecycle cleanup, and explicit
authoring-context capture for deferred content.

The resolver lowers an `AnyView` into a wrapper node and a
type-stamped payload node:

```text
AnyView identity
+-- AnyViewPayload<ErasedStaticType> identity
    +-- concrete content
```

The wrapper identity stays stable for a stable authored `AnyView`
position. The payload identity includes the erased static payload type.
If the erased static type is unchanged, the payload subtree keeps its
retained state, lifecycle registrations, focus/action registrations,
and measurement reuse. If the erased static type changes, the payload
subtree is structurally replaced and normal `ViewGraph` removal
cancels tasks, runs disappear handlers, and drops the removed state
slots.

Concrete payload content is resolved through the normal `resolveView`
path so custom views receive ordinary retained graph ownership.
`scopedAnyView(...)` still restores the authored owner for deferred
content: action follow-up invalidation remains pointed at the owner
that authored the action, while the concrete payload participates in
the retained graph at its payload identity.

Explicit `.id(...)` values inside an `AnyView` payload remain authored
identities for focus, actions, and user-directed lookup. To keep those
external identities stable without preserving incompatible state, the
resolver asks `ViewGraph` to prune the old payload subtree before it
resolves content for a changed erased static payload type.

This refinement does **not** make `AnyView` the preferred storage type.
Typed builders and generic `Content: View` storage remain the default;
new public `[AnyView]`, `() -> AnyView`, or builder-returning-`AnyView`
APIs still require explicit policy justification.

Practical examples for framework consumers are documented in the
`SwiftTUIViews` DocC article for `AnyView`. Maintainer-specific examples,
including acceptable test fixtures, builder-backbone compatibility, deferred
content capture, and dangerous internal erasure patterns, are documented in
[ANYVIEW_INTERNALS.md](../ANYVIEW_INTERNALS.md).
