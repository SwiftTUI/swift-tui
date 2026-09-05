public import SwiftTUICore

/// Presents scrollable content along one or both axes.
public struct ScrollView<Content: View>: PrimitiveView, ResolvableView {
  public var axes: Axis.Set
  @State private var internalPosition = ScrollCellOffset.zero
  @State private var panAnchor: ScrollPanAnchor?
  private var explicitPosition: Binding<ScrollCellOffset>?
  private let contentAuthoringScope: CapturedSubviewScope
  private let interactionAuthoringScope: AuthoringContext?
  private var content: Content
  public var position: Binding<ScrollCellOffset> {
    explicitPosition ?? $internalPosition
  }
  public init(
    _ axes: Axis.Set = .vertical,
    @ViewBuilder content: () -> Content
  ) {
    self.axes = axes
    explicitPosition = nil
    interactionAuthoringScope = currentAuthoringContext()
    contentAuthoringScope = makeCapturedSubviewScope()
    self.content = content()
  }
  public init(
    _ axes: Axis.Set = .vertical,
    position: Binding<ScrollCellOffset>,
    @ViewBuilder content: () -> Content
  ) {
    self.axes = axes
    explicitPosition = position
    interactionAuthoringScope = currentAuthoringContext()
    contentAuthoringScope = makeCapturedSubviewScope()
    self.content = content()
  }
  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    return withDynamicPropertyUpdateScope(self, for: context) {
      let indicatorAxes = resolvedIndicatorAxes(
        environment: context.environmentValues
      )
      // Direct-manipulation panning is the host's call, not the view's: only a
      // host whose native paradigm is touch declares it (see
      // ``PointerInputCapabilities/supportsScrollPanning``). On terminals and
      // desktop pointer hosts the body leaves the press stream alone, so a
      // click-drag over scroll content stays a click-drag.
      let allowsPanning = context.environmentValues.pointerInputCapabilities
        .supportsScrollPanning
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
      if isFocused {
        // When the scroll view itself is focused, highlight all visible
        // scroll indicators so the user sees which view owns focus.
        focusedIndicatorAxes = indicatorAxes
      } else {
        if indicatorAxes.contains(.vertical),
          focusedIdentity == verticalScrollIndicatorIdentity(for: context.identity)
        {
          focusedIndicatorAxes.insert(.vertical)
        }
        if indicatorAxes.contains(.horizontal),
          focusedIdentity == horizontalScrollIndicatorIdentity(for: context.identity)
        {
          focusedIndicatorAxes.insert(.horizontal)
        }
      }
      let style = context.environmentValues.scrollViewStyle
      let configuration = ScrollViewStyleConfiguration(
        axes: axes, visibleIndicatorAxes: indicatorAxes, focusedIndicatorAxes: focusedIndicatorAxes,
        allowsDirectManipulation: allowsPanning, isEnabled: context.environmentValues.isEnabled,
        showsFocusEffect: showsFocusEffect, styleEnvironment: styleEnvironment)
      let presentation = validatedScrollPresentation(
        style.presentation(for: configuration), configuration: configuration,
        styleLabel: style.description, identity: context.identity)
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
            binding.wrappedValue = ScrollCellOffset(x: offset.x, y: offset.y)
          },
          bindingSourceID: binding.bindingSourceID
        )
        let scrollCommandRegistry = context.scrollCommandRegistry
        let registerScrollKeyHandler: (Identity, ScrollIndicatorAxis?) -> Void = {
          identity, targetAxis in
          intake.registerKeyPressHandler(identity: identity) { keyPress in
            guard keyPress.modifiers.isEmpty else {
              return false
            }
            let event = keyPress.key
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
              next = ScrollCellOffset(x: clamped.x, y: clamped.y)
            }
            guard next != current else {
              return false
            }
            binding.wrappedValue = next
            return true
          }
        }
        registerScrollKeyHandler(context.identity, nil)
        registerScrollKeyHandler(verticalScrollIndicatorIdentity(for: context.identity), .vertical)
        registerScrollKeyHandler(
          horizontalScrollIndicatorIdentity(for: context.identity),
          .horizontal
        )

        let rootRouteID = runtimePrimaryRouteID(for: context.identity)
        // `RouteID` carries the registering node's `ownerNodeID`, so a re-minted
        // owner mints a NEW key instead of replacing the previous one. The
        // structural key is the authored site, which lets
        // `PointerNodeRecord.absorbAdopted` retire the site's previous route
        // instead of accumulating one per generation.
        intake.registerPointerHandler(
          routeID: rootRouteID,
          structuralKey: context.identity,
          handler: makeScrollBodyPointerHandler(
            scrollAxes: axes,
            allowsPanning: allowsPanning,
            binding: binding,
            panBinding: $panAnchor
          )
        )

        let registerIndicatorPointerHandler: (ScrollIndicatorAxis, Identity) -> Void = {
          axis, identity in
          let routeID = runtimePrimaryRouteID(for: identity)
          intake.registerPointerHandler(
            routeID: routeID,
            structuralKey: identity,
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
      var drawMetadata = DrawMetadata(
        backgroundStyle: presentation.backgroundStyle,
        scrollIndicatorAxes: indicatorAxes.isEmpty ? nil : indicatorAxes,
        focusedScrollIndicatorAxes: focusedIndicatorAxes.isEmpty ? nil : focusedIndicatorAxes,
        opacity: presentation.opacity, clipsToBounds: true)
      drawMetadata.scrollIndicatorAppearance = .init(
        contentInsets: presentation.contentInsets,
        verticalGlyph: presentation.verticalIndicatorGlyph,
        horizontalGlyph: presentation.horizontalIndicatorGlyph,
        foregroundStyle: presentation.indicatorStyle,
        focusedForegroundStyle: presentation.focusedIndicatorStyle,
        reservesSpace: presentation.reservesIndicatorSpace)

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
              indicatorAxes: indicatorAxes,
              contentInsets: presentation.contentInsets,
              reservesIndicatorSpace: presentation.reservesIndicatorSpace
            )
          ).resolvedBehavior,
          drawMetadata: drawMetadata,
          semanticMetadata: scrollViewMetadata(
            accessibilityRole: indicatorAxes.isEmpty
              ? .scrollView : .scrollViewWithIndicators,
            capturesPointerOnPress: allowsPanning
          )
        )
      ]
    }
  }

  /// Builds the pointer handler for the scroll body's primary route.
  ///
  /// Always handles wheel scrolling. Handles direct-manipulation panning
  /// (down/dragged/up) only when the host declares
  /// ``PointerInputCapabilities/supportsScrollPanning``; otherwise the press
  /// stream is left entirely to whatever the pointer is actually over.
  private func makeScrollBodyPointerHandler(
    scrollAxes: Axis.Set,
    allowsPanning: Bool,
    binding: Binding<ScrollCellOffset>,
    panBinding: Binding<ScrollPanAnchor?>
  ) -> @MainActor (LocalPointerEvent) -> PointerDispatchOutcome {
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
          return .ignored
        }

        if let ctx = event.scrollContext {
          next = clampedScrollOffset(next, in: ctx)
        }

        guard next != current else {
          return .ignored
        }

        binding.wrappedValue = next
        return .claimed

      // Direct-manipulation panning: a touch drag that starts on the scroll
      // view's own content (not on an inner control) pans the content so it
      // follows the finger. iOS, Android, and coarse-pointer browsers forward
      // exactly this gesture path as `.dragged`, so panning lights up on those
      // hosts once the body captures the drag stream. The body only claims the
      // press while content actually overflows, so non-scrollable drags still
      // bubble to a parent scroll view or gesture.
      //
      // Hosts whose native paradigm is a desktop pointer never reach these
      // branches: `allowsPanning` is false, the press stream is ignored, and
      // the semantic metadata drops `captureOnPress` so the run loop does not
      // capture the body either.
      case .down(.primary):
        guard allowsPanning, let ctx = event.scrollContext else {
          return .ignored
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
          return .ignored
        }
        let canPanX = scrollAxes.contains(.horizontal) && ctx.maxScrollX > 0
        let canPanY = scrollAxes.contains(.vertical) && ctx.maxScrollY > 0
        guard canPanX || canPanY else {
          return .ignored
        }
        panBinding.wrappedValue = ScrollPanAnchor(
          startLocation: event.location.location,
          startOffset: binding.wrappedValue
        )
        return .claimed

      case .dragged(.primary):
        // A capability flip mid-gesture (a browser switching from touch to
        // mouse) must not leave a live anchor panning; the `.up` below still
        // clears it unconditionally so the anchor cannot get stuck.
        guard allowsPanning, let anchor = panBinding.wrappedValue else {
          return .ignored
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
        return .claimed

      case .up(.primary):
        guard panBinding.wrappedValue != nil else {
          return .ignored
        }
        panBinding.wrappedValue = nil
        return .claimed

      default:
        return .ignored
      }
    }
  }

  /// Builds the pointer handler for a scroll indicator's primary route.
  ///
  /// Maps press/drag locations on the indicator track to a scroll offset on the
  /// indicator's axis, using exactly the state the inline handler captured.
  private func makeIndicatorPointerHandler(
    axis: ScrollIndicatorAxis,
    binding: Binding<ScrollCellOffset>
  ) -> @MainActor (LocalPointerEvent) -> PointerDispatchOutcome {
    return { event in
      switch event.kind {
      case .down(.primary), .dragged(.primary), .up(.primary):
        guard let scrollContext = event.scrollContext else { return .ignored }
        // The route publishes the layout's content viewport. The hit region
        // already supplies the indicator track; do not deduct its reservation
        // again when mapping a pointer position to the shared scroll range.
        let viewportLength =
          axis == .vertical
          ? scrollContext.viewportRect.size.height : scrollContext.viewportRect.size.width
        let contentLength =
          axis == .vertical
          ? scrollContext.contentBounds.size.height : scrollContext.contentBounds.size.width
        let metrics = ScrollIndicatorMetrics(
          axis: axis, rect: event.targetRect, maxOffset: max(0, contentLength - viewportLength),
          viewportLength: viewportLength, contentLength: contentLength)
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
          return .claimed
        }

        if case .down(.primary) = event.kind {
          return .claimed
        }

        return .ignored
      default:
        return .ignored
      }
    }
  }
}
