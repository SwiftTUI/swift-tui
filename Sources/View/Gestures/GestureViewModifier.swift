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
    // No deadline scheduling is available from the resolve context at this
    // stage — gesture recognizers that require timers (e.g. long-press) will
    // obtain a scheduler when the runtime is live. For now the closure is a
    // no-op; Task 19 will wire a live scheduler reference here.
    let requestDeadline: @MainActor @Sendable (MonotonicInstant) -> Void = { _ in }

    let buildContext = GestureRecognizerBuildContext(
      attachingIdentity: node.identity,
      gestureStateRegistry: context.localGestureStateRegistry,
      requestDeadline: requestDeadline
    )
    let recognizer = gesture._makeRecognizer(context: buildContext)
    gestureRegistry.register(identity: node.identity, recognizer: recognizer)

    // Forward pointer events through the recognizer.
    let routeID = primaryRouteID(for: node.identity)
    pointerRegistry.register(routeID: routeID) { event in
      let disposition = recognizer.handle(event: event)
      return disposition == .handled
    }

    // Stamp semantic metadata: must hit-test; captureOnPress when the
    // gesture needs drag continuation (temporary heuristic — Task 19
    // replaces this with a static protocol hook).
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

// MARK: - Gesture capture heuristic

/// Temporary heuristic — Task 19 replaces this with
/// `G._needsPointerCapture`.
///
/// `TapGesture` and `SpatialTapGesture` (and all their decorator wrappers
/// such as `.onEnded`, `.onChanged`, `.map`, `.updating`) do not require
/// pointer capture. Everything else defaults to `true` (conservative).
private func gestureNeedsCapture<G: Gesture>(_ gesture: G) -> Bool {
  let typeName = String(describing: type(of: gesture))
  if typeName.contains("TapGesture") {
    return false
  }
  if typeName.contains("SpatialTapGesture") {
    return false
  }
  // Conservative default for everything else.
  return true
}
