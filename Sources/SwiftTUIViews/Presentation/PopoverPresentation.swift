public import SwiftTUICore

// `PopoverAttachmentAnchor` and its unit→cell `attachmentRect` resolution live
// in `PopoverAttachmentAnchor.swift`.

extension View {
  /// Presents a compact popover attached to this view.
  public func popover<PopoverContent: View>(
    isPresented: Binding<Bool>,
    attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
    arrowEdge: Edge? = nil,
    @ViewBuilder content popoverContent: () -> PopoverContent
  ) -> some View {
    modifier(
      BuiltinPopoverPresentationModifier(
        isPresented: isPresented,
        attachmentAnchor: attachmentAnchor,
        arrowEdge: arrowEdge,
        popoverContent: popoverContent(),
        popoverContentAuthoringContext: makeDeferredAuthoringContext(),
        dismissAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }

  /// Presents a compact popover for the current optional item.
  public func popover<Item: Identifiable & Sendable, PopoverContent: View>(
    item: Binding<Item?>,
    attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
    arrowEdge: Edge? = nil,
    @ViewBuilder content popoverContent: @escaping @MainActor (Item) -> PopoverContent
  ) -> some View where Item.ID: Sendable {
    modifier(
      BuiltinItemPopoverPresentationModifier(
        item: item,
        attachmentAnchor: attachmentAnchor,
        arrowEdge: arrowEdge,
        popoverContent: popoverContent,
        popoverContentAuthoringContext: makeDeferredAuthoringContext(),
        dismissAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }

  /// Presents a lightweight tip as a source-attached popover.
  public func popoverTip<Tip: PopoverTip>(
    _ tip: Tip?,
    isPresented: Binding<Bool>? = nil,
    attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
    arrowEdge: Edge? = nil,
    action: @escaping @MainActor @Sendable (PopoverTipAction) -> Void = { _ in }
  ) -> some View {
    modifier(
      PopoverTipModifier(
        tip: tip,
        isPresented: isPresented,
        attachmentAnchor: attachmentAnchor,
        arrowEdge: arrowEdge,
        action: action,
        actionAuthoringContext: makeDeferredAuthoringContext(),
        dismissAuthoringContext: makeDeferredAuthoringContext()
      )
    )
  }
}

package struct BuiltinPopoverPresentationModifier<PopoverContent: View>: PrimitiveViewModifier {
  package var isPresented: Binding<Bool>
  package var attachmentAnchor: PopoverAttachmentAnchor
  package var arrowEdge: Edge?
  package var popoverContent: PopoverContent
  package var popoverContentAuthoringContext: AuthoringContext?
  package var dismissAuthoringContext: AuthoringContext?

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    guard isPresented.wrappedValue else {
      return [node]
    }

    let sourceIdentity = node.identity
    let dismissInvalidator = context.invalidationProxy?.invalidator
    let portalEntryID = presentationAttachment(for: node, token: "popover")
    let itemID = portalEntryID.description
    let item = popoverPresentationItem(
      id: itemID,
      portalEntryID: portalEntryID,
      sourceIdentity: sourceIdentity,
      attachmentAnchor: attachmentAnchor,
      arrowEdge: arrowEdge,
      modalPolicy: .disablesBaseInteraction,
      contentPayloads: withAuthoringContext(popoverContentAuthoringContext) {
        portalDeclaredBuilderChildren(from: popoverContent)
      },
      dismiss: { [isPresented, dismissAuthoringContext, dismissInvalidator, sourceIdentity] in
        withAuthoringContext(dismissAuthoringContext) {
          isPresented.wrappedValue = false
        }
        dismissInvalidator?.requestInvalidation(of: [sourceIdentity])
      }
    )

    mergePopoverDeclaration(
      item,
      sourceIdentity: sourceIdentity,
      into: &node
    )
    return [node]
  }
}

package struct BuiltinItemPopoverPresentationModifier<
  Item: Identifiable & Sendable,
  PopoverContent: View
>: PrimitiveViewModifier where Item.ID: Sendable {
  package var item: Binding<Item?>
  package var attachmentAnchor: PopoverAttachmentAnchor
  package var arrowEdge: Edge?
  package var popoverContent: @MainActor (Item) -> PopoverContent
  package var popoverContentAuthoringContext: AuthoringContext?
  package var dismissAuthoringContext: AuthoringContext?

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    guard let currentItem = item.wrappedValue else {
      return [node]
    }

    let sourceIdentity = node.identity
    let dismissInvalidator = context.invalidationProxy?.invalidator
    let portalEntryID = presentationAttachment(
      for: node,
      token: "popover:\(String(reflecting: currentItem.id))"
    )
    let itemID = portalEntryID.description
    let item = popoverPresentationItem(
      id: itemID,
      portalEntryID: portalEntryID,
      sourceIdentity: sourceIdentity,
      attachmentAnchor: attachmentAnchor,
      arrowEdge: arrowEdge,
      modalPolicy: .disablesBaseInteraction,
      contentPayloads: withAuthoringContext(popoverContentAuthoringContext) {
        portalDeclaredBuilderChildren(from: popoverContent(currentItem))
      },
      dismiss: { [item, dismissAuthoringContext, dismissInvalidator, sourceIdentity] in
        withAuthoringContext(dismissAuthoringContext) {
          item.wrappedValue = nil
        }
        dismissInvalidator?.requestInvalidation(of: [sourceIdentity])
      }
    )

    mergePopoverDeclaration(
      item,
      sourceIdentity: sourceIdentity,
      into: &node
    )
    return [node]
  }
}

package struct PopoverTipModifier<Tip: PopoverTip>: PrimitiveViewModifier {
  @State private var dismissedTipID: String?

  package var tip: Tip?
  package var isPresented: Binding<Bool>?
  package var attachmentAnchor: PopoverAttachmentAnchor
  package var arrowEdge: Edge?
  package var action: @MainActor @Sendable (PopoverTipAction) -> Void
  package var actionAuthoringContext: AuthoringContext?
  package var dismissAuthoringContext: AuthoringContext?

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    guard let tip, tip.isEligible else {
      return [node]
    }

    let tipID = String(reflecting: tip.id)
    if isPresented == nil, dismissedTipID == tipID {
      return [node]
    }
    if let isPresented, !isPresented.wrappedValue {
      return [node]
    }

    let sourceIdentity = node.identity
    let dismissInvalidator = context.invalidationProxy?.invalidator
    let dismissedTipID = $dismissedTipID
    let actionAuthoringContext = actionAuthoringContext
    let portalEntryID = presentationAttachment(
      for: node,
      token: "popoverTip:\(tipID)"
    )
    let itemID = portalEntryID.description
    let dismiss: @MainActor @Sendable () -> Void = {
      [
        isPresented, dismissAuthoringContext, dismissInvalidator, sourceIdentity, dismissedTipID,
        tipID
      ] in
      withAuthoringContext(dismissAuthoringContext) {
        if let isPresented {
          isPresented.wrappedValue = false
        } else {
          dismissedTipID.wrappedValue = tipID
        }
      }
      dismissInvalidator?.requestInvalidation(of: [sourceIdentity])
    }
    let performAction: @MainActor @Sendable (PopoverTipAction) -> Void = { tipAction in
      withAuthoringContext(actionAuthoringContext) {
        action(tipAction)
      }
    }
    let tipActions = tip.actions
    let item = popoverPresentationItem(
      id: itemID,
      portalEntryID: portalEntryID,
      sourceIdentity: sourceIdentity,
      attachmentAnchor: attachmentAnchor,
      arrowEdge: arrowEdge,
      modalPolicy: tipActions.isEmpty ? .nonModal : .disablesBaseInteraction,
      contentPayloads: portalDeclaredBuilderChildren(
        from: PopoverTipContent(
          title: tip.title,
          message: tip.message,
          icon: tip.icon,
          actions: tipActions,
          action: performAction,
          dismiss: dismiss
        )
      ),
      dismiss: dismiss
    )

    mergePopoverDeclaration(
      item,
      sourceIdentity: sourceIdentity,
      into: &node
    )
    return [node]
  }
}

private struct PopoverTipContent: View {
  var title: Text
  var message: Text?
  var icon: Text?
  var actions: [PopoverTipAction]
  var action: @MainActor @Sendable (PopoverTipAction) -> Void
  var dismiss: @MainActor @Sendable () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .center, spacing: 1) {
        if let icon {
          icon
        }
        title
          .bold()
      }
      if let message {
        message
          .foregroundStyle(.muted)
      }
      if !actions.isEmpty {
        HStack(spacing: 1) {
          ForEach(actions) { tipAction in
            Button(tipAction.title) {
              action(tipAction)
              dismiss()
            }
          }
        }
        .padding(.top, 1)
      }
    }
  }
}

@MainActor
package struct HostedPopoverPresentation: View {
  package var item: PopoverPresentationItem

  package init(
    item: PopoverPresentationItem
  ) {
    self.item = item
  }

  package var body: some View {
    GeometryReader { proxy in
      let sourceFrame = proxy.placedFrameTable.frame(for: item.sourceIdentity)
      PopoverPlacementLayout(
        containerSize: proxy.size,
        sourceFrame: sourceFrame,
        attachmentAnchor: item.attachmentAnchor,
        arrowEdge: item.arrowEdge
      ) {
        PromptPresentationSurface(item: item.surfaceItem)
          .fixedSize(horizontal: true, vertical: true)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }
}

private struct PopoverPlacementLayout: Layout {
  var containerSize: CellSize
  var sourceFrame: CellRect?
  var attachmentAnchor: PopoverAttachmentAnchor
  var arrowEdge: Edge?

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews _: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    LayoutSize(
      width: resolvedLength(proposal.width, fallback: containerSize.width),
      height: resolvedLength(proposal.height, fallback: containerSize.height)
    )
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    guard let surface = subviews.first else {
      return
    }

    let surfaceSize = surface.sizeThatFits(.unspecified)
    let container = CellRect(
      origin: bounds.origin,
      size: LayoutSize(
        width: max(0, bounds.size.width),
        height: max(0, bounds.size.height)
      )
    )
    let source = attachmentAnchor.attachmentRect(
      in: sourceFrame ?? fallbackSourceFrame(in: container)
    )
    let origin = popoverOrigin(
      for: surfaceSize,
      source: source,
      in: container,
      preferredEdge: arrowEdge
    )

    surface.place(
      at: origin,
      anchor: .topLeading,
      proposal: .init(width: surfaceSize.width, height: surfaceSize.height)
    )
  }
}

private func popoverPresentationItem(
  id: String,
  portalEntryID: PortalEntryID,
  sourceIdentity: Identity,
  attachmentAnchor: PopoverAttachmentAnchor,
  arrowEdge: Edge?,
  modalPolicy: PortalModalPolicy,
  contentPayloads: [PortalContentPayload],
  dismiss: @escaping @MainActor @Sendable () -> Void
) -> PopoverPresentationItem {
  let surfaceItem = PromptPresentationItem(
    id: id,
    portalEntryID: portalEntryID,
    title: "",
    descriptor: popoverPromptPresentationDescriptor(
      createsFocusScope: modalPolicy == .disablesBaseInteraction
    ),
    actionPayloads: [],
    messagePayloads: [],
    contentPayloads: contentPayloads,
    dismiss: dismiss
  )
  return PopoverPresentationItem(
    id: id,
    portalEntryID: portalEntryID,
    sourceIdentity: sourceIdentity,
    attachmentAnchor: attachmentAnchor,
    arrowEdge: arrowEdge,
    modalPolicy: modalPolicy,
    surfaceItem: surfaceItem
  )
}

private func popoverPromptPresentationDescriptor(
  createsFocusScope: Bool
) -> PromptPresentationDescriptor {
  PromptPresentationDescriptor(
    alignment: .topLeading,
    accessibilityRole: .popover,
    backdropOpacity: 0,
    defaultDismissTitle: "Close",
    headerTone: .accent,
    minWidth: 0,
    scrollMinHeight: 1,
    scrollIdealHeight: 8,
    scrollMaxHeight: 32,
    bodyMode: .contentOnly,
    chrome: .menu,
    borderStyle: StrokeStyle(),
    contentSizing: .intrinsic,
    createsFocusScope: createsFocusScope
  )
}

@MainActor
private func mergePopoverDeclaration(
  _ item: PopoverPresentationItem,
  sourceIdentity: Identity,
  into node: inout ResolvedNode
) {
  node.preferenceValues.merge(
    PresentationCoordinatorDeclarationPreferenceKey.self,
    value: .init(
      declarations: [
        .init(sourceIdentity: sourceIdentity) { registry in
          registry.popover.sync(
            sourceIdentity: sourceIdentity,
            items: [item]
          )
        }
      ]
    )
  )
}

private func popoverOrigin(
  for surfaceSize: LayoutSize,
  source: CellRect,
  in container: CellRect,
  preferredEdge: Edge?
) -> LayoutPoint {
  let candidates = edgeCandidates(preferredEdge)
  for edge in candidates {
    let origin = candidateOrigin(
      edge: edge,
      surfaceSize: surfaceSize,
      source: source,
      in: container
    )
    if contains(surfaceSize, at: origin, in: container) {
      return origin
    }
  }

  return clampedOrigin(
    LayoutPoint(
      x: container.origin.x + max(0, (container.size.width - surfaceSize.width) / 2),
      y: container.origin.y + max(0, (container.size.height - surfaceSize.height) / 2)
    ),
    surfaceSize: surfaceSize,
    in: container
  )
}

private func edgeCandidates(
  _ preferredEdge: Edge?
) -> [Edge] {
  let automatic: [Edge] = [.trailing, .bottom, .leading, .top]
  guard let preferredEdge else {
    return automatic
  }

  var candidates = [preferredEdge, oppositeEdge(preferredEdge)]
  for edge in automatic where !candidates.contains(edge) {
    candidates.append(edge)
  }
  return candidates
}

private func candidateOrigin(
  edge: Edge,
  surfaceSize: LayoutSize,
  source: CellRect,
  in container: CellRect
) -> LayoutPoint {
  let gap = 1
  var origin: LayoutPoint
  switch edge {
  case .top:
    origin = LayoutPoint(
      x: source.origin.x + (source.size.width - surfaceSize.width) / 2,
      y: source.origin.y - surfaceSize.height - gap
    )
    origin.x = clampedCrossAxis(origin.x, length: surfaceSize.width, in: container.horizontalRange)
  case .bottom:
    origin = LayoutPoint(
      x: source.origin.x + (source.size.width - surfaceSize.width) / 2,
      y: source.maxY + gap
    )
    origin.x = clampedCrossAxis(origin.x, length: surfaceSize.width, in: container.horizontalRange)
  case .leading:
    origin = LayoutPoint(
      x: source.origin.x - surfaceSize.width - gap,
      y: source.origin.y + (source.size.height - surfaceSize.height) / 2
    )
    origin.y = clampedCrossAxis(origin.y, length: surfaceSize.height, in: container.verticalRange)
  case .trailing:
    origin = LayoutPoint(
      x: source.maxX + gap,
      y: source.origin.y + (source.size.height - surfaceSize.height) / 2
    )
    origin.y = clampedCrossAxis(origin.y, length: surfaceSize.height, in: container.verticalRange)
  }
  return origin
}

private func contains(
  _ size: LayoutSize,
  at origin: LayoutPoint,
  in container: CellRect
) -> Bool {
  origin.x >= container.origin.x
    && origin.y >= container.origin.y
    && origin.x + size.width <= container.maxX
    && origin.y + size.height <= container.maxY
}

private func clampedOrigin(
  _ origin: LayoutPoint,
  surfaceSize: LayoutSize,
  in container: CellRect
) -> LayoutPoint {
  LayoutPoint(
    x: clampedCrossAxis(origin.x, length: surfaceSize.width, in: container.horizontalRange),
    y: clampedCrossAxis(origin.y, length: surfaceSize.height, in: container.verticalRange)
  )
}

private func clampedCrossAxis(
  _ value: Int,
  length: Int,
  in range: ClosedRange<Int>
) -> Int {
  min(max(value, range.lowerBound), max(range.lowerBound, range.upperBound - max(0, length)))
}

private func fallbackSourceFrame(
  in container: CellRect
) -> CellRect {
  CellRect(
    origin: CellPoint(
      x: container.origin.x + container.size.width / 2,
      y: container.origin.y + container.size.height / 2
    ),
    size: CellSize(width: 1, height: 1)
  )
}

private func oppositeEdge(
  _ edge: Edge
) -> Edge {
  switch edge {
  case .top: .bottom
  case .bottom: .top
  case .leading: .trailing
  case .trailing: .leading
  }
}

private func resolvedLength(
  _ dimension: ProposedDimension,
  fallback: Int
) -> Int {
  switch dimension {
  case .finite(let value):
    max(0, value)
  case .infinity, .unspecified:
    max(0, fallback)
  }
}

extension CellRect {
  fileprivate var horizontalRange: ClosedRange<Int> {
    origin.x...max(origin.x, maxX)
  }

  fileprivate var verticalRange: ClosedRange<Int> {
    origin.y...max(origin.y, maxY)
  }
}
