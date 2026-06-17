package import SwiftTUICore

/// A view that compares equal to its previous value by its wrapped content's
/// `==`, letting the renderer reuse the whole wrapped subtree without
/// re-evaluating it when the content is unchanged.
///
/// SwiftTUI's memoized-body reuse reuses a node's committed subtree when its view
/// value is unchanged and it recorded no `@State`/`@Observable` reads. The gate
/// is **`Equatable`-only**: a view participates only by conforming to `Equatable`.
/// ``EquatableView`` is the `.equatable()` opt-in: it wraps an *already-`Equatable`*
/// `Content` (the `Content: Equatable` bound is required) and relocates the reuse
/// boundary onto its own node, so the wrapped subtree can be a boundary even where
/// the enclosing view is not `Equatable`. On a match it reuses the whole subtree —
/// *including any `ForEach`/`Button` closures inside*, which are descendants of the
/// reused boundary and never compared.
///
/// Prefer conforming the boundary view to `Equatable` *directly* unless you
/// specifically need this distinct boundary node — a plain `struct …: View,
/// Equatable` already participates in the gate with no wrapper, and avoids the
/// extra node and the `ForEach`/conditional identity shift noted below.
///
/// Two ways to opt in, with different safety models:
///
/// - **Conform a view to `Equatable` directly.** Its *own* body's reads gate
///   reuse: if it reads `@State`/`@Observable` it is never memo-reused, and if it
///   reads focus/press state it is excluded too. (`@Environment` reads of
///   snapshot-covered keys are fine — the gate verifies the environment is
///   unchanged independently.) This is the safer form.
/// - **Wrap a subtree in ``EquatableView`` (`.equatable()`).** The wrapper
///   forwards its `content` transparently and reads nothing itself, so the
///   wrapper node is always memo-eligible and its `==` is the *sole* contract:
///   it must capture everything the wrapped subtree's rendering depends on. A
///   wrapped subtree that depends on `@State`/focus the `==` does not reflect
///   will be served stale. Prefer wrapping subtrees that are pure functions of
///   `Content`'s compared fields.
///
/// > Important: `==` is a correctness contract, not a hint. If it ignores a
/// > value the wrapped subtree depends on (the classic captured-closure hazard),
/// > the reused subtree will be stale — exactly as SwiftUI's `EquatableView`
/// > documents.
///
/// Note: unlike SwiftUI's, this wrapper occupies its own graph node (an
/// `"EquatableView"` structural-path segment), so applying `.equatable()` inside
/// a `ForEach`/conditional shifts identity vs. the unwrapped form; conform the
/// boundary view to `Equatable` directly when identity continuity matters.
///
/// Usually applied through ``SwiftUICore/View/equatable()`` rather than
/// constructed directly.
public struct EquatableView<Content: View & Equatable>: PrimitiveView, ResolvableView {
  package var content: Content

  public init(content: Content) {
    self.content = content
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    // Resolve `content` transparently as this node's subtree (the `Group`
    // idiom), so the EquatableView node is the reuse boundary whose committed
    // subtree is the wrapped content. EquatableView is deliberately NOT a
    // `DeclaredChildrenView`: that path splices a child into its parent without
    // a `resolveView` call, which would deny the wrapper its own graph node and
    // the `memoViewValue` capture the memo gate compares against.
    resolveDeclaredChildren(
      content,
      in: context,
      kindName: "EquatableView"
    )
  }
}

// The `Equatable` conformance is isolated to the main actor: `Content` is a
// `View` value, hence main-actor-isolated, so `==` must read `content` on the
// main actor. The memo comparator is `@MainActor`, so it can open and call this
// isolated `==`. (A nonisolated `==` cannot read the non-`Sendable` `content`.)
extension EquatableView: @MainActor Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.content == rhs.content
  }
}

extension View where Self: Equatable {
  /// Wraps this view in an ``EquatableView`` so the renderer reuses its subtree
  /// when the view compares equal to its previous value. See ``EquatableView``
  /// for the read-free boundary requirement and the `==`-is-a-contract caveat.
  public func equatable() -> EquatableView<Self> {
    EquatableView(content: self)
  }
}
