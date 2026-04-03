package import Core

/// Controls whether a toolbar is rendered above or below the main content.
public enum ToolbarPlacement: Hashable, Sendable {
  case top
  case bottom
}

/// Controls which edge a toolbar entry belongs to within its toolbar row.
public enum ToolbarAlignment: Hashable, Sendable {
  case leading
  case trailing
}

/// Controls the visual treatment used by terminal-native toolbars.
public enum ToolbarStyle: Hashable, Sendable {
  case `default`
}

private enum ToolbarScopePlacementKey: EnvironmentKey {
  static let defaultValue: ToolbarPlacement? = nil
}

extension EnvironmentValues {
  package var toolbarScopePlacement: ToolbarPlacement? {
    get { self[ToolbarScopePlacementKey.self] }
    set { self[ToolbarScopePlacementKey.self] = newValue }
  }
}

// AnyView policy: toolbar builders are authored with heterogeneous child views
// and stored for later root-host rendering.
private struct ToolbarDefinitionRegistration: @unchecked Sendable {
  var attachmentIdentity: Identity
  var placement: ToolbarPlacement
  var style: ToolbarStyle
  var leadingViews: [AnyView]
  var trailingViews: [AnyView]
}

// AnyView policy: contextual toolbar items are authored in-place and hoisted to
// the root toolbar host for later rendering.
private struct ToolbarItemRegistration: @unchecked Sendable {
  var attachmentIdentity: Identity
  var placement: ToolbarPlacement
  var alignment: ToolbarAlignment
  var isEnabled: Bool
  var itemViews: [AnyView]
}

private struct ToolbarPreferenceValue: Sendable {
  var definitions: [ToolbarDefinitionRegistration] = []
  var items: [ToolbarItemRegistration] = []
}

private enum ToolbarPreferenceKey: PreferenceKey {
  static let defaultValue = ToolbarPreferenceValue()

  static func reduce(
    value: inout ToolbarPreferenceValue,
    nextValue: () -> ToolbarPreferenceValue
  ) {
    let next = nextValue()
    value.definitions.append(contentsOf: next.definitions)
    value.items.append(contentsOf: next.items)
  }
}

extension View {
  /// Defines a toolbar for `placement` and establishes the nearest contextual
  /// toolbar scope for descendants in this subtree.
  public func toolbar<Leading: View, Trailing: View>(
    placement: ToolbarPlacement = .bottom,
    @ViewBuilder leading: () -> Leading,
    @ViewBuilder trailing: () -> Trailing
  ) -> some View {
    ToolbarModifier(
      content: self,
      placement: placement,
      leading: leading(),
      trailing: trailing()
    )
  }

  /// Registers a contextual toolbar item within the nearest enclosing toolbar
  /// scope.
  public func toolbarItem<Item: View>(
    alignment: ToolbarAlignment,
    isEnabled: Bool = true,
    @ViewBuilder item: () -> Item
  ) -> some View {
    ToolbarItemModifier(
      content: self,
      alignment: alignment,
      isEnabled: isEnabled,
      item: item()
    )
  }
}

private struct ToolbarModifier<Content: View, Leading: View, Trailing: View>:
  View, ResolvableView
{
  var content: Content
  var placement: ToolbarPlacement
  var leading: Leading
  var trailing: Trailing

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let scopedContext = context.settingEnvironment(
      \.toolbarScopePlacement,
      to: placement
    )
    var node = content.resolve(in: scopedContext)
    node.preferenceValues.merge(
      ToolbarPreferenceKey.self,
      value: .init(
        definitions: [
          .init(
            attachmentIdentity: node.identity,
            placement: placement,
            style: context.environmentValues.toolbarStyle,
            leadingViews: erasedDeclaredBuilderChildren(from: leading),
            trailingViews: erasedDeclaredBuilderChildren(from: trailing)
          )
        ]
      )
    )
    return [node]
  }
}

private struct ToolbarItemModifier<Content: View, Item: View>: View, ResolvableView {
  var content: Content
  var alignment: ToolbarAlignment
  var isEnabled: Bool
  var item: Item

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    guard let placement = context.environmentValues.toolbarScopePlacement else {
      return [node]
    }

    node.preferenceValues.merge(
      ToolbarPreferenceKey.self,
      value: .init(
        items: [
          .init(
            attachmentIdentity: node.identity,
            placement: placement,
            alignment: alignment,
            isEnabled: isEnabled,
            itemViews: erasedDeclaredBuilderChildren(from: item)
          )
        ]
      )
    )
    return [node]
  }
}

private enum ToolbarRenderRole: Sendable {
  case staticItem
  case contextual
}

// AnyView policy: flattened toolbar entries are built from heterogeneous
// toolbar builders before layout-time selection.
private struct ToolbarRenderItem {
  var view: AnyView
  var attachmentIdentity: Identity
  var alignment: ToolbarAlignment
  var role: ToolbarRenderRole
  var isEnabled: Bool
  var overflowRank: Int
}

private struct ToolbarSortKey: Comparable {
  var depth: Int
  var sourceOrder: Int

  static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.depth == rhs.depth {
      return lhs.sourceOrder < rhs.sourceOrder
    }
    return lhs.depth < rhs.depth
  }
}

private struct ToolbarOverflowSortKey: Comparable {
  var category: Int
  var sharedDepth: Int
  var hops: Int
  var sourceOrder: Int

  static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.category != rhs.category {
      return lhs.category < rhs.category
    }
    if lhs.sharedDepth != rhs.sharedDepth {
      return lhs.sharedDepth > rhs.sharedDepth
    }
    if lhs.hops != rhs.hops {
      return lhs.hops < rhs.hops
    }
    return lhs.sourceOrder < rhs.sourceOrder
  }
}

private struct PendingToolbarContextualItem {
  var view: AnyView
  var attachmentIdentity: Identity
  var alignment: ToolbarAlignment
  var isEnabled: Bool
  var sourceOrder: Int
  var overflowKey: ToolbarOverflowSortKey
}

package struct ToolbarHostingRoot<Content: View>: View, ResolvableView {
  package var content: Content

  package init(content: Content) {
    self.content = content
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let baseNode = normalizeResolvedElements(
      resolveViewElements(content, in: context),
      in: context
    )
    let preferences = baseNode.preferenceValues[ToolbarPreferenceKey.self]
    let hasTopToolbar = preferences.definitions.contains(where: { $0.placement == .top })
    let hasBottomToolbar = preferences.definitions.contains(where: { $0.placement == .bottom })

    guard hasTopToolbar || hasBottomToolbar else {
      return [baseNode]
    }

    let hostContext = context.child(component: .named("ToolbarHost"))
    let baseContext = hostContext.child(component: .named("base"))
    let hostedBaseNode = normalizeResolvedElements(
      resolveViewElements(content, in: baseContext),
      in: baseContext
    )
    var children: [ResolvedNode] = []
    children.reserveCapacity(4)

    if hasTopToolbar {
      children.append(
        ToolbarPlacementSurface(
          style: toolbarStyle(
            for: .top,
            in: preferences
          ),
          items: toolbarItems(
            for: .top,
            in: preferences,
            focusedIdentity: context.environmentValues.focusedIdentity
          )
        )
        .resolve(in: hostContext.child(component: .named("top")))
      )
    }

    children.append(hostedBaseNode)

    if hasBottomToolbar {
      children.append(
        Spacer(minLength: 0)
          .resolve(in: hostContext.child(component: .named("spacer")))
      )
    }

    if hasBottomToolbar {
      children.append(
        ToolbarPlacementSurface(
          style: toolbarStyle(
            for: .bottom,
            in: preferences
          ),
          items: toolbarItems(
            for: .bottom,
            in: preferences,
            focusedIdentity: context.environmentValues.focusedIdentity
          )
        )
        .resolve(in: hostContext.child(component: .named("bottom")))
      )
    }

    return [
      ResolvedNode(
        identity: hostContext.identity,
        kind: .view("ToolbarHost"),
        children: children,
        environmentSnapshot: hostContext.environment,
        transactionSnapshot: hostContext.transaction,
        layoutBehavior: .stack(
          axis: .vertical,
          spacing: 0,
          horizontalAlignment: .leading,
          verticalAlignment: .center
        )
      )
    ]
  }

  private func toolbarStyle(
    for placement: ToolbarPlacement,
    in preferences: ToolbarPreferenceValue
  ) -> ToolbarStyle {
    preferences.definitions
      .enumerated()
      .filter { $0.element.placement == placement }
      .sorted { lhs, rhs in
        let lhsKey = ToolbarSortKey(
          depth: lhs.element.attachmentIdentity.components.count,
          sourceOrder: lhs.offset
        )
        let rhsKey = ToolbarSortKey(
          depth: rhs.element.attachmentIdentity.components.count,
          sourceOrder: rhs.offset
        )
        return lhsKey < rhsKey
      }
      .last?
      .element
      .style ?? .default
  }

  private func toolbarItems(
    for placement: ToolbarPlacement,
    in preferences: ToolbarPreferenceValue,
    focusedIdentity: Identity?
  ) -> [ToolbarRenderItem] {
    var renderItems: [ToolbarRenderItem] = []
    renderItems.reserveCapacity(
      preferences.definitions.count * 4 + preferences.items.count * 2
    )

    let definitions = preferences.definitions
      .enumerated()
      .filter { $0.element.placement == placement }
      .sorted { lhs, rhs in
        let lhsKey = ToolbarSortKey(
          depth: lhs.element.attachmentIdentity.components.count,
          sourceOrder: lhs.offset
        )
        let rhsKey = ToolbarSortKey(
          depth: rhs.element.attachmentIdentity.components.count,
          sourceOrder: rhs.offset
        )
        return lhsKey < rhsKey
      }
      .map(\.element)

    guard !definitions.isEmpty else {
      return []
    }

    for definition in definitions {
      for view in definition.leadingViews {
        renderItems.append(
          .init(
            view: view,
            attachmentIdentity: definition.attachmentIdentity,
            alignment: .leading,
            role: .staticItem,
            isEnabled: true,
            overflowRank: .max
          )
        )
      }
    }

    let contextualItems = contextualRenderItems(
      for: placement,
      in: preferences,
      focusedIdentity: focusedIdentity
    )
    renderItems.append(contentsOf: contextualItems.filter { $0.alignment == .leading })

    for definition in definitions {
      for view in definition.trailingViews.reversed() {
        renderItems.append(
          .init(
            view: view,
            attachmentIdentity: definition.attachmentIdentity,
            alignment: .trailing,
            role: .staticItem,
            isEnabled: true,
            overflowRank: .max
          )
        )
      }
    }

    renderItems.append(contentsOf: contextualItems.filter { $0.alignment == .trailing })
    return renderItems
  }

  private func contextualRenderItems(
    for placement: ToolbarPlacement,
    in preferences: ToolbarPreferenceValue,
    focusedIdentity: Identity?
  ) -> [ToolbarRenderItem] {
    let registrations = preferences.items
      .enumerated()
      .filter { $0.element.placement == placement }
      .sorted { lhs, rhs in
        let lhsKey = ToolbarSortKey(
          depth: lhs.element.attachmentIdentity.components.count,
          sourceOrder: lhs.offset
        )
        let rhsKey = ToolbarSortKey(
          depth: rhs.element.attachmentIdentity.components.count,
          sourceOrder: rhs.offset
        )
        return lhsKey < rhsKey
      }
      .map(\.element)

    var pending: [PendingToolbarContextualItem] = []
    pending.reserveCapacity(registrations.count * 2)
    var sourceOrder = 0

    for registration in registrations {
      let views =
        registration.alignment == .leading
        ? registration.itemViews
        : registration.itemViews.reversed()
      for view in views {
        pending.append(
          .init(
            view: view,
            attachmentIdentity: registration.attachmentIdentity,
            alignment: registration.alignment,
            isEnabled: registration.isEnabled,
            sourceOrder: sourceOrder,
            overflowKey: overflowKey(
              for: registration.attachmentIdentity,
              focusedIdentity: focusedIdentity,
              sourceOrder: sourceOrder
            )
          )
        )
        sourceOrder += 1
      }
    }

    let ranked = pending.sorted { lhs, rhs in
      lhs.overflowKey < rhs.overflowKey
    }

    var overflowRanks: [Int: Int] = [:]
    overflowRanks.reserveCapacity(ranked.count)
    for (rank, item) in ranked.enumerated() {
      overflowRanks[item.sourceOrder] = rank
    }

    return pending.map { item in
      ToolbarRenderItem(
        view: item.view,
        attachmentIdentity: item.attachmentIdentity,
        alignment: item.alignment,
        role: .contextual,
        isEnabled: item.isEnabled,
        overflowRank: overflowRanks[item.sourceOrder] ?? .max
      )
    }
  }

  private func overflowKey(
    for itemIdentity: Identity,
    focusedIdentity: Identity?,
    sourceOrder: Int
  ) -> ToolbarOverflowSortKey {
    guard let focusedIdentity else {
      return .init(
        category: 3,
        sharedDepth: 0,
        hops: 0,
        sourceOrder: sourceOrder
      )
    }

    if itemIdentity == focusedIdentity {
      return .init(
        category: 0,
        sharedDepth: itemIdentity.components.count,
        hops: 0,
        sourceOrder: sourceOrder
      )
    }

    if itemIdentity.isAncestor(of: focusedIdentity) {
      return .init(
        category: 1,
        sharedDepth: itemIdentity.components.count,
        hops: focusedIdentity.components.count - itemIdentity.components.count,
        sourceOrder: sourceOrder
      )
    }

    let sharedDepth = sharedIdentityDepth(
      lhs: itemIdentity,
      rhs: focusedIdentity
    )
    let hops =
      (itemIdentity.components.count - sharedDepth)
      + (focusedIdentity.components.count - sharedDepth)

    return .init(
      category: 2,
      sharedDepth: sharedDepth,
      hops: hops,
      sourceOrder: sourceOrder
    )
  }

  private func sharedIdentityDepth(
    lhs: Identity,
    rhs: Identity
  ) -> Int {
    zip(lhs.components, rhs.components)
      .prefix { left, right in
        left == right
      }
      .count
  }
}

private struct ToolbarPlacementSurface: View {
  var style: ToolbarStyle

  // AnyView policy: toolbar surfaces render hoisted heterogeneous toolbar
  // entries after the root host selects a placement.
  var items: [ToolbarRenderItem]

  var body: some View {
    ToolbarRowLayout().callAsFunction {
      ForEach(items.indices, id: \.self) { index in
        items[index].view
          .disabled(!items[index].isEnabled)
          .fixedSize()
          .layoutValue(
            key: ToolbarLayoutMetadataKey.self,
            value: .init(
              alignment: items[index].alignment,
              role: items[index].role,
              overflowRank: items[index].overflowRank
            )
          )
      }
    }
    .frame(
      maxWidth: .infinity,
      minHeight: .finite(1),
      idealHeight: .finite(1),
      maxHeight: .finite(1),
      alignment: .leading
    )
    .background {
      Rectangle().fill(backgroundStyle)
    }
  }

  private var backgroundStyle: AnyShapeStyle {
    switch style {
    case .default:
      AnyShapeStyle(.terminalRow(.neutral))
    }
  }
}

private struct ToolbarLayoutMetadata: Sendable {
  var alignment: ToolbarAlignment
  var role: ToolbarRenderRole
  var overflowRank: Int
}

private struct ToolbarLayoutMetadataKey: LayoutValueKey {
  static let defaultValue = ToolbarLayoutMetadata(
    alignment: .leading,
    role: .staticItem,
    overflowRank: .max
  )
}

private struct ToolbarFrame {
  var index: Int
  var x: Int
  var width: Int
}

private struct ToolbarRowLayout: Layout {
  private let spacing = 1

  func makeCache(subviews _: LayoutSubviews) {}

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    let widths = measuredWidths(for: subviews)
    let naturalWidth = naturalWidth(
      for: subviews,
      widths: widths
    )

    let resolvedWidth: Int
    switch proposal.width {
    case .finite(let value):
      resolvedWidth = value
    case .unspecified, .infinity:
      resolvedWidth = naturalWidth
    }

    return .init(
      width: resolvedWidth,
      height: max(1, measuredHeights(for: subviews).max() ?? 1)
    )
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    guard !subviews.isEmpty else {
      return
    }

    let widths = measuredWidths(for: subviews)
    let selected = selectedFrames(
      for: subviews,
      widths: widths,
      availableWidth: bounds.size.width
    )

    for frame in selected.leading + selected.trailing {
      subviews[frame.index].place(
        at: .init(
          x: bounds.origin.x + frame.x,
          y: bounds.origin.y
        ),
        anchor: .topLeading,
        proposal: .init(
          width: .finite(frame.width),
          height: .finite(bounds.size.height)
        )
      )
    }
  }

  private func measuredWidths(
    for subviews: LayoutSubviews
  ) -> [Int] {
    subviews.map { subview in
      subview.sizeThatFits(
        .init(
          width: .unspecified,
          height: .finite(1)
        )
      ).width
    }
  }

  private func measuredHeights(
    for subviews: LayoutSubviews
  ) -> [Int] {
    subviews.map { subview in
      subview.sizeThatFits(
        .init(
          width: .unspecified,
          height: .finite(1)
        )
      ).height
    }
  }

  private func naturalWidth(
    for subviews: LayoutSubviews,
    widths: [Int]
  ) -> Int {
    let leadingIndices = subviews.indices.filter {
      subviews[$0][ToolbarLayoutMetadataKey.self].alignment == .leading
    }
    let trailingIndices = subviews.indices.filter {
      subviews[$0][ToolbarLayoutMetadataKey.self].alignment == .trailing
    }
    return max(
      clusterWidth(
        for: leadingIndices,
        widths: widths
      )
        + clusterWidth(
          for: trailingIndices,
          widths: widths
        ),
      0
    )
  }

  private func selectedFrames(
    for subviews: LayoutSubviews,
    widths: [Int],
    availableWidth: Int
  ) -> (leading: [ToolbarFrame], trailing: [ToolbarFrame]) {
    let selectedStaticLeading = subviews.indices.filter { index in
      let metadata = subviews[index][ToolbarLayoutMetadataKey.self]
      return metadata.alignment == .leading && metadata.role == .staticItem
    }
    let selectedStaticTrailing = subviews.indices.filter { index in
      let metadata = subviews[index][ToolbarLayoutMetadataKey.self]
      return metadata.alignment == .trailing && metadata.role == .staticItem
    }
    let contextualCandidates = subviews.indices
      .filter { index in
        subviews[index][ToolbarLayoutMetadataKey.self].role == .contextual
      }
      .sorted { lhs, rhs in
        let lhsMetadata = subviews[lhs][ToolbarLayoutMetadataKey.self]
        let rhsMetadata = subviews[rhs][ToolbarLayoutMetadataKey.self]
        if lhsMetadata.overflowRank == rhsMetadata.overflowRank {
          return lhs < rhs
        }
        return lhsMetadata.overflowRank < rhsMetadata.overflowRank
      }

    var selectedContextual: Set<Int> = []
    for candidate in contextualCandidates {
      var tentative = selectedContextual
      tentative.insert(candidate)
      if layoutFits(
        selectedLeading: selectedStaticLeading
          + tentative.filter {
            subviews[$0][ToolbarLayoutMetadataKey.self].alignment == .leading
          }.sorted(),
        selectedTrailing: selectedStaticTrailing
          + tentative.filter {
            subviews[$0][ToolbarLayoutMetadataKey.self].alignment == .trailing
          }.sorted(),
        widths: widths,
        availableWidth: availableWidth
      ) {
        selectedContextual = tentative
      }
    }

    let selectedLeading =
      selectedStaticLeading
      + selectedContextual.filter {
        subviews[$0][ToolbarLayoutMetadataKey.self].alignment == .leading
      }.sorted()
    let selectedTrailing =
      selectedStaticTrailing
      + selectedContextual.filter {
        subviews[$0][ToolbarLayoutMetadataKey.self].alignment == .trailing
      }.sorted()

    return (
      leading: placeLeadingFrames(
        for: selectedLeading,
        widths: widths
      ),
      trailing: placeTrailingFrames(
        for: selectedTrailing,
        widths: widths,
        availableWidth: availableWidth
      )
    )
  }

  private func layoutFits(
    selectedLeading: [Int],
    selectedTrailing: [Int],
    widths: [Int],
    availableWidth: Int
  ) -> Bool {
    let leadingFrames = placeLeadingFrames(
      for: selectedLeading,
      widths: widths
    )
    let trailingFrames = placeTrailingFrames(
      for: selectedTrailing,
      widths: widths,
      availableWidth: availableWidth
    )
    let allFrames = leadingFrames + trailingFrames
    guard
      allFrames.allSatisfy({ frame in
        frame.x >= 0 && frame.x + frame.width <= availableWidth
      })
    else {
      return false
    }
    return !framesOverlap(
      leading: leadingFrames,
      trailing: trailingFrames
    )
  }

  private func placeLeadingFrames(
    for indices: [Int],
    widths: [Int]
  ) -> [ToolbarFrame] {
    var frames: [ToolbarFrame] = []
    frames.reserveCapacity(indices.count)
    var cursor = 0

    for index in indices {
      let width = widths[index]
      frames.append(
        .init(
          index: index,
          x: cursor,
          width: width
        )
      )
      cursor += width + spacing
    }

    return frames
  }

  private func placeTrailingFrames(
    for indices: [Int],
    widths: [Int],
    availableWidth: Int
  ) -> [ToolbarFrame] {
    var frames: [ToolbarFrame] = []
    frames.reserveCapacity(indices.count)
    var cursor = availableWidth

    for index in indices {
      let width = widths[index]
      cursor -= width
      frames.append(
        .init(
          index: index,
          x: cursor,
          width: width
        )
      )
      cursor -= spacing
    }

    return frames
  }

  private func framesOverlap(
    leading: [ToolbarFrame],
    trailing: [ToolbarFrame]
  ) -> Bool {
    for leadingFrame in leading {
      let leadingRange = leadingFrame.x..<(leadingFrame.x + leadingFrame.width)
      for trailingFrame in trailing {
        let trailingRange = trailingFrame.x..<(trailingFrame.x + trailingFrame.width)
        if leadingRange.overlaps(trailingRange) {
          return true
        }
      }
    }
    return false
  }

  private func clusterWidth(
    for indices: [Int],
    widths: [Int]
  ) -> Int {
    guard !indices.isEmpty else {
      return 0
    }
    return indices.reduce(0) { partial, index in
      partial + widths[index]
    } + (indices.count - 1) * spacing
  }
}
