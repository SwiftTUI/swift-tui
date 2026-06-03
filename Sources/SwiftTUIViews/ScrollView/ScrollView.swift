public import SwiftTUICore

/// Presents scrollable content along one or both axes.
public struct ScrollView<Content: View>: PrimitiveView, ResolvableView {
  public var axes: Axis.Set
  public var showsIndicators: Bool
  @State private var internalPosition = ScrollPosition.zero
  private var explicitPosition: Binding<ScrollPosition>?
  private let contentAuthoringScope: AuthoringContext?
  private let interactionAuthoringScope: AuthoringContext?
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
    interactionAuthoringScope = currentAuthoringContext()
    contentAuthoringScope = makeDeferredAuthoringContext()
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
    interactionAuthoringScope = currentAuthoringContext()
    contentAuthoringScope = makeDeferredAuthoringContext()
    self.content = content()
  }
  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let dynamicPropertyScope = dynamicPropertyAuthoringContext(for: context)
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
        if isFocused {
          // When the scroll view itself is focused, highlight all visible
          // scroll indicators so the user sees which view owns focus.
          focusedIndicatorAxes = axes
        } else {
          if focusedIdentity == verticalScrollIndicatorIdentity(for: context.identity) {
            focusedIndicatorAxes.insert(.vertical)
          }
          if focusedIdentity == horizontalScrollIndicatorIdentity(for: context.identity) {
            focusedIndicatorAxes.insert(.horizontal)
          }
        }
      }
      // The scroll view container itself should not show a focus ring —
      // only the scroll indicator highlights when the scroll view is focused.
      let containerChrome = styleEnvironment.controlChrome(
        isEnabled: context.environmentValues.isEnabled,
        isFocused: false
      )
      if context.environmentValues.isEnabled {
        let binding = position
        let authoringContext =
          currentImperativeAuthoringContextSnapshot()
          ?? ImperativeAuthoringContextSnapshot(interactionAuthoringScope)
        context.localScrollPositionRegistry?.register(
          identity: context.identity,
          currentOffset: {
            let current = binding.wrappedValue
            return ScrollOffset(x: current.x, y: current.y)
          },
          applyOffset: { offset in
            withImperativeAuthoringContext(authoringContext) {
              binding.wrappedValue = ScrollPosition(x: offset.x, y: offset.y)
            }
          }
        )
        let registerKeyHandler: (Identity, ScrollIndicatorAxis?) -> Void = { identity, targetAxis in
          context.localKeyHandlerRegistry?.register(identity: identity) { event in
            withImperativeAuthoringContext(authoringContext) {
              if let edge = scrollBoundaryEdge(for: event, targetAxis: targetAxis) {
                return context.localScrollPositionRegistry?.scrollToEdge(
                  edge,
                  scopeIdentity: context.identity
                ) ?? false
              }

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

        let rootRouteID = runtimePrimaryRouteID(for: context.identity)
        context.localPointerHandlerRegistry?.register(routeID: rootRouteID) { event in
          guard case .scrolled(let deltaX, let deltaY) = event.kind else {
            return false
          }
          return withImperativeAuthoringContext(authoringContext) {
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
          let routeID = runtimePrimaryRouteID(for: identity)
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
              return withImperativeAuthoringContext(authoringContext) {
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
      let child = withAuthoringContext(contentAuthoringScope) {
        content.resolve(in: context.child(component: .named("ScrollContent")))
      }
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
            scrollIndicatorAxes: indicatorVisibility == .visible ? axes : nil,
            focusedScrollIndicatorAxes: focusedIndicatorAxes.isEmpty ? nil : focusedIndicatorAxes,
            scrollIndicatorForegroundStyle: indicatorFocusStyle,
            opacity: containerChrome.opacity,
            clipsToBounds: true
          ),
          semanticMetadata: scrollViewMetadata(
            accessibilityRole: indicatorVisibility == .visible
              ? .scrollViewWithIndicators : .scrollView
          )
        )
      ]
    }
  }
}
