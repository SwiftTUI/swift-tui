@_spi(Testing) import SwiftTUICore

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
    return styleValuesAreEqualForReuse(style, other.style)
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
    // TabBody is the seam the `8ace32a5` regression wedged on, and so the
    // reason `resolveStyleBody` rebases rather than mints a fresh scope.
    resolveStyleBody(
      bindingForwardedDynamicPropertyCaptures(style).makeBody(configuration: configuration),
      styleLabel: style.snapshotLabel,
      in: context
    )
  }
}

// The builtin tab-view styles: stateless, so type identity settles reuse.
extension AutomaticTabViewStyle: ReuseTransparentStyle {}
extension UnderlineTabViewStyle: ReuseTransparentStyle {}
extension LiteralTabsTabViewStyle: ReuseTransparentStyle {}
extension PowerlineTabViewStyle: ReuseTransparentStyle {}

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
