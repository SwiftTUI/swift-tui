@_spi(Testing) package import SwiftTUICore

protocol AnyTabViewStyleBox: Sendable {
  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation

  @MainActor
  func resolveBody(
    configuration: TabViewStyleConfiguration,
    presentation: TabViewStylePresentation,
    controlIdentity: Identity,
    activeContentIndex: Int?,
    activeContent: DeferredViewPayload?,
    in context: ResolveContext
  ) -> ResolvedNode
}

struct ConcreteAnyTabViewStyleBox<S: TabViewStyle>: AnyTabViewStyleBox {
  let style: S

  @MainActor
  func presentation(
    for configuration: TabViewStyleConfiguration
  ) -> TabViewStylePresentation {
    style.presentation(for: configuration)
  }

  @MainActor
  func resolveBody(
    configuration: TabViewStyleConfiguration,
    presentation: TabViewStylePresentation,
    controlIdentity: Identity,
    activeContentIndex: Int?,
    activeContent: DeferredViewPayload?,
    in context: ResolveContext
  ) -> ResolvedNode {
    TabViewStyleBodyHost(
      layoutBehavior: tabViewContainerAnyLayout.resolvedBehavior,
      strip: FrameworkHostedTabStripView(
        style: style,
        controlIdentity: controlIdentity,
        configuration: configuration,
        presentation: presentation
      ),
      activeContentIndex: activeContentIndex,
      activeContent: activeContent,
      overflow: FrameworkHostedTabOverflowSlotView(
        style: style,
        controlIdentity: controlIdentity,
        configuration: configuration,
        presentation: presentation
      )
    ).resolve(in: context)
  }
}

private enum TabViewLayoutSubviewRole: String, Sendable {
  case strip
  case content
  case overflow
}

private enum TabViewLayoutSubviewRoleKey: LayoutValueKey {
  static let defaultValue = TabViewLayoutSubviewRole.content
}

@MainActor
private let tabViewContainerAnyLayout = AnyLayout(TabViewContainerLayout())

private struct TabViewContainerLayout: SendableLayout {
  var measurementReuseSignature: String {
    "TabViewContainerLayout"
  }

  var placementReuseSignature: String {
    "TabViewContainerLayout"
  }

  func makeCache(subviews _: LayoutSubviews) {}

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    let stripSubview = subview(role: .strip, in: subviews)
    let contentSubview = subview(role: .content, in: subviews)

    let stripSize =
      stripSubview?.sizeThatFits(
        .init(width: proposal.width, height: .unspecified)
      ) ?? .zero
    let contentSize =
      contentSubview?.sizeThatFits(
        .init(
          width: proposal.width,
          height: reducedDimension(proposal.height, by: stripSize.height)
        )
      ) ?? .zero

    return .init(
      width: max(stripSize.width, contentSize.width),
      height: stripSize.height + contentSize.height
    )
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    let stripSubview = subview(role: .strip, in: subviews)
    let contentSubview = subview(role: .content, in: subviews)
    let overflowSubview = subview(role: .overflow, in: subviews)

    let stripSize =
      stripSubview?.sizeThatFits(
        .init(width: .finite(bounds.size.width), height: .unspecified)
      ) ?? .zero

    stripSubview?.place(
      at: bounds.origin,
      anchor: .topLeading,
      proposal: .init(
        width: .finite(bounds.size.width),
        height: .finite(stripSize.height)
      )
    )

    contentSubview?.place(
      at: .init(
        x: bounds.origin.x,
        y: bounds.origin.y + stripSize.height
      ),
      anchor: .topLeading,
      proposal: .init(
        width: .finite(bounds.size.width),
        height: .finite(max(0, bounds.size.height - stripSize.height))
      )
    )

    overflowSubview?.place(
      at: bounds.origin,
      anchor: .topLeading,
      proposal: .init(
        width: .finite(bounds.size.width),
        height: .finite(bounds.size.height)
      )
    )
  }

  private func subview(
    role: TabViewLayoutSubviewRole,
    in subviews: LayoutSubviews
  ) -> LayoutSubview? {
    subviews.first { $0[TabViewLayoutSubviewRoleKey.self] == role }
  }

  private func reducedDimension(
    _ dimension: ProposedDimension,
    by amount: Int
  ) -> ProposedDimension {
    switch dimension {
    case .unspecified:
      .unspecified
    case .finite(let value):
      .finite(max(0, value - amount))
    case .infinity:
      .infinity
    }
  }
}

private struct TabViewStyleBodyHost<Strip: View, Overflow: View>: PrimitiveView, ResolvableView {
  let layoutBehavior: LayoutBehavior
  let strip: Strip
  let activeContentIndex: Int?
  let activeContent: DeferredViewPayload?
  let overflow: Overflow

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let stripNode = strip.resolve(
      in: context.child(component: .named("strip-view"))
    )
    let overflowNode = overflow.resolve(
      in: context.child(component: .named("overflow-view"))
    )
    let contentChildren: [ResolvedNode]
    if let activeContent {
      contentChildren = [
        resolveView(
          DeferredPayloadView(payload: activeContent),
          in: context.indexedChild(
            kind: .init(rawValue: "TabContentPayload"),
            index: activeContentIndex ?? 0
          )
        )
      ]
    } else {
      contentChildren = []
    }

    let stripSlot = TabViewLayoutSlotNode(
      kindName: "TabStripSlot",
      role: .strip,
      children: [stripNode]
    ).resolve(
      in: context.child(component: .named("strip-slot"))
    )
    let contentSlot = TabViewLayoutSlotNode(
      kindName: "TabContentSlot",
      role: .content,
      layoutBehavior: .flexibleFrame(
        minWidth: nil,
        idealWidth: nil,
        maxWidth: .infinity,
        minHeight: nil,
        idealHeight: nil,
        maxHeight: .infinity,
        alignment: .topLeading
      ),
      children: contentChildren
    ).resolve(
      in: context.child(component: .named("content-slot"))
    )
    let overflowSlot = TabViewLayoutSlotNode(
      kindName: "TabOverflowSlot",
      role: .overflow,
      children: [overflowNode]
    ).resolve(
      in: context.child(component: .named("overflow-slot"))
    )

    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("TabViewStyleBody"),
        children: [stripSlot, contentSlot, overflowSlot],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: layoutBehavior
      )
    ]
  }
}

private struct TabViewLayoutSlotNode: PrimitiveView, ResolvableView {
  let kindName: String
  let role: TabViewLayoutSubviewRole
  var layoutBehavior: LayoutBehavior = .intrinsic
  var children: [ResolvedNode]

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let layoutMetadata = LayoutMetadata().settingLayoutValue(
      role,
      for: ObjectIdentifier(TabViewLayoutSubviewRoleKey.self),
      debugName: String(reflecting: TabViewLayoutSubviewRoleKey.self),
      debugValue: role.rawValue
    )

    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view(kindName),
        children: children,
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: layoutBehavior,
        layoutMetadata: layoutMetadata
      )
    ]
  }
}

private struct FrameworkHostedTabStripView<S: TabViewStyle>: View {
  let style: S
  let controlIdentity: Identity
  let configuration: TabViewStyleConfiguration
  let presentation: TabViewStylePresentation

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      ForEach(presentation.visibleOptionIndices, id: \.self) { index in
        PointerRouteView(
          identity: tabItemIdentity(
            for: controlIdentity,
            index: index
          ),
          content: style.makeTabBody(
            configuration: configuration,
            item: tabStyleItemConfiguration(
              for: configuration,
              index: index
            )
          )
        )
      }

      if let overflow = presentation.overflowMenu {
        PointerRouteView(
          identity: tabOverflowTriggerIdentity(for: controlIdentity),
          content: style.makeOverflowTriggerBody(
            configuration: configuration,
            trigger: tabOverflowTriggerConfiguration(for: overflow)
          )
        )
      }

      Spacer(minLength: 0)
    }
    .frame(height: presentation.stripHeight, alignment: .leading)
    .background {
      style.makeStripBackground(
        configuration: configuration,
        presentation: presentation
      )
    }
  }
}

private struct FrameworkHostedTabOverflowSlotView<S: TabViewStyle>: View {
  let style: S
  let controlIdentity: Identity
  let configuration: TabViewStyleConfiguration
  let presentation: TabViewStylePresentation

  @ViewBuilder
  var body: some View {
    if let overflow = presentation.overflowMenu, overflow.isExpanded {
      HStack(alignment: .top, spacing: 0) {
        Spacer(minLength: 0)
          .frame(width: overflow.triggerLeadingWidth)
        FrameworkHostedTabOverflowMenuView(
          style: style,
          controlIdentity: controlIdentity,
          configuration: configuration,
          overflow: overflow
        )
        Spacer(minLength: 0)
      }
      .padding(
        .init(
          top: presentation.stripHeight,
          leading: 0,
          bottom: 0,
          trailing: 0
        )
      )
    } else {
      EmptyView()
    }
  }
}

private struct FrameworkHostedTabOverflowMenuView<S: TabViewStyle>: View {
  let style: S
  let controlIdentity: Identity
  let configuration: TabViewStyleConfiguration
  let overflow: TabViewOverflowMenuPresentation

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(overflow.overflowIndices, id: \.self) { index in
        PointerRouteView(
          identity: tabOverflowItemIdentity(
            for: controlIdentity,
            index: index
          ),
          content: style.makeOverflowItemBody(
            configuration: configuration,
            item: tabStyleItemConfiguration(
              for: configuration,
              index: index
            ),
            overflow: overflow
          )
        )
      }
    }
    .padding(overflow.contentPadding)
    .background {
      if let backgroundStyle = overflow.backgroundStyle {
        RoundedRectangle(cornerRadius: overflow.cornerRadius)
          .inset(by: overflow.borderInset)
          .fill(backgroundStyle)
      }
    }
    .overlay {
      if let borderStyle = overflow.borderStyle {
        RoundedRectangle(cornerRadius: overflow.cornerRadius)
          .strokeBorder(borderStyle)
      }
    }
    .fixedSize(horizontal: true, vertical: true)
  }
}

private func tabStyleItemConfiguration(
  for configuration: TabViewStyleConfiguration,
  index: Int
) -> TabViewStyleItemConfiguration {
  let focusActive = configuration.isFocused && configuration.showsFocusEffect
  let label =
    if configuration.options.indices.contains(index) {
      configuration.options[index].label
    } else {
      TabItemLabel("Tab \(index + 1)")
    }

  return .init(
    index: index,
    label: label,
    isSelected: configuration.selectedIndex == index,
    isFocused: focusActive && configuration.focusedIndex == index
  )
}

private func tabOverflowTriggerConfiguration(
  for overflow: TabViewOverflowMenuPresentation
) -> TabViewOverflowTriggerConfiguration {
  .init(
    label: overflow.triggerLabel,
    isSelected: overflow.isTriggerSelected,
    isFocused: overflow.isTriggerFocused,
    isExpanded: overflow.isExpanded,
    overflowIndices: overflow.overflowIndices,
    leadingWidth: overflow.triggerLeadingWidth
  )
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
