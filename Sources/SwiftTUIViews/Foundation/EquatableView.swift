import SwiftTUICore

/// A view that compares its wrapped content with its previous value through `==`.
/// If the content is unchanged, the renderer reuses the wrapped subtree without evaluating it again.
///
/// SwiftTUI's memoized-body reuse requires unchanged view inputs, environment,
/// and current dependency certificates throughout the committed subtree.
/// Scalar `@State` reads and tracked observation registrations can be certified.
/// Uncovered reads, including opaque state and focus or press state, prevent reuse.
/// ``EquatableView`` supplies an explicit comparison boundary for content that
/// already conforms to `Equatable`; its `Content: Equatable` bound is required.
///
/// Prefer direct `Equatable` conformance when the view itself is the intended
/// boundary. Use this wrapper to create a distinct boundary around its content.
/// Both forms validate the subtree's recorded dependencies before reuse.
/// Equality must still account for authored inputs, including values captured by
/// closures, that dependency tracking cannot independently validate.
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
  /// for dependency certificate requirements and the equality contract.
  public func equatable() -> EquatableView<Self> {
    EquatableView(content: self)
  }
}
