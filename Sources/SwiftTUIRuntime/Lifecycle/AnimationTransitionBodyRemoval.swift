@_spi(Testing) package import SwiftTUICore
import SwiftTUIViews

/// The body channel of a removal in flight.
///
/// A transition with a body removes a view by moving from the state on screen
/// to the body of its `.didDisappear` phase. The departing content was torn
/// down when the removal started, so the body is evaluated outside the graph
/// around a stand-in for the content
/// (``TransitionBodyRegistration/resolve(phase:contentSize:)``), and the
/// frozen placed content is put where each stand-in lands.
///
/// This value is what the removal entry keeps for that: the `.didDisappear`
/// body as a resolved tree, the frozen content, and the identities whose
/// property animations the removal owns. Those animations are ordinary
/// `(identity, slot)` entries of the controller. Their samples are written
/// into ``samples`` instead of the live tree, which no longer holds those
/// identities. The value is plain `Sendable` data, so it rides the controller
/// checkpoint and the per-frame draft like the rest of a ``RemovalEntry``.
package struct RemovalBodyState: Sendable {
  /// The identity of the transition root: the view the body emitted that the
  /// removal is keyed on. The composed tree replaces this node inside the
  /// frozen placed snapshot of the removal.
  package var rootIdentity: Identity
  /// The body of the `.didDisappear` phase at the transition root, with a
  /// stand-in where each placement of the content is. Its slots hold the
  /// values the removal ends at.
  package var workingRoot: ResolvedNode
  /// The placed rect the transition root had on screen. The working tree is
  /// laid out at its origin under its size.
  package var rootRect: CellRect
  /// The z-index the transition root was placed with.
  package var rootZIndex: Double
  /// The frozen placed content for each stand-in of the working tree, keyed
  /// by the stand-in's identity.
  package var contents: [Identity: PlacedNode]
  /// The frozen placed contents in tree order, for a stand-in that only
  /// appears once the working tree is laid out.
  package var orderedContents: [PlacedNode]
  /// The foreground style and the tint the body hands to the content in the
  /// `.didDisappear` phase, for each view of the frozen content that inherits
  /// them. The views of the content read both from the environment, so the
  /// body's values land on them and not on a wrapper.
  package var contentStyles: [Identity: RemovalContentStyle]
  /// The identities whose property animations this removal owns: the views
  /// of the working tree that were on screen, and the content views in
  /// ``contentStyles`` that animate.
  package var ownedIdentities: Set<Identity>
  /// The owned animations the removal itself started or retargeted. The
  /// removal lasts while one of them runs. An owned animation that was
  /// already in flight toward a value the removal does not change (the rest
  /// of an insertion, a view of the body that pulses forever) plays on in the
  /// overlay and does not hold it: it ends with the removal.
  package var drivingKeys: Set<AnimationKey> = []
  /// Whether the transition also has built-in effects. A removal without
  /// them has no curve of its own and ends when its last owned animation
  /// does.
  package var hasEffectChannel: Bool
  /// The values the owned animations sampled on the current frame, by
  /// identity. A slot without a sample shows the value of ``workingRoot``.
  package var samples: [Identity: [AnimatableSlot: AnyAnimatable]] = [:]
}

/// The inherited styles a removal body gives one view of the frozen content.
package struct RemovalContentStyle: Sendable {
  package var foregroundStyle: AnyShapeStyle?
  package var tintStyle: AnyShapeStyle?
}

/// Plans and draws the body channel of a removal transition.
///
/// The counterpart of ``AnimationTransitionBodyInsertion``. Planning runs
/// once, on the frame the view leaves: it finds the transition root and the
/// content inside the frozen subtree, evaluates the `.didDisappear` body, and
/// lists the slots that animate from the value on screen. Composition runs on
/// every frame of the removal, on the main actor before the frame tail: it
/// lays the body out at the frozen rect and puts the frozen content under it,
/// so the tail receives a finished placed tree.
///
/// Rules that follow from the working tree being the `.didDisappear` body:
///
/// - A value that cannot interpolate shows its `.didDisappear` value from the
///   first frame of the removal and holds it.
/// - A view only the `.didDisappear` phase has is drawn from the first frame.
///   Nothing it declares runs: the scope has no graph and no registry. That
///   is reported when the view declares handlers (``Plan/issues``).
/// - A view only the identity phase has is gone on the first frame.
/// - Each placement of `content` shows the frozen content.
/// - The content was resolved before the removal and is not resolved again.
///   An environment value the `.didDisappear` phase writes for it does not
///   reach it, which is reported. A foreground style and a tint are applied
///   when a view is drawn, so those two do reach it, and animate.
enum AnimationTransitionBodyRemoval {
  /// What a removal that plays its body starts with.
  struct Plan {
    var state: RemovalBodyState
    /// For each owned identity, the slots on screen and the slots of the
    /// `.didDisappear` phase. The controller enqueues the differences.
    var changes: [AnimationTransitionBodyInsertion.SlotChange]
    /// What the removal cannot honour: handlers on a view only the
    /// `.didDisappear` phase has, and environment values that phase writes
    /// for the content.
    var issues: [RuntimeIssue] = []
  }

  enum Outcome {
    case plays(Plan)
    /// The body cannot be drawn around the departing content. The removal
    /// shows the frozen view without it.
    case unavailable(RuntimeIssue)
  }

  /// One placement of the content in the frozen subtree.
  private struct FrozenContent {
    /// The boundary node, which carries the environment the body handed to
    /// the content in the identity phase.
    var boundary: ResolvedNode
    var content: ResolvedNode
    var placed: PlacedNode
  }

  /// A phase of the body, flattened.
  private struct Flattened {
    var roots: [Identity] = []
    var wrappers: [ResolvedNode] = []
    var standIns: [ResolvedNode] = []
  }

  /// Plans the body channel for the removal of the transition root at
  /// `rootIdentity`.
  ///
  /// - Parameters:
  ///   - frozenResolved: the canonical resolved subtree the removal injects.
  ///   - frozenPlaced: the placed subtree at the same node, as drawn on the
  ///     previous frame.
  ///   - previousSnapshots: the slots of every view of the previous frame.
  ///   - effectOwnsRootOpacity: whether the transition's built-in effects
  ///     fade the departing view. They then own the opacity of the root.
  @MainActor
  static func plan(
    of registration: TransitionBodyRegistration,
    rootIdentity: Identity,
    frozenResolved: ResolvedNode,
    frozenPlaced: PlacedNode,
    previousSnapshots: [Identity: AnimatableSnapshot],
    hasEffectChannel: Bool,
    effectOwnsRootOpacity: Bool
  ) -> Outcome {
    guard
      let frozenRoot = AnimationTreeQueries.findResolvedSubtree(
        in: frozenResolved, identity: rootIdentity),
      let frozenRootPlaced = AnimationTreeQueries.findPlacedSubtree(
        in: frozenPlaced, identity: rootIdentity)
    else {
      return .unavailable(contentNotFoundIssue(for: registration))
    }

    // The content of each boundary the host registered that lies under this
    // root. A body with several roots has the boundaries of all of them.
    var frozenContents: [FrozenContent] = []
    for boundaryIdentity in registration.boundaryIdentities {
      guard
        let boundary = AnimationTreeQueries.findResolvedSubtree(
          in: frozenRoot, identity: boundaryIdentity),
        boundary.kind == .view(.transitionContent),
        let content = boundary.children.first,
        let placedBoundary = AnimationTreeQueries.findPlacedSubtree(
          in: frozenRootPlaced, identity: boundaryIdentity),
        let placed = placedBoundary.children.first(where: { $0.identity == content.identity })
      else { continue }
      frozenContents.append(FrozenContent(boundary: boundary, content: content, placed: placed))
    }
    // A body that places `content` inside a view that resolves during layout
    // has no registered boundary: the content is somewhere in that view, and
    // nothing here can tell where.
    if frozenContents.isEmpty, registration.boundaryIdentities.isEmpty,
      containsLayoutRealizedStructure(frozenRoot)
    {
      return .unavailable(contentNotFoundIssue(for: registration))
    }

    let frozenSizes = Dictionary(
      frozenContents.map { ($0.content.identity, $0.placed.bounds.size) },
      uniquingKeysWith: { first, _ in first })
    let tree = registration.resolve(phase: .didDisappear) { frozenSizes[$0] ?? .zero }
    // The identity phase evaluated the same way, for the checks below that
    // compare two phases. The tree on screen came through the graph and this
    // one does not, so a difference between those two is not evidence of a
    // difference between the phases. It is evaluated only when a check has
    // something to confirm.
    var evaluatedIdentityPhase: Flattened?
    func identityPhase() -> Flattened {
      if let evaluatedIdentityPhase { return evaluatedIdentityPhase }
      var flattened = Flattened()
      for root in registration.resolve(phase: .identity).roots {
        flattened.roots.append(root.identity)
        collect(root, into: &flattened)
      }
      evaluatedIdentityPhase = flattened
      return flattened
    }
    var workingRoot = tree.roots.first { $0.identity == rootIdentity }
    if workingRoot == nil {
      // The roots of this phase have other identities than those on screen.
      // Pair them by position among the roots of the identity phase.
      if let index = identityPhase().roots.firstIndex(of: rootIdentity),
        tree.roots.indices.contains(index)
      {
        workingRoot = tree.roots[index]
      }
    }
    guard var workingRoot else {
      return .unavailable(contentNotFoundIssue(for: registration))
    }

    var flattened = Flattened()
    collect(workingRoot, into: &flattened)

    // Pair each stand-in with frozen content: the content at the same
    // identity, else the content at the same position, else the last one.
    // So a body that places `content` twice shows it twice.
    var contents: [Identity: PlacedNode] = [:]
    var pairedContents: [(standIn: ResolvedNode, frozen: FrozenContent)] = []
    var resized: [Identity: CellSize] = [:]
    for (index, standIn) in flattened.standIns.enumerated() {
      guard !frozenContents.isEmpty else {
        return .unavailable(contentNotFoundIssue(for: registration))
      }
      let frozen =
        frozenContents.first { $0.content.identity == standIn.identity }
        ?? frozenContents[min(index, frozenContents.count - 1)]
      contents[standIn.identity] = frozen.placed
      pairedContents.append((standIn, frozen))
      if standIn.intrinsicSize != frozen.placed.bounds.size {
        resized[standIn.identity] = frozen.placed.bounds.size
      }
    }
    if !resized.isEmpty {
      workingRoot = resizingStandIns(in: workingRoot, to: resized)
    }

    // A modifier applied outside the transition stamped the root after the
    // body did. Keep what it stamped: this tree is the body alone.
    if workingRoot.identity == rootIdentity, let stamps = registration.rootStamps[rootIdentity] {
      carryOuterStamps(onto: &workingRoot, onScreen: frozenRoot, body: stamps)
      flattened = Flattened()
      collect(workingRoot, into: &flattened)
    }

    // Every view of the working tree that was on screen animates from the
    // value it shows to its value in this phase.
    let frozenIdentities = AnimationTreeQueries.collectIdentities(in: frozenRoot)
    var owned: Set<Identity> = []
    var changes: [AnimationTransitionBodyInsertion.SlotChange] = []
    for wrapper in flattened.wrappers {
      guard frozenIdentities.contains(wrapper.identity),
        var displayed = previousSnapshots[wrapper.identity]
      else { continue }
      var target = AnimatableSnapshot.extract(from: wrapper)
      if effectOwnsRootOpacity, wrapper.identity == rootIdentity {
        // The effect channel fades the departing view to nothing, from the
        // opacity on screen. The root keeps the opacity it has, so the
        // product is continuous and ends at zero.
        displayed[.opacity] = nil
        target[.opacity] = nil
      }
      owned.insert(wrapper.identity)
      changes.append(
        .init(identity: wrapper.identity, viewNodeID: nil, previous: displayed, current: target))
    }
    if effectOwnsRootOpacity, workingRoot.identity == rootIdentity {
      var drawMetadata = workingRoot.drawMetadata
      drawMetadata.baseStyle.explicitOpacity = previousSnapshots[rootIdentity]?.opacity
      workingRoot.drawMetadata = drawMetadata
    }

    var contentStyles: [Identity: RemovalContentStyle] = [:]
    for (standIn, frozen) in pairedContents {
      appendInheritedStyles(
        from: standIn, to: frozen, previousSnapshots: previousSnapshots,
        styles: &contentStyles, owned: &owned, changes: &changes)
    }

    var issues: [RuntimeIssue] = []
    // A view of this phase that was not on screen is drawn and nothing more.
    // Its handlers never run, which would be a silent no-op.
    let unmounted = flattened.wrappers.filter {
      !frozenIdentities.contains($0.identity) && declaresHandlers($0)
    }
    if !unmounted.isEmpty {
      let identityIdentities = Set(identityPhase().wrappers.map(\.identity))
      let removalOnly = unmounted.filter { !identityIdentities.contains($0.identity) }
      if !removalOnly.isEmpty {
        issues.append(handlersIgnoredIssue(for: registration, viewCount: removalOnly.count))
      }
    }
    // The content was resolved under the environment of the identity phase
    // and is drawn as it was. An environment value this phase writes for it
    // changes nothing, which would be a silent no-op too.
    var ignoredKeys: Set<String> = []
    for (standIn, frozen) in pairedContents {
      let onScreen = unappliedEnvironmentKeys(
        of: standIn.environmentSnapshot, against: frozen.boundary.environmentSnapshot)
      guard !onScreen.isEmpty else { continue }
      if let identityStandIn = identityPhase().standIns.first(where: {
        $0.identity == standIn.identity
      }) {
        ignoredKeys.formUnion(
          unappliedEnvironmentKeys(
            of: standIn.environmentSnapshot, against: identityStandIn.environmentSnapshot))
      } else {
        ignoredKeys.formUnion(onScreen)
      }
    }
    if !ignoredKeys.isEmpty {
      issues.append(environmentIgnoredIssue(for: registration, keys: ignoredKeys.sorted()))
    }

    return .plays(
      Plan(
        state: RemovalBodyState(
          rootIdentity: rootIdentity,
          workingRoot: workingRoot,
          rootRect: frozenRootPlaced.bounds,
          rootZIndex: frozenRootPlaced.zIndex,
          contents: contents,
          orderedContents: frozenContents.map(\.placed),
          contentStyles: contentStyles,
          ownedIdentities: owned,
          hasEffectChannel: hasEffectChannel
        ),
        changes: changes,
        issues: issues
      )
    )
  }

  /// The frozen placed snapshot of a removal with the transition root
  /// replaced by the body as it shows on the current frame.
  ///
  /// The working tree takes the frame's samples, is measured under the size
  /// the root had on screen and placed at the root's origin. Each stand-in is
  /// replaced by its frozen content, moved to the stand-in's origin. The
  /// content keeps its frozen size and layout: a body that gives it another
  /// size moves or crops it and does not lay it out again.
  @MainActor
  static func compose(_ body: RemovalBodyState, in frozenTarget: PlacedNode) -> PlacedNode {
    var presented = body.workingRoot
    if !body.samples.isEmpty {
      var visitedNodeCount = 0
      var appliedIdentities: Set<Identity> = []
      presented = AnimationPropertyValueApplication.applyInterpolatedValues(
        tree: presented,
        interpolatedByNodeID: [:],
        interpolatedIdentityByNodeID: [:],
        interpolatedByIdentity: body.samples,
        parentByIdentity: [:],
        childIndexByIdentity: [:],
        visitedNodeCount: &visitedNodeCount,
        appliedIdentities: &appliedIdentities
      )
    }
    let engine = LayoutEngine()
    let measured = engine.measure(
      presented,
      proposal: ProposedSize(width: body.rootRect.size.width, height: body.rootRect.size.height))
    var placed = engine.place(presented, measured: measured, origin: body.rootRect.origin)
    placed.zIndex = body.rootZIndex
    var unmatched = 0
    placed = graftingContents(of: body, into: placed, unmatched: &unmatched)
    var result = frozenTarget
    return replace(body.rootIdentity, in: &result, with: placed) ? result : frozenTarget
  }

  /// The slot changes that take a view inserted again during its removal
  /// from the state the removal shows to the live identity body.
  ///
  /// Each view of the removal's working tree that the new tree also has
  /// starts from its `.didDisappear` value. A slot whose animation is still
  /// in flight is retargeted by the controller from its sample, with its
  /// velocity. The content views that took an inherited style start from
  /// that style.
  static func reinsertionChanges(
    from body: RemovalBodyState,
    insertedIdentity: Identity,
    in frame: AnimationTransitionBodyInsertion.Frame
  ) -> [AnimationTransitionBodyInsertion.SlotChange] {
    var flattened = Flattened()
    collect(body.workingRoot, into: &flattened)
    var changes: [AnimationTransitionBodyInsertion.SlotChange] = []
    for wrapper in flattened.wrappers {
      guard let live = frame.snapshots[wrapper.identity],
        AnimationTransitionBodyInsertion.animates(wrapper.identity, in: frame),
        AnimationTransitionBodyInsertion.isInside(
          wrapper.identity, subtreeOf: insertedIdentity, in: frame)
      else { continue }
      changes.append(
        .init(
          identity: wrapper.identity,
          viewNodeID: frame.nodeIDs[wrapper.identity],
          previous: AnimatableSnapshot.extract(from: wrapper),
          current: live
        )
      )
    }
    for (identity, style) in body.contentStyles {
      guard let live = frame.snapshots[identity],
        AnimationTransitionBodyInsertion.animates(identity, in: frame),
        AnimationTransitionBodyInsertion.isInside(identity, subtreeOf: insertedIdentity, in: frame)
      else { continue }
      var displayed = live
      if let foreground = AnimatableSnapshot.extractAnimatableShapeStyle(
        from: style.foregroundStyle), live[.foregroundShapeStyle] != nil
      {
        displayed[.foregroundShapeStyle] = foreground
      }
      if let tint = AnimatableSnapshot.extractAnimatableShapeStyle(from: style.tintStyle),
        live[.tintShapeStyle] != nil
      {
        displayed[.tintShapeStyle] = tint
      }
      changes.append(
        .init(
          identity: identity, viewNodeID: frame.nodeIDs[identity], previous: displayed,
          current: live))
    }
    return changes
  }

  // MARK: - Planning helpers

  private static func collect(_ node: ResolvedNode, into flattened: inout Flattened) {
    if node.kind == .view(.transitionContentStandIn) {
      flattened.standIns.append(node)
      return
    }
    flattened.wrappers.append(node)
    for child in node.children {
      collect(child, into: &flattened)
    }
  }

  private static func resizingStandIns(
    in node: ResolvedNode,
    to sizes: [Identity: CellSize]
  ) -> ResolvedNode {
    var node = node
    if node.kind == .view(.transitionContentStandIn) {
      if let size = sizes[node.identity] { node.intrinsicSize = size }
      return node
    }
    node.setChildrenPreservingDerivedState(
      node.children.map { resizingStandIns(in: $0, to: sizes) })
    return node
  }

  /// Keeps on the root of a phase evaluated outside the graph what modifiers
  /// outside the transition stamped on the root on screen.
  ///
  /// `.transition(T()).clipShape(shape)` resolves the body and then adds the
  /// clip to the body's root node, so the node on screen is the body's stamps
  /// merged with the outer ones. A scratch phase comes from the body alone.
  /// `body` is what the body left on the root in the identity phase; whatever
  /// the root on screen has beyond that came from outside, and is merged into
  /// `root` the way the modifiers merged it: an opacity multiplies, clip
  /// shapes and draw effects append. For the rest, a value the body does not
  /// change between its phases takes what is on screen.
  ///
  /// The insertion uses it too, on the root of the `.willAppear` phase: a
  /// clip path of the body interpolates only against a mask with the same
  /// number of shapes.
  static func carryOuterStamps(
    onto root: inout ResolvedNode,
    onScreen: ResolvedNode,
    body: TransitionBodyRootStamps
  ) {
    let live = onScreen.drawMetadata
    if live != body.drawMetadata {
      var metadata = root.drawMetadata
      if let liveOpacity = live.baseStyle.explicitOpacity,
        liveOpacity != body.drawMetadata.baseStyle.explicitOpacity
      {
        let bodyOpacity = body.drawMetadata.baseStyle.explicitOpacity ?? 1
        if bodyOpacity != 0 {
          metadata.baseStyle.explicitOpacity =
            (metadata.baseStyle.explicitOpacity ?? 1) * (liveOpacity / bodyOpacity)
        }
      }
      let bodyClips = body.drawMetadata.shapeClips
      if live.shapeClips.count > bodyClips.count,
        Array(live.shapeClips.prefix(bodyClips.count)) == bodyClips
      {
        metadata.shapeClips += live.shapeClips[bodyClips.count...]
      }
      // Everything but the two that compound.
      func remainder(_ metadata: DrawMetadata) -> DrawMetadata {
        var metadata = metadata
        metadata.baseStyle.explicitOpacity = nil
        metadata.shapeClips = []
        return metadata
      }
      if remainder(live) != remainder(body.drawMetadata),
        remainder(metadata) == remainder(body.drawMetadata)
      {
        var carried = live
        carried.baseStyle.explicitOpacity = metadata.baseStyle.explicitOpacity
        carried.shapeClips = metadata.shapeClips
        metadata = carried
      }
      root.drawMetadata = metadata
    }
    let liveEffects = onScreen.drawEffects.ordered
    let bodyEffects = body.drawEffects.ordered
    if liveEffects.count > bodyEffects.count,
      Array(liveEffects.prefix(bodyEffects.count)) == bodyEffects
    {
      root.drawEffects.ordered += liveEffects[bodyEffects.count...]
    }
    if onScreen.surfaceComposition != body.surfaceComposition,
      root.surfaceComposition == body.surfaceComposition
    {
      root.surfaceComposition = onScreen.surfaceComposition
    }
    if onScreen.layoutMetadata != body.layoutMetadata, root.layoutMetadata == body.layoutMetadata {
      root.layoutMetadata = onScreen.layoutMetadata
    }
    if onScreen.matchedGeometry != body.matchedGeometry,
      root.matchedGeometry == body.matchedGeometry
    {
      root.matchedGeometry = onScreen.matchedGeometry
    }
  }

  private static func containsLayoutRealizedStructure(_ node: ResolvedNode) -> Bool {
    if node.layoutRealizedContent != nil || node.indexedChildSource != nil { return true }
    return node.children.contains(where: containsLayoutRealizedStructure)
  }

  /// Whether a view declares something that only a mounted view runs: a
  /// lifecycle handler, a task, a change observer, or an interaction.
  private static func declaresHandlers(_ node: ResolvedNode) -> Bool {
    if !node.lifecycleMetadata.isEmpty || node.lifecycleMetadata.changeObservationCount > 0 {
      return true
    }
    if node.semanticMetadata.focusParticipation == .included
      || node.semanticMetadata.participatesInPointerHitTesting
    {
      return true
    }
    let handlers = node.handlerInventory
    return !handlers.actionIdentities.isEmpty || !handlers.keyHandlerIdentities.isEmpty
      || !handlers.commandScopes.isEmpty || !handlers.dropScopes.isEmpty
      || !handlers.gestureRouteIdentities.isEmpty
  }

  /// The names of the environment keys whose values differ between what a
  /// phase hands to the content and `other`, leaving out the two the removal
  /// applies to frozen content: a foreground style and a tint that the phase
  /// sets.
  private static func unappliedEnvironmentKeys(
    of environment: EnvironmentSnapshot,
    against other: EnvironmentSnapshot
  ) -> [String] {
    guard environment != other else { return [] }
    return environment.differingValueDebugNames(from: other).compactMap { name in
      // The debug name of a private key carries a context address. The last
      // component is the stable part.
      let key = name.split(separator: ".").last.map(String.init) ?? name
      if key == "ForegroundStyleKey", environment.style.foregroundStyle != nil { return nil }
      if key == "TintStyleKey", environment.style.tintStyle != nil { return nil }
      return key
    }
  }

  /// Records the foreground style and the tint the `.didDisappear` body hands
  /// to the content, for the views of the frozen content that inherit them.
  ///
  /// The boundary carries what the body handed to the content in the identity
  /// phase, and the stand-in carries it for this phase. A view of the content
  /// that still sees the boundary's value, and sets none of its own, takes
  /// the stand-in's. It animates there when both values interpolate, and
  /// shows the new value at once when they do not.
  private static func appendInheritedStyles(
    from standIn: ResolvedNode,
    to frozen: FrozenContent,
    previousSnapshots: [Identity: AnimatableSnapshot],
    styles: inout [Identity: RemovalContentStyle],
    owned: inout Set<Identity>,
    changes: inout [AnimationTransitionBodyInsertion.SlotChange]
  ) {
    let liveForeground = frozen.boundary.environmentSnapshot.style.foregroundStyle
    let liveTint = frozen.boundary.environmentSnapshot.style.tintStyle
    let targetForeground = standIn.environmentSnapshot.style.foregroundStyle
    let targetTint = standIn.environmentSnapshot.style.tintStyle
    let foregroundChanges = targetForeground != nil && targetForeground != liveForeground
    let tintChanges = targetTint != nil && targetTint != liveTint
    guard foregroundChanges || tintChanges else { return }

    var pending = [frozen.content]
    while let node = pending.popLast() {
      pending.append(contentsOf: node.children)
      var style = styles[node.identity] ?? RemovalContentStyle()
      var displayed = AnimatableSnapshot()
      var target = AnimatableSnapshot()
      if foregroundChanges,
        AnimatableSnapshot.extractAnimatableShapeStyle(
          from: node.drawMetadata.baseStyle.foregroundStyle) == nil,
        node.environmentSnapshot.style.foregroundStyle == liveForeground
      {
        style.foregroundStyle = targetForeground
        if let shown = previousSnapshots[node.identity]?[.foregroundShapeStyle],
          let end = AnimatableSnapshot.extractAnimatableShapeStyle(from: targetForeground)
        {
          displayed[.foregroundShapeStyle] = shown
          target[.foregroundShapeStyle] = end
        }
      }
      if tintChanges, node.environmentSnapshot.style.tintStyle == liveTint {
        style.tintStyle = targetTint
        if let shown = previousSnapshots[node.identity]?[.tintShapeStyle],
          let end = AnimatableSnapshot.extractAnimatableShapeStyle(from: targetTint)
        {
          displayed[.tintShapeStyle] = shown
          target[.tintShapeStyle] = end
        }
      }
      guard style.foregroundStyle != nil || style.tintStyle != nil else { continue }
      styles[node.identity] = style
      if !target.values.isEmpty {
        owned.insert(node.identity)
        changes.append(
          .init(identity: node.identity, viewNodeID: nil, previous: displayed, current: target))
      }
    }
  }

  // MARK: - Composition helpers

  private static func graftingContents(
    of body: RemovalBodyState,
    into node: PlacedNode,
    unmatched: inout Int
  ) -> PlacedNode {
    if node.kind == .view(.transitionContentStandIn) {
      var content: PlacedNode
      if let matched = body.contents[node.identity] {
        content = matched
      } else if !body.orderedContents.isEmpty {
        // A stand-in that resolved during layout was not there to pair when
        // the removal was planned.
        content = body.orderedContents[min(unmatched, body.orderedContents.count - 1)]
        unmatched += 1
      } else {
        return node
      }
      translateBounds(
        &content,
        dx: SaturatingConversion.subtracting(node.bounds.origin.x, content.bounds.origin.x),
        dy: SaturatingConversion.subtracting(node.bounds.origin.y, content.bounds.origin.y))
      if !body.contentStyles.isEmpty {
        applyContentStyles(of: body, to: &content)
      }
      return content
    }
    guard !node.children.isEmpty else { return node }
    var node = node
    node.children = node.children.map {
      graftingContents(of: body, into: $0, unmatched: &unmatched)
    }
    return node
  }

  private static func applyContentStyles(of body: RemovalBodyState, to node: inout PlacedNode) {
    if let style = body.contentStyles[node.identity] {
      let samples = body.samples[node.identity]
      if let foreground = samples?[.foregroundShapeStyle].flatMap(
        AnimationPropertyValueApplication.unwrapShapeStyle) ?? style.foregroundStyle
      {
        var drawMetadata = node.drawMetadata
        drawMetadata.baseStyle.foregroundStyle = foreground
        node.drawMetadata = drawMetadata
      }
      if let tint = samples?[.tintShapeStyle].flatMap(
        AnimationPropertyValueApplication.unwrapShapeStyle) ?? style.tintStyle
      {
        node.environmentSnapshot.style.tintStyle = tint
      }
    }
    var children = node.children
    for index in children.indices {
      applyContentStyles(of: body, to: &children[index])
    }
    node.children = children
  }

  /// Replaces the first node at `identity`, in tree order, with `replacement`.
  private static func replace(
    _ identity: Identity,
    in node: inout PlacedNode,
    with replacement: PlacedNode
  ) -> Bool {
    if node.identity == identity {
      node = replacement
      return true
    }
    var children = node.children
    for index in children.indices
    where replace(identity, in: &children[index], with: replacement) {
      node.children = children
      return true
    }
    return false
  }

  // MARK: - Issues

  /// The issue for a body whose content cannot be found in the departing
  /// view.
  static func contentNotFoundIssue(for registration: TransitionBodyRegistration) -> RuntimeIssue {
    RuntimeIssue(
      severity: .warning,
      code: .Transition.removalContentNotFound,
      message:
        "The removal of the transition \(registration.transitionTypeDescription) could not "
        + "find where its body placed the content, so the body does not play on removal: the "
        + "view leaves as its built-in effects alone would take it, or at once when the "
        + "transition has none. This happens when the body places content inside a view that "
        + "resolves during layout, such as a GeometryReader or a lazy stack. Place content "
        + "outside such a view, for example with the GeometryReader in a background or an "
        + "overlay of content.",
      identity: registration.identity,
      source: "Transition.body(content:phase:)"
    )
  }

  /// The issue for environment values the `.didDisappear` phase of a body
  /// writes for its content, which the departing content does not see.
  static func environmentIgnoredIssue(
    for registration: TransitionBodyRegistration,
    keys: [String]
  ) -> RuntimeIssue {
    RuntimeIssue(
      severity: .warning,
      code: .Transition.removalEnvironmentIgnored,
      message:
        "The body of the transition \(registration.transitionTypeDescription) gives its "
        + "content other environment values in its didDisappear phase than in its identity "
        + "phase (\(keys.joined(separator: ", "))). The departing content was resolved "
        + "before the removal began and is drawn as it was, so it does not show them. A "
        + "foreground style and a tint are the exceptions. Use a modifier that draws around "
        + "content, such as an opacity, a clip shape or an overlay, or keep the value the "
        + "same in both phases.",
      identity: registration.identity,
      source: "Transition.body(content:phase:)"
    )
  }

  /// The issue for views that exist only in the `.didDisappear` phase of a
  /// body and declare handlers, which a removal never runs.
  static func handlersIgnoredIssue(
    for registration: TransitionBodyRegistration,
    viewCount: Int
  ) -> RuntimeIssue {
    let views = viewCount == 1 ? "a view" : "\(viewCount) views"
    return RuntimeIssue(
      severity: .warning,
      code: .Transition.removalHandlersIgnored,
      message:
        "The body of the transition \(registration.transitionTypeDescription) has \(views) "
        + "in its didDisappear phase that its identity phase does not have, with lifecycle "
        + "handlers, tasks or interaction handlers. A removal draws the body of the "
        + "didDisappear phase without mounting it, so those handlers never run. Keep such "
        + "a view in the identity phase too, or give it no handlers.",
      identity: registration.identity,
      source: "Transition.body(content:phase:)"
    )
  }
}
