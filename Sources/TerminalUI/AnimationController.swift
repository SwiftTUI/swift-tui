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

    // Foreground/background colors.  `.foregroundStyle(color)` on a
    // generic view writes to the environment rather than to the node's
    // own draw metadata; leaf views such as `TextFigure` pick it up from
    // the environment at rasterize time.  Prefer the node's local draw
    // metadata (set by text-specific modifiers) and fall back to the
    // environment snapshot so environment-carried colors are still
    // animated.
    snapshot.foregroundColor =
      extractColor(from: node.drawMetadata.baseStyle.foregroundStyle)
      ?? extractColor(from: node.environmentSnapshot.style.foregroundStyle)
    snapshot.backgroundColor =
      extractColor(from: node.drawMetadata.baseStyle.backgroundStyle)
    snapshot.borderColor =
      extractColor(from: node.drawMetadata.borderShapeStyle)

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
    case .flexibleFrame(
      let minWidth, let idealWidth, let maxWidth,
      let minHeight, let idealHeight, let maxHeight,
      _):
      // Pick a representative finite dimension for each axis: prefer
      // max, then ideal, then min.  Most user-authored animation targets
      // either `.frame(maxWidth: X)` (stretching with a cap) or a
      // single fixed `.frame(width: X)` — the latter already takes the
      // `.frame` branch above.  Apply will update the same dimension
      // this extract selected, keeping the other dimensions untouched.
      snapshot.frameWidth = firstFiniteValue(of: [maxWidth, idealWidth, minWidth])
      snapshot.frameHeight = firstFiniteValue(of: [maxHeight, idealHeight, minHeight])
    default:
      break
    }

    return snapshot
  }

  private static func firstFiniteValue(of dimensions: [ProposedDimension?]) -> Int? {
    for dimension in dimensions {
      if case .finite(let value) = dimension {
        return value
      }
    }
    return nil
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
  /// Per-key persistent state threaded into
  /// ``CustomAnimation/animate(value:time:context:)`` on each tick.
  /// Built-in bezier/spring curves ignore this; custom animations can
  /// use it to persist bookkeeping across frames.
  package var customState: AnimationState = .init()
  /// Batch identifier copied from ``TransactionSnapshot/animationBatchID``
  /// at enqueue time.  Used to look up a registered completion closure
  /// when every animation in the batch has drained.
  package var batchID: AnimationBatchID?
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
///
/// The snapshot holds the full subtree as it existed at the moment the
/// node was removed from the live resolved tree, along with the parent
/// identity and child-index needed to re-inject the subtree in roughly
/// the same visual position during the removal animation.
package struct RemovalEntry: Sendable {
  package var snapshot: ResolvedNode
  package var parentIdentity: Identity?
  package var childIndex: Int
  package var transition: AnyTransition
  package var animationBox: AnimationBox?
  package var startTime: MonotonicInstant
  /// Opacity at the moment the removal was snapped.  Normally `1.0`
  /// (the identity phase value), but when the view was still fading
  /// in via an interrupted insertion, the controller samples the
  /// mid-flight opacity and stores it here so the removal continues
  /// from the value currently on screen instead of snapping back
  /// to full opacity.
  package var startOpacity: Double = 1.0
  /// Frozen PlacedNode subtree captured from the previous frame's
  /// placed tree at the moment the removal was snapped.  When
  /// present, the controller injects this subtree into the placed
  /// tree after layout (draw-only overlay) instead of re-injecting
  /// at the resolved level.  When nil (no previous placed tree
  /// cached), the controller falls back to the resolved-level
  /// injection path — see ``applyInterpolations(to:at:)``.
  package var placedSnapshot: PlacedNode? = nil
}

/// An insertion offset animation tracked separately from the
/// ``activeAnimations`` map so it can be applied at placed level
/// rather than via ``applyValue`` on the resolved tree.
///
/// ``applyValue`` for ``AnimatableProperty/offsetX`` only mutates
/// nodes whose `layoutBehavior` is already ``LayoutBehavior/offset``
/// — which is never true for intrinsic-layout leaves like `Text`.
/// Wrapping those leaves in a new `.offset` layout doesn't work
/// either because ``LayoutEngine``'s `.offset` variant requires a
/// child.  Instead the controller tracks the insertion offset
/// delta per identity and translates the matching placed node's
/// bounds after layout runs.
package struct InsertionOffsetAnimation: Sendable {
  package var from: (x: Int, y: Int)
  package var animationBox: AnimationBox
  package var startTime: MonotonicInstant
  package var batchID: AnimationBatchID?
  package var customState: AnimationState = .init()
}

@MainActor
package final class AnimationController {
  private var previousSnapshots: [Identity: AnimatableSnapshot] = [:]
  /// Full tree from the previous frame, retained so removals can capture
  /// their subtrees.
  private var previousTreeRoot: ResolvedNode?
  /// Previous frame's placed tree, captured at the end of each frame
  /// via ``capturePlacedTree(_:)``.  Used by removal detection to
  /// look up the disappearing identity's frozen bounds and inject
  /// the overlay at placed level instead of routing it back through
  /// measure/place.
  private var previousPlacedRoot: PlacedNode?
  /// Active insertion-offset animations keyed by identity.  Applied
  /// at placed level via ``applyPlacedOverlays`` alongside removal
  /// overlays — see ``InsertionOffsetAnimation``.
  private var insertionOffsetAnimations: [Identity: InsertionOffsetAnimation] = [:]
  /// Parent identity, as walked from the previous frame's tree.
  private var previousParentByIdentity: [Identity: Identity] = [:]
  /// Child index within the previous parent's children list.
  private var previousChildIndexByIdentity: [Identity: Int] = [:]
  private var activeAnimations: [AnimationKey: ActiveAnimation] = [:]
  private var registeredAnimations: [AnimationBox: Animation] = [:]
  /// Completion closures registered by ``withAnimation`` overloads.
  /// The controller fires and removes the entry once every animation
  /// (and every removal overlay) tagged with the batch ID has drained.
  private var completionClosures: [AnimationBatchID: @Sendable () -> Void] = [:]
  /// Per-batch active-animation counts.  Incremented on enqueue;
  /// decremented when an animation completes or is superseded.  When
  /// a count hits zero, the matching completion closure fires.
  private var batchRefCounts: [AnimationBatchID: Int] = [:]
  /// Registrations collected during the *current* frame's resolve pass.
  /// Used to look up transitions on INSERTION.
  private var transitionsByIdentity: [Identity: AnyTransition] = [:]
  /// Registrations that were live at the end of the *previous* frame's
  /// resolve pass.  Used to look up transitions on REMOVAL, because the
  /// disappearing view's `.transition()` modifier is not evaluated in
  /// the current frame — its branch is gone.
  private var previousTransitionsByIdentity: [Identity: AnyTransition] = [:]
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

  /// Stores a snapshot of the placed tree at the end of the frame so
  /// the next frame's removal detection can find the disappearing
  /// identity's frozen bounds without re-running layout.
  ///
  /// Called by the render pipeline after ``place`` runs.  When no
  /// removal overlays are pending this is a cheap reference copy.
  package func capturePlacedTree(_ placed: PlacedNode) {
    previousPlacedRoot = placed
  }

  /// Runs the placed-level animation pass after layout: injects any
  /// pending removal overlays and translates any active insertion
  /// offsets.  Called between place and semantics in the render
  /// pipeline.
  ///
  /// Overlays injected this way never flow through measure or place,
  /// so sibling layout is not disturbed when the removed view lived
  /// inside a VStack or other flow container.  They carry the
  /// transient flag, so semantics/focus/lifecycle skip them.
  ///
  /// Insertion offsets translate the bounds of in-tree placed nodes
  /// by an interpolated delta so `.transition(.move(edge:))` and
  /// friends work on intrinsic-layout leaves (where `applyValue`
  /// can't rewrite the layoutBehavior).
  package func applyPlacedOverlays(
    to tree: inout PlacedNode,
    at timestamp: MonotonicInstant
  ) {
    // 1. Inject removal overlays.
    if !removingIdentities.isEmpty {
      var injections: [Identity: [(childIndex: Int, snapshot: PlacedNode)]] = [:]

      for (identity, entry) in removingIdentities {
        guard let placedSnapshot = entry.placedSnapshot,
          let parentId = entry.parentIdentity
        else {
          continue  // No placed capture → resolved-level path handles it.
        }

        let modifiers: TransitionModifiers
        if let box = entry.animationBox, let anim = registeredAnimations[box] {
          let elapsed = entry.startTime.duration(to: timestamp)
          if let progress = anim.evaluate(elapsed: elapsed) {
            modifiers = interpolateRemovalModifiers(
              from: entry.startOpacity,
              to: entry.transition.removalModifiers(),
              progress: progress
            )
          } else {
            continue  // Completion handled in applyInterpolations.
          }
        } else {
          continue
        }

        var clone = placedSnapshot
        applyPlacedOverlayModifiers(modifiers, to: &clone)
        injections[parentId, default: []].append(
          (childIndex: entry.childIndex, snapshot: clone)
        )
      }

      if !injections.isEmpty {
        tree = injectPlacedOverlays(tree: tree, injections: injections)
      }
    }

    // 2. Translate placed nodes for insertion offset animations.
    if !insertionOffsetAnimations.isEmpty {
      var offsetsByIdentity: [Identity: (dx: Int, dy: Int)] = [:]
      var completedInsertions: [Identity] = []

      for (identity, entry) in insertionOffsetAnimations {
        guard let anim = registeredAnimations[entry.animationBox] else {
          completedInsertions.append(identity)
          continue
        }
        let elapsed = entry.startTime.duration(to: timestamp)
        var state = entry.customState
        let evaluated = anim.evaluate(elapsed: elapsed, state: &state)
        insertionOffsetAnimations[identity]?.customState = state

        guard let progress = evaluated else {
          // Animation complete: delta is 0 (fully at final position).
          completedInsertions.append(identity)
          continue
        }
        // Insertion interpolates `from` → 0.
        // At progress p, interpolated = from * (1 - p).
        let dx = Int(Double(entry.from.x) * (1.0 - progress))
        let dy = Int(Double(entry.from.y) * (1.0 - progress))
        offsetsByIdentity[identity] = (dx: dx, dy: dy)
      }

      for identity in completedInsertions {
        if let entry = insertionOffsetAnimations.removeValue(forKey: identity) {
          releaseBatch(entry.batchID)
        }
      }

      if !offsetsByIdentity.isEmpty {
        tree = translatePlacedNodesByIdentity(
          tree: tree,
          offsets: offsetsByIdentity
        )
      }
    }
  }

  /// Walks the placed tree and translates the bounds of any node
  /// whose identity is in `offsets`, along with the bounds of every
  /// descendant (so children move with their parent).
  private func translatePlacedNodesByIdentity(
    tree: PlacedNode,
    offsets: [Identity: (dx: Int, dy: Int)]
  ) -> PlacedNode {
    var node = tree
    if let delta = offsets[node.identity] {
      var translated = node
      translateBounds(&translated, dx: delta.dx, dy: delta.dy)
      return translated
    }
    let walked = node.children.map { child in
      translatePlacedNodesByIdentity(tree: child, offsets: offsets)
    }
    node.children = walked
    return node
  }

  /// Applies transition modifiers to a placed overlay subtree.
  /// Opacity cascades to every descendant's drawMetadata; offsets
  /// translate the root bounds (and, transitively, the descendant
  /// bounds via the same delta).  The overlay subtree carries
  /// isTransient = true on every node so the semantic extractor and
  /// lifecycle coordinator skip it.
  private func applyPlacedOverlayModifiers(
    _ modifiers: TransitionModifiers,
    to node: inout PlacedNode
  ) {
    // Mark the whole subtree transient.
    markTransient(&node)

    // Opacity cascades via drawMetadata.
    if let opacity = modifiers.opacity {
      applyOpacityCascadingPlaced(&node, opacity: opacity)
    }

    // Offset translates the bounds of every node in the subtree by
    // the same delta.  Sub-cell fractional offsets are rounded to
    // integer cells.
    let dx = modifiers.offsetX ?? 0
    let dy = modifiers.offsetY ?? 0
    if dx != 0 || dy != 0 {
      translateBounds(&node, dx: dx, dy: dy)
    }
  }

  private func markTransient(_ node: inout PlacedNode) {
    node.isTransient = true
    var children = node.children
    for i in children.indices {
      markTransient(&children[i])
    }
    node.children = children
  }

  private func applyOpacityCascadingPlaced(
    _ node: inout PlacedNode,
    opacity: Double
  ) {
    var drawMetadata = node.drawMetadata
    let base = drawMetadata.baseStyle.explicitOpacity ?? 1.0
    drawMetadata.baseStyle.explicitOpacity = base * opacity
    node.drawMetadata = drawMetadata

    var children = node.children
    for i in children.indices {
      applyOpacityCascadingPlaced(&children[i], opacity: opacity)
    }
    node.children = children
  }

  private func translateBounds(
    _ node: inout PlacedNode,
    dx: Int,
    dy: Int
  ) {
    let delta = Point(x: dx, y: dy)
    node.bounds = Rect(
      origin: Point(
        x: node.bounds.origin.x + delta.x,
        y: node.bounds.origin.y + delta.y
      ),
      size: node.bounds.size
    )
    node.contentBounds = Rect(
      origin: Point(
        x: node.contentBounds.origin.x + delta.x,
        y: node.contentBounds.origin.y + delta.y
      ),
      size: node.contentBounds.size
    )
    if let clip = node.clipBounds {
      node.clipBounds = Rect(
        origin: Point(
          x: clip.origin.x + delta.x,
          y: clip.origin.y + delta.y
        ),
        size: clip.size
      )
    }
    var children = node.children
    for i in children.indices {
      translateBounds(&children[i], dx: dx, dy: dy)
    }
    node.children = children
  }

  private func injectPlacedOverlays(
    tree: PlacedNode,
    injections: [Identity: [(childIndex: Int, snapshot: PlacedNode)]]
  ) -> PlacedNode {
    var node = tree
    var children = node.children.map { child in
      injectPlacedOverlays(tree: child, injections: injections)
    }
    if let injectionsForNode = injections[node.identity] {
      let sorted = injectionsForNode.sorted { $0.childIndex < $1.childIndex }
      for injection in sorted {
        let insertIndex = min(injection.childIndex, children.count)
        children.insert(injection.snapshot, at: insertIndex)
      }
    }
    node.children = children
    return node
  }

  /// Returns an animation request representative of whatever is
  /// currently in flight, or nil if no animations are active.
  ///
  /// Used by the rendering pipeline to keep tick frames from
  /// accidentally snapping: if an `@Observable` write lands on the
  /// same frame as an animation tick the scheduler would normally
  /// produce a transaction with `.inherit`, which the controller's
  /// diff path treats as "snap immediately".  Injecting the dominant
  /// active request lets value-change diffs inside that resolve
  /// retarget the in-flight animation instead.
  ///
  /// Returns the first active animation's box — all active animations
  /// in a batch share the same box, and cross-batch interleavings
  /// resolve the same way a fresh `withAnimation` would be.
  package func dominantActiveRequest() -> AnimationRequest? {
    guard let first = activeAnimations.values.first else { return nil }
    return .animate(first.animationBox)
  }

  /// Called by the View layer at the start of resolve so the controller
  /// can collect up-to-date `.transition()` registrations.  The sink
  /// replaces the current map wholesale — any identity that was in the
  /// previous frame but is not re-registered this frame loses its
  /// transition association — but the PREVIOUS frame's registrations
  /// are preserved so removal detection can still find transitions for
  /// views whose branches are gone.
  package func beginTransitionCollection() {
    previousTransitionsByIdentity = transitionsByIdentity
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
    var newParentByIdentity: [Identity: Identity] = [:]
    var newChildIndexByIdentity: [Identity: Int] = [:]
    processNode(
      node,
      parentIdentity: nil,
      childIndex: 0,
      transaction: transaction,
      timestamp: timestamp,
      snapshotAccumulator: &newSnapshots,
      parentAccumulator: &newParentByIdentity,
      childIndexAccumulator: &newChildIndexByIdentity
    )

    // Detect insertions and removals by diffing identity sets.  Skip
    // identities that are already mid-removal: they exist in the
    // injected overlay but not in the live tree, so they should not be
    // re-inserted as "new".
    let newIdentities = Set(newSnapshots.keys)
    let liveIdentities = previousIdentities.subtracting(removingIdentities.keys)
    let insertedIdentities = newIdentities.subtracting(previousIdentities)
    let removedIdentities = liveIdentities.subtracting(newIdentities)

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

    // Process removals: look up the full subtree and position from the
    // previous frame so the animation controller can re-inject them as
    // non-semantic overlays each tick until the exit animation
    // completes.
    //
    // The transition is registered against the leaf identity that the
    // `.transition()` modifier's child resolved to, but that leaf may
    // be wrapped by layout modifiers (e.g. `.padding(1)`) which
    // themselves have distinct identities and disappear at the same
    // time.  Walk up the previous parent chain until we find an
    // ancestor that is still in the new tree — that's the insertion
    // point — and capture the deepest disappearing ancestor as the
    // subtree to inject.  This way the entire wrapped unit fades out.
    for identity in removedIdentities {
      guard removingIdentities[identity] == nil else { continue }
      // Removal look-up uses the PREVIOUS frame's registrations: the
      // disappearing view's `.transition()` modifier isn't evaluated in
      // the current frame (its branch is gone), so `transitionsByIdentity`
      // no longer contains an entry for it.  The previous frame captured
      // the registration while the view was still present.
      guard let transition = previousTransitionsByIdentity[identity],
        let previousRoot = previousTreeRoot
      else { continue }

      // Walk up: injectionTarget is the deepest ancestor that is ALSO
      // gone from the new tree.  injectionParent is the first surviving
      // ancestor (or nil if none exists, in which case we can't inject).
      var injectionTarget = identity
      var injectionParent = previousParentByIdentity[identity]
      while let parent = injectionParent, !newIdentities.contains(parent) {
        injectionTarget = parent
        injectionParent = previousParentByIdentity[parent]
      }

      guard injectionParent != nil,
        let subtree = findSubtree(in: previousRoot, identity: injectionTarget)
      else { continue }

      // Before clearing the injected subtree's active animations, peek
      // at any mid-flight opacity animation on the transition's
      // registered identity (or anywhere in the subtree) so the
      // removal can start from the displayed value instead of
      // snapping back to 1.0.  Must run before the filter below.
      let injectedIdentities = collectIdentities(in: subtree)
      var initialOpacity: Double = 1.0
      let keyOnTarget = AnimationKey(identity: identity, property: .opacity)
      if let existing = activeAnimations[keyOnTarget],
        let sampled = sample(existing, at: timestamp),
        case .double(let value) = sampled
      {
        initialOpacity = value
      } else {
        for sid in injectedIdentities {
          let k = AnimationKey(identity: sid, property: .opacity)
          if let existing = activeAnimations[k],
            let sampled = sample(existing, at: timestamp),
            case .double(let value) = sampled
          {
            initialOpacity = value
            break
          }
        }
      }

      // Now clear in-flight active animations for every identity in
      // the injected subtree — the exit animation supersedes them.
      // (Batch refcounts from those superseded animations are released
      // below in a follow-up pass so the completion closure sees the
      // exit animation replace the insertion cleanly.)
      let supersededEntries = activeAnimations.filter {
        injectedIdentities.contains($0.key.identity)
      }
      activeAnimations = activeAnimations.filter {
        !injectedIdentities.contains($0.key.identity)
      }
      for (_, entry) in supersededEntries {
        releaseBatch(entry.batchID)
      }

      // If a previous placed tree is cached, look up the frozen
      // placed subtree for the same identity so the overlay can be
      // injected post-layout (draw-only, no layout-shift).
      let placedSnapshot: PlacedNode?
      if let previousPlacedRoot {
        placedSnapshot = findPlacedSubtree(
          in: previousPlacedRoot,
          identity: injectionTarget
        )
      } else {
        placedSnapshot = nil
      }

      removingIdentities[identity] = RemovalEntry(
        snapshot: subtree,
        parentIdentity: injectionParent,
        childIndex: previousChildIndexByIdentity[injectionTarget] ?? 0,
        transition: transition,
        animationBox: transaction.animationRequest.animationBoxIfAny,
        startTime: timestamp,
        startOpacity: initialOpacity,
        placedSnapshot: placedSnapshot
      )
    }

    previousSnapshots = newSnapshots
    previousIdentities = newIdentities
    previousTreeRoot = node
    previousParentByIdentity = newParentByIdentity
    previousChildIndexByIdentity = newChildIndexByIdentity
  }

  /// Recursively searches a resolved tree for the subtree rooted at
  /// `identity` and returns a copy of it.
  private func findSubtree(
    in root: ResolvedNode,
    identity: Identity
  ) -> ResolvedNode? {
    if root.identity == identity { return root }
    for child in root.children {
      if let match = findSubtree(in: child, identity: identity) {
        return match
      }
    }
    return nil
  }

  /// Recursively searches a placed tree for the subtree rooted at
  /// `identity` and returns a copy of it.  Used to capture the
  /// frozen bounds of a disappearing subtree for draw-only overlay
  /// injection.
  private func findPlacedSubtree(
    in root: PlacedNode,
    identity: Identity
  ) -> PlacedNode? {
    if root.identity == identity { return root }
    for child in root.children {
      if let match = findPlacedSubtree(in: child, identity: identity) {
        return match
      }
    }
    return nil
  }

  /// Returns the set of every identity in a subtree (inclusive).
  private func collectIdentities(in subtree: ResolvedNode) -> Set<Identity> {
    var result: Set<Identity> = [subtree.identity]
    for child in subtree.children {
      result.formUnion(collectIdentities(in: child))
    }
    return result
  }

  /// Marks every node in the subtree as transient so the semantic
  /// extractor, focus tracker, and lifecycle coordinator skip the
  /// overlay during routing even though it still flows through
  /// layout + draw for the duration of the exit animation.
  private func markTransient(_ node: inout ResolvedNode) {
    node.isTransient = true
    var children = node.children
    for i in children.indices {
      markTransient(&children[i])
    }
    node.setChildrenPreservingDerivedState(children)
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
    let batchID = transaction.animationBatchID
    // Enqueue an animation for each modifier effect the transition
    // declares.  From values are derived from the modifiers (offset
    // shift, reduced opacity); to values are identity.  If an animation
    // for the same (identity, property) is already mid-flight — e.g.
    // an interrupted removal — sample its currently displayed value
    // and use that as the new `from`, so the insertion starts from
    // whatever is on screen instead of snapping back to the declared
    // `willAppear` value.
    if let startOpacity = modifiers.opacity {
      let target = snapshot.opacity ?? 1.0
      let key = AnimationKey(identity: identity, property: .opacity)
      let effectiveFrom =
        sampleCurrentValue(for: key, at: timestamp)
        ?? .double(startOpacity)
      if let existing = activeAnimations[key] { releaseBatch(existing.batchID) }
      retainBatch(batchID)
      activeAnimations[key] =
        ActiveAnimation(
          from: effectiveFrom,
          to: .double(target),
          animationBox: box,
          startTime: timestamp,
          batchID: batchID
        )
    }
    // Insertion offsets route through a separate placed-level path
    // rather than activeAnimations, because applyValue can't
    // translate intrinsic-layout leaves like Text (LayoutEngine's
    // .offset variant requires `resolved.children.first`).  The
    // placed-level path walks the post-layout tree and translates
    // matching bounds directly.
    if modifiers.offsetX != nil || modifiers.offsetY != nil {
      let fromX = modifiers.offsetX ?? 0
      let fromY = modifiers.offsetY ?? 0
      if let existing = insertionOffsetAnimations[identity] {
        releaseBatch(existing.batchID)
      }
      retainBatch(batchID)
      insertionOffsetAnimations[identity] = InsertionOffsetAnimation(
        from: (x: fromX, y: fromY),
        animationBox: box,
        startTime: timestamp,
        batchID: batchID
      )
    }
  }

  /// Returns the currently interpolated value of the animation at
  /// `key` if one is in flight, or nil if the slot is empty.  Used by
  /// the insertion path to retarget from the displayed value when a
  /// mid-flight animation gets interrupted by an opposite toggle.
  private func sampleCurrentValue(
    for key: AnimationKey,
    at timestamp: MonotonicInstant
  ) -> AnimatableValue? {
    guard let existing = activeAnimations[key] else { return nil }
    return sample(existing, at: timestamp)
  }

  private func processNode(
    _ node: ResolvedNode,
    parentIdentity: Identity?,
    childIndex: Int,
    transaction: TransactionSnapshot,
    timestamp: MonotonicInstant,
    snapshotAccumulator: inout [Identity: AnimatableSnapshot],
    parentAccumulator: inout [Identity: Identity],
    childIndexAccumulator: inout [Identity: Int]
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
      // A child transaction's .animate overrides inherit the parent's
      // batch ID when its own is nil; that way `.animation(_:value:)`
      // subtree overrides don't lose the `withAnimation` completion
      // association.
      let effectiveBatchID =
        node.transactionSnapshot.animationBatchID ?? transaction.animationBatchID
      diffAndEnqueue(
        identity: node.identity,
        previous: previous,
        current: snapshot,
        request: effectiveRequest,
        batchID: effectiveBatchID,
        timestamp: timestamp
      )
    }
    // First time we see an identity: no animation, just record the snapshot.

    snapshotAccumulator[node.identity] = snapshot
    if let parentIdentity {
      parentAccumulator[node.identity] = parentIdentity
    }
    childIndexAccumulator[node.identity] = childIndex

    for (index, child) in node.children.enumerated() {
      processNode(
        child,
        parentIdentity: node.identity,
        childIndex: index,
        transaction: transaction,
        timestamp: timestamp,
        snapshotAccumulator: &snapshotAccumulator,
        parentAccumulator: &parentAccumulator,
        childIndexAccumulator: &childIndexAccumulator
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
    batchID: AnimationBatchID?,
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
      batchID: batchID,
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
      batchID: batchID,
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
      batchID: batchID,
      timestamp: timestamp
    )
    enqueueIfChanged(
      identity: identity,
      property: .borderColor,
      previous: previous.borderColor,
      current: current.borderColor,
      toValue: AnimatableValue.color,
      fromValue: AnimatableValue.color,
      request: request,
      batchID: batchID,
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
      batchID: batchID,
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
      batchID: batchID,
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
      batchID: batchID,
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
      batchID: batchID,
      timestamp: timestamp
    )
    enqueueIfChanged(
      identity: identity,
      property: .paddingTop,
      previous: previous.padding?.top,
      current: current.padding?.top,
      toValue: AnimatableValue.integer,
      fromValue: AnimatableValue.integer,
      request: request,
      batchID: batchID,
      timestamp: timestamp
    )
    enqueueIfChanged(
      identity: identity,
      property: .paddingLeading,
      previous: previous.padding?.leading,
      current: current.padding?.leading,
      toValue: AnimatableValue.integer,
      fromValue: AnimatableValue.integer,
      request: request,
      batchID: batchID,
      timestamp: timestamp
    )
    enqueueIfChanged(
      identity: identity,
      property: .paddingBottom,
      previous: previous.padding?.bottom,
      current: current.padding?.bottom,
      toValue: AnimatableValue.integer,
      fromValue: AnimatableValue.integer,
      request: request,
      batchID: batchID,
      timestamp: timestamp
    )
    enqueueIfChanged(
      identity: identity,
      property: .paddingTrailing,
      previous: previous.padding?.trailing,
      current: current.padding?.trailing,
      toValue: AnimatableValue.integer,
      fromValue: AnimatableValue.integer,
      request: request,
      batchID: batchID,
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
    batchID: AnimationBatchID?,
    timestamp: MonotonicInstant
  ) {
    guard previous != current else { return }

    let key = AnimationKey(identity: identity, property: property)

    switch request {
    case .inherit, .disabled:
      // Snap immediately — clear any active animation for this key,
      // including its batch reference count.
      if let superseded = activeAnimations.removeValue(forKey: key) {
        releaseBatch(superseded.batchID)
      }

    case .animate(let box):
      guard let previousValue = previous, let currentValue = current else {
        // One side is nil — cannot interpolate.  Snap.
        if let superseded = activeAnimations.removeValue(forKey: key) {
          releaseBatch(superseded.batchID)
        }
        return
      }

      // Retarget: if an animation already exists, sample its current
      // value and use it as the new `from`.
      let effectiveFrom: AnimatableValue
      if let existing = activeAnimations[key],
        let sampled = sample(existing, at: timestamp)
      {
        effectiveFrom = sampled
        // The old animation is being superseded — release its batch
        // ref before we overwrite the slot.  The new animation may
        // belong to the same batch (retain happens below) or to a
        // different one.
        releaseBatch(existing.batchID)
      } else {
        effectiveFrom = fromValue(previousValue)
      }

      retainBatch(batchID)
      activeAnimations[key] = ActiveAnimation(
        from: effectiveFrom,
        to: toValue(currentValue),
        animationBox: box,
        startTime: timestamp,
        batchID: batchID
      )
    }
  }

  private func retainBatch(_ batchID: AnimationBatchID?) {
    guard let batchID else { return }
    batchRefCounts[batchID, default: 0] += 1
  }

  private func releaseBatch(_ batchID: AnimationBatchID?) {
    guard let batchID, let count = batchRefCounts[batchID] else { return }
    let newCount = count - 1
    if newCount <= 0 {
      batchRefCounts.removeValue(forKey: batchID)
      if let closure = completionClosures.removeValue(forKey: batchID) {
        closure()
      }
    } else {
      batchRefCounts[batchID] = newCount
    }
  }

  /// Applies interpolated values to the resolved tree for the given
  /// timestamp.  Returns a tick result describing scheduling needs.
  package func applyInterpolations(
    to tree: inout ResolvedNode,
    at timestamp: MonotonicInstant
  ) -> AnimationTickResult {
    guard !activeAnimations.isEmpty || !removingIdentities.isEmpty else {
      lastTickResult = AnimationTickResult()
      return lastTickResult
    }

    var keysToRemove: [AnimationKey] = []
    var affectedIdentities: Set<Identity> = []
    var latestDeadline: MonotonicInstant = timestamp
    var hasPendingWork = false

    // Build per-identity interpolated value maps for fast tree walk.
    var interpolated: [Identity: [AnimatableProperty: AnimatableValue]] = [:]

    // Record the batches that completed animations belong to so we can
    // release their ref counts in a second pass (after this iteration
    // closes).  Releasing during the iteration would mutate
    // activeAnimations and invalidate the dictionary traversal.
    var completedBatches: [AnimationBatchID] = []

    for (key, animation) in activeAnimations {
      guard let anim = registeredAnimations[animation.animationBox] else {
        keysToRemove.append(key)
        if let batchID = animation.batchID { completedBatches.append(batchID) }
        continue
      }
      let elapsed = animation.startTime.duration(to: timestamp)
      var state = animation.customState
      let evaluated = anim.evaluate(elapsed: elapsed, state: &state)
      // Store the updated custom state back on the active animation so
      // the next tick carries user bookkeeping forward.
      activeAnimations[key]?.customState = state
      guard let progress = evaluated else {
        // Animation complete — snap to final value and purge.
        interpolated[key.identity, default: [:]][key.property] = animation.to
        keysToRemove.append(key)
        if let batchID = animation.batchID { completedBatches.append(batchID) }
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
      hasPendingWork = true
    }

    // Remove completed animations.
    for key in keysToRemove {
      activeAnimations.removeValue(forKey: key)
    }
    // Release the batch references for everything that completed.
    // ``releaseBatch`` fires the matching completion closure when the
    // ref count hits zero.
    for batchID in completedBatches {
      releaseBatch(batchID)
    }

    // Process removal entries: compute interpolated transition modifiers
    // and prepare them for injection back into the tree.
    var removalsToPurge: [Identity] = []
    var injectionsByParent: [Identity: [(childIndex: Int, snapshot: ResolvedNode)]] = [:]

    for (identity, entry) in removingIdentities {
      let modifiers: TransitionModifiers
      var animationComplete = false

      if let box = entry.animationBox, let anim = registeredAnimations[box] {
        let elapsed = entry.startTime.duration(to: timestamp)
        if let progress = anim.evaluate(elapsed: elapsed) {
          // Interpolate from the entry's captured starting opacity
          // (normally 1.0 = identity, but may be lower if this
          // removal interrupted a mid-flight insertion) toward the
          // removal modifiers.  Progress 0 == starting state,
          // progress 1 == fully removed.
          modifiers = interpolateRemovalModifiers(
            from: entry.startOpacity,
            to: entry.transition.removalModifiers(),
            progress: progress
          )
        } else {
          animationComplete = true
          modifiers = entry.transition.removalModifiers()
        }
      } else {
        // No animation intent carried through — snap.
        animationComplete = true
        modifiers = .identity
      }

      if animationComplete {
        removalsToPurge.append(identity)
        affectedIdentities.insert(identity)
        continue
      }

      // When a placed snapshot was captured in the previous frame
      // we inject the overlay at the PLACED level (after layout)
      // via ``applyPlacedOverlays`` — skip resolved-level injection
      // here so the overlay doesn't run through measure/place.  This
      // closes the VStack layout-shift gap.
      if entry.placedSnapshot == nil {
        // Resolved-level fallback path (no cached placed tree).
        // Clone the subtree and apply the interpolated transition
        // modifiers recursively so leaf views (text, etc.) pick up
        // the fading opacity even if the transition was applied
        // higher up in the subtree.  Mark every node in the cloned
        // overlay as transient so the semantic extractor, focus
        // tracker, and lifecycle coordinator skip them.
        var subtreeCopy = entry.snapshot
        markTransient(&subtreeCopy)
        applyTransitionModifiersRecursively(modifiers, to: &subtreeCopy)
        if let parentId = entry.parentIdentity {
          injectionsByParent[parentId, default: []].append(
            (childIndex: entry.childIndex, snapshot: subtreeCopy)
          )
        }
      }
      affectedIdentities.insert(identity)
      latestDeadline = timestamp.advanced(by: frameInterval)
      hasPendingWork = true
    }

    for identity in removalsToPurge {
      removingIdentities.removeValue(forKey: identity)
    }

    // Apply interpolated values for in-tree animations.
    tree = applyInterpolatedValues(tree: tree, interpolated: interpolated)

    // Inject removal overlays at their previous parent/index.
    if !injectionsByParent.isEmpty {
      tree = injectRemovals(tree: tree, injectionsByParent: injectionsByParent)
    }

    // Insertion offset animations live on the placed side of the
    // pipeline (applyPlacedOverlays) but they still need to keep
    // the run loop ticking until they complete.
    if !insertionOffsetAnimations.isEmpty {
      hasPendingWork = true
      if latestDeadline == timestamp {
        latestDeadline = timestamp.advanced(by: frameInterval)
      }
      for identity in insertionOffsetAnimations.keys {
        affectedIdentities.insert(identity)
      }
    }

    let result = AnimationTickResult(
      hasActiveAnimations: hasPendingWork,
      nextDeadline: hasPendingWork ? latestDeadline : nil,
      affectedIdentities: affectedIdentities
    )
    lastTickResult = result
    return result
  }

  /// Interpolates from a starting opacity (typically 1.0 = identity,
  /// but lower if this removal interrupted a mid-flight insertion)
  /// toward the removal modifiers based on `progress`.  Progress is
  /// reported by the animation curve — 0 means "just starting", 1
  /// means "fully removed".
  private func interpolateRemovalModifiers(
    from startOpacity: Double,
    to target: TransitionModifiers,
    progress: Double
  ) -> TransitionModifiers {
    var result = TransitionModifiers.identity
    if let targetOpacity = target.opacity {
      result.opacity = startOpacity + (targetOpacity - startOpacity) * progress
    }
    if let targetOffsetX = target.offsetX {
      result.offsetX = Int(Double(targetOffsetX) * progress)
    }
    if let targetOffsetY = target.offsetY {
      result.offsetY = Int(Double(targetOffsetY) * progress)
    }
    return result
  }

  /// Applies transition modifiers recursively to every node in the
  /// subtree.  Opacity cascades (since rasterizer reads per-node
  /// opacity and text leaves need to see it).  Offset is applied only
  /// at the subtree root — either in place on an `.intrinsic` node,
  /// composed into an existing `.offset` variant, or via a fresh
  /// wrapping node when the root already carries a non-offset layout
  /// (`.frame`, `.padding`, etc.).  The wrapping approach lets
  /// transitions like `.move(edge:)` slide a framed or padded view.
  private func applyTransitionModifiersRecursively(
    _ modifiers: TransitionModifiers,
    to node: inout ResolvedNode
  ) {
    // Opacity cascades down to every descendant so the text leaf
    // (which actually renders) sees the faded value.
    if let opacity = modifiers.opacity {
      var drawMetadata = node.drawMetadata
      // If the node already has an explicit opacity, multiply so the
      // animation composes with authored opacity.
      let base = drawMetadata.baseStyle.explicitOpacity ?? 1.0
      drawMetadata.baseStyle.explicitOpacity = base * opacity
      node.drawMetadata = drawMetadata
    }

    var children = node.children
    for i in children.indices {
      var child = children[i]
      // Recurse with opacity only (offset stays at the root).
      var childMods = TransitionModifiers.identity
      childMods.opacity = modifiers.opacity
      applyTransitionModifiersRecursively(childMods, to: &child)
      children[i] = child
    }
    // Shape is unchanged (same count, just interpolated opacity on
    // each child) so we bypass the derived-state recomputes on the
    // normal children setter.
    node.setChildrenPreservingDerivedState(children)

    // Apply offset to the root of the subtree only.
    let offsetX = modifiers.offsetX ?? 0
    let offsetY = modifiers.offsetY ?? 0
    guard offsetX != 0 || offsetY != 0 else { return }

    switch node.layoutBehavior {
    case .intrinsic:
      // Variant is changing .intrinsic → .offset; reuse bit may
      // change, so use the normal setter.
      node.layoutBehavior = .offset(x: offsetX, y: offsetY)

    case .offset(let existingX, let existingY):
      // Compose with an existing offset by summation.  Variant
      // unchanged → bypass derived-state recomputes.
      node.setLayoutBehaviorPreservingDerivedState(
        .offset(x: existingX + offsetX, y: existingY + offsetY)
      )

    default:
      // Root already carries a non-offset layout (frame, padding,
      // flexibleFrame, stack, etc.).  Wrap it in a fresh offset
      // node so the transition offset composes with the authored
      // layout instead of being silently dropped.
      //
      // The wrapper's identity is derived from the root by appending
      // a private component so it is stable across ticks (same
      // identity produces the same wrapping, no structural churn).
      let wrapperIdentity = Identity(
        components: node.identity.components + ["__transitionOffset"]
      )
      var wrapped = ResolvedNode(
        identity: wrapperIdentity,
        kind: .view("TransitionOffset"),
        children: [node],
        environmentSnapshot: node.environmentSnapshot,
        transactionSnapshot: node.transactionSnapshot,
        layoutBehavior: .offset(x: offsetX, y: offsetY)
      )
      // The wrapper inherits the wrapped root's transient flag so
      // the whole overlay skips semantics / focus / lifecycle.
      wrapped.isTransient = node.isTransient
      node = wrapped
    }
  }

  /// Walks the current tree and injects removal snapshots at their
  /// previous parent identity and child index.  If the previous index
  /// exceeds the current children count, the snapshot is appended at
  /// the end.
  private func injectRemovals(
    tree: ResolvedNode,
    injectionsByParent: [Identity: [(childIndex: Int, snapshot: ResolvedNode)]]
  ) -> ResolvedNode {
    var node = tree
    // Recurse first so child injections happen before parent-level
    // splicing — this preserves the visual order of nested removals.
    var children = node.children.map { child in
      injectRemovals(tree: child, injectionsByParent: injectionsByParent)
    }
    if let injections = injectionsByParent[node.identity] {
      let sorted = injections.sorted { $0.childIndex < $1.childIndex }
      for injection in sorted {
        let insertIndex = min(injection.childIndex, children.count)
        children.insert(injection.snapshot, at: insertIndex)
      }
    }
    node.children = children
    return node
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
    // Recursively apply interpolated values to children; the shape
    // is unchanged so bypass the derived-state recomputes.
    let interpolatedChildren = node.children.map { child in
      applyInterpolatedValues(tree: child, interpolated: interpolated)
    }
    node.setChildrenPreservingDerivedState(interpolatedChildren)
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

    case (.borderColor, .color(let color)):
      var drawMetadata = node.drawMetadata
      drawMetadata.borderShapeStyle = .color(color)
      node.drawMetadata = drawMetadata

    case (.offsetX, .integer(let x)):
      if case .offset(_, let y) = node.layoutBehavior {
        // Variant unchanged (still .offset), only numeric values move.
        node.setLayoutBehaviorPreservingDerivedState(.offset(x: x, y: y))
      }

    case (.offsetY, .integer(let y)):
      if case .offset(let x, _) = node.layoutBehavior {
        node.setLayoutBehaviorPreservingDerivedState(.offset(x: x, y: y))
      }

    case (.frameWidth, .integer(let width)):
      switch node.layoutBehavior {
      case .frame(_, let height, let alignment):
        node.setLayoutBehaviorPreservingDerivedState(
          .frame(width: width, height: height, alignment: alignment)
        )
      case .flexibleFrame(
        let minWidth, let idealWidth, let maxWidth,
        let minHeight, let idealHeight, let maxHeight,
        let alignment):
        let (newMax, newIdeal, newMin) = Self.replaceFirstFinite(
          width: width,
          dimensions: (maxWidth, idealWidth, minWidth)
        )
        node.setLayoutBehaviorPreservingDerivedState(
          .flexibleFrame(
            minWidth: newMin,
            idealWidth: newIdeal,
            maxWidth: newMax,
            minHeight: minHeight,
            idealHeight: idealHeight,
            maxHeight: maxHeight,
            alignment: alignment
          ))
      default:
        break
      }

    case (.frameHeight, .integer(let height)):
      switch node.layoutBehavior {
      case .frame(let width, _, let alignment):
        node.setLayoutBehaviorPreservingDerivedState(
          .frame(width: width, height: height, alignment: alignment)
        )
      case .flexibleFrame(
        let minWidth, let idealWidth, let maxWidth,
        let minHeight, let idealHeight, let maxHeight,
        let alignment):
        let (newMax, newIdeal, newMin) = Self.replaceFirstFinite(
          width: height,
          dimensions: (maxHeight, idealHeight, minHeight)
        )
        node.setLayoutBehaviorPreservingDerivedState(
          .flexibleFrame(
            minWidth: minWidth,
            idealWidth: idealWidth,
            maxWidth: maxWidth,
            minHeight: newMin,
            idealHeight: newIdeal,
            maxHeight: newMax,
            alignment: alignment
          ))
      default:
        break
      }

    case (.paddingTop, .integer(let value)):
      if case .padding(var insets) = node.layoutBehavior {
        insets.top = value
        node.setLayoutBehaviorPreservingDerivedState(.padding(insets))
      }

    case (.paddingLeading, .integer(let value)):
      if case .padding(var insets) = node.layoutBehavior {
        insets.leading = value
        node.setLayoutBehaviorPreservingDerivedState(.padding(insets))
      }

    case (.paddingBottom, .integer(let value)):
      if case .padding(var insets) = node.layoutBehavior {
        insets.bottom = value
        node.setLayoutBehaviorPreservingDerivedState(.padding(insets))
      }

    case (.paddingTrailing, .integer(let value)):
      if case .padding(var insets) = node.layoutBehavior {
        insets.trailing = value
        node.setLayoutBehaviorPreservingDerivedState(.padding(insets))
      }

    default:
      break
    }
  }

  /// Replaces the first `.finite(_)` dimension (searched in max → ideal
  /// → min order) with the new integer value, leaving the others
  /// untouched.  Used by ``applyValue`` to write interpolated frame
  /// dimensions back to the same `.flexibleFrame` slot they were
  /// extracted from.
  private static func replaceFirstFinite(
    width value: Int,
    dimensions: (max: ProposedDimension?, ideal: ProposedDimension?, min: ProposedDimension?)
  ) -> (max: ProposedDimension?, ideal: ProposedDimension?, min: ProposedDimension?) {
    if case .finite = dimensions.max {
      return (.finite(value), dimensions.ideal, dimensions.min)
    }
    if case .finite = dimensions.ideal {
      return (dimensions.max, .finite(value), dimensions.min)
    }
    if case .finite = dimensions.min {
      return (dimensions.max, dimensions.ideal, .finite(value))
    }
    return dimensions
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
  ///
  /// Clears every stored field so no stale state leaks across a reset —
  /// leaving `removingIdentities` or `previousTreeRoot` alive would cause
  /// the next tick after reset to try to re-inject a subtree from a
  /// previous-generation tree.
  package func reset() {
    previousSnapshots.removeAll(keepingCapacity: true)
    previousTreeRoot = nil
    previousPlacedRoot = nil
    previousParentByIdentity.removeAll(keepingCapacity: true)
    previousChildIndexByIdentity.removeAll(keepingCapacity: true)
    insertionOffsetAnimations.removeAll(keepingCapacity: true)
    activeAnimations.removeAll(keepingCapacity: true)
    registeredAnimations.removeAll(keepingCapacity: true)
    completionClosures.removeAll(keepingCapacity: true)
    batchRefCounts.removeAll(keepingCapacity: true)
    transitionsByIdentity.removeAll(keepingCapacity: true)
    previousTransitionsByIdentity.removeAll(keepingCapacity: true)
    pendingTransitionsByIdentity.removeAll(keepingCapacity: true)
    removingIdentities.removeAll(keepingCapacity: true)
    previousIdentities.removeAll(keepingCapacity: true)
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

extension AnimationController: AnimationCompletionSink {
  package func registerCompletion(
    batchID: AnimationBatchID,
    closure: @escaping @Sendable () -> Void
  ) {
    // Store the closure; it fires when the batch's ref count hits zero
    // in ``releaseBatch``.  Registering a second closure for the same
    // batch ID replaces the first, matching SwiftUI's last-writer-wins
    // behavior when overlapping ``withAnimation`` calls collide.
    completionClosures[batchID] = closure
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
