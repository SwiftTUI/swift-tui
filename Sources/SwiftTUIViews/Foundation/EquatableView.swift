import SwiftTUICore

/// A view that compares its wrapped content with its previous value through `==`.
/// If the content is unchanged, the renderer reuses the wrapped subtree without evaluating it again.
///
/// SwiftTUI's memoized-body reuse reuses a node's committed subtree when its view
/// value is unchanged and it recorded no `@State`/`@Observable` reads. The gate
/// uses only `Equatable`. A view participates only when it conforms to `Equatable`.
/// ``EquatableView`` is the `.equatable()` opt-in.
/// It wraps a `Content` value that already conforms to `Equatable`.
/// The `Content: Equatable` bound is required.
/// It moves the reuse boundary to its own node.
/// Thus, the wrapped subtree can be a boundary when the enclosing view is not `Equatable`.
/// On a match, it reuses the whole subtree, including
/// any `ForEach` or `Button` closures inside, which are descendants of the
/// reused boundary and never compared.
///
/// Prefer direct `Equatable` conformance for the boundary view.
/// Use this distinct boundary node only when you need it.
/// A plain `struct …: View, Equatable` already participates in the gate with no wrapper.
/// It also avoids the extra node and the `ForEach` or conditional identity shift noted below.
///
/// Two methods provide different safety models:
///
/// - **Conform a view to `Equatable` directly.** The body reads of the view control reuse.
///   If it reads `@State` or `@Observable`, the renderer does not use memoized reuse.
///   Focus or press state also prevents reuse. (`@Environment` reads of
///   snapshot-covered keys are safe because the gate makes sure that the environment is
///   unchanged independently.) This is the safer form.
/// - **Wrap a subtree in ``EquatableView`` (`.equatable()`).** The wrapper
///   forwards its `content` transparently and reads nothing itself, so the
///   wrapper node is always memo-eligible. Its `==` is the *sole* contract.
///   It must capture everything the wrapped subtree's rendering depends on. A
///   wrapped subtree that depends on `@State`/focus the `==` does not reflect
///   will be served stale. Prefer wrapping subtrees that are pure functions of
///   `Content`'s compared fields.
///
/// > Important: `==` is a correctness contract, not a hint. If it ignores a
/// > value the wrapped subtree depends on (the classic captured-closure hazard),
/// > the reused subtree will be stale. This behavior matches the documentation for
/// > SwiftUI `EquatableView`.
///
/// Note: Unlike the SwiftUI wrapper, this wrapper occupies its own graph node.
/// This node is an `"EquatableView"` structural-path segment.
/// Thus, `.equatable()` inside a `ForEach` or conditional shifts identity relative to the unwrapped form.
/// Conform the
/// boundary view to `Equatable` directly when identity continuity matters.
///
/// Usually applied through ``View/equatable()`` rather than
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
