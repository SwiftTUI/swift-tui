@_spi(Testing) import SwiftTUICore

protocol AnyTabViewStyleBox: AnyStyleBox {

  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation

  @MainActor
  func resolveBody(
    configuration: TabViewStyleBodyConfiguration,
    in context: ResolveContext
  ) -> ResolveWork<ResolvedNode>
}

extension ConcreteStyleBox: AnyTabViewStyleBox where S: TabViewStyle {

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
  ) -> ResolveWork<ResolvedNode> {
    // TabBody is the seam the `8ace32a5` regression wedged on, and so the
    // reason `resolveStyleBody` rebases rather than mints a fresh scope.
    resolveBody(
      configuration: configuration, styleLabel: style.snapshotLabel, in: context,
      makeBody: { style, configuration in style.makeBody(configuration: configuration) })
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
