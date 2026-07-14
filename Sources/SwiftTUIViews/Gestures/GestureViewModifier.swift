public import SwiftTUICore

// MARK: - View.gesture(_:including:)

extension View {
  public func gesture<G: Gesture>(
    _ gesture: G,
    including mask: GestureMask = .all
  ) -> some View {
    modifier(
      GestureAttachmentModifier(
        gesture: gesture,
        mask: mask
      )
    )
  }
}

// MARK: - GestureAttachmentModifier

@MainActor
public struct GestureAttachmentModifier<G: Gesture>: PrimitiveViewModifier {
  let gesture: G
  let mask: GestureMask

  package func resolve<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    // A mask without `.subviews` (`.gesture`, `.none`) disables descendant
    // gesture attachments: record this chain node's suppression scope
    // before resolving the content so every subview attachment sees it.
    // Chain levels stacked on this same node share `context.identity` and
    // stay exempt — see `PropagatedRegistries.gestureSuppressionScopes`.
    var contentContext = context
    if !mask.contains(.subviews) {
      contentContext.gestureSuppressionScopes.append(context.identity)
    }
    // Resolve the content first so its identity and region exist.
    var node = content.resolve(in: contentContext)

    // If the mask excludes this gesture, short-circuit.
    guard mask.contains(.gesture) else {
      return [node]
    }

    // An ancestor attachment's mask excluded its subview hierarchy — this
    // attachment never registers (no recognizer, pointer route, or
    // hit-test stamp, so events fall through to the masking ancestor).
    guard !context.gestureSuppressionScopes.contains(where: { $0 != context.identity }) else {
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

    // Key registration and routing on the nearest entity-rerooted
    // descendant: a `.id(_:)` below the chain re-roots the interactive
    // content's identity space, and keying on it keeps an active gesture
    // routed across a conditional-branch re-resolve that re-mints the chain
    // node (the branch is part of the chain's structural identity; the
    // entity is not). `node.identity` stays the record-replacement site key
    // so a per-generation entity below a surviving site cannot accumulate
    // one registration per generation.
    let routeIdentity = gestureRouteIdentity(for: node)

    let buildContext = GestureRecognizerBuildContext(
      attachingIdentity: routeIdentity,
      gestureStateRegistry: context.localGestureStateRegistry,
      requestDeadline: requestDeadline
    )

    // Drop stale `@GestureState` bindings from prior body evaluations
    // before the fresh recognizer registers its own. `.register`
    // appends (one `.updating` node = one binding), and
    // `.gesture(_:)` rebuilds the tree on every resolve — without
    // this clear, the per-identity bindings array grows unboundedly
    // across frames, retaining discarded `GestureStateBox` instances.
    if !gestureRegistry.hasCurrentPassRecognizer(for: routeIdentity) {
      context.localGestureStateRegistry?.clearBindings(for: routeIdentity)
    }

    // The combinator decorators (`onEnded`/`onChanged`/`map`/`updating`)
    // self-capture their dispatch scope from the ambient during
    // `_makeRecognizer`; establish the resolve context's stamped
    // registration environment around the build so those captures see the
    // attachment point's environment, not the enclosing body's (F16).
    let intake = HandlerDescriptorIntake(context: context)
    let recognizer = intake.withRegistrationEnvironmentScope {
      gesture._makeRecognizer(context: buildContext)
    }
    gestureRegistry.registerStacked(
      identity: routeIdentity,
      structuralKey: node.identity,
      recognizer: recognizer
    )

    // Forward pointer events through the recognizer. The handler
    // closure looks up the *current* recognizer from
    // `LocalGestureRegistry` at dispatch time rather than capturing
    // the one built above by value: `.gesture(_:)` rebuilds the tree
    // on every body evaluation, but `register(identity:recognizer:)`
    // preserves an `isActive` recognizer across rebuilds — so the
    // recognizer resolved here on one resolve may end up being kept
    // across the next, and we must route events to whichever wins.
    let routeID = runtimePrimaryRouteID(for: routeIdentity)
    let gestureRegistryRef = gestureRegistry
    let handlerIdentity = routeIdentity
    pointerRegistry.register(routeID: routeID, structuralKey: node.identity) { event in
      guard let current = gestureRegistryRef.recognizer(for: handlerIdentity) else {
        return false
      }
      // One-shot recognizers park in absorbing terminal phases; when the
      // fired action mutates no state, no re-resolve re-authors a fresh
      // recognizer and the parked terminal would swallow every later
      // interaction (F128). A fresh press is unambiguously a new
      // interaction: re-arm terminal recognizers first. `reArm` no-ops
      // while non-terminal, so active interactions are never disturbed.
      if case .down = event.kind {
        current.reArm()
      }
      let disposition = current.handle(event: event)
      return disposition == .handled
    }

    // Stamp semantic metadata: must hit-test; captureOnPress when the
    // gesture needs drag continuation (resolved via static protocol hook).
    let capture = gestureNeedsCapture(gesture)
    var gestureMetadata = SemanticMetadata(
      participatesInPointerHitTesting: true,
      captureOnPress: capture,
      allowsHitTesting: true
    )
    if routeIdentity != node.identity {
      gestureMetadata.explicitRouteIdentity = routeIdentity
    }
    node.semanticMetadata = node.semanticMetadata.merging(gestureMetadata)
    return [node]
  }
}

/// The identity gesture routing keys on: the nearest entity-rerooted
/// descendant reachable through single-child structure, or the node's own
/// identity when none exists. The descent stops at any node that hit-tests
/// or focuses on its own — an outer gesture must not claim an inner
/// control's route space. Shared with the pointer-hover modifier, whose
/// routes survive the same conditional-branch re-mints.
@MainActor
func gestureRouteIdentity(for node: ResolvedNode) -> Identity {
  if node.entityIdentity != nil {
    return node.identity
  }
  var cursor = node
  while cursor.entityIdentity == nil, cursor.children.count == 1 {
    let child = cursor.children[0]
    if child.semanticMetadata.participatesInPointerHitTesting
      || child.semanticMetadata.isFocusable
    {
      return node.identity
    }
    cursor = child
  }
  return cursor.entityIdentity != nil ? cursor.identity : node.identity
}

// MARK: - View.contentShape(_:)

extension View {
  /// Overrides the hit-test region for gesture recognition.
  /// Pass `nil` to use the view's natural bounds.
  public func contentShape(_ rect: CellRect?) -> some View {
    modifier(
      ContentShapeModifier(
        explicitRect: rect
      )
    )
  }

  /// Overrides the hit-test region for gesture recognition with a continuous path.
  public func contentShape(_ path: Path) -> some View {
    modifier(
      ContentShapeModifier(
        explicitPath: path
      )
    )
  }

  /// Names this view's placed frame so gestures can resolve locations in it.
  public func coordinateSpace(name: some Hashable & Sendable) -> some View {
    modifier(
      NamedCoordinateSpaceModifier(
        name: String(describing: name)
      )
    )
  }
}

@MainActor
public struct ContentShapeModifier: PrimitiveViewModifier, Sendable, Equatable {
  let explicitRect: CellRect?
  let explicitPath: Path?

  init(
    explicitRect: CellRect?
  ) {
    self.explicitRect = explicitRect
    explicitPath = nil
  }

  init(
    explicitPath: Path
  ) {
    explicitRect = nil
    self.explicitPath = explicitPath
  }

  package func resolve<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    guard explicitRect != nil || explicitPath != nil else { return [node] }
    node.semanticMetadata = node.semanticMetadata.merging(
      SemanticMetadata(
        participatesInPointerHitTesting: true,
        explicitInteractionRect: explicitRect,
        explicitInteractionPath: explicitPath
      )
    )
    return [node]
  }
}

@MainActor
public struct NamedCoordinateSpaceModifier: PrimitiveViewModifier, Sendable, Equatable {
  let name: String

  package func resolve<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.semanticMetadata = node.semanticMetadata.merging(
      SemanticMetadata(namedCoordinateSpaceName: name)
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
    maximumDistance: Double = 0,
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
