# Public Surface Policy

Last updated: March 30, 2026

This note defines how the package should think about its public API shape after the public-surface consolidation.

## Principle

The package should present one primary authoring story:

- write views with the SwiftUI-shaped surface in `View`
- use the runtime in `TerminalUI`, with `TerminalUIScenes` as the optional multi-scene layer
- treat `Core` as pipeline and data-model infrastructure

Anything outside that shape must justify why it is public.

## Canonical Surface

The canonical public surface is the one used in README examples, architecture docs, and ordinary application code:

- `View` and the SwiftUI-shaped container and leaf APIs
- property wrappers and environment plumbing that feel like SwiftUI
- runtime integration points in `TerminalUI` that host those views in a terminal session
- `TerminalUIScenes` only when the app needs the separate multi-scene runtime story

If a feature can be expressed naturally on that surface, it should be documented there first.

## Compatibility Tier

Some package-only symbols still exist because the repo is carrying internal compatibility and test seams.

Those seams are allowed to remain only if one of these is true:

- they are required by existing adopters
- they are needed to keep the runtime or tests stable during migration
- they are intentionally documented as package-only internals

Package-only seams should not be the first example a new reader sees.

Experimental or showcase targets follow the same rule. They may remain in the repository for demos, tests, and design exploration, but they should not be exported as package products unless they have graduated into the canonical public story.

## Low-Level Construction Policy

The `*` authoring nodes are not part of the public authoring story.

They may remain package-only when:

- a test needs to validate internal reuse or identity behavior directly
- a compatibility path is still being migrated
- a symbol is a narrow adapter around the canonical surface

They should not be expanded casually. If a new feature can be authored on `View`, it should usually stay there.

## Styling Policy

Semantic styling is the preferred model.

The old public string-style helpers and public `Theme` shims have already been removed from `View`.

Any remaining styling compatibility should stay confined to lower-level core types and should not re-enter the main `View` authoring surface. New docs should show typed semantic style APIs instead.

## Transitional Runtime Policy

Runtime bridges and staging adapters are acceptable while the package is still reconciling old host shapes with the current commit model.

If retained, host-staging adapters belong in this category as package-internal compatibility seams, not as part of the public story.

Compatibility factories such as the old `Package` helpers do not qualify as canonical runtime API and should not be reintroduced.

## View Lowering Policy

- Public `View` stays body-only.
- Public builder-taking APIs should accept typed `@ViewBuilder` closures, not `[AnyView]`.
- Internal lowering protocols such as `ResolvableView` must stay package-only.
- There is no public replacement for direct primitive lowering in this release.

## AnyView Policy

`AnyView` remains part of the supported surface as a narrow type-erasure escape hatch,
but it is not the default authoring model for this package.

- Prefer typed `@ViewBuilder` closures and generic `Content: View` storage.
- Do not add public APIs that expose `[AnyView]`, builder closures returning `AnyView`, or direct node-erasure construction seams.
- Internal `AnyView` storage is acceptable only for heterogeneous child storage, deferred authored-content capture, or local branch unification when concrete view types genuinely diverge.
- If authored content is stored for later evaluation, capture it with `scopedAnyView(...)`, not plain `AnyView(...)`, so dynamic-property scope and identity-bound state continue to behave correctly.
- New stored `AnyView`, `[AnyView]`, or closure-returning-`AnyView` members should carry a nearby `AnyView policy:` comment explaining why typed storage is not practical in that file.
- Reviewers should treat new erasure sites as design decisions, not as convenience refactors.

## Review Checklist

Before adding a new public symbol, ask:

1. Can the feature be expressed on the canonical SwiftUI-shaped surface instead?
2. Does the symbol help new app code, or only package-local migration and test compatibility?
3. Will the README and architecture docs still read as a single coherent story if this lands?
4. Can the feature live behind an internal or test-support seam instead?
5. Is this really a supported product surface, or is it still prototype or showcase code that should remain target-only inside the package?

If the answer points toward internal compatibility rather than product direction, the symbol should stay non-public.
