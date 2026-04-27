package import Core
package import View

/// Identifies a logical animatable slot on a ``ResolvedNode``.  Each
/// slot maps to a specific writeback destination in ``applyValue``.
///
/// Compound slots (``foregroundShapeStyle``, ``backgroundShapeStyle``,
/// ``borderShapeStyle``, ``shapeFillStyle``, ``shapeStrokeStyle``) carry
/// heterogeneous animatable values — the slot identifies the
/// destination but the wrapped ``AnyAnimatable`` determines the concrete
/// type (Color, LinearGradient, RadialGradient, PatternFill).
///
/// **Where is the slot stored on `ResolvedNode`?** Two separate paths
/// reach the rasterizer:
///
/// - **`.foregroundShapeStyle` / `.backgroundShapeStyle` /
///   `.borderShapeStyle`** — style set by a `.foregroundStyle(_:)` /
///   `.background(_:)` / `.border(_:)` modifier.  Stored on
///   `node.drawMetadata.baseStyle.foregroundStyle` (and friends), or
///   inherited through the environment.  Leaf views like `Text` and
///   `TextFigure` resolve these at paint time.
/// - **`.shapeFillStyle` / `.shapeStrokeStyle`** — style set by a
///   `Shape.fill(_:)` / `Shape.stroke(_:)` / `Shape.strokeBorder(_:)`
///   modifier.  Stored *inside* `node.drawPayload` as
///   `.shape(ShapePayload(operation: .fill(style:mode:)))` (or
///   `.stroke(...)`).  The rasterizer reads this directly and never
///   consults `baseStyle.foregroundStyle` when the shape operation
///   carries a non-nil style.
///
/// These are two independent storage locations for what SwiftUI
/// conceptually treats as "the fill of a shape", and animations
/// targeting one must NOT be confused for the other.  A
/// `Rectangle().fill(LinearGradient(...))` writes to `.shapeFillStyle`;
/// a `Rectangle().foregroundStyle(LinearGradient(...))` writes to
/// `.foregroundShapeStyle`.  Both extract and apply paths here are
/// slot-specific so the two writeback destinations stay separate.
package enum AnimatableSlot: Hashable, Sendable {
  case opacity
  case foregroundShapeStyle
  case backgroundShapeStyle
  case borderShapeStyle
  case borderBlendPhase
  case padding
  case offset
  case position
  case frameWidth
  case frameHeight
  case shapeFillStyle
  case shapeStrokeStyle
}

/// Keyed identifier for a single active animation.  Carries the view
/// ``Identity`` plus a ``Scope`` discriminator that selects between
/// the per-property slot path, the placed-level insertion offset
/// path, and the placed-level matched-geometry path.  Every (identity,
/// scope) pairing can be in flight independently.
package struct AnimationKey: Hashable, Sendable {
  /// Discriminates the per-key payload that lives on ``ActiveAnimation``
  /// and selects which apply path consumes it.
  package enum Scope: Hashable, Sendable {
    /// A property animation against a specific ``AnimatableSlot``.
    case property(AnimatableSlot)
    /// A transition-driven insertion offset animation (placed level).
    case insertionOffset
    /// A matched-geometry translation animation (placed level).
    case matchedGeometry
  }

  package var identity: Identity
  package var scope: Scope

  package init(identity: Identity, scope: Scope) {
    self.identity = identity
    self.scope = scope
  }

  /// Convenience initializer for the property scope, preserving the
  /// pre-Phase-4 call shape `AnimationKey(identity:slot:)` at every
  /// historic call site.
  package init(identity: Identity, slot: AnimatableSlot) {
    self.identity = identity
    self.scope = .property(slot)
  }
}

/// Snapshot of every tracked animatable slot's value for one view
/// ``Identity`` after a resolve pass.  Stored per-identity in
/// ``AnimationController/previousSnapshots`` and diffed against the
/// next frame's snapshot to detect changes.
package struct AnimatableSnapshot: Sendable {
  package var values: [AnimatableSlot: AnyAnimatable]

  package init(values: [AnimatableSlot: AnyAnimatable] = [:]) {
    self.values = values
  }

  package subscript(slot: AnimatableSlot) -> AnyAnimatable? {
    get { values[slot] }
    set { values[slot] = newValue }
  }

  /// Extracts every animatable slot from the given resolved node.
  /// Slots whose source value is missing or not-Animatable are
  /// simply absent from the result dictionary.
  package static func extract(from node: ResolvedNode) -> AnimatableSnapshot {
    var snapshot = AnimatableSnapshot()

    // Opacity (Double)
    if let opacity = node.drawMetadata.baseStyle.explicitOpacity {
      snapshot[.opacity] = AnyAnimatable(opacity)
    }

    // Foreground/background/border shape styles.  `.foregroundStyle(color)`
    // on a generic view writes to the environment rather than to the
    // node's own draw metadata; leaf views such as `TextFigure` pick it
    // up from the environment at rasterize time.  Prefer the node's
    // local draw metadata and fall back to the environment snapshot so
    // environment-carried styles are still animated.  Note this is a
    // coalesce — an untracked local style (e.g. `.semantic`) still
    // falls through to the environment, matching the pre-Phase-3
    // extractColor behaviour.
    if let fg = extractAnimatableShapeStyle(
      from: node.drawMetadata.baseStyle.foregroundStyle
    )
      ?? extractAnimatableShapeStyle(
        from: node.environmentSnapshot.style.foregroundStyle
      )
    {
      snapshot[.foregroundShapeStyle] = fg
    }

    if let bg = extractAnimatableShapeStyle(
      from: node.drawMetadata.baseStyle.backgroundStyle
    ) {
      snapshot[.backgroundShapeStyle] = bg
    }

    if let border = extractAnimatableShapeStyle(
      from: node.drawMetadata.borderShapeStyle
    ) {
      snapshot[.borderShapeStyle] = border
    }

    // Shape draw payloads.  `Rectangle().fill(LinearGradient(...))` and
    // friends write their style into ``DrawPayload/shape(_:)``'s
    // ``ShapePayload/operation``, NOT into `baseStyle.foregroundStyle`.
    // Extract those styles into dedicated slots so Shape.fill / .stroke
    // animations flow through the same interpolation pipeline as the
    // `.foregroundStyle(_:)` modifier path.  A nil operation style
    // means the shape inherits from `baseStyle.foregroundStyle` at
    // paint time — in that case the .foregroundShapeStyle extraction
    // above already covers it.
    if case .shape(let shapePayload) = node.drawPayload {
      switch shapePayload.operation {
      case .fill(let style, _):
        if let fill = extractAnimatableShapeStyle(from: style) {
          snapshot[.shapeFillStyle] = fill
        }
      case .stroke(let style, _, _, _):
        if let stroke = extractAnimatableShapeStyle(from: style) {
          snapshot[.shapeStrokeStyle] = stroke
        }
      }
    }

    // Layout-derived slots.
    switch node.layoutBehavior {
    case .padding(let insets):
      snapshot[.padding] = AnyAnimatable(insets)
    case .offset(let x, let y):
      snapshot[.offset] = AnyAnimatable(AnimatablePair(x, y))
    case .position(let x, let y):
      snapshot[.position] = AnyAnimatable(AnimatablePair(x, y))
    case .frame(let width, let height, _):
      if let width { snapshot[.frameWidth] = AnyAnimatable(width) }
      if let height { snapshot[.frameHeight] = AnyAnimatable(height) }
    case .border(_, _, _, _, let blend, let blendPhase, _):
      // Only populate the phase slot when a ``BorderBlend`` is attached.
      // `.border` layouts without a blend have nothing to animate here —
      // the static zero default would otherwise create a phantom
      // "identity → 0" diff on any border that ever transitioned from
      // a blend to a plain foreground.
      if blend != nil {
        snapshot[.borderBlendPhase] = AnyAnimatable(blendPhase)
      }
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
      if let w = firstFiniteValue(of: [maxWidth, idealWidth, minWidth]) {
        snapshot[.frameWidth] = AnyAnimatable(w)
      }
      if let h = firstFiniteValue(of: [maxHeight, idealHeight, minHeight]) {
        snapshot[.frameHeight] = AnyAnimatable(h)
      }
    default:
      break
    }

    return snapshot
  }

  /// Back-compat shim: a lot of pre-Phase-3 tests assert on
  /// `snapshot.foregroundColor` directly.  Expose a computed accessor
  /// that unwraps the ``.foregroundShapeStyle`` slot when it happens to
  /// carry a plain `Color`, so the assertion set doesn't have to move
  /// wholesale to the new subscript form.
  package var foregroundColor: Color? {
    self[.foregroundShapeStyle]?.unwrap(as: Color.self)
  }

  package var backgroundColor: Color? {
    self[.backgroundShapeStyle]?.unwrap(as: Color.self)
  }

  package var borderColor: Color? {
    self[.borderShapeStyle]?.unwrap(as: Color.self)
  }

  package var opacity: Double? {
    self[.opacity]?.unwrap(as: Double.self)
  }

  package var frameWidth: Int? {
    self[.frameWidth]?.unwrap(as: Int.self)
  }

  package var frameHeight: Int? {
    self[.frameHeight]?.unwrap(as: Int.self)
  }

  /// Unwraps an ``AnyShapeStyle`` to a concrete animatable value
  /// the controller can interpolate.  Returns `nil` for shape
  /// styles that can't be reduced to a single animatable
  /// conformance (semantic tokens, terminal chrome, etc.).
  private static func extractAnimatableShapeStyle(
    from style: AnyShapeStyle?
  ) -> AnyAnimatable? {
    guard let style else { return nil }
    switch style {
    case .color(let color):
      return AnyAnimatable(color)
    case .linearGradient(let gradient):
      return AnyAnimatable(gradient)
    case .radialGradient(let gradient):
      return AnyAnimatable(gradient)
    case .patternFill(let pattern):
      return AnyAnimatable(pattern)
    case .opacity(let inner, _):
      return extractAnimatableShapeStyle(from: inner)
    case .terminalChrome, .semantic:
      return nil
    }
  }

  private static func firstFiniteValue(of dimensions: [ProposedDimension?]) -> Int? {
    for dimension in dimensions {
      if case .finite(let value) = dimension {
        return value
      }
    }
    return nil
  }
}

/// Per-kind payload carried on ``ActiveAnimation``.  The case selects
/// how the animation is sampled and how its output is applied to the
/// resolved/placed tree.
package enum AnimationKind: Sendable {
  /// A property animation on a specific ``AnimatableSlot``.  The
  /// `from`/`to` values are interpolated and written back through
  /// ``AnimationController/applyValue``.
  case property(from: AnyAnimatable, to: AnyAnimatable)
  /// A transition-driven insertion offset animation applied at
  /// placed level (cannot route through the slot path because it
  /// operates on intrinsic-layout leaves).  The `from` tuple holds
  /// the starting (x, y) delta; the animation interpolates from
  /// `from` toward (0, 0).
  case insertionOffset(from: (x: Int, y: Int))
  /// A matched-geometry translation animation between two placed
  /// bounds.  At progress 0 the target identity renders at
  /// `fromBounds`; at progress 1 it renders at its natural new
  /// bounds (looked up in the current placed tree).
  case matchedGeometry(fromBounds: Rect)
}

/// An animation currently in flight for one ``AnimationKey``.
package struct ActiveAnimation: Sendable {
  /// The per-kind payload.  Selects how this animation is sampled
  /// and applied to the tree.
  package var kind: AnimationKind
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
///
/// Phase 4 split the previously overloaded ``hasActiveAnimations`` /
/// ``affectedIdentities`` fields:
///
/// - ``hasPendingWork`` is the scheduling signal — `true` whenever the
///   tick produced any work that needs another frame, including
///   identity-agnostic stranded-batch drains.
/// - ``redrawIdentities`` is the visibility signal — the set of view
///   identities whose rendered cells must be redrawn this frame.  May
///   be empty even when ``hasPendingWork`` is `true` (the drain case),
///   so the run loop must not gate the wake-up on this set being
///   non-empty.
package struct AnimationTickResult: Sendable {
  /// `true` when the tick produced pending work and the scheduler
  /// should wake up again before ``nextDeadline``.
  package var hasPendingWork: Bool
  /// The absolute time by which the scheduler must wake for the
  /// next tick.  `nil` when no wake-up is needed.
  package var nextDeadline: MonotonicInstant?
  /// Identities whose rendered cells need to be redrawn this frame.
  /// Used by the render pipeline's incremental presentation diff to
  /// decide which subtrees need re-rasterizing — NOT by the run loop
  /// to decide whether to schedule another tick.
  package var redrawIdentities: Set<Identity>

  package init(
    hasPendingWork: Bool = false,
    nextDeadline: MonotonicInstant? = nil,
    redrawIdentities: Set<Identity> = []
  ) {
    self.hasPendingWork = hasPendingWork
    self.nextDeadline = nextDeadline
    self.redrawIdentities = redrawIdentities
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
  /// Per-key persistent state threaded into the removal animation's
  /// ``CustomAnimation/animate(value:time:context:)`` on each tick.
  /// Built-in bezier/spring curves ignore this; custom animations can
  /// use it to persist bookkeeping across the frames of an exit
  /// transition (e.g. a spring that accumulates velocity).
  package var customState: AnimationState = .init()
}

package struct PlacedAnimationOverlaySnapshot: Sendable {
  package var removalOverlays: [PlacedRemovalOverlaySnapshot]
  package var insertionOffsets: [PlacedAnimationOverlayOffset]
  package var matchedGeometryOffsets: [PlacedAnimationOverlayOffset]

  package init(
    removalOverlays: [PlacedRemovalOverlaySnapshot] = [],
    insertionOffsets: [PlacedAnimationOverlayOffset] = [],
    matchedGeometryOffsets: [PlacedAnimationOverlayOffset] = []
  ) {
    self.removalOverlays = removalOverlays
    self.insertionOffsets = insertionOffsets
    self.matchedGeometryOffsets = matchedGeometryOffsets
  }
}

package struct PlacedRemovalOverlaySnapshot: Sendable {
  package var parentIdentity: Identity
  package var childIndex: Int
  package var snapshot: PlacedNode
  package var modifiers: TransitionModifiers

  package init(
    parentIdentity: Identity,
    childIndex: Int,
    snapshot: PlacedNode,
    modifiers: TransitionModifiers
  ) {
    self.parentIdentity = parentIdentity
    self.childIndex = childIndex
    self.snapshot = snapshot
    self.modifiers = modifiers
  }
}

package struct PlacedAnimationOverlayOffset: Sendable {
  package var identity: Identity
  package var dx: Int
  package var dy: Int

  package init(
    identity: Identity,
    dx: Int,
    dy: Int
  ) {
    self.identity = identity
    self.dx = dx
    self.dy = dy
  }
}

package func applyPlacedAnimationOverlaySnapshot(
  _ snapshot: PlacedAnimationOverlaySnapshot,
  to tree: inout PlacedNode
) {
  if !snapshot.removalOverlays.isEmpty {
    var injections: [Identity: [(childIndex: Int, snapshot: PlacedNode)]] = [:]
    for removal in snapshot.removalOverlays {
      var clone = removal.snapshot
      applyPlacedOverlayModifiers(removal.modifiers, to: &clone)
      injections[removal.parentIdentity, default: []].append(
        (childIndex: removal.childIndex, snapshot: clone)
      )
    }
    tree = injectPlacedOverlays(tree: tree, injections: injections)
  }

  let insertionOffsets = overlayOffsetMap(snapshot.insertionOffsets)
  if !insertionOffsets.isEmpty {
    tree = translatePlacedNodesByIdentity(
      tree: tree,
      offsets: insertionOffsets
    )
  }

  let matchedGeometryOffsets = overlayOffsetMap(snapshot.matchedGeometryOffsets)
  if !matchedGeometryOffsets.isEmpty {
    tree = translatePlacedNodesByIdentity(
      tree: tree,
      offsets: matchedGeometryOffsets
    )
  }
}

private func overlayOffsetMap(
  _ offsets: [PlacedAnimationOverlayOffset]
) -> [Identity: (dx: Int, dy: Int)] {
  var result: [Identity: (dx: Int, dy: Int)] = [:]
  for offset in offsets {
    result[offset.identity] = (dx: offset.dx, dy: offset.dy)
  }
  return result
}

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

private func applyPlacedOverlayModifiers(
  _ modifiers: TransitionModifiers,
  to node: inout PlacedNode
) {
  markTransient(&node)

  if let opacity = modifiers.opacity {
    applyOpacityCascadingPlaced(&node, opacity: opacity)
  }

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

@MainActor
package final class AnimationController: Sendable {
  package struct Checkpoint {
    fileprivate var previousSnapshots: [Identity: AnimatableSnapshot]
    fileprivate var previousTreeRoot: ResolvedNode?
    fileprivate var previousPlacedRoot: PlacedNode?
    fileprivate var previousMatchedGeometryBounds: [MatchedGeometryKey: Rect]
    fileprivate var previousMatchedKeyIdentities: [MatchedGeometryKey: Identity]
    fileprivate var previousParentByIdentity: [Identity: Identity]
    fileprivate var previousChildIndexByIdentity: [Identity: Int]
    fileprivate var activeAnimations: [AnimationKey: ActiveAnimation]
    fileprivate var registeredAnimations: [AnimationBox: Animation]
    fileprivate var completionClosures: [AnimationBatchID: @Sendable () -> Void]
    fileprivate var batchRefCounts: [AnimationBatchID: Int]
    fileprivate var pendingEmptyBatchCompletions: [AnimationBatchID: MonotonicInstant]
    fileprivate var transitionsByIdentity: [Identity: AnyTransition]
    fileprivate var previousTransitionsByIdentity: [Identity: AnyTransition]
    fileprivate var pendingTransitionsByIdentity: [Identity: AnyTransition]
    fileprivate var removingIdentities: [Identity: RemovalEntry]
    fileprivate var previousIdentities: Set<Identity>
    fileprivate var lastTickResult: AnimationTickResult
    fileprivate var isFrameHeadTransactionActive: Bool
    fileprivate var deferredFrameHeadCompletions: [@Sendable () -> Void]
  }

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
  /// Placed bounds for every matched-geometry key observed in the
  /// previous frame's placed tree.  Seeded by ``capturePlacedTree``
  /// and consulted by the next frame's match detection.
  private var previousMatchedGeometryBounds: [MatchedGeometryKey: Rect] = [:]
  /// Which identity held each matched-geometry key in the previous
  /// frame.  A match fires when the current frame maps the same key
  /// to a *different* identity — regardless of whether either
  /// identity is newly inserted.
  private var previousMatchedKeyIdentities: [MatchedGeometryKey: Identity] = [:]
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
  /// Batches whose `withAnimation { ... } completion: { ... }` scope
  /// registered a completion closure but produced zero retained
  /// animations during their resolve pass — e.g. because the only
  /// changes in the body touched a property the controller doesn't
  /// expose as an ``AnimatableSlot``.
  ///
  /// Each entry stores the absolute time the controller should fire
  /// the completion.  ``applyInterpolations`` walks this map on every
  /// tick and drains entries whose deadline has elapsed, keeping
  /// stranded completions from leaking indefinitely.  A SwiftUI-shaped
  /// guarantee: every `withAnimation` completion eventually fires,
  /// even when the body changed nothing the controller can
  /// interpolate.
  private var pendingEmptyBatchCompletions: [AnimationBatchID: MonotonicInstant] = [:]
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
  private var isFrameHeadTransactionActive = false
  private var deferredFrameHeadCompletions: [@Sendable () -> Void] = []

  /// Target frame interval during active animation (30 FPS).
  private let frameInterval: Duration = .milliseconds(33)
  /// Default duration used for transition animations when no explicit
  /// animation is in the transaction.
  private let defaultTransitionDuration: Duration = .milliseconds(250)

  package init() {}

  package func beginFrameHeadTransaction() -> Checkpoint {
    precondition(
      !isFrameHeadTransactionActive,
      "AnimationController frame-head transactions cannot be nested."
    )
    let checkpoint = makeCheckpoint()
    isFrameHeadTransactionActive = true
    deferredFrameHeadCompletions.removeAll(keepingCapacity: true)
    return checkpoint
  }

  package func commitFrameHeadTransaction(_ checkpoint: Checkpoint) {
    precondition(
      isFrameHeadTransactionActive,
      "No AnimationController frame-head transaction is active."
    )
    let completions = deferredFrameHeadCompletions
    isFrameHeadTransactionActive = checkpoint.isFrameHeadTransactionActive
    deferredFrameHeadCompletions = checkpoint.deferredFrameHeadCompletions
    for completion in completions {
      completion()
    }
  }

  package func abortFrameHeadTransaction(_ checkpoint: Checkpoint) {
    precondition(
      isFrameHeadTransactionActive,
      "No AnimationController frame-head transaction is active."
    )
    restore(checkpoint)
  }

  private func makeCheckpoint() -> Checkpoint {
    Checkpoint(
      previousSnapshots: previousSnapshots,
      previousTreeRoot: previousTreeRoot,
      previousPlacedRoot: previousPlacedRoot,
      previousMatchedGeometryBounds: previousMatchedGeometryBounds,
      previousMatchedKeyIdentities: previousMatchedKeyIdentities,
      previousParentByIdentity: previousParentByIdentity,
      previousChildIndexByIdentity: previousChildIndexByIdentity,
      activeAnimations: activeAnimations,
      registeredAnimations: registeredAnimations,
      completionClosures: completionClosures,
      batchRefCounts: batchRefCounts,
      pendingEmptyBatchCompletions: pendingEmptyBatchCompletions,
      transitionsByIdentity: transitionsByIdentity,
      previousTransitionsByIdentity: previousTransitionsByIdentity,
      pendingTransitionsByIdentity: pendingTransitionsByIdentity,
      removingIdentities: removingIdentities,
      previousIdentities: previousIdentities,
      lastTickResult: lastTickResult,
      isFrameHeadTransactionActive: isFrameHeadTransactionActive,
      deferredFrameHeadCompletions: deferredFrameHeadCompletions
    )
  }

  private func restore(_ checkpoint: Checkpoint) {
    previousSnapshots = checkpoint.previousSnapshots
    previousTreeRoot = checkpoint.previousTreeRoot
    previousPlacedRoot = checkpoint.previousPlacedRoot
    previousMatchedGeometryBounds = checkpoint.previousMatchedGeometryBounds
    previousMatchedKeyIdentities = checkpoint.previousMatchedKeyIdentities
    previousParentByIdentity = checkpoint.previousParentByIdentity
    previousChildIndexByIdentity = checkpoint.previousChildIndexByIdentity
    activeAnimations = checkpoint.activeAnimations
    registeredAnimations = checkpoint.registeredAnimations
    completionClosures = checkpoint.completionClosures
    batchRefCounts = checkpoint.batchRefCounts
    pendingEmptyBatchCompletions = checkpoint.pendingEmptyBatchCompletions
    transitionsByIdentity = checkpoint.transitionsByIdentity
    previousTransitionsByIdentity = checkpoint.previousTransitionsByIdentity
    pendingTransitionsByIdentity = checkpoint.pendingTransitionsByIdentity
    removingIdentities = checkpoint.removingIdentities
    previousIdentities = checkpoint.previousIdentities
    lastTickResult = checkpoint.lastTickResult
    isFrameHeadTransactionActive = checkpoint.isFrameHeadTransactionActive
    deferredFrameHeadCompletions = checkpoint.deferredFrameHeadCompletions
  }

  /// Stores a snapshot of the placed tree at the end of the frame so
  /// the next frame's removal detection can find the disappearing
  /// identity's frozen bounds without re-running layout.  Also
  /// collects matched-geometry bounds + identities so the next
  /// frame can detect key → identity swaps and start matched
  /// geometry animations.
  ///
  /// Called by the render pipeline after ``place`` runs.  When no
  /// removal overlays are pending this is a cheap reference copy.
  package func capturePlacedTree(_ placed: PlacedNode) {
    previousPlacedRoot = placed
    var matchedBounds: [MatchedGeometryKey: Rect] = [:]
    var matchedIdentities: [MatchedGeometryKey: Identity] = [:]
    Self.collectMatchedGeometry(
      placed,
      bounds: &matchedBounds,
      identities: &matchedIdentities
    )
    previousMatchedGeometryBounds = matchedBounds
    previousMatchedKeyIdentities = matchedIdentities
  }

  /// Walks the placed tree and records the bounds and identity of
  /// every node tagged with a ``MatchedGeometryKey``.  Nodes whose
  /// config is `isSource: false` never contribute their bounds —
  /// they still receive match translations on frames where their
  /// key is swapped to another identity, but a non-source instance
  /// can't make another instance animate by disappearing.
  ///
  /// If multiple source-contributing nodes carry the same key in
  /// one frame (undefined in SwiftUI as well) the last-walked
  /// entry wins.
  private static func collectMatchedGeometry(
    _ node: PlacedNode,
    bounds: inout [MatchedGeometryKey: Rect],
    identities: inout [MatchedGeometryKey: Identity]
  ) {
    if let config = node.matchedGeometry, config.isSource {
      bounds[config.key] = node.bounds
      identities[config.key] = node.identity
    }
    for child in node.children {
      collectMatchedGeometry(child, bounds: &bounds, identities: &identities)
    }
  }

  /// Number of matched-geometry animations currently in flight.
  /// Test hook.
  package var activeMatchedGeometryCount: Int {
    activeAnimations.keys.lazy.filter { $0.scope == .matchedGeometry }.count
  }

  /// Number of matched-geometry keys captured from the previous
  /// frame's placed tree.  Test hook used to verify that
  /// capturePlacedTree is observing the matched-geometry field.
  package var previousMatchedGeometryKeyCount: Int {
    previousMatchedGeometryBounds.count
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
    let snapshot = placedAnimationOverlaySnapshot(
      for: tree,
      at: timestamp
    )
    applyPlacedAnimationOverlaySnapshot(
      snapshot,
      to: &tree
    )
  }

  /// Samples placed-level animation state into an explicit value
  /// snapshot that can be applied away from the main actor.
  ///
  /// This method still owns animation bookkeeping: custom animation
  /// state is advanced, completed keys are released, and batch
  /// completions can fire. The returned snapshot is pure data.
  package func placedAnimationOverlaySnapshot(
    for tree: PlacedNode,
    at timestamp: MonotonicInstant
  ) -> PlacedAnimationOverlaySnapshot {
    // 1. Inject removal overlays.
    var removalOverlays: [PlacedRemovalOverlaySnapshot] = []
    if !removingIdentities.isEmpty {
      for (identity, entry) in removingIdentities {
        guard let placedSnapshot = entry.placedSnapshot,
          let parentId = entry.parentIdentity
        else {
          continue  // No placed capture → resolved-level path handles it.
        }

        let modifiers: TransitionModifiers
        if let box = entry.animationBox, let anim = registeredAnimations[box] {
          let elapsed = entry.startTime.duration(to: timestamp)
          var state = entry.customState
          let evaluated = anim.evaluate(elapsed: elapsed, state: &state)
          // Write the updated custom state back so the next tick of
          // the exit transition carries user bookkeeping forward
          // (matches the active-animation tick loop pattern).
          removingIdentities[identity]?.customState = state
          if let progress = evaluated {
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

        removalOverlays.append(
          .init(
            parentIdentity: parentId,
            childIndex: entry.childIndex,
            snapshot: placedSnapshot,
            modifiers: modifiers
          )
        )
      }
    }

    // 2. Translate placed nodes for insertion offset animations.
    //    Filter the unified active map down to the .insertionOffset
    //    scope; everything else (property + matchedGeometry) is
    //    ignored on this pass.
    var insertionOffsetsByIdentity: [Identity: (dx: Int, dy: Int)] = [:]
    var completedInsertionKeys: [AnimationKey] = []

    for (key, entry) in activeAnimations {
      guard key.scope == .insertionOffset else { continue }
      guard case .insertionOffset(let from) = entry.kind else { continue }
      guard let anim = registeredAnimations[entry.animationBox] else {
        completedInsertionKeys.append(key)
        continue
      }
      let elapsed = entry.startTime.duration(to: timestamp)
      var state = entry.customState
      let evaluated = anim.evaluate(elapsed: elapsed, state: &state)
      activeAnimations[key]?.customState = state

      guard let progress = evaluated else {
        // Animation complete: delta is 0 (fully at final position).
        completedInsertionKeys.append(key)
        continue
      }
      // Insertion interpolates `from` → 0.
      // At progress p, interpolated = from * (1 - p).
      let dx = Int(Double(from.x) * (1.0 - progress))
      let dy = Int(Double(from.y) * (1.0 - progress))
      insertionOffsetsByIdentity[key.identity] = (dx: dx, dy: dy)
    }

    for key in completedInsertionKeys {
      if let entry = activeAnimations.removeValue(forKey: key) {
        releaseBatch(entry.batchID)
      }
    }

    // 3. Apply matched-geometry translations.  At progress 0 the
    //    new identity renders at the PREVIOUS frame's bounds; at
    //    progress 1 it renders at its natural new bounds.  Same
    //    filter pattern: only .matchedGeometry-scoped keys.
    var matchedDeltasByIdentity: [Identity: (dx: Int, dy: Int)] = [:]
    var completedMatchedKeys: [AnimationKey] = []

    for (key, entry) in activeAnimations {
      guard key.scope == .matchedGeometry else { continue }
      guard case .matchedGeometry(let fromBounds) = entry.kind else { continue }
      guard let anim = registeredAnimations[entry.animationBox] else {
        completedMatchedKeys.append(key)
        continue
      }
      let elapsed = entry.startTime.duration(to: timestamp)
      var state = entry.customState
      let evaluated = anim.evaluate(elapsed: elapsed, state: &state)
      activeAnimations[key]?.customState = state

      guard let progress = evaluated else {
        completedMatchedKeys.append(key)
        continue
      }

      // Look up the new placed bounds for this identity in the
      // current tree.  The translation delta is
      //     (fromBounds.origin - toBounds.origin) * (1 - progress)
      // so at progress 0 we land on fromBounds and at progress 1
      // we land on the natural new position.
      guard let toBounds = Self.findBounds(in: tree, identity: key.identity)
      else { continue }
      let deltaX =
        Double(fromBounds.origin.x - toBounds.origin.x)
        * (1.0 - progress)
      let deltaY =
        Double(fromBounds.origin.y - toBounds.origin.y)
        * (1.0 - progress)
      matchedDeltasByIdentity[key.identity] = (
        dx: Int(deltaX.rounded()),
        dy: Int(deltaY.rounded())
      )
    }

    for key in completedMatchedKeys {
      if let entry = activeAnimations.removeValue(forKey: key) {
        releaseBatch(entry.batchID)
      }
    }

    return .init(
      removalOverlays: removalOverlays,
      insertionOffsets: insertionOffsetsByIdentity.map { identity, offset in
        .init(
          identity: identity,
          dx: offset.dx,
          dy: offset.dy
        )
      },
      matchedGeometryOffsets: matchedDeltasByIdentity.map { identity, offset in
        .init(
          identity: identity,
          dx: offset.dx,
          dy: offset.dy
        )
      }
    )
  }

  private static func findBounds(
    in node: PlacedNode,
    identity: Identity
  ) -> Rect? {
    if node.identity == identity { return node.bounds }
    for child in node.children {
      if let found = findBounds(in: child, identity: identity) {
        return found
      }
    }
    return nil
  }

  /// Number of insertion-offset animations currently in flight.
  /// Test hook so integration tests can pin the enqueue path
  /// without exposing the entire private map.
  package var activeInsertionOffsetCount: Int {
    activeAnimations.keys.lazy.filter { $0.scope == .insertionOffset }.count
  }

  /// Number of in-tree (drawMetadata / layoutBehavior) animations
  /// currently in flight.  Test hook.  Counts only ``.property``
  /// scopes so the meaning matches the pre-Phase-4 contract — placed
  /// overlay scopes have their own counters above.
  package var activeAnimationCount: Int {
    activeAnimations.keys.lazy.filter {
      if case .property = $0.scope { return true }
      return false
    }.count
  }

  /// Called by the View layer at the start of resolve so the controller
  /// can collect up-to-date `.transition()` registrations.
  ///
  /// The PREVIOUS frame's registrations are preserved so removal
  /// detection can still find transitions for views whose branches are
  /// gone.  Registrations for identities whose subtrees are not
  /// re-evaluated this frame survive in `transitionsByIdentity` via a
  /// merge in ``finishTransitionCollection()``; stale entries for
  /// identities that leave the tree are pruned at the end of
  /// ``processResolvedTree(_:transaction:timestamp:)``.
  package func beginTransitionCollection() {
    previousTransitionsByIdentity = transitionsByIdentity
    pendingTransitionsByIdentity.removeAll(keepingCapacity: true)
  }

  package func finishTransitionCollection() {
    // Merge newly registered transitions into the existing map so
    // that registrations for non-re-evaluated subtrees survive
    // across selective-evaluation frames.  Without this, a
    // PhaseAnimator-only tick would wipe every other subtree's
    // transition and the next removal couldn't find it.
    for (identity, transition) in pendingTransitionsByIdentity {
      transitionsByIdentity[identity] = transition
    }
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
    var newMatchedKeysByIdentity: [Identity: MatchedGeometryKey] = [:]
    processNode(
      node,
      parentIdentity: nil,
      childIndex: 0,
      transaction: transaction,
      timestamp: timestamp,
      snapshotAccumulator: &newSnapshots,
      parentAccumulator: &newParentByIdentity,
      childIndexAccumulator: &newChildIndexByIdentity,
      matchedKeyAccumulator: &newMatchedKeysByIdentity
    )

    // Detect insertions and removals by diffing identity sets.  Skip
    // identities that are already mid-removal: they exist in the
    // injected overlay but not in the live tree, so they should not be
    // re-inserted as "new".
    let newIdentities = Set(newSnapshots.keys)
    let liveIdentities = previousIdentities.subtracting(removingIdentities.keys)
    let insertedIdentities = newIdentities.subtracting(previousIdentities)
    let removedIdentities = liveIdentities.subtracting(newIdentities)

    // Matched-geometry detection.  A match fires when the current
    // frame's (identity, key) mapping differs from the previous
    // frame's — regardless of whether either identity is newly
    // inserted.  Both "swap via reorder" and "swap via if/else"
    // cases are handled by comparing previous vs new key→identity
    // maps.  Collect the set of keys that matched so the
    // counterpart removal/transition can be skipped.
    var matchedKeysConsumedByMatch: Set<MatchedGeometryKey> = []
    for (identity, key) in newMatchedKeysByIdentity {
      // Skip if the same identity held this key last frame — no
      // swap, no translation.
      if let previousIdentity = previousMatchedKeyIdentities[key],
        previousIdentity == identity
      {
        continue
      }
      guard let fromBounds = previousMatchedGeometryBounds[key] else { continue }
      guard case .animate(let box) = transaction.animationRequest else {
        // Without withAnimation intent the match snaps to the new
        // location immediately.
        continue
      }
      let batchID = transaction.animationBatchID
      let matchedKey = AnimationKey(
        identity: identity, scope: .matchedGeometry
      )
      if let existing = activeAnimations[matchedKey] {
        releaseBatch(existing.batchID)
      }
      retainBatch(batchID)
      activeAnimations[matchedKey] = ActiveAnimation(
        kind: .matchedGeometry(fromBounds: fromBounds),
        animationBox: box,
        startTime: timestamp,
        batchID: batchID
      )
      matchedKeysConsumedByMatch.insert(key)
    }

    // Process insertions: kick off willAppear -> identity animations.
    // Skip insertions that are part of a matched-geometry swap —
    // those use the matched-geometry pathway and shouldn't fire a
    // redundant willAppear transition.
    //
    // Also skip structural first-appearances: when an identity's
    // parent was also just inserted, the whole subtree appeared
    // because a container was mounted (e.g. tab switch), NOT because
    // a conditional toggled inside withAnimation.  Playing insertion
    // transitions for these would cause spurious fade-ins whenever a
    // PhaseAnimator or other continuous animation shares the frame
    // transaction.  This matches SwiftUI, which only fires
    // .transition() when the view's conditional presence changes.
    for identity in insertedIdentities {
      if let key = newMatchedKeysByIdentity[identity],
        matchedKeysConsumedByMatch.contains(key)
      {
        continue
      }
      // Structural first-appearance guard: if the parent identity is
      // also freshly inserted, this view appeared as part of a bulk
      // mount, not a conditional toggle.
      if let parent = newParentByIdentity[identity],
        insertedIdentities.contains(parent)
      {
        continue
      }
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
      // If the removed identity's matched-geometry key was
      // consumed by a match on this frame, the counterpart insertion
      // already owns the visual transition.  Skip the removal
      // overlay so the old view just disappears.
      if let previousRoot = previousTreeRoot,
        let previousNode = findNode(in: previousRoot, identity: identity),
        let removedConfig = previousNode.matchedGeometry,
        matchedKeysConsumedByMatch.contains(removedConfig.key)
      {
        continue
      }
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
      //
      // The walk ONLY passes through single-child wrapper nodes
      // (.padding, .frame, .offset, etc.).  When a removed ancestor
      // has multiple children in the previous tree it is a structural
      // container (VStack, HStack, ScrollView, …) — climbing past it
      // would capture an entire unrelated subtree as the removal
      // overlay, which is what happens during a tab switch where the
      // PhaseAnimator’s frame-level .animate leaks to the transition.
      // Stopping here means injectionParent might still be a removed
      // identity, which the guard below converts into a skip.
      var injectionTarget = identity
      var injectionParent = previousParentByIdentity[identity]
      while let parent = injectionParent, !newIdentities.contains(parent) {
        // Stop before climbing through a multi-child container.
        if let parentNode = findNode(in: previousRoot, identity: parent),
          parentNode.children.count > 1
        {
          break
        }
        injectionTarget = parent
        injectionParent = previousParentByIdentity[parent]
      }

      // injectionParent must be a surviving identity in the new tree.
      // If the walk-up stopped at a multi-child container (break),
      // injectionParent may still be a removed identity — skip.
      guard let injectionParent, newIdentities.contains(injectionParent),
        let subtree = findSubtree(in: previousRoot, identity: injectionTarget)
      else { continue }

      // Before clearing the injected subtree's active animations, peek
      // at any mid-flight opacity animation on the transition's
      // registered identity (or anywhere in the subtree) so the
      // removal can start from the displayed value instead of
      // snapping back to 1.0.  Must run before the filter below.
      let injectedIdentities = collectIdentities(in: subtree)
      var initialOpacity: Double = 1.0
      let keyOnTarget = AnimationKey(identity: identity, slot: .opacity)
      if let existing = activeAnimations[keyOnTarget],
        let sampled = sample(existing, at: timestamp),
        let value = sampled.unwrap(as: Double.self)
      {
        initialOpacity = value
      } else {
        for sid in injectedIdentities {
          let k = AnimationKey(identity: sid, slot: .opacity)
          if let existing = activeAnimations[k],
            let sampled = sample(existing, at: timestamp),
            let value = sampled.unwrap(as: Double.self)
          {
            initialOpacity = value
            break
          }
        }
      }

      // Supersede any in-flight animations on identities that are being
      // re-injected from the removed subtree.  The unified activeAnimations
      // map means this filter is scope-agnostic: property animations,
      // insertion-offset animations, and matched-geometry animations are
      // all swept together.  Any withAnimation completion closures ref-
      // counted by these entries fire immediately here (via releaseBatch
      // below), rather than at each animation's natural curve completion —
      // matching SwiftUI's interrupt semantics where a removal supersedes
      // any in-progress insertion or matched-geometry transition.
      //
      // Pre-Phase-4, insertion-offset and matched-geometry animations
      // lived in separate side-channel maps and were not touched by this
      // filter, so they would tick to natural completion (or be purged
      // later by the placed-overlay loop's "registration missing" path)
      // even after the exit animation started.
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

    // Prune transition registrations for identities that are no
    // longer in the live tree.  Their registration was already
    // copied into previousTransitionsByIdentity at the start of
    // this frame, so any removal that needed it has already found
    // it.  Pruning prevents unbounded growth of the map.
    transitionsByIdentity = transitionsByIdentity.filter { key, _ in
      newIdentities.contains(key)
    }

    previousSnapshots = newSnapshots
    previousIdentities = newIdentities
    previousTreeRoot = node
    previousParentByIdentity = newParentByIdentity
    previousChildIndexByIdentity = newChildIndexByIdentity

    // Drain stranded completions.  Any batch that has a registered
    // completion closure but no live ref count (no property, no
    // removal, no insertion, no matched-geometry retained it) will
    // otherwise leak forever — and any `withAnimation` caller that
    // await-ed on its completion (like ``PhaseAnimator``) would hang.
    // Schedule a drain for each such batch here; the drain fires
    // after the animation's nominal duration in ``applyInterpolations``.
    scheduleStrandedBatchDrains(
      transaction: transaction,
      timestamp: timestamp
    )
  }

  /// Records a delayed completion firing when the current resolve
  /// pass opens a batch that never gets retained.  Called at the end
  /// of ``processResolvedTree`` once every retain path has had a
  /// chance to bump ``batchRefCounts``.
  ///
  /// Only acts on the batch carried by the incoming transaction —
  /// that is, the batch *this* `withAnimation` scope just opened.
  /// Completions for other batches (e.g. registered but not yet
  /// brought through a resolve pass) are left alone so they can be
  /// handled by their own home frame.
  ///
  /// The drain delay matches the animation's nominal wall-clock
  /// duration, so callers that asked for a 500 ms animation still
  /// observe a 500 ms delay before their completion fires — even
  /// when the body changed nothing the controller can interpolate.
  /// An animation with ``RepeatBehavior/forever`` has no logical
  /// completion time and is skipped entirely, matching SwiftUI's
  /// behavior of never firing `withAnimation` completions for
  /// `.repeatForever` scopes.
  private func scheduleStrandedBatchDrains(
    transaction: TransactionSnapshot,
    timestamp: MonotonicInstant
  ) {
    // Find the one batch this resolve pass was opened for.  A single
    // ``withAnimation`` scope opens exactly one batch per top-level
    // call; nested `.animation(_:value:)` modifiers don't register
    // completions, so we only ever have at most one stranded batch
    // to consider per pass.
    guard let batchID = transaction.animationBatchID else { return }
    // A batch already tracked by ``batchRefCounts`` has at least
    // one retained animation that will release it via the normal
    // path — leave it alone.
    guard batchRefCounts[batchID] == nil else { return }
    // Only act on batches that registered a completion closure.  A
    // plain `withAnimation(anim) { ... }` (no completion overload)
    // never calls ``registerCompletion``, so there's nothing to
    // drain even when the body changes nothing tracked.
    guard completionClosures[batchID] != nil else { return }
    // Don't reschedule a drain that's already pending from a
    // previous resolve pass.
    guard pendingEmptyBatchCompletions[batchID] == nil else { return }

    let drainDelay: Duration?
    switch transaction.animationRequest {
    case .animate(let box):
      if let animation = registeredAnimations[box] {
        // ``totalDuration`` is `nil` for `.repeatForever`.
        drainDelay = animation.totalDuration
      } else {
        // Box without registration — fire immediately.  The
        // registration usually happens at withAnimation-time, so
        // a missing entry means the caller wanted a snap or
        // constructed the transaction manually.
        drainDelay = .zero
      }
    case .disabled, .inherit:
      // `withAnimation(nil, body, completion)` routes through here:
      // no animation was requested, so the completion is logically
      // complete as soon as the body returns.
      drainDelay = .zero
    }

    guard let drainDelay else {
      // Infinite animation — don't fire the completion, matching
      // SwiftUI.  Drop the closure so it doesn't leak indefinitely
      // as every subsequent frame would revisit it.
      completionClosures.removeValue(forKey: batchID)
      return
    }

    pendingEmptyBatchCompletions[batchID] =
      timestamp.advanced(by: drainDelay)
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

  /// Convenience wrapper around ``findSubtree(in:identity:)`` used
  /// by matched-geometry removal detection — same behavior, more
  /// readable name at the call site.
  private func findNode(
    in root: ResolvedNode,
    identity: Identity
  ) -> ResolvedNode? {
    findSubtree(in: root, identity: identity)
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
      let key = AnimationKey(identity: identity, slot: .opacity)
      let effectiveFrom: AnyAnimatable =
        sampleCurrentValue(for: key, at: timestamp)
        ?? AnyAnimatable(startOpacity)
      if let existing = activeAnimations[key] { releaseBatch(existing.batchID) }
      retainBatch(batchID)
      activeAnimations[key] = ActiveAnimation(
        kind: .property(
          from: effectiveFrom,
          to: AnyAnimatable(target)
        ),
        animationBox: box,
        startTime: timestamp,
        batchID: batchID
      )
    }
    // Insertion offsets route through a placed-level scope rather
    // than the property path, because applyValue can't translate
    // intrinsic-layout leaves like Text (LayoutEngine's .offset
    // variant requires `resolved.children.first`).  The placed-level
    // path walks the post-layout tree and translates matching
    // bounds directly.
    if modifiers.offsetX != nil || modifiers.offsetY != nil {
      let fromX = modifiers.offsetX ?? 0
      let fromY = modifiers.offsetY ?? 0
      let offsetKey = AnimationKey(identity: identity, scope: .insertionOffset)
      if let existing = activeAnimations[offsetKey] {
        releaseBatch(existing.batchID)
      }
      retainBatch(batchID)
      activeAnimations[offsetKey] = ActiveAnimation(
        kind: .insertionOffset(from: (x: fromX, y: fromY)),
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
  ) -> AnyAnimatable? {
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
    childIndexAccumulator: inout [Identity: Int],
    matchedKeyAccumulator: inout [Identity: MatchedGeometryKey]
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
    if let config = node.matchedGeometry {
      matchedKeyAccumulator[node.identity] = config.key
    }

    for (index, child) in node.children.enumerated() {
      processNode(
        child,
        parentIdentity: node.identity,
        childIndex: index,
        transaction: transaction,
        timestamp: timestamp,
        snapshotAccumulator: &snapshotAccumulator,
        parentAccumulator: &parentAccumulator,
        childIndexAccumulator: &childIndexAccumulator,
        matchedKeyAccumulator: &matchedKeyAccumulator
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
    // Union of slot keys from both snapshots — a slot that appears
    // in only one snapshot is a "one side nil" change and snaps.
    var slots = Set(previous.values.keys)
    slots.formUnion(current.values.keys)

    for slot in slots {
      enqueueSlotChangeIfNeeded(
        identity: identity,
        slot: slot,
        previous: previous[slot],
        current: current[slot],
        request: request,
        batchID: batchID,
        timestamp: timestamp
      )
    }
  }

  private func enqueueSlotChangeIfNeeded(
    identity: Identity,
    slot: AnimatableSlot,
    previous: AnyAnimatable?,
    current: AnyAnimatable?,
    request: AnimationRequest,
    batchID: AnimationBatchID?,
    timestamp: MonotonicInstant
  ) {
    // No change → nothing to do.
    guard previous != current else { return }

    let key = AnimationKey(identity: identity, slot: slot)

    switch request {
    case .inherit, .disabled:
      if let superseded = activeAnimations.removeValue(forKey: key) {
        releaseBatch(superseded.batchID)
      }

    case .animate(let box):
      guard let previous, let current else {
        // One side nil — cannot interpolate, snap.
        if let superseded = activeAnimations.removeValue(forKey: key) {
          releaseBatch(superseded.batchID)
        }
        return
      }

      // Retarget: if an animation already exists, sample its current
      // value and use it as the new `from` — matches the existing
      // mid-flight retarget behavior.
      let effectiveFrom: AnyAnimatable
      if let existing = activeAnimations[key],
        let sampled = sample(existing, at: timestamp)
      {
        effectiveFrom = sampled
        releaseBatch(existing.batchID)
      } else {
        effectiveFrom = previous
      }

      retainBatch(batchID)
      activeAnimations[key] = ActiveAnimation(
        kind: .property(from: effectiveFrom, to: current),
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
        fireOrDeferCompletion(closure)
      }
    } else {
      batchRefCounts[batchID] = newCount
    }
  }

  private func fireOrDeferCompletion(_ completion: @escaping @Sendable () -> Void) {
    guard isFrameHeadTransactionActive else {
      completion()
      return
    }
    deferredFrameHeadCompletions.append(completion)
  }

  /// Applies interpolated values to the resolved tree for the given
  /// timestamp.  Returns a tick result describing scheduling needs.
  package func applyInterpolations(
    to tree: inout ResolvedNode,
    at timestamp: MonotonicInstant
  ) -> AnimationTickResult {
    guard
      !activeAnimations.isEmpty
        || !removingIdentities.isEmpty
        || !pendingEmptyBatchCompletions.isEmpty
    else {
      lastTickResult = AnimationTickResult()
      return lastTickResult
    }

    var keysToRemove: [AnimationKey] = []
    var redrawIdentities: Set<Identity> = []
    var latestDeadline: MonotonicInstant = timestamp
    var hasPendingWork = false

    // Build per-identity interpolated value maps for fast tree walk.
    var interpolated: [Identity: [AnimatableSlot: AnyAnimatable]] = [:]

    // Record the batches that completed animations belong to so we can
    // release their ref counts in a second pass (after this iteration
    // closes).  Releasing during the iteration would mutate
    // activeAnimations and invalidate the dictionary traversal.
    var completedBatches: [AnimationBatchID] = []

    // Walk every active animation regardless of scope.  Property
    // scopes are sampled here and write into ``interpolated`` for
    // application by ``applyInterpolatedValues`` below.  Placed-level
    // scopes (insertion offset, matched geometry) only need the run
    // loop to keep ticking on this pass — their actual evaluation +
    // translation runs inside ``applyPlacedOverlays``, and we must
    // not double-evaluate stateful CustomAnimation curves here.
    for (key, animation) in activeAnimations {
      switch animation.kind {
      case .property(let from, let to):
        guard let anim = registeredAnimations[animation.animationBox] else {
          keysToRemove.append(key)
          if let batchID = animation.batchID { completedBatches.append(batchID) }
          continue
        }
        let elapsed = animation.startTime.duration(to: timestamp)
        var state = animation.customState
        let evaluated = anim.evaluate(elapsed: elapsed, state: &state)
        // Store the updated custom state back on the active animation
        // so the next tick carries user bookkeeping forward.
        activeAnimations[key]?.customState = state

        guard let progress = evaluated else {
          // Animation complete — snap to final value and purge.
          interpolated[key.identity, default: [:]][propertySlot(for: key)] = to
          keysToRemove.append(key)
          if let batchID = animation.batchID { completedBatches.append(batchID) }
          redrawIdentities.insert(key.identity)
          continue
        }
        let value = interpolate(from: from, to: to, progress: progress)
        interpolated[key.identity, default: [:]][propertySlot(for: key)] = value
        redrawIdentities.insert(key.identity)
        latestDeadline = timestamp.advanced(by: frameInterval)
        hasPendingWork = true

      case .insertionOffset, .matchedGeometry:
        // Placed-level scopes don't read or write the resolved tree
        // here.  Their kind payload only mutates the placed tree
        // inside ``applyPlacedOverlays``, which advances the
        // animation's custom state and releases the entry on
        // completion.  This pass simply marks the loop as having
        // pending work so the scheduler keeps ticking.  Don't call
        // ``evaluate(elapsed:state:)`` on the registered Animation
        // here — that would double-evaluate stateful CustomAnimation
        // curves once per frame (this loop + applyPlacedOverlays).
        hasPendingWork = true
        if latestDeadline == timestamp {
          latestDeadline = timestamp.advanced(by: frameInterval)
        }
        redrawIdentities.insert(key.identity)
      }
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
        var state = entry.customState
        let evaluated = anim.evaluate(elapsed: elapsed, state: &state)
        // Write the updated custom state back so the next tick of
        // the exit transition carries user bookkeeping forward
        // (matches the active-animation tick loop pattern).
        removingIdentities[identity]?.customState = state
        if let progress = evaluated {
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
        redrawIdentities.insert(identity)
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
      redrawIdentities.insert(identity)
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

    // Drain stranded `withAnimation` completions whose target time
    // has elapsed.  Any batch whose resolve pass found no animatable
    // property to retain was parked here by
    // ``scheduleStrandedBatchDrains``; we fire its completion once
    // the wall-clock has caught up to the animation's nominal
    // duration.  The closure is removed in a single pass so the same
    // drain can't double-fire across subsequent ticks.
    if !pendingEmptyBatchCompletions.isEmpty {
      var drainedBatchIDs: [AnimationBatchID] = []
      for (batchID, deadline) in pendingEmptyBatchCompletions {
        if deadline <= timestamp {
          drainedBatchIDs.append(batchID)
          continue
        }
        // Still in flight — keep the run loop ticking until its
        // deadline arrives.  Adopt the earliest still-pending drain
        // deadline so the scheduler wakes exactly when needed.
        hasPendingWork = true
        if latestDeadline == timestamp || deadline < latestDeadline {
          latestDeadline = deadline
        }
      }
      for batchID in drainedBatchIDs {
        pendingEmptyBatchCompletions.removeValue(forKey: batchID)
        if let closure = completionClosures.removeValue(forKey: batchID) {
          fireOrDeferCompletion(closure)
        }
      }
    }

    let result = AnimationTickResult(
      hasPendingWork: hasPendingWork,
      nextDeadline: hasPendingWork ? latestDeadline : nil,
      redrawIdentities: redrawIdentities
    )
    lastTickResult = result
    return result
  }

  /// Extracts the ``AnimatableSlot`` from a property-scoped key.
  /// Traps when called on a non-property scope — every caller filters
  /// on ``AnimationKind.property`` first, so a non-property key
  /// reaching this helper is a controller bug.
  private func propertySlot(for key: AnimationKey) -> AnimatableSlot {
    guard case .property(let slot) = key.scope else {
      preconditionFailure(
        "propertySlot(for:) called on non-property key scope=\(key.scope)"
      )
    }
    return slot
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
    interpolated: [Identity: [AnimatableSlot: AnyAnimatable]]
  ) -> ResolvedNode {
    var node = tree
    if let values = interpolated[node.identity] {
      for (slot, value) in values {
        applyValue(&node, slot: slot, value: value)
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
    slot: AnimatableSlot,
    value: AnyAnimatable
  ) {
    switch slot {
    case .opacity:
      guard let opacity = value.unwrap(as: Double.self) else { return }
      var drawMetadata = node.drawMetadata
      drawMetadata.baseStyle.explicitOpacity = opacity
      node.drawMetadata = drawMetadata

    case .foregroundShapeStyle:
      guard let style = unwrapShapeStyle(value) else { return }
      var drawMetadata = node.drawMetadata
      drawMetadata.baseStyle.foregroundStyle = style
      node.drawMetadata = drawMetadata

    case .backgroundShapeStyle:
      guard let style = unwrapShapeStyle(value) else { return }
      var drawMetadata = node.drawMetadata
      drawMetadata.baseStyle.backgroundStyle = style
      node.drawMetadata = drawMetadata

    case .borderShapeStyle:
      guard let style = unwrapShapeStyle(value) else { return }
      var drawMetadata = node.drawMetadata
      drawMetadata.borderShapeStyle = style
      node.drawMetadata = drawMetadata

    case .borderBlendPhase:
      guard let phase = value.unwrap(as: Double.self) else { return }
      // Replace only the phase; all other border fields (set, fg, bg,
      // blend, sides) stay identical.  Uses the
      // preserving-derived-state helper because the shape/variant is
      // unchanged — we just rotate the gradient start.
      if case .border(
        let set,
        let placement,
        let foreground,
        let background,
        let blend,
        _,
        let sides
      ) = node.layoutBehavior {
        node.setLayoutBehaviorPreservingDerivedState(
          .border(
            set,
            placement: placement,
            foreground: foreground,
            background: background,
            blend: blend,
            blendPhase: phase,
            sides: sides
          )
        )
      }

    case .padding:
      guard let insets = value.unwrap(as: EdgeInsets.self) else { return }
      if case .padding = node.layoutBehavior {
        node.setLayoutBehaviorPreservingDerivedState(.padding(insets))
      }

    case .offset:
      guard let pair = value.unwrap(as: AnimatablePair<Int, Int>.self)
      else { return }
      if case .offset = node.layoutBehavior {
        node.setLayoutBehaviorPreservingDerivedState(
          .offset(x: pair.first, y: pair.second)
        )
      }

    case .position:
      guard let pair = value.unwrap(as: AnimatablePair<Int, Int>.self)
      else { return }
      if case .position = node.layoutBehavior {
        node.setLayoutBehaviorPreservingDerivedState(
          .position(x: pair.first, y: pair.second)
        )
      }

    case .frameWidth:
      guard let width = value.unwrap(as: Int.self) else { return }
      applyFrameWidth(width, to: &node)

    case .frameHeight:
      guard let height = value.unwrap(as: Int.self) else { return }
      applyFrameHeight(height, to: &node)

    case .shapeFillStyle:
      guard let style = unwrapShapeStyle(value) else { return }
      guard case .shape(let shapePayload) = node.drawPayload,
        case .fill(_, let mode) = shapePayload.operation
      else {
        return
      }
      node.drawPayload = .shape(
        ShapePayload(
          geometry: shapePayload.geometry,
          insetAmount: shapePayload.insetAmount,
          operation: .fill(style: style, mode: mode)
        )
      )

    case .shapeStrokeStyle:
      guard let style = unwrapShapeStyle(value) else { return }
      guard case .shape(let shapePayload) = node.drawPayload,
        case .stroke(_, let strokeStyle, let strokeBorder, let backgroundStyle) =
          shapePayload.operation
      else {
        return
      }
      node.drawPayload = .shape(
        ShapePayload(
          geometry: shapePayload.geometry,
          insetAmount: shapePayload.insetAmount,
          operation: .stroke(
            style: style,
            strokeStyle: strokeStyle,
            strokeBorder: strokeBorder,
            backgroundStyle: backgroundStyle
          )
        )
      )
    }
  }

  private func unwrapShapeStyle(_ value: AnyAnimatable) -> AnyShapeStyle? {
    if let color = value.unwrap(as: Color.self) {
      return .color(color)
    }
    if let linear = value.unwrap(as: LinearGradient.self) {
      return .linearGradient(linear)
    }
    if let radial = value.unwrap(as: RadialGradient.self) {
      return .radialGradient(radial)
    }
    if let pattern = value.unwrap(as: PatternFill.self) {
      return .patternFill(pattern)
    }
    return nil
  }

  private func applyFrameWidth(_ width: Int, to node: inout ResolvedNode) {
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
  }

  private func applyFrameHeight(_ height: Int, to node: inout ResolvedNode) {
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

  /// Samples the current interpolated value of a property-scoped
  /// animation at `timestamp`.  Returns `nil` for non-property kinds —
  /// the placed-level scopes (insertion offset, matched geometry)
  /// produce translation deltas rather than ``AnyAnimatable`` values
  /// and don't participate in the property retarget path.
  ///
  /// The custom-state writeback is intentionally discarded: the only
  /// caller (``sampleCurrentValue(for:at:)`` from the retarget /
  /// insertion paths) immediately releases the existing animation
  /// after sampling, so the advanced state would be thrown away on
  /// the next line anyway.  If a future caller needs to keep the
  /// animation alive after sampling, this helper should be split.
  private func sample(
    _ animation: ActiveAnimation,
    at timestamp: MonotonicInstant
  ) -> AnyAnimatable? {
    guard case .property(let from, let to) = animation.kind else {
      return nil
    }
    guard let anim = registeredAnimations[animation.animationBox] else {
      return nil
    }
    let elapsed = animation.startTime.duration(to: timestamp)
    var state = animation.customState
    guard let progress = anim.evaluate(elapsed: elapsed, state: &state) else {
      return to
    }
    return interpolate(from: from, to: to, progress: progress)
  }

  private func interpolate(
    from: AnyAnimatable,
    to: AnyAnimatable,
    progress: Double
  ) -> AnyAnimatable {
    // Snap to target on type mismatch — the controller should never
    // produce a slot animation where the types differ
    // (``diffAndEnqueue`` doesn't enqueue in that case), but
    // belt-and-suspenders here.
    from.interpolated(to: to, progress: progress) ?? to
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
    previousMatchedGeometryBounds.removeAll(keepingCapacity: true)
    previousMatchedKeyIdentities.removeAll(keepingCapacity: true)
    activeAnimations.removeAll(keepingCapacity: true)
    registeredAnimations.removeAll(keepingCapacity: true)
    completionClosures.removeAll(keepingCapacity: true)
    batchRefCounts.removeAll(keepingCapacity: true)
    pendingEmptyBatchCompletions.removeAll(keepingCapacity: true)
    transitionsByIdentity.removeAll(keepingCapacity: true)
    previousTransitionsByIdentity.removeAll(keepingCapacity: true)
    pendingTransitionsByIdentity.removeAll(keepingCapacity: true)
    removingIdentities.removeAll(keepingCapacity: true)
    previousIdentities.removeAll(keepingCapacity: true)
    lastTickResult = .init()
    isFrameHeadTransactionActive = false
    deferredFrameHeadCompletions.removeAll(keepingCapacity: true)
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
