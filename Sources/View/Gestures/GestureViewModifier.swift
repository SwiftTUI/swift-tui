public import Core

// MARK: - View.gesture(_:including:)

extension View {
  public func gesture<G: Gesture>(
    _ gesture: G,
    including mask: GestureMask = .all
  ) -> some View {
    _AttachGestureModifier(content: self, gesture: gesture, mask: mask)
  }
}

// MARK: - _AttachGestureModifier

@MainActor
struct _AttachGestureModifier<Content: View, G: Gesture>: View, ResolvableView {
  let content: Content
  let gesture: G
  let mask: GestureMask

  var body: Never { neverBody() }

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    // Resolve the content first so its identity and region exist.
    var node = content.resolve(in: context)

    // If the mask excludes this gesture, short-circuit.
    guard mask.contains(.gesture) else {
      return [node]
    }

    guard let gestureRegistry = context.localGestureRegistry,
      let pointerRegistry = context.localPointerHandlerRegistry
    else {
      return [node]
    }

    // Build the recognizer tree.
    // Forward deadline requests to the frame scheduler when one is present
    // in the resolve context. This closure is populated at runtime by the
    // RunLoop so that gestures like LongPressGesture can schedule timed wakes.
    let scheduleDeadline = context.requestDeadline
    let requestDeadline: @MainActor @Sendable (MonotonicInstant) -> Void = { instant in
      scheduleDeadline?(instant)
    }

    let buildContext = GestureRecognizerBuildContext(
      attachingIdentity: node.identity,
      gestureStateRegistry: context.localGestureStateRegistry,
      requestDeadline: requestDeadline
    )

    // Drop stale `@GestureState` bindings from prior body evaluations
    // before the fresh recognizer registers its own. `.register`
    // appends (one `.updating` node = one binding), and
    // `.gesture(_:)` rebuilds the tree on every resolve — without
    // this clear, the per-identity bindings array grows unboundedly
    // across frames, retaining discarded `GestureStateBox` instances.
    context.localGestureStateRegistry?.clearBindings(for: node.identity)

    let recognizer = gesture._makeRecognizer(context: buildContext)
    gestureRegistry.register(identity: node.identity, recognizer: recognizer)

    // Forward pointer events through the recognizer. The handler
    // closure looks up the *current* recognizer from
    // `LocalGestureRegistry` at dispatch time rather than capturing
    // the one built above by value: `.gesture(_:)` rebuilds the tree
    // on every body evaluation, but `register(identity:recognizer:)`
    // preserves an `isActive` recognizer across rebuilds — so the
    // recognizer resolved here on one resolve may end up being kept
    // across the next, and we must route events to whichever wins.
    let routeID = primaryRouteID(for: node.identity)
    let gestureRegistryRef = gestureRegistry
    let handlerIdentity = node.identity
    pointerRegistry.register(routeID: routeID) { event in
      guard let current = gestureRegistryRef.recognizer(for: handlerIdentity) else {
        return false
      }
      let disposition = current.handle(event: event)
      return disposition == .handled
    }

    // Stamp semantic metadata: must hit-test; captureOnPress when the
    // gesture needs drag continuation (resolved via static protocol hook).
    let capture = gestureNeedsCapture(gesture)
    node.semanticMetadata = node.semanticMetadata.merging(
      SemanticMetadata(
        participatesInPointerHitTesting: true,
        captureOnPress: capture,
        allowsHitTesting: true
      )
    )
    return [node]
  }
}

// MARK: - View.contentShape(_:)

extension View {
  /// Overrides the hit-test region for gesture recognition.
  /// Pass `nil` to use the view's natural bounds.
  public func contentShape(_ rect: Rect?) -> some View {
    _ContentShapeModifier(content: self, explicitRect: rect)
  }
}

@MainActor
struct _ContentShapeModifier<Content: View>: View, ResolvableView {
  let content: Content
  let explicitRect: Rect?

  var body: Never { neverBody() }

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    guard let explicitRect else { return [node] }
    node.semanticMetadata = node.semanticMetadata.merging(
      SemanticMetadata(
        participatesInPointerHitTesting: true,
        explicitInteractionRect: explicitRect
      )
    )
    return [node]
  }
}

// MARK: - View.onTapGesture(count:perform:)

extension View {
  /// Adds a tap gesture recognizer that fires `action` after the
  /// requested number of consecutive taps lands on the view.
  ///
  /// Equivalent to `.gesture(TapGesture(count: count).onEnded { _ in action() })`.
  /// Use TapGesture directly if you need to compose with other
  /// gesture modifiers.
  public func onTapGesture(
    count: Int = 1,
    perform action: @escaping @MainActor () -> Void
  ) -> some View {
    gesture(TapGesture(count: count).onEnded { _ in action() })
  }
}

// MARK: - View.onLongPressGesture(minimumDuration:maximumDistance:perform:)

extension View {
  /// Adds a long-press gesture that fires `action` after the user
  /// holds the view for at least `minimumDuration`.
  ///
  /// Equivalent to
  /// `.gesture(LongPressGesture(minimumDuration: minimumDuration,
  ///                            maximumDistance: maximumDistance)
  ///           .onEnded { _ in action() })`.
  public func onLongPressGesture(
    minimumDuration: Duration = .milliseconds(500),
    maximumDistance: Int = 0,
    perform action: @escaping @MainActor () -> Void
  ) -> some View {
    gesture(
      LongPressGesture(
        minimumDuration: minimumDuration,
        maximumDistance: maximumDistance
      )
      .onEnded { _ in action() }
    )
  }
}

// MARK: - Gesture capture lookup

@MainActor
private func gestureNeedsCapture<G: Gesture>(_ gesture: G) -> Bool {
  G._needsPointerCapture
}
