public import SwiftTUICore

/// Presents scrollable content along one or both axes.
public struct ScrollView<Content: View>: PrimitiveView, ResolvableView {
  public var axes: Axis.Set
  public var showsIndicators: Bool
  @State private var internalPosition = ScrollPosition.zero
  @State private var panAnchor: ScrollPanAnchor?
  private var explicitPosition: Binding<ScrollPosition>?
  private let contentAuthoringScope: CapturedSubviewScope
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
    contentAuthoringScope = makeCapturedSubviewScope()
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
    contentAuthoringScope = makeCapturedSubviewScope()
    self.content = content()
  }
  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let dynamicPropertyScope = dynamicPropertyAuthoringContext(for: context)
    return withAuthoringContext(dynamicPropertyScope) {
      let indicatorVisibility = effectiveIndicatorVisibility(
        environment: context.environmentValues.scrollIndicatorVisibility
      )
      let styleEnvironment = context.environmentValues.styleEnvironmentSnapshot
      // Target-scoped side-field read: this body compares `focusedIdentity`
      // exclusively against the scroll view itself and its two synthetic
      // indicator identities, so a focus move onto anything else (a focused
      // control inside the scrolled content) leaves this output
      // byte-identical. Declaring the targets keeps this container off the
      // affected-reader path of content-descendant focus moves — a sheet's
      // content scroll view must not re-broaden the chrome-only demotion of
      // focusables inside it.
      let focusedIdentity = context.environmentValues.focusedIdentity(
        comparedAgainst: [
          context.identity,
          verticalScrollIndicatorIdentity(for: context.identity),
          horizontalScrollIndicatorIdentity(for: context.identity),
        ]
      )
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
        let intake = HandlerDescriptorIntake(
          context: context,
          fallbackAuthoringScope: interactionAuthoringScope
        )
        intake.registerScrollPosition(
          identity: context.identity,
          currentOffset: {
            let current = binding.wrappedValue
            return ScrollOffset(x: current.x, y: current.y)
          },
          applyOffset: { offset in
            binding.wrappedValue = ScrollPosition(x: offset.x, y: offset.y)
          }
        )
        let scrollCommandRegistry = context.scrollCommandRegistry
        let registerKeyHandler: (Identity, ScrollIndicatorAxis?) -> Void = { identity, targetAxis in
          intake.registerKeyHandler(identity: identity) { event in
            if let edge = scrollBoundaryEdge(for: event, targetAxis: targetAxis) {
              return scrollCommandRegistry?.scrollToEdge(
                edge,
                scopeIdentity: context.identity
              ) ?? false
            }

            let current = binding.wrappedValue
            var next = current
            guard applyScrollKey(event, to: &next, targetAxis: targetAxis) else {
              return false
            }
            // Clamp against the route's live geometry: without this the
            // bound offset grows past the content edge and reverse keys
            // spin before the viewport moves. The wheel path clamps the
            // same way via its pointer scroll context.
            if let scrollCommandRegistry {
              let clamped = scrollCommandRegistry.clampedOffset(
                ScrollOffset(x: next.x, y: next.y),
                scopeIdentity: context.identity
              )
              next = ScrollPosition(x: clamped.x, y: clamped.y)
            }
            guard next != current else {
              return false
            }
            binding.wrappedValue = next
            return true
          }
        }
        registerKeyHandler(context.identity, nil)
        registerKeyHandler(verticalScrollIndicatorIdentity(for: context.identity), .vertical)
        registerKeyHandler(
          horizontalScrollIndicatorIdentity(for: context.identity),
          .horizontal
        )

        let rootRouteID = runtimePrimaryRouteID(for: context.identity)
        intake.registerPointerHandler(
          routeID: rootRouteID,
          handler: makeScrollBodyPointerHandler(
            scrollAxes: axes,
            binding: binding,
            panBinding: $panAnchor
          )
        )

        let registerIndicatorPointerHandler: (ScrollIndicatorAxis, Identity) -> Void = {
          axis, identity in
          let routeID = runtimePrimaryRouteID(for: identity)
          intake.registerPointerHandler(
            routeID: routeID,
            handler: makeIndicatorPointerHandler(
              axis: axis,
              binding: binding
            )
          )
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
      let child = withAuthoringContext(contentAuthoringScope.authoringContext) {
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

  /// Builds the pointer handler for the scroll body's primary route.
  ///
  /// Handles wheel scrolling and direct-manipulation panning (down/dragged/up)
  /// using exactly the state the inline handler captured.
  private func makeScrollBodyPointerHandler(
    scrollAxes: Axis.Set,
    binding: Binding<ScrollPosition>,
    panBinding: Binding<ScrollPanAnchor?>
  ) -> @MainActor (LocalPointerEvent) -> Bool {
    return { event in
      switch event.kind {
      case .scrolled(let deltaX, let deltaY):
        let current = binding.wrappedValue
        var next = current
        var changed = false
        if scrollAxes.contains(.horizontal), deltaX != 0 {
          next.scrollBy(x: deltaX)
          changed = true
        }
        if scrollAxes.contains(.vertical), deltaY != 0 {
          next.scrollBy(y: deltaY)
          changed = true
        }

        guard changed else {
          return false
        }

        if let ctx = event.scrollContext {
          next = clampedScrollOffset(next, in: ctx)
        }

        guard next != current else {
          return false
        }

        binding.wrappedValue = next
        return true

      // Direct-manipulation panning: a touch/pointer drag that starts on the
      // scroll view's own content (not on an inner control) pans the content
      // so it follows the finger. This is the same gesture path iOS and
      // Android already forward as `.dragged`, so panning lights up on every
      // host once the body captures the drag stream. The body only claims
      // the press while content actually overflows, so non-scrollable drags
      // still bubble to a parent scroll view or gesture.
      case .down(.primary):
        guard let ctx = event.scrollContext else {
          return false
        }
        // Only claim a press that landed directly on the scroll body, not
        // one that bubbled up from an inner control. A direct body hit
        // carries the viewport as its `targetRect`; a press on an inner
        // button/slider carries that control's (smaller) rect. Without this
        // guard the body claims the `.down`/`.up` stream of every press over
        // overflowing content — shadowing the inner control's activation, so
        // taps on buttons inside a scroll view never fire. A drag that
        // begins on an inner control is still handed to the scroll view by
        // the run loop's drag-threshold takeover, which re-dispatches a
        // synthetic body `.down` whose `targetRect` is the viewport.
        guard event.targetRect == ctx.viewportRect else {
          return false
        }
        let canPanX = scrollAxes.contains(.horizontal) && ctx.maxScrollX > 0
        let canPanY = scrollAxes.contains(.vertical) && ctx.maxScrollY > 0
        guard canPanX || canPanY else {
          return false
        }
        panBinding.wrappedValue = ScrollPanAnchor(
          startLocation: event.location.location,
          startOffset: binding.wrappedValue
        )
        return true

      case .dragged(.primary):
        guard let anchor = panBinding.wrappedValue else {
          return false
        }
        let current = binding.wrappedValue
        let location = event.location.location
        var next = anchor.startOffset
        // Content follows the finger: dragging down (location.y increases)
        // reveals content above (offset decreases). This is the natural
        // touch convention, opposite the wheel's `.scrolled` mapping. The
        // fractional delta is rounded so sub-cell drags track smoothly.
        if scrollAxes.contains(.horizontal) {
          next.x = Int(
            (Double(anchor.startOffset.x) - (location.x - anchor.startLocation.x)).rounded()
          )
        }
        if scrollAxes.contains(.vertical) {
          next.y = Int(
            (Double(anchor.startOffset.y) - (location.y - anchor.startLocation.y)).rounded()
          )
        }
        if let ctx = event.scrollContext {
          next = clampedScrollOffset(next, in: ctx)
        } else {
          next.x = max(0, next.x)
          next.y = max(0, next.y)
        }
        if next != current {
          binding.wrappedValue = next
        }
        return true

      case .up(.primary):
        guard panBinding.wrappedValue != nil else {
          return false
        }
        panBinding.wrappedValue = nil
        return true

      default:
        return false
      }
    }
  }

  /// Builds the pointer handler for a scroll indicator's primary route.
  ///
  /// Maps press/drag locations on the indicator track to a scroll offset on the
  /// indicator's axis, using exactly the state the inline handler captured.
  private func makeIndicatorPointerHandler(
    axis: ScrollIndicatorAxis,
    binding: Binding<ScrollPosition>
  ) -> @MainActor (LocalPointerEvent) -> Bool {
    return { event in
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
      default:
        return false
      }
    }
  }
}
