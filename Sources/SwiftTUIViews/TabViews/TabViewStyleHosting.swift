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
    // Node-backed with the enclosing control's authoring scope rebased onto
    // the style-body node — see ConcreteAnyButtonStyleBox.resolveBody for the
    // hollow-placeholder / seed-degradation constraint this pins. TabBody is
    // the seam the 8ace32a5 regression wedged on (tab-hosted scroll panes
    // silently losing input-driven @State writes).
    resolveView(
      style.makeBody(configuration: configuration),
      in: context,
      authoringContextOverride: currentAuthoringContext()
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
