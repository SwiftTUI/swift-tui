@_spi(Testing) package import SwiftTUICore

protocol AnyTabViewStyleBox: Sendable {
  func isEqualForReuse(to other: any AnyTabViewStyleBox) -> Bool

  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation

  @MainActor
  func resolveBody(
    configuration: TabViewStyleBodyConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode
}

struct ConcreteAnyTabViewStyleBox<S: TabViewStyle>: AnyTabViewStyleBox {
  let style: S

  func isEqualForReuse(to other: any AnyTabViewStyleBox) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    if style is AutomaticTabViewStyle
      || style is UnderlineTabViewStyle
      || style is LiteralTabsTabViewStyle
      || style is PowerlineTabViewStyle
    {
      return true
    }
    return typedValuesAreEqualForReuse(style, other.style)
  }

  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    style.presentation(for: configuration)
  }

  @MainActor
  func resolveBody(
    configuration: TabViewStyleBodyConfiguration,
    in context: ResolveContext
  ) -> ResolvedNode {
    normalizeResolvedElements(
      resolveViewElements(
        style.makeBody(configuration: configuration),
        in: context
      ),
      in: context
    )
  }
}

package func tabItemIdentity(
  for controlIdentity: Identity,
  index: Int
) -> Identity {
  controlIdentity.child(.indexed("TabItem", index: index))
}

package func tabOverflowTriggerIdentity(
  for controlIdentity: Identity
) -> Identity {
  controlIdentity.child(.named("TabOverflowTrigger"))
}

package func tabOverflowItemIdentity(
  for controlIdentity: Identity,
  index: Int
) -> Identity {
  controlIdentity.child(.indexed("TabOverflowItem", index: index))
}
