public import Core

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
    let dynamicPropertyScope = makeAuthoringContext(for: context)
    return withAuthoringContext(dynamicPropertyScope) {
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
        let dynamicPropertyScope = currentAuthoringContext()
        let registerKeyHandler: (Identity, ScrollIndicatorAxis?) -> Void = { identity, targetAxis in
          context.localKeyHandlerRegistry?.register(identity: identity) { event in
            withAuthoringContext(dynamicPropertyScope) {
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
          return withAuthoringContext(dynamicPropertyScope) {
            let current = binding.wrappedValue
            var next = current
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

            if let ctx = event.scrollContext {
              let maxX = max(0, ctx.contentBounds.size.width - ctx.viewportRect.size.width)
              let maxY = max(0, ctx.contentBounds.size.height - ctx.viewportRect.size.height)
              next.x = min(max(0, next.x), maxX)
              next.y = min(max(0, next.y), maxY)
            }

            guard next != current else {
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
              return withAuthoringContext(dynamicPropertyScope) {
                let current = binding.wrappedValue
                var next = current
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

                if next != current {
                  binding.wrappedValue = next
                  return true
                }

                if case .down(.primary) = event.kind {
                  return true
                }

                return false
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
            opacity: isFocused && showsFocusEffect
              ? contentChrome.opacity : containerChrome.opacity,
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
      proposal: .init(width: childSize.width, height: childSize.height),
      viewportContext: .init(
        axes: axes,
        viewportRect: viewportBounds,
        contentOffset: .init(x: clampedOffset.x, y: clampedOffset.y)
      )
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
