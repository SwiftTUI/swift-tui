public import SwiftTUICore
public import SwiftTUIViews

@_spi(Runners) public struct WindowSceneConfiguration<Content: View> {
  @_spi(Runners) public var identifier: WindowIdentifier
  @_spi(Runners) public var title: String?
  @_spi(Runners) public var rootIdentity: Identity
  @_spi(Runners) public var exitKeyBindings: ExitKeyBindings

  private let makeScopedRootViewClosure: @MainActor () -> ScopedBuilder<Content>

  package init(
    identifier: WindowIdentifier,
    title: String?,
    rootIdentity: Identity,
    exitKeyBindings: ExitKeyBindings = .default,
    makeRootView: @escaping @MainActor () -> ScopedBuilder<Content>
  ) {
    self.identifier = identifier
    self.title = title
    self.rootIdentity = rootIdentity
    self.exitKeyBindings = exitKeyBindings
    makeScopedRootViewClosure = makeRootView
  }

  @_spi(Runners) @MainActor public func makeRootView() -> Content {
    makeScopedRootViewClosure().build()
  }

  @MainActor
  package func makeScopedRootView() -> ScopedBuilder<Content> {
    makeScopedRootViewClosure()
  }
}

package struct WindowHostLayout: SendableLayout {
  package var measurementReuseSignature: String {
    "WindowHostLayout"
  }

  package var placementReuseSignature: String {
    "WindowHostLayout"
  }

  package func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    let fallbackSize = subviews.reduce(into: LayoutSize.zero) { partial, subview in
      let measured = subview.sizeThatFits(proposal)
      partial.width = max(partial.width, measured.width)
      partial.height = max(partial.height, measured.height)
    }

    return LayoutSize(
      width: resolvedDimension(proposal.width, fallback: fallbackSize.width),
      height: resolvedDimension(proposal.height, fallback: fallbackSize.height)
    )
  }

  package func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    let fillProposal = ProposedViewSize(
      width: bounds.size.width,
      height: bounds.size.height
    )

    for subview in subviews {
      subview.place(
        at: bounds.origin,
        anchor: .topLeading,
        proposal: fillProposal
      )
    }
  }

  private func resolvedDimension(
    _ dimension: ProposedDimension,
    fallback: Int
  ) -> Int {
    switch dimension {
    case .finite(let value):
      return max(0, value)
    case .unspecified, .infinity:
      return max(0, fallback)
    }
  }
}

package struct WindowHostView<Content: View>: View {
  package let content: Content

  package init(content: Content) {
    self.content = content
  }

  // The scene's root node is a focus-scope boundary so that every
  // focus region produced underneath this window carries the
  // window's identity on its `scopePath`. This is the invariant
  // `ActionScope` (see `WindowGroup: ActionScope`) relies on.
  package var body: some View {
    WindowHostLayout {
      content
    }
    .clipped()
    .focusScope()
  }
}
