public import Core

/// A transparent structural container that groups child views.
public struct Group<Content: View>: View, ResolvableView {
  package var content: Content

  public init(
    @ViewBuilder content: () -> Content
  ) {
    self.content = content()
  }

  package init(children: [AnyView]) where Content == VariadicView<AnyView> {
    content = VariadicView(children)
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    resolveDeclaredChildren(
      content,
      in: context,
      kindName: "Group"
    )
  }
}

/// Generates repeated content from a random-access collection.
public struct ForEach<Data, ID, Content>: View, ResolvableView
where Data: RandomAccessCollection, ID: Hashable, Content: View {
  public var data: Data
  public var id: KeyPath<Data.Element, ID>
  private let content: (Data.Element) -> Content

  public init(
    _ data: Data,
    id: KeyPath<Data.Element, ID>,
    @ViewBuilder content: @escaping (Data.Element) -> Content
  ) {
    self.data = data
    self.id = id
    self.content = content
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var resolved: [ResolvedNode] = []
    for element in data {
      let elementContext = context.replacingIdentity(
        with: context.identity.explicitID(element[keyPath: id])
      )
      let view = elementContext.trackingObservableAccess {
        content(element)
      }
      resolved.append(contentsOf: view.resolveElements(in: elementContext))
    }
    return resolved
  }
}

extension ForEach where Data.Element: Identifiable, ID == Data.Element.ID {
  public init(
    _ data: Data,
    @ViewBuilder content: @escaping (Data.Element) -> Content
  ) {
    self.init(data, id: \.id, content: content)
  }
}

extension ForEach where Data == Range<Int>, ID == Int {
  public init(
    _ data: Range<Int>,
    @ViewBuilder content: @escaping (Int) -> Content
  ) {
    self.init(data, id: \.self, content: content)
  }
}

/// Chooses the first child whose layout fits the proposed space.
public struct ViewThatFits<Content: View>: View, ResolvableView {
  public var axes: Axis.Set
  package var content: Content

  public init(
    in axes: Axis.Set = [.horizontal, .vertical],
    @ViewBuilder content: () -> Content
  ) {
    self.axes = axes
    self.content = content()
  }

  package init(
    in axes: Axis.Set = [.horizontal, .vertical],
    children: [AnyView]
  ) where Content == VariadicView<AnyView> {
    self.axes = axes
    content = VariadicView(children)
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let resolvedChildren = resolveDeclaredChildren(
      content,
      in: context,
      kindName: "ViewThatFits"
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("ViewThatFits"),
        children: resolvedChildren,
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .viewThatFits(axes)
      )
    ]
  }
}

private struct ScrollViewLayout: Layout {
  private struct IndicatorInsets: Equatable {
    var trailing: Int = 0
    var bottom: Int = 0
  }

  var axes: Axis.Set
  var position: ScrollPosition
  var showsIndicators: Bool
  func makeCache(subviews _: LayoutSubviews) {}
  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    guard let subview = subviews.first else {
      return .zero
    }

    let measurement = measuredContent(for: proposal, subview: subview)
    let childSize = measurement.childSize
    let indicatorInsets = measurement.indicatorInsets

    return .init(
      width: viewportDimension(
        childSize.width,
        proposal: proposal.width,
        scrollsAlong: axes.contains(.horizontal),
        reserved: indicatorInsets.trailing
      ),
      height: viewportDimension(
        childSize.height,
        proposal: proposal.height,
        scrollsAlong: axes.contains(.vertical),
        reserved: indicatorInsets.bottom
      )
    )
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    guard let subview = subviews.first else {
      return
    }

    let measurement = measuredContent(for: proposal, subview: subview)
    let childSize = measurement.childSize
    let indicatorInsets = measurement.indicatorInsets
    let viewportBounds = contentViewport(in: bounds, indicatorInsets: indicatorInsets)
    let clampedOffset = contentOffset(
      childSize: childSize,
      viewportSize: viewportBounds.size
    )
    subview.place(
      at: .init(
        x: viewportBounds.origin.x - clampedOffset.x,
        y: viewportBounds.origin.y - clampedOffset.y
      ),
      anchor: .topLeading,
      proposal: .init(width: childSize.width, height: childSize.height)
    )
  }

  private func contentProposal(
    for proposal: ProposedViewSize,
    indicatorInsets: IndicatorInsets
  ) -> ProposedViewSize {
    .init(
      width: axes.contains(.horizontal)
        ? .unspecified
        : reducedDimension(proposal.width, by: indicatorInsets.trailing),
      height: axes.contains(.vertical)
        ? .unspecified
        : reducedDimension(proposal.height, by: indicatorInsets.bottom)
    )
  }

  private func viewportDimension(
    _ child: Int,
    proposal: ProposedDimension,
    scrollsAlong axis: Bool,
    reserved: Int
  ) -> Int {
    switch proposal {
    case .unspecified:
      return child + reserved
    case .finite(let value):
      if axis {
        return min(child + reserved, value)
      }
      return value
    case .infinity:
      return child + reserved
    }
  }

  private func measuredContent(
    for proposal: ProposedViewSize,
    subview: LayoutSubview
  ) -> (childSize: LayoutSize, indicatorInsets: IndicatorInsets) {
    var indicatorInsets = IndicatorInsets()
    var childSize = LayoutSize.zero

    for _ in 0..<3 {
      childSize = subview.sizeThatFits(
        contentProposal(for: proposal, indicatorInsets: indicatorInsets)
      )
      let nextInsets = requiredIndicatorInsets(
        for: childSize,
        proposal: proposal,
        currentInsets: indicatorInsets
      )
      if nextInsets == indicatorInsets {
        return (childSize, indicatorInsets)
      }
      indicatorInsets = nextInsets
    }

    childSize = subview.sizeThatFits(
      contentProposal(for: proposal, indicatorInsets: indicatorInsets)
    )
    return (childSize, indicatorInsets)
  }

  private func requiredIndicatorInsets(
    for childSize: LayoutSize,
    proposal: ProposedViewSize,
    currentInsets: IndicatorInsets
  ) -> IndicatorInsets {
    guard showsIndicators else {
      return .init()
    }

    let contentViewportWidth = viewportValue(
      for: proposal.width,
      fallback: childSize.width,
      reserved: currentInsets.trailing
    )
    let contentViewportHeight = viewportValue(
      for: proposal.height,
      fallback: childSize.height,
      reserved: currentInsets.bottom
    )

    return .init(
      trailing: axes.contains(.vertical) && childSize.height > contentViewportHeight ? 1 : 0,
      bottom: axes.contains(.horizontal) && childSize.width > contentViewportWidth ? 1 : 0
    )
  }

  private func viewportValue(
    for dimension: ProposedDimension,
    fallback: Int,
    reserved: Int
  ) -> Int {
    switch dimension {
    case .unspecified, .infinity:
      return fallback
    case .finite(let value):
      return max(0, value - reserved)
    }
  }

  private func reducedDimension(
    _ dimension: ProposedDimension,
    by amount: Int
  ) -> ProposedDimension {
    switch dimension {
    case .finite(let value):
      return .finite(max(0, value - amount))
    case .unspecified, .infinity:
      return dimension
    }
  }

  private func contentViewport(
    in bounds: LayoutRect,
    indicatorInsets: IndicatorInsets
  ) -> LayoutRect {
    .init(
      origin: bounds.origin,
      size: .init(
        width: max(0, bounds.size.width - indicatorInsets.trailing),
        height: max(0, bounds.size.height - indicatorInsets.bottom)
      )
    )
  }

  private func contentOffset(
    childSize: LayoutSize,
    viewportSize: LayoutSize
  ) -> ScrollPosition {
    ScrollPosition(
      x: clampedOffset(
        requested: position.x,
        content: childSize.width,
        viewport: viewportSize.width,
        isScrollable: axes.contains(.horizontal)
      ),
      y: clampedOffset(
        requested: position.y,
        content: childSize.height,
        viewport: viewportSize.height,
        isScrollable: axes.contains(.vertical)
      )
    )
  }

  private func clampedOffset(
    requested: Int,
    content: Int,
    viewport: Int,
    isScrollable: Bool
  ) -> Int {
    guard isScrollable else {
      return 0
    }
    return min(max(0, requested), max(0, content - viewport))
  }
}

extension ScrollViewLayout: MeasurementLayoutReuseProviding {
  var measurementLayoutReuseSignature: String {
    "ScrollViewLayout:\(axes.rawValue):\(showsIndicators)"
  }
}

/// Presents scrollable content along one or both axes.
public struct ScrollView<Content: View>: View, ResolvableView {
  public var axes: Axis.Set
  public var showsIndicators: Bool
  @State private var internalPosition = ScrollPosition.zero
  private var explicitPosition: Binding<ScrollPosition>?
  private var content: Content
  public var position: Binding<ScrollPosition> {
    explicitPosition ?? $internalPosition
  }
  public init(
    _ axes: Axis.Set = .vertical,
    showsIndicators: Bool = true,
    @ViewBuilder content: () -> Content
  ) {
    self.axes = axes
    self.showsIndicators = showsIndicators
    explicitPosition = nil
    self.content = content()
  }
  public init(
    _ axes: Axis.Set = .vertical,
    showsIndicators: Bool = true,
    position: Binding<ScrollPosition>,
    @ViewBuilder content: () -> Content
  ) {
    self.axes = axes
    self.showsIndicators = showsIndicators
    explicitPosition = position
    self.content = content()
  }
  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let indicatorVisibility = effectiveIndicatorVisibility(
      environment: context.environmentValues.scrollIndicatorVisibility
    )
    let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
    let focusedIdentity = context.environmentValues.focusedIdentity
    let isFocused = focusedIdentity == context.identity
    let showsFocusEffect = context.environmentValues.isFocusEffectEnabled
    var focusedIndicatorAxes: AxisSet = []
    if indicatorVisibility == .visible {
      if focusedIdentity == verticalScrollIndicatorIdentity(for: context.identity) {
        focusedIndicatorAxes.insert(.vertical)
      }
      if focusedIdentity == horizontalScrollIndicatorIdentity(for: context.identity) {
        focusedIndicatorAxes.insert(.horizontal)
      }
    }
    let containerChrome = styleEnvironment.controlChrome(
      isEnabled: context.environmentValues.isEnabled,
      isFocused: isFocused && showsFocusEffect
    )
    let contentChrome = styleEnvironment.rowChrome(
      isEnabled: context.environmentValues.isEnabled,
      isFocused: isFocused && showsFocusEffect,
      isSelected: isFocused && showsFocusEffect
    )
    if context.environmentValues.isEnabled {
      let binding = position
      let dynamicPropertyScope = currentDynamicPropertyScope()
      let registerKeyHandler: (Identity, ScrollIndicatorAxis?) -> Void = { identity, targetAxis in
        context.localKeyHandlerRegistry?.register(identity: identity) { event in
          withDynamicPropertyScope(dynamicPropertyScope) {
            var next = binding.wrappedValue
            guard applyScrollKey(event, to: &next, targetAxis: targetAxis) else {
              return false
            }
            binding.wrappedValue = next
            return true
          }
        }
      }
      registerKeyHandler(context.identity, nil)
      registerKeyHandler(verticalScrollIndicatorIdentity(for: context.identity), .vertical)
      registerKeyHandler(
        horizontalScrollIndicatorIdentity(for: context.identity),
        .horizontal
      )

      let rootRouteID = primaryRouteID(for: context.identity)
      context.localPointerHandlerRegistry?.register(routeID: rootRouteID) { event in
        guard case .scrolled(let deltaX, let deltaY) = event.kind else {
          return false
        }
        return withDynamicPropertyScope(dynamicPropertyScope) {
          var next = binding.wrappedValue
          var changed = false
          if axes.contains(.horizontal), deltaX != 0 {
            next.scrollBy(x: deltaX)
            changed = true
          }
          if axes.contains(.vertical), deltaY != 0 {
            next.scrollBy(y: deltaY)
            changed = true
          }

          guard changed else {
            return false
          }
          binding.wrappedValue = next
          return true
        }
      }

      let registerIndicatorPointerHandler: (ScrollIndicatorAxis, Identity) -> Void = {
        axis, identity in
        let routeID = primaryRouteID(for: identity)
        context.localPointerHandlerRegistry?.register(routeID: routeID) { event in
          switch event.kind {
          case .down(.primary), .dragged(.primary), .up(.primary):
            guard
              let scrollContext = event.scrollContext,
              let metrics = resolvedScrollIndicatorMetrics(
                viewportRect: scrollContext.viewportRect,
                contentBounds: scrollContext.contentBounds,
                axes: axes,
                axis: axis
              )
            else {
              return false
            }
            return withDynamicPropertyScope(dynamicPropertyScope) {
              var next = binding.wrappedValue
              switch axis {
              case .horizontal:
                next.scrollTo(
                  x: metrics.targetOffset(
                    for: event.location,
                    currentOffset: next.x
                  )
                )
              case .vertical:
                next.scrollTo(
                  y: metrics.targetOffset(
                    for: event.location,
                    currentOffset: next.y
                  )
                )
              }

              binding.wrappedValue = next
              return true
            }
          default:
            return false
          }
        }
      }
      registerIndicatorPointerHandler(
        .vertical,
        verticalScrollIndicatorIdentity(for: context.identity)
      )
      registerIndicatorPointerHandler(
        .horizontal,
        horizontalScrollIndicatorIdentity(for: context.identity)
      )
    }
    let child = content.resolve(in: context.child(component: .named("ScrollContent")))
    let indicatorFocusStyle =
      showsFocusEffect && !focusedIndicatorAxes.isEmpty
      ? styleEnvironment.controlChrome(
        isEnabled: context.environmentValues.isEnabled,
        isFocused: true
      ).borderStyle
      : nil

    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("ScrollView"),
        children: [child],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: AnyLayout(
          ScrollViewLayout(
            axes: axes,
            position: position.wrappedValue,
            showsIndicators: indicatorVisibility == .visible
          )
        ).resolvedBehavior,
        drawMetadata: .init(
          backgroundStyle: isFocused && showsFocusEffect ? contentChrome.backgroundStyle : nil,
          scrollIndicatorAxes: indicatorVisibility == .visible ? axes : nil,
          focusedScrollIndicatorAxes: focusedIndicatorAxes.isEmpty ? nil : focusedIndicatorAxes,
          scrollIndicatorForegroundStyle: indicatorFocusStyle,
          opacity: isFocused && showsFocusEffect ? contentChrome.opacity : containerChrome.opacity,
          clipsToBounds: true
        ),
        semanticMetadata: scrollViewMetadata(
          presentationRole: indicatorVisibility == .visible
            ? .scrollViewWithIndicators : .scrollView
        )
      )
    ]
  }

}

/// Arranges children vertically using stack layout rules.
public struct VStack<Content: View>: View, ResolvableView {
  public var alignment: HorizontalAlignment
  public var spacing: Int?
  package var content: Content

  public init(
    alignment: HorizontalAlignment = .center,
    spacing: Int? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.alignment = alignment
    self.spacing = spacing
    self.content = content()
  }

  package init(
    alignment: HorizontalAlignment = .center,
    spacing: Int? = nil,
    children: [AnyView]
  ) where Content == VariadicView<AnyView> {
    self.alignment = alignment
    self.spacing = spacing
    content = VariadicView(children)
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let resolvedChildren = resolveDeclaredChildren(
      content,
      in: context,
      kindName: "VStack"
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("VStack"),
        children: resolvedChildren,
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .stack(
          axis: .vertical,
          spacing: spacing,
          horizontalAlignment: alignment,
          verticalAlignment: .center
        )
      )
    ]
  }
}

/// Arranges children horizontally using stack layout rules.
public struct HStack<Content: View>: View, ResolvableView {
  public var alignment: VerticalAlignment
  public var spacing: Int?
  package var content: Content

  public init(
    alignment: VerticalAlignment = .center,
    spacing: Int? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.alignment = alignment
    self.spacing = spacing
    self.content = content()
  }

  package init(
    alignment: VerticalAlignment = .center,
    spacing: Int? = nil,
    children: [AnyView]
  ) where Content == VariadicView<AnyView> {
    self.alignment = alignment
    self.spacing = spacing
    content = VariadicView(children)
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let resolvedChildren = resolveDeclaredChildren(
      content,
      in: context,
      kindName: "HStack"
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("HStack"),
        children: resolvedChildren,
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .stack(
          axis: .horizontal,
          spacing: spacing,
          horizontalAlignment: .center,
          verticalAlignment: alignment
        )
      )
    ]
  }
}

/// Overlays children along the z axis using alignment rules.
public struct ZStack<Content: View>: View, ResolvableView {
  public var alignment: Alignment
  package var content: Content

  public init(
    alignment: Alignment = .center,
    @ViewBuilder content: () -> Content
  ) {
    self.alignment = alignment
    self.content = content()
  }

  package init(
    alignment: Alignment = .center,
    children: [AnyView]
  ) where Content == VariadicView<AnyView> {
    self.alignment = alignment
    content = VariadicView(children)
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let resolvedChildren = resolveDeclaredChildren(
      content,
      in: context,
      kindName: "ZStack"
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("ZStack"),
        children: resolvedChildren,
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction,
        layoutBehavior: .overlay(alignment: alignment)
      )
    ]
  }
}

@MainActor
func composedView(from children: [AnyView]) -> AnyView {
  switch children.count {
  case 0:
    return AnyView(EmptyView())
  case 1:
    return children[0]
  default:
    return AnyView(Group(children: children))
  }
}
