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
///
/// A view or a modifier of the body that conforms to `Animatable` animates
/// its `animatableData` too, from what the live view presented to what the
/// `.didDisappear` phase gives it. The removal owns those value animations
/// by site (``valueSites``). Their samples are not written anywhere: the
/// body is evaluated again with them, on every frame the removal draws, and
/// the result replaces ``workingRoot``.
///
/// A removal owns a site only when its root holds the site
/// (``TransitionBodySiteHolders``) and no live view resolves there any more.
/// A body with several roots has a removal for each root that leaves, and a
/// root can leave while the others stay: a site another root holds, or one
/// a view that stayed still resolves, is not this removal's to animate, and
/// the removal leaves it as it is.
package struct RemovalBodyState: Sendable {
  /// The identity of the transition root: the view the body emitted that the
  /// removal is keyed on. The composed tree replaces this node inside the
  /// frozen placed snapshot of the removal.
  package var rootIdentity: Identity
  /// The body of the `.didDisappear` phase at the transition root, with a
  /// stand-in where each placement of the content is. Its slots hold the
  /// values the removal ends at.
  package var workingRoot: ResolvedNode
  var cellPreparations: RemovalCellPreparations?
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
  /// Each placement of the content in the frozen subtree, in tree order: the
  /// boundary the body put around it, the content, and the content as it was
  /// placed. The steps that make a `.didDisappear` body ready to draw read
  /// them, when the removal is planned and on every frame that evaluates the
  /// body again.
  package var frozenContents: [RemovalFrozenContent] = []
  /// The position of the root the removal draws among the roots of the
  /// `.didDisappear` body, when that body has no root at ``rootIdentity``
  /// and the root was paired by position.
  package var fallbackRootIndex: Int? = nil
  /// Whether the transition's built-in effects fade the departing view. The
  /// root of the working tree then keeps ``heldRootOpacity``, the opacity it
  /// had on screen, and the effect channel fades from there.
  package var holdsRootOpacity = false
  package var heldRootOpacity: Double? = nil
  /// The views and the modifiers of the `.didDisappear` body that conform to
  /// `Animatable` and that this removal animates, by site, with the data
  /// that phase gives each: where the site's animation ends. The removal
  /// owns the value animation at each of these keys, as it owns the property
  /// animations of ``ownedIdentities``. Empty for a body with no such view
  /// or modifier, which is then evaluated once, when the removal is planned.
  package var valueSites: [AnimationKey: AnyAnimatable] = [:]
  /// The instant of the frame ``workingRoot`` was last evaluated for. A body
  /// with sites is evaluated at most once a frame.
  package var valueResolveInstant: MonotonicInstant? = nil
  /// The data ``workingRoot`` was last evaluated with, for each site that
  /// was given other data than the `.didDisappear` phase gives it. The body
  /// is evaluated again when this differs from what the sites present.
  package var valueAnswers: [AnimationKey: AnyAnimatable] = [:]

  /// Whether ``workingRoot`` was evaluated with every site at the data the
  /// `.didDisappear` phase gives it. It then needs no further evaluation
  /// until a site presents something else.
  package var valueTreeIsAtRest: Bool { valueAnswers.isEmpty }

  /// `answers` without the entries that give a site the data the phase
  /// gives it anyway: the form ``valueAnswers`` is kept in.
  package func normalizedValueAnswers(
    _ answers: [AnimationKey: AnyAnimatable]
  ) -> [AnimationKey: AnyAnimatable] {
    answers.filter { key, value in valueSites[key] != value }
  }
}

/// The inherited styles a removal body gives one view of the frozen content.
package struct RemovalContentStyle: Sendable {
  package var foregroundStyle: AnyShapeStyle?
  package var tintStyle: AnyShapeStyle?
}

/// One placement of the content in the frozen subtree of a removal.
package struct RemovalFrozenContent: Sendable {
  /// The boundary node, which carries the environment the body handed to
  /// the content in the identity phase.
  package var boundary: ResolvedNode
  package var content: ResolvedNode
  package var placed: PlacedNode
}

/// Plans and draws the body channel of a removal transition.
///
/// The counterpart of ``AnimationTransitionBodyInsertion``. Planning runs
/// once, on the frame the view leaves: it finds the transition root and the
/// content inside the frozen subtree, evaluates the `.didDisappear` body, and
/// lists the slots that animate from the value on screen. Composition runs on
/// every frame the removal draws, on the main actor before the frame tail: it
/// lays the body out at the frozen rect and puts the frozen content under it,
/// so the tail receives a finished placed tree. A body with an `Animatable`
/// view or modifier in it is evaluated again before it is composed, with the
/// data each such site presents on the frame, and takes the steps planning
/// took after its evaluation
/// (``workingTree(from:inputs:fallbackRootIndex:)``). A body with none is
/// evaluated once, when the removal is planned.
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
    /// What each site of ``RemovalBodyState/valueSites`` showed, for the
    /// sites a live view or modifier resolved at. The removal's animation of
    /// a site starts at the data the site presents on the removal frame.
    var liveSites: [AnimationKey: LiveSite] = [:]
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

  /// What one live `Animatable` view or modifier shows.
  struct LiveSite {
    /// The data the site's body last ran with: what the tree on screen was
    /// evaluated with.
    var shown: AnyAnimatable
    /// The data the site presents on the frame being prepared: this frame's
    /// sample of its animation when one is in flight, else its target.
    var presented: AnyAnimatable
  }

  /// What the `Animatable` views and modifiers of the departing body show,
  /// by site. Both answers are `nil` for a site no live view resolved at.
  struct LiveSiteData {
    /// ``LiveSite/shown`` of the site.
    var shown: (AnimationKey) -> AnyAnimatable?
    /// ``LiveSite/presented`` of the site.
    var presented: (AnimationKey) -> AnyAnimatable?
    /// Whether a view of the tree this frame resolved still resolves the
    /// site: a root of the body that stayed while another left. A removal
    /// takes no such site over.
    var staysLive: (AnimationKey) -> Bool

    /// A body none of whose sites is live.
    static var none: LiveSiteData {
      LiveSiteData(shown: { _ in nil }, presented: { _ in nil }, staysLive: { _ in false })
    }
  }

  /// A phase of the body, flattened.
  private struct Flattened {
    var roots: [Identity] = []
    var wrappers: [ResolvedNode] = []
    var standIns: [ResolvedNode] = []
  }

  /// What the steps between an evaluation of the `.didDisappear` body and a
  /// tree that can be drawn read, beside the evaluated body. Each is fixed
  /// when the removal is planned.
  private struct WorkingTreeInputs {
    var rootIdentity: Identity
    /// The transition root as it was on screen, with the stamps of the
    /// modifiers outside the transition.
    var frozenRoot: ResolvedNode
    var frozenContents: [RemovalFrozenContent]
    /// What the body alone left on the root in the identity phase.
    var rootStamps: TransitionBodyRootStamps?
    var holdsRootOpacity: Bool
    var heldRootOpacity: Double?
  }

  /// A `.didDisappear` body made ready to draw.
  private struct WorkingTree {
    /// The root the removal draws, with its stand-ins sized, the stamps of
    /// the modifiers outside the transition, and the opacity a fading effect
    /// holds.
    var root: ResolvedNode
    /// Every node of ``root`` except the content stand-ins, in tree order.
    var wrappers: [ResolvedNode]
    /// Each stand-in with the frozen content it shows.
    var paired: [(standIn: ResolvedNode, frozen: RemovalFrozenContent)]
    /// The frozen placed content by the identity of its stand-in.
    var contents: [Identity: PlacedNode]
    /// The inherited styles this phase hands to the views of the content.
    var contentStyles: [Identity: RemovalContentStyle]
    /// Where ``contentStyles`` came from, one entry for each view and
    /// placement, in the order they were applied.
    var styleApplications: [InheritedStyleApplication]
  }

  /// One inherited style of the `.didDisappear` phase landing on one view of
  /// the frozen content.
  private struct InheritedStyleApplication {
    var identity: Identity
    var foregroundStyle: AnyShapeStyle?
    var tintStyle: AnyShapeStyle?
  }

  /// Plans the body channel for the removal of the transition root at
  /// `rootIdentity`.
  ///
  /// The `.didDisappear` body is evaluated with each `Animatable` view and
  /// modifier in it at the data that site shows on screen
  /// (``LiveSiteData/shown``). The tree on screen and this tree then differ
  /// only where the phase makes them differ, and those differences are the
  /// slots that animate. What a site drives is equal in both: it does not
  /// animate as a slot. It animates as the site's data, and the body is
  /// evaluated again with each sample
  /// (``evaluateWorkingTree(of:registration:answers:)``).
  /// When a site is in flight, its sample for this frame differs from what
  /// is on screen, and the body is evaluated a second time with the samples
  /// to get the tree this frame draws.
  ///
  /// - Parameters:
  ///   - frozenResolved: the canonical resolved subtree the removal injects.
  ///   - frozenPlaced: the placed subtree at the same node, as drawn on the
  ///     previous frame.
  ///   - previousSnapshots: the slots of every view of the previous frame.
  ///   - effectOwnsRootOpacity: whether the transition's built-in effects
  ///     fade the departing view. They then own the opacity of the root.
  ///   - liveSites: what the `Animatable` views and modifiers of the
  ///     departing body show.
  ///   - timestamp: the instant of the removal frame.
  @MainActor
  static func plan(
    of registration: TransitionBodyRegistration,
    rootIdentity: Identity,
    frozenResolved: ResolvedNode,
    frozenPlaced: PlacedNode,
    previousSnapshots: [Identity: AnimatableSnapshot],
    hasEffectChannel: Bool,
    effectOwnsRootOpacity: Bool,
    liveSites: LiveSiteData = .none,
    timestamp: MonotonicInstant? = nil
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
    var frozenContents: [RemovalFrozenContent] = []
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
      frozenContents.append(
        RemovalFrozenContent(boundary: boundary, content: content, placed: placed))
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
    // The sites of the body ask this sink for their data. It answers with
    // what each one shows on screen, and records what the phase wrote.
    let shownSink = TransitionBodyValueSink(answering: liveSites.shown)
    let tree = registration.resolve(phase: .didDisappear, valueSink: shownSink) {
      frozenSizes[$0] ?? .zero
    }
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
    // The roots of this phase can have other identities than those on
    // screen. They are then paired by position among the roots of the
    // identity phase.
    var fallbackRootIndex: Int?
    if !tree.roots.contains(where: { $0.identity == rootIdentity }) {
      fallbackRootIndex = identityPhase().roots.firstIndex(of: rootIdentity)
    }
    let inputs = WorkingTreeInputs(
      rootIdentity: rootIdentity,
      frozenRoot: frozenRoot,
      frozenContents: frozenContents,
      rootStamps: registration.rootStamps[rootIdentity],
      holdsRootOpacity: effectOwnsRootOpacity,
      heldRootOpacity: effectOwnsRootOpacity ? previousSnapshots[rootIdentity]?.opacity : nil
    )
    guard
      let working = workingTree(from: tree, inputs: inputs, fallbackRootIndex: fallbackRootIndex)
    else {
      return .unavailable(contentNotFoundIssue(for: registration))
    }

    // Every view of the working tree that was on screen animates from the
    // value it shows to its value in this phase.
    let frozenIdentities = AnimationTreeQueries.collectIdentities(in: frozenRoot)
    var owned: Set<Identity> = []
    var changes: [AnimationTransitionBodyInsertion.SlotChange] = []
    for wrapper in working.wrappers {
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
    // A view of the content that takes an inherited style animates there
    // when the style on screen and the new one both interpolate.
    for application in working.styleApplications {
      var displayed = AnimatableSnapshot()
      var target = AnimatableSnapshot()
      if let shown = previousSnapshots[application.identity]?[.foregroundShapeStyle],
        let end = AnimatableSnapshot.extractAnimatableShapeStyle(
          from: application.foregroundStyle)
      {
        displayed[.foregroundShapeStyle] = shown
        target[.foregroundShapeStyle] = end
      }
      if let shown = previousSnapshots[application.identity]?[.tintShapeStyle],
        let end = AnimatableSnapshot.extractAnimatableShapeStyle(from: application.tintStyle)
      {
        displayed[.tintShapeStyle] = shown
        target[.tintShapeStyle] = end
      }
      if !target.values.isEmpty {
        owned.insert(application.identity)
        changes.append(
          .init(
            identity: application.identity, viewNodeID: nil, previous: displayed, current: target))
      }
    }

    var issues: [RuntimeIssue] = []
    // A view of this phase that was not on screen is drawn and nothing more.
    // Its handlers never run, which would be a silent no-op.
    let unmounted = working.wrappers.filter {
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
    for (standIn, frozen) in working.paired {
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

    // The sites of the body that this removal takes: the ones its root
    // holds, unless a view that stayed still resolves there. The others
    // belong to the body's other roots, or to a view that is still live,
    // and this removal leaves them as they are.
    let rootIndex = tree.roots.firstIndex { $0.identity == rootIdentity } ?? fallbackRootIndex
    let holders = TransitionBodySiteHolders(roots: tree.roots)
    var valueSites: [AnimationKey: AnyAnimatable] = [:]
    for key in shownSink.sites {
      guard let rootIndex, let phaseData = shownSink.phaseData[key],
        holders.holderIndex(ofSiteAt: key.identity) == rootIndex, !liveSites.staysLive(key)
      else { continue }
      valueSites[key] = phaseData
    }
    // Each of those sites that a live view resolved starts from the data it
    // presents on this frame. When that is not what is on screen (an
    // animation of the site is in flight and has moved on), the tree this
    // frame draws is the body evaluated with the presented data.
    var planned: [AnimationKey: LiveSite] = [:]
    var presentedDiffersFromShown = false
    for key in shownSink.sites where valueSites[key] != nil {
      guard let shown = liveSites.shown(key), let presented = liveSites.presented(key) else {
        continue
      }
      planned[key] = LiveSite(shown: shown, presented: presented)
      if shown != presented {
        presentedDiffersFromShown = true
      }
    }
    var drawn = working
    if presentedDiffersFromShown {
      let presentedTree = registration.resolve(
        phase: .didDisappear,
        valueSink: TransitionBodyValueSink(answers: planned.mapValues(\.presented))
      ) { frozenSizes[$0] ?? .zero }
      if let presented = workingTree(
        from: presentedTree, inputs: inputs, fallbackRootIndex: fallbackRootIndex)
      {
        drawn = presented
      }
    }

    var state = RemovalBodyState(
      rootIdentity: rootIdentity,
      workingRoot: drawn.root,
      rootRect: frozenRootPlaced.bounds,
      rootZIndex: frozenRootPlaced.zIndex,
      contents: drawn.contents,
      orderedContents: frozenContents.map(\.placed),
      contentStyles: drawn.contentStyles,
      ownedIdentities: owned,
      hasEffectChannel: hasEffectChannel,
      frozenContents: frozenContents,
      fallbackRootIndex: fallbackRootIndex,
      holdsRootOpacity: inputs.holdsRootOpacity,
      heldRootOpacity: inputs.heldRootOpacity,
      valueSites: valueSites,
      valueResolveInstant: timestamp
    )
    state.valueAnswers = state.normalizedValueAnswers(planned.mapValues(\.presented))
    return .plays(Plan(state: state, changes: changes, liveSites: planned, issues: issues))
  }

  /// Evaluates the `.didDisappear` body of a removal again, with each of its
  /// `Animatable` views and modifiers at the data in `answers`.
  ///
  /// `answers` holds this frame's sample for each site whose animation is in
  /// flight. A site without an answer evaluates with the data the phase
  /// gives it, which is where its animation ended. Removals of one body
  /// that are given the same answers share one evaluation:
  /// ``refreshWorkingTree(of:from:registration:frozenResolved:answers:at:)``
  /// takes the result for each.
  @MainActor
  static func evaluateWorkingTree(
    of body: RemovalBodyState,
    registration: TransitionBodyRegistration,
    answers: [AnimationKey: AnyAnimatable]
  ) -> TransitionPhaseTree {
    let contents = body.contents
    return registration.resolve(
      phase: .didDisappear, valueSink: TransitionBodyValueSink(answers: answers)
    ) { contents[$0]?.bounds.size ?? .zero }
  }

  /// Makes `tree`, the `.didDisappear` body as just evaluated, the tree the
  /// removal draws.
  ///
  /// The evaluated body takes the steps it took when the removal was planned
  /// (``workingTree(from:inputs:fallbackRootIndex:)``), so the stand-ins,
  /// the stamps of the modifiers outside the transition and the inherited
  /// styles are those of this evaluation. A body that can no longer be
  /// drawn around the content keeps the tree it had.
  ///
  /// - Parameter answers: what the body was evaluated with, as
  ///   ``RemovalBodyState/valueAnswers`` keeps it.
  static func refreshWorkingTree(
    of body: inout RemovalBodyState,
    from tree: TransitionPhaseTree,
    registration: TransitionBodyRegistration,
    frozenResolved: ResolvedNode,
    answers: [AnimationKey: AnyAnimatable],
    at timestamp: MonotonicInstant
  ) {
    body.valueResolveInstant = timestamp
    body.valueAnswers = answers
    guard
      let frozenRoot = AnimationTreeQueries.findResolvedSubtree(
        in: frozenResolved, identity: body.rootIdentity)
    else { return }
    let inputs = WorkingTreeInputs(
      rootIdentity: body.rootIdentity,
      frozenRoot: frozenRoot,
      frozenContents: body.frozenContents,
      rootStamps: registration.rootStamps[body.rootIdentity],
      holdsRootOpacity: body.holdsRootOpacity,
      heldRootOpacity: body.heldRootOpacity
    )
    guard
      let working = workingTree(
        from: tree, inputs: inputs, fallbackRootIndex: body.fallbackRootIndex)
    else { return }
    body.workingRoot = working.root
    body.contents = working.contents
    body.contentStyles = working.contentStyles
  }

  /// Makes an evaluated `.didDisappear` body ready to draw: the steps a
  /// removal takes after every evaluation of that body, when it is planned
  /// and on each frame a site of the body animates.
  ///
  /// 1. Pick the root the removal is keyed on: the root at the removal's
  ///    identity, else the root at `fallbackRootIndex`.
  /// 2. Pair each stand-in with frozen content (the content at the same
  ///    identity, else the content at the same position, else the last one,
  ///    so a body that places `content` twice shows it twice), and give the
  ///    stand-in the size the content was placed with.
  /// 3. Keep on the root what modifiers outside the transition stamped on
  ///    it: this tree is the body alone.
  /// 4. Keep the opacity the root had on screen when the transition's
  ///    built-in effects fade the view.
  /// 5. Record the foreground style and the tint the body hands to the
  ///    content, for the views of the frozen content that inherit them.
  ///
  /// Returns `nil` when the body has no root to draw, or places content that
  /// the frozen subtree does not have.
  private static func workingTree(
    from tree: TransitionPhaseTree,
    inputs: WorkingTreeInputs,
    fallbackRootIndex: Int?
  ) -> WorkingTree? {
    var selectedRoot = tree.roots.first { $0.identity == inputs.rootIdentity }
    if selectedRoot == nil, let fallbackRootIndex, tree.roots.indices.contains(fallbackRootIndex) {
      selectedRoot = tree.roots[fallbackRootIndex]
    }
    guard var workingRoot = selectedRoot else { return nil }

    var flattened = Flattened()
    collect(workingRoot, into: &flattened)

    var contents: [Identity: PlacedNode] = [:]
    var paired: [(standIn: ResolvedNode, frozen: RemovalFrozenContent)] = []
    var resized: [Identity: CellSize] = [:]
    for (index, standIn) in flattened.standIns.enumerated() {
      guard !inputs.frozenContents.isEmpty else { return nil }
      let frozen =
        inputs.frozenContents.first { $0.content.identity == standIn.identity }
        ?? inputs.frozenContents[min(index, inputs.frozenContents.count - 1)]
      contents[standIn.identity] = frozen.placed
      paired.append((standIn, frozen))
      if standIn.intrinsicSize != frozen.placed.bounds.size {
        resized[standIn.identity] = frozen.placed.bounds.size
      }
    }
    if !resized.isEmpty {
      workingRoot = resizingStandIns(in: workingRoot, to: resized)
    }

    if workingRoot.identity == inputs.rootIdentity {
      if let stamps = inputs.rootStamps {
        carryOuterStamps(onto: &workingRoot, onScreen: inputs.frozenRoot, body: stamps)
      }
      if inputs.holdsRootOpacity {
        var drawMetadata = workingRoot.drawMetadata
        drawMetadata.baseStyle.explicitOpacity = inputs.heldRootOpacity
        workingRoot.drawMetadata = drawMetadata
      }
    }
    flattened = Flattened()
    collect(workingRoot, into: &flattened)

    var contentStyles: [Identity: RemovalContentStyle] = [:]
    var styleApplications: [InheritedStyleApplication] = []
    for (standIn, frozen) in paired {
      recordInheritedStyles(
        from: standIn, to: frozen, styles: &contentStyles, applications: &styleApplications)
    }

    return WorkingTree(
      root: workingRoot,
      wrappers: flattened.wrappers,
      paired: paired,
      contents: contents,
      contentStyles: contentStyles,
      styleApplications: styleApplications
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
    // A view of the body that resolves during layout (the content of a
    // `GeometryReader`) is evaluated here, and may conform to `Animatable`.
    // It belongs to a body that is drawn and not mounted, so it asks no
    // sink: bound to the frame's controller, its pull would leave a record
    // there for a site no live view has.
    var placed = AnimatableValueStorage.withSink(nil) {
      let measured = engine.measure(
        presented,
        proposal: ProposedSize(
          width: body.rootRect.size.width, height: body.rootRect.size.height))
      return engine.place(presented, measured: measured, origin: body.rootRect.origin)
    }
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
  /// the stand-in's. The planner animates it there when both values
  /// interpolate; a value that does not interpolate shows at once.
  private static func recordInheritedStyles(
    from standIn: ResolvedNode,
    to frozen: RemovalFrozenContent,
    styles: inout [Identity: RemovalContentStyle],
    applications: inout [InheritedStyleApplication]
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
      var application = InheritedStyleApplication(identity: node.identity)
      if foregroundChanges,
        AnimatableSnapshot.extractAnimatableShapeStyle(
          from: node.drawMetadata.baseStyle.foregroundStyle) == nil,
        node.environmentSnapshot.style.foregroundStyle == liveForeground
      {
        style.foregroundStyle = targetForeground
        application.foregroundStyle = targetForeground
      }
      if tintChanges, node.environmentSnapshot.style.tintStyle == liveTint {
        style.tintStyle = targetTint
        application.tintStyle = targetTint
      }
      guard style.foregroundStyle != nil || style.tintStyle != nil else { continue }
      styles[node.identity] = style
      if application.foregroundStyle != nil || application.tintStyle != nil {
        applications.append(application)
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
