package import Core
package import View

/// Identifies a specific animatable property on a specific view identity.
package struct AnimationKey: Hashable, Sendable {
  package var identity: Identity
  package var property: AnimatableProperty
}

/// Enumeration of properties the animation controller knows how to
/// interpolate.
package enum AnimatableProperty: Hashable, Sendable {
  case opacity
  case foregroundColor
  case backgroundColor
  case borderColor
  case paddingTop
  case paddingLeading
  case paddingBottom
  case paddingTrailing
  case offsetX
  case offsetY
  case frameWidth
  case frameHeight
}

/// A concrete animatable value tagged by type for cheap interpolation
/// dispatch.
package enum AnimatableValue: Sendable, Equatable {
  case double(Double)
  case integer(Int)
  case color(Color)
}

/// Snapshot of animatable properties for one identity after resolve.
package struct AnimatableSnapshot: Equatable, Sendable {
  package var opacity: Double?
  package var foregroundColor: Color?
  package var backgroundColor: Color?
  package var borderColor: Color?
  package var padding: EdgeInsets?
  package var offsetX: Int?
  package var offsetY: Int?
  package var frameWidth: Int?
  package var frameHeight: Int?

  package init() {}

  package static func extract(from node: ResolvedNode) -> AnimatableSnapshot {
    var snapshot = AnimatableSnapshot()

    // Opacity
    if let explicit = node.drawMetadata.baseStyle.explicitOpacity {
      snapshot.opacity = explicit
    }

    // Foreground/background colors
    snapshot.foregroundColor = extractColor(from: node.drawMetadata.baseStyle.foregroundStyle)
    snapshot.backgroundColor = extractColor(from: node.drawMetadata.baseStyle.backgroundStyle)

    // Layout-derived animatables
    switch node.layoutBehavior {
    case .padding(let insets):
      snapshot.padding = insets
    case .offset(let x, let y):
      snapshot.offsetX = x
      snapshot.offsetY = y
    case .frame(let width, let height, _):
      snapshot.frameWidth = width
      snapshot.frameHeight = height
    default:
      break
    }

    return snapshot
  }

  private static func extractColor(from style: AnyShapeStyle?) -> Color? {
    guard let style else { return nil }
    switch style {
    case .color(let color):
      return color
    case .opacity(let inner, _):
      return extractColor(from: inner)
    default:
      return nil
    }
  }
}

/// An animation currently in flight for one (identity, property) key.
package struct ActiveAnimation: Sendable {
  package var from: AnimatableValue
  package var to: AnimatableValue
  package var animationBox: AnimationBox
  package var startTime: MonotonicInstant
}

/// Result of a tick: tells the runtime whether more frames are needed
/// and when the next one should arrive.
package struct AnimationTickResult: Sendable {
  package var hasActiveAnimations: Bool
  package var nextDeadline: MonotonicInstant?
  package var affectedIdentities: Set<Identity>

  package init(
    hasActiveAnimations: Bool = false,
    nextDeadline: MonotonicInstant? = nil,
    affectedIdentities: Set<Identity> = []
  ) {
    self.hasActiveAnimations = hasActiveAnimations
    self.nextDeadline = nextDeadline
    self.affectedIdentities = affectedIdentities
  }
}

/// The stateful per-renderer animation engine.
///
/// Lives for the lifetime of one renderer and holds: the previous frame's
/// animatable snapshot for each identity (used to detect changes), the
/// set of currently active animations keyed by (identity, property), and
/// a mapping from ``AnimationBox`` to the concrete ``Animation`` it came
/// from (so tick sampling can re-enter the View-layer animation logic).
/// Snapshot of a removed view retained for visual-only exit animation.
package struct RemovalEntry: Sendable {
  package var snapshot: ResolvedNode
  package var transition: AnyTransition
  package var animationBox: AnimationBox?
  package var startTime: MonotonicInstant
}

@MainActor
package final class AnimationController {
  private var previousSnapshots: [Identity: AnimatableSnapshot] = [:]
  private var previousResolvedByIdentity: [Identity: ResolvedNode] = [:]
  private var activeAnimations: [AnimationKey: ActiveAnimation] = [:]
  private var registeredAnimations: [AnimationBox: Animation] = [:]
  private var transitionsByIdentity: [Identity: AnyTransition] = [:]
  private var pendingTransitionsByIdentity: [Identity: AnyTransition] = [:]
  private var removingIdentities: [Identity: RemovalEntry] = [:]
  private var previousIdentities: Set<Identity> = []
  package private(set) var lastTickResult: AnimationTickResult = .init()

  /// Target frame interval during active animation (30 FPS).
  private let frameInterval: Duration = .milliseconds(33)
  /// Default duration used for transition animations when no explicit
  /// animation is in the transaction.
  private let defaultTransitionDuration: Duration = .milliseconds(250)

  package init() {}

  /// Called by the View layer at the start of resolve so the controller
  /// can collect up-to-date `.transition()` registrations.  The sink
  /// replaces the old map wholesale — any identity that was in the
  /// previous frame but is not re-registered this frame loses its
  /// transition association.
  package func beginTransitionCollection() {
    pendingTransitionsByIdentity.removeAll(keepingCapacity: true)
  }

  package func finishTransitionCollection() {
    transitionsByIdentity = pendingTransitionsByIdentity
  }

  /// Registers a concrete animation so the controller can re-hydrate it
  /// later from a box carried in a ``TransactionSnapshot``.
  @discardableResult
  package func register(_ animation: Animation) -> AnimationBox {
    let box = animation.animationBox
    registeredAnimations[box] = animation
    return box
  }

  /// Called after resolve, before measure.  Compares the new resolved
  /// tree to the previous snapshot and starts or retargets animations
  /// for changed properties.
  package func processResolvedTree(
    _ node: ResolvedNode,
    transaction: TransactionSnapshot,
    timestamp: MonotonicInstant
  ) {
    // If the incoming transaction carries an animation box, make sure
    // the controller has the concrete Animation registered.  In normal
    // flow ``DefaultRenderer.register(animation:)`` already registered
    // it at withAnimation-time, but guard here in case the caller
    // constructed the transaction directly.
    if case .animate(let box) = transaction.animationRequest,
      registeredAnimations[box] == nil
    {
      // Box without registration — tick sampling will no-op for this
      // batch but the controller will still record snapshots so
      // future changes can animate.
    }

    var newSnapshots: [Identity: AnimatableSnapshot] = [:]
    var newResolvedByIdentity: [Identity: ResolvedNode] = [:]
    processNode(
      node,
      transaction: transaction,
      timestamp: timestamp,
      accumulator: &newSnapshots,
      resolvedAccumulator: &newResolvedByIdentity
    )

    // Detect insertions and removals by diffing identity sets.
    let newIdentities = Set(newSnapshots.keys)
    let insertedIdentities = newIdentities.subtracting(previousIdentities)
    let removedIdentities = previousIdentities.subtracting(newIdentities)

    // Process insertions: kick off willAppear -> identity animations.
    for identity in insertedIdentities {
      guard let transition = transitionsByIdentity[identity] else { continue }
      enqueueInsertionAnimation(
        identity: identity,
        transition: transition,
        snapshot: newSnapshots[identity] ?? .init(),
        transaction: transaction,
        timestamp: timestamp
      )
    }

    // Process removals: retain the frozen snapshot and start the exit
    // animation.  The snapshot becomes a non-semantic overlay purely
    // for draw-time rendering.
    for identity in removedIdentities {
      // Ignore identities that are already mid-removal (don't restart).
      guard removingIdentities[identity] == nil else { continue }
      guard let transition = transitionsByIdentity[identity],
        let snapshot = previousResolvedByIdentity[identity]
      else { continue }
      removingIdentities[identity] = RemovalEntry(
        snapshot: snapshot,
        transition: transition,
        animationBox: (transaction.animationRequest.animationBoxIfAny),
        startTime: timestamp
      )
    }

    // Purge snapshots for identities that no longer exist in the tree.
    previousSnapshots = newSnapshots
    previousResolvedByIdentity = newResolvedByIdentity
    previousIdentities = newIdentities
  }

  private func enqueueInsertionAnimation(
    identity: Identity,
    transition: AnyTransition,
    snapshot: AnimatableSnapshot,
    transaction: TransactionSnapshot,
    timestamp: MonotonicInstant
  ) {
    let modifiers = transition.insertionModifiers()
    guard case .animate(let box) = transaction.animationRequest else {
      // No animation intent — snap to identity immediately.
      return
    }
    // Enqueue an animation for each modifier effect the transition
    // declares.  From values are derived from the modifiers (offset
    // shift, reduced opacity); to values are identity.
    if let startOpacity = modifiers.opacity {
      let target = snapshot.opacity ?? 1.0
      activeAnimations[AnimationKey(identity: identity, property: .opacity)] =
        ActiveAnimation(
          from: .double(startOpacity),
          to: .double(target),
          animationBox: box,
          startTime: timestamp
        )
    }
    if let startOffsetX = modifiers.offsetX {
      let target = snapshot.offsetX ?? 0
      activeAnimations[AnimationKey(identity: identity, property: .offsetX)] =
        ActiveAnimation(
          from: .integer(startOffsetX),
          to: .integer(target),
          animationBox: box,
          startTime: timestamp
        )
    }
    if let startOffsetY = modifiers.offsetY {
      let target = snapshot.offsetY ?? 0
      activeAnimations[AnimationKey(identity: identity, property: .offsetY)] =
        ActiveAnimation(
          from: .integer(startOffsetY),
          to: .integer(target),
          animationBox: box,
          startTime: timestamp
        )
    }
  }

  private func processNode(
    _ node: ResolvedNode,
    transaction: TransactionSnapshot,
    timestamp: MonotonicInstant,
    accumulator: inout [Identity: AnimatableSnapshot],
    resolvedAccumulator: inout [Identity: ResolvedNode]
  ) {
    let snapshot = AnimatableSnapshot.extract(from: node)
    let previous = previousSnapshots[node.identity]

    // Determine the effective animation request: child transactions
    // override parent; otherwise inherit.
    let effectiveRequest = effectiveAnimationRequest(
      node: node,
      parent: transaction
    )

    if let previous {
      diffAndEnqueue(
        identity: node.identity,
        previous: previous,
        current: snapshot,
        request: effectiveRequest,
        timestamp: timestamp
      )
    }
    // First time we see an identity: no animation, just record the snapshot.

    accumulator[node.identity] = snapshot
    // Store a children-less copy so removal overlays don't accidentally
    // retain heavy subtrees.
    var leafCopy = node
    leafCopy.children = []
    resolvedAccumulator[node.identity] = leafCopy

    for child in node.children {
      processNode(
        child,
        transaction: transaction,
        timestamp: timestamp,
        accumulator: &accumulator,
        resolvedAccumulator: &resolvedAccumulator
      )
    }
  }

  private func effectiveAnimationRequest(
    node: ResolvedNode,
    parent: TransactionSnapshot
  ) -> AnimationRequest {
    // Node's transaction snapshot carries the most-specific intent.
    switch node.transactionSnapshot.animationRequest {
    case .inherit:
      return parent.animationRequest
    case .disabled, .animate:
      return node.transactionSnapshot.animationRequest
    }
  }

  private func diffAndEnqueue(
    identity: Identity,
    previous: AnimatableSnapshot,
    current: AnimatableSnapshot,
    request: AnimationRequest,
    timestamp: MonotonicInstant
  ) {
    enqueueIfChanged(
      identity: identity,
      property: .opacity,
      previous: previous.opacity,
      current: current.opacity,
      toValue: AnimatableValue.double,
      fromValue: AnimatableValue.double,
      request: request,
      timestamp: timestamp
    )
    enqueueIfChanged(
      identity: identity,
      property: .foregroundColor,
      previous: previous.foregroundColor,
      current: current.foregroundColor,
      toValue: AnimatableValue.color,
      fromValue: AnimatableValue.color,
      request: request,
      timestamp: timestamp
    )
    enqueueIfChanged(
      identity: identity,
      property: .backgroundColor,
      previous: previous.backgroundColor,
      current: current.backgroundColor,
      toValue: AnimatableValue.color,
      fromValue: AnimatableValue.color,
      request: request,
      timestamp: timestamp
    )
    enqueueIfChanged(
      identity: identity,
      property: .offsetX,
      previous: previous.offsetX,
      current: current.offsetX,
      toValue: AnimatableValue.integer,
      fromValue: AnimatableValue.integer,
      request: request,
      timestamp: timestamp
    )
    enqueueIfChanged(
      identity: identity,
      property: .offsetY,
      previous: previous.offsetY,
      current: current.offsetY,
      toValue: AnimatableValue.integer,
      fromValue: AnimatableValue.integer,
      request: request,
      timestamp: timestamp
    )
    enqueueIfChanged(
      identity: identity,
      property: .frameWidth,
      previous: previous.frameWidth,
      current: current.frameWidth,
      toValue: AnimatableValue.integer,
      fromValue: AnimatableValue.integer,
      request: request,
      timestamp: timestamp
    )
    enqueueIfChanged(
      identity: identity,
      property: .frameHeight,
      previous: previous.frameHeight,
      current: current.frameHeight,
      toValue: AnimatableValue.integer,
      fromValue: AnimatableValue.integer,
      request: request,
      timestamp: timestamp
    )
  }

  private func enqueueIfChanged<T: Equatable>(
    identity: Identity,
    property: AnimatableProperty,
    previous: T?,
    current: T?,
    toValue: (T) -> AnimatableValue,
    fromValue: (T) -> AnimatableValue,
    request: AnimationRequest,
    timestamp: MonotonicInstant
  ) {
    guard previous != current else { return }

    let key = AnimationKey(identity: identity, property: property)

    switch request {
    case .inherit, .disabled:
      // Snap immediately — clear any active animation for this key.
      activeAnimations.removeValue(forKey: key)

    case .animate(let box):
      guard let previousValue = previous, let currentValue = current else {
        // One side is nil — cannot interpolate.  Snap.
        activeAnimations.removeValue(forKey: key)
        return
      }

      // Retarget: if an animation already exists, sample its current
      // value and use it as the new `from`.
      let effectiveFrom: AnimatableValue
      if let existing = activeAnimations[key],
        let sampled = sample(existing, at: timestamp)
      {
        effectiveFrom = sampled
      } else {
        effectiveFrom = fromValue(previousValue)
      }

      activeAnimations[key] = ActiveAnimation(
        from: effectiveFrom,
        to: toValue(currentValue),
        animationBox: box,
        startTime: timestamp
      )
    }
  }

  /// Applies interpolated values to the resolved tree for the given
  /// timestamp.  Returns a tick result describing scheduling needs.
  package func applyInterpolations(
    to tree: inout ResolvedNode,
    at timestamp: MonotonicInstant
  ) -> AnimationTickResult {
    guard !activeAnimations.isEmpty else {
      lastTickResult = AnimationTickResult()
      return lastTickResult
    }

    var keysToRemove: [AnimationKey] = []
    var affectedIdentities: Set<Identity> = []
    var latestDeadline: MonotonicInstant = timestamp

    // Build per-identity interpolated value maps for fast tree walk.
    var interpolated: [Identity: [AnimatableProperty: AnimatableValue]] = [:]

    for (key, animation) in activeAnimations {
      guard let anim = registeredAnimations[animation.animationBox] else {
        keysToRemove.append(key)
        continue
      }
      let elapsed = animation.startTime.duration(to: timestamp)
      guard let progress = anim.evaluate(elapsed: elapsed) else {
        // Animation complete — snap to final value and purge.
        interpolated[key.identity, default: [:]][key.property] = animation.to
        keysToRemove.append(key)
        affectedIdentities.insert(key.identity)
        continue
      }
      let value = interpolate(
        from: animation.from,
        to: animation.to,
        progress: progress
      )
      interpolated[key.identity, default: [:]][key.property] = value
      affectedIdentities.insert(key.identity)
      latestDeadline = timestamp.advanced(by: frameInterval)
    }

    // Remove completed animations.
    for key in keysToRemove {
      activeAnimations.removeValue(forKey: key)
    }

    // Apply interpolated values by walking the tree.
    tree = applyInterpolatedValues(tree: tree, interpolated: interpolated)

    let result = AnimationTickResult(
      hasActiveAnimations: !activeAnimations.isEmpty,
      nextDeadline: activeAnimations.isEmpty ? nil : latestDeadline,
      affectedIdentities: affectedIdentities
    )
    lastTickResult = result
    return result
  }

  private func applyInterpolatedValues(
    tree: ResolvedNode,
    interpolated: [Identity: [AnimatableProperty: AnimatableValue]]
  ) -> ResolvedNode {
    var node = tree
    if let values = interpolated[node.identity] {
      for (property, value) in values {
        applyValue(&node, property: property, value: value)
      }
    }
    node.children = node.children.map { child in
      applyInterpolatedValues(tree: child, interpolated: interpolated)
    }
    return node
  }

  private func applyValue(
    _ node: inout ResolvedNode,
    property: AnimatableProperty,
    value: AnimatableValue
  ) {
    switch (property, value) {
    case (.opacity, .double(let opacity)):
      var drawMetadata = node.drawMetadata
      drawMetadata.baseStyle.explicitOpacity = opacity
      node.drawMetadata = drawMetadata

    case (.foregroundColor, .color(let color)):
      var drawMetadata = node.drawMetadata
      drawMetadata.baseStyle.foregroundStyle = .color(color)
      node.drawMetadata = drawMetadata

    case (.backgroundColor, .color(let color)):
      var drawMetadata = node.drawMetadata
      drawMetadata.baseStyle.backgroundStyle = .color(color)
      node.drawMetadata = drawMetadata

    case (.offsetX, .integer(let x)):
      if case .offset(_, let y) = node.layoutBehavior {
        node.layoutBehavior = .offset(x: x, y: y)
      }

    case (.offsetY, .integer(let y)):
      if case .offset(let x, _) = node.layoutBehavior {
        node.layoutBehavior = .offset(x: x, y: y)
      }

    case (.frameWidth, .integer(let width)):
      if case .frame(_, let height, let alignment) = node.layoutBehavior {
        node.layoutBehavior = .frame(
          width: width, height: height, alignment: alignment
        )
      }

    case (.frameHeight, .integer(let height)):
      if case .frame(let width, _, let alignment) = node.layoutBehavior {
        node.layoutBehavior = .frame(
          width: width, height: height, alignment: alignment
        )
      }

    default:
      break
    }
  }

  private func sample(
    _ animation: ActiveAnimation,
    at timestamp: MonotonicInstant
  ) -> AnimatableValue? {
    guard let anim = registeredAnimations[animation.animationBox] else {
      return nil
    }
    let elapsed = animation.startTime.duration(to: timestamp)
    guard let progress = anim.evaluate(elapsed: elapsed) else {
      return animation.to
    }
    return interpolate(
      from: animation.from,
      to: animation.to,
      progress: progress
    )
  }

  private func interpolate(
    from: AnimatableValue,
    to: AnimatableValue,
    progress: Double
  ) -> AnimatableValue {
    switch (from, to) {
    case (.double(let a), .double(let b)):
      return .double(a + (b - a) * progress)
    case (.integer(let a), .integer(let b)):
      let delta = Double(b - a) * progress
      return .integer(a + Int(delta))
    case (.color(let a), .color(let b)):
      return .color(a.interpolated(to: b, progress: progress, method: .perceptual))
    default:
      return to
    }
  }

  /// Resets all per-identity state.  Used when the renderer is disposed
  /// or the view tree is completely reset.
  package func reset() {
    previousSnapshots.removeAll(keepingCapacity: true)
    activeAnimations.removeAll(keepingCapacity: true)
    registeredAnimations.removeAll(keepingCapacity: true)
    lastTickResult = .init()
  }
}

extension AnimationController: AnimationRegistrationSink {
  package func registerAnimationBox(
    _ box: AnimationBox,
    payload: any Sendable
  ) {
    if let animation = payload as? Animation {
      registeredAnimations[box] = animation
    }
  }
}

extension AnimationController: TransitionRegistrationSink {
  package func registerTransition(
    for identity: Identity,
    transition: any Sendable
  ) {
    if let anyTransition = transition as? AnyTransition {
      pendingTransitionsByIdentity[identity] = anyTransition
    }
  }
}
