@_spi(Testing) import SwiftTUICore
import SwiftTUIViews

/// Plans the body channel of an insertion transition.
///
/// A transition with a body animates from the body of its `.willAppear` phase
/// to the body of its `.identity` phase. The live tree is the identity body
/// from the first frame. This type evaluates the `.willAppear` body outside
/// the graph (``TransitionBodyRegistration/resolve(phase:contentSize:)``) and
/// pairs it with the live tree by identity. Every slot that holds a different
/// value in the two trees becomes an ordinary property animation, which the
/// controller enqueues through the path a changed slot of a live view takes.
///
/// Three rules follow from pairing by identity:
///
/// - A slot that exists in one tree only cannot interpolate. The live value
///   shows from the first frame.
/// - A view that exists in the live tree only is present from the first frame.
/// - A view that exists in the `.willAppear` body only is never displayed.
///   That would be a silent no-op, so it is reported
///   (``Origin/phaseOnlyIssue``).
///
/// The foreground style and the tint reach the content through the
/// environment, where each view below reads them. A body that sets either one
/// differently in the two phases therefore changes the slots of the content's
/// own views. The stand-in records the environment the body hands to the
/// content in the `.willAppear` phase, and the live boundary records it for
/// the identity phase. Every view of the live content that still sees the
/// boundary's value, and sets none of its own, animates from the stand-in's.
///
/// A view or a modifier of the body that conforms to `Animatable` is not a
/// slot. Its `animatableData` is one more value that animates from the
/// origin phase, and its body runs with each sample. That needs the frame
/// head: the live body resolves there, with the data of the identity phase,
/// before the injection stage qualifies the insertion. So on such a frame
/// the head qualifies the insertion first, evaluates the `.willAppear` phase
/// with a sink that records what the phase wrote for each site
/// (``TransitionBodyValueSink``), starts each site's animation from there and
/// evaluates the owners again
/// (`AnimationController.prepareTransitionBodyInsertions`). The first
/// presented frame then holds what the `.willAppear` body produces wherever a
/// site drives it, so the pairing here finds no difference there and the two
/// mechanisms never animate one value twice. The head's ``Decision`` and its
/// evaluated phase are handed to the injection stage, which does not decide
/// or evaluate again.
enum AnimationTransitionBodyInsertion {
  /// The tables of the frame being processed that the body channel reads.
  struct Frame {
    var root: ResolvedNode
    var snapshots: [Identity: AnimatableSnapshot]
    var nodeIDs: [Identity: ViewNodeID]
    var parents: [Identity: Identity]
    var transactions: [Identity: TransactionSnapshot]
  }

  /// A body evaluated in its `.willAppear` phase, flattened.
  struct Origin {
    struct Wrapper {
      var identity: Identity
      var snapshot: AnimatableSnapshot
    }

    struct Content {
      /// The identity of the stand-in, which is the identity of the content.
      var identity: Identity
      var foregroundStyle: AnyShapeStyle?
      var tintStyle: AnyShapeStyle?
    }

    /// Every node of the body except the content stand-ins, in tree order.
    var wrappers: [Wrapper] = []
    /// The content stand-ins, in tree order.
    var contents: [Content] = []
    /// Set when the body has a view in this phase that its identity phase
    /// does not have.
    var phaseOnlyIssue: RuntimeIssue?
  }

  /// What is decided once for the body channel of one insertion.
  ///
  /// The frame head decides it when a view or a modifier of the body conforms
  /// to `Animatable`, because the data of such a site has to start animating
  /// before the frame resolves for the last time. The injection stage then
  /// reads the head's decision. For every other body the injection stage
  /// decides, with the same code.
  struct Decision: Sendable {
    /// The transaction the insertion animates under.
    var transaction: TransactionSnapshot
    /// Whether the insertion has a curve. Without one it snaps.
    var plays: Bool
    /// The identity of the removal this insertion interrupts, when the view
    /// came back while its removal was in flight. The body then continues
    /// from what that removal shows and not from its `.willAppear` phase.
    var returnedRemovalIdentity: Identity?
  }

  /// The slots of one live node that animate from the origin phase.
  struct SlotChange {
    var identity: Identity
    var viewNodeID: ViewNodeID?
    /// The node's slots in the origin phase.
    var previous: AnimatableSnapshot
    /// The node's slots in the live tree.
    var current: AnimatableSnapshot
  }

  /// The roots of the `.willAppear` phase of `registration`, each with the
  /// stamps of the modifiers outside the transition.
  ///
  /// A modifier applied outside the transition stamped the live root after
  /// the body did. A phase evaluated in the scratch scope is the body alone,
  /// so its root gets the same stamps: the two then differ only where the
  /// body does. What the outer modifiers stamped is the difference between
  /// the live root and what the body alone left on it, so `root` and
  /// `parents` have to be the tree of the evaluation `registration` was
  /// registered in.
  ///
  /// `evaluated` is the phase when the caller has evaluated it already, with
  /// a sink of its own. Without it the phase is evaluated here.
  @MainActor
  static func willAppearRoots(
    of registration: TransitionBodyRegistration,
    evaluated: TransitionPhaseTree? = nil,
    root: ResolvedNode,
    parents: [Identity: Identity]
  ) -> [ResolvedNode] {
    (evaluated ?? registration.resolve(phase: .willAppear)).roots.map { phaseRoot in
      var phaseRoot = phaseRoot
      if let stamps = registration.rootStamps[phaseRoot.identity],
        let live = subtree(at: phaseRoot.identity, root: root, parents: parents)
      {
        AnimationTransitionBodyRemoval.carryOuterStamps(
          onto: &phaseRoot, onScreen: live, body: stamps)
      }
      return phaseRoot
    }
  }

  /// Evaluates the `.willAppear` phase of `registration` and flattens it.
  ///
  /// `willAppearRoots` are the roots of that phase when the frame head has
  /// evaluated it already, to learn where the data of the body's
  /// `Animatable` views and modifiers starts
  /// (``willAppearRoots(of:evaluated:root:parents:)``). The phase is then not
  /// evaluated a second time.
  @MainActor
  static func origin(
    of registration: TransitionBodyRegistration,
    in frame: Frame,
    willAppearRoots: [ResolvedNode]? = nil
  ) -> Origin {
    var origin = Origin()
    let roots =
      willAppearRoots
      ?? Self.willAppearRoots(of: registration, root: frame.root, parents: frame.parents)
    for root in roots {
      collect(root, into: &origin)
    }
    // A view of the origin phase that the live tree does not have is never
    // displayed. The live tree came through the graph and the origin did not,
    // so confirm against the identity phase evaluated the same way before
    // reporting: a view the two scratch phases share is not phase-only.
    let absent = origin.wrappers.filter { frame.snapshots[$0.identity] == nil }
    if !absent.isEmpty {
      var identityPhase: Set<Identity> = []
      for root in registration.resolve(phase: .identity).roots {
        identityPhase.formUnion(AnimationTreeQueries.collectIdentities(in: root))
      }
      let phaseOnly = absent.filter { !identityPhase.contains($0.identity) }
      if !phaseOnly.isEmpty {
        origin.phaseOnlyIssue = phaseOnlyIssue(for: registration, viewCount: phaseOnly.count)
      }
    }
    return origin
  }

  /// The slot changes to animate for the insertion of `insertedIdentity`: the
  /// nodes of `origin` inside that subtree whose slots differ from the live
  /// tree's, and the content views that inherit a foreground style or a tint
  /// the body changed.
  static func changes(
    from origin: Origin,
    insertedIdentity: Identity,
    in frame: Frame
  ) -> [SlotChange] {
    var changes: [SlotChange] = []
    for wrapper in origin.wrappers {
      guard let current = frame.snapshots[wrapper.identity],
        animates(wrapper.identity, in: frame),
        isInside(wrapper.identity, subtreeOf: insertedIdentity, in: frame),
        hasInterpolableDifference(wrapper.snapshot, current)
      else { continue }
      changes.append(
        SlotChange(
          identity: wrapper.identity,
          viewNodeID: frame.nodeIDs[wrapper.identity],
          previous: wrapper.snapshot,
          current: current
        )
      )
    }
    for content in origin.contents
    where isInside(content.identity, subtreeOf: insertedIdentity, in: frame) {
      appendInheritedStyleChanges(for: content, in: frame, to: &changes)
    }
    return changes
  }

  private static func collect(_ node: ResolvedNode, into origin: inout Origin) {
    if node.kind == .view(.transitionContentStandIn) {
      origin.contents.append(
        Origin.Content(
          identity: node.identity,
          foregroundStyle: node.environmentSnapshot.style.foregroundStyle,
          tintStyle: node.environmentSnapshot.style.tintStyle
        )
      )
      return
    }
    origin.wrappers.append(
      Origin.Wrapper(identity: node.identity, snapshot: AnimatableSnapshot.extract(from: node))
    )
    for child in node.children {
      collect(child, into: &origin)
    }
  }

  /// A node whose own effective transaction is disabled snaps, as any change
  /// to it would: reduced motion, stable output, or an authored
  /// `disablesAnimations` inside the body.
  static func animates(_ identity: Identity, in frame: Frame) -> Bool {
    frame.transactions[identity]?.animationRequest != .disabled
  }

  static func isInside(
    _ identity: Identity,
    subtreeOf ancestor: Identity,
    in frame: Frame
  ) -> Bool {
    isInside(identity, subtreeOf: ancestor, parents: frame.parents)
  }

  /// Whether `identity` is `ancestor` or lies below it, by the parent of each
  /// identity in a resolved tree.
  static func isInside(
    _ identity: Identity,
    subtreeOf ancestor: Identity,
    parents: [Identity: Identity]
  ) -> Bool {
    var candidate: Identity? = identity
    while let current = candidate {
      if current == ancestor { return true }
      candidate = parents[current]
    }
    return false
  }

  /// Whether some slot holds a value in both snapshots and the two differ.
  private static func hasInterpolableDifference(
    _ origin: AnimatableSnapshot,
    _ live: AnimatableSnapshot
  ) -> Bool {
    origin.values.contains { slot, value in
      guard let liveValue = live[slot] else { return false }
      return liveValue != value
    }
  }

  private static func appendInheritedStyleChanges(
    for content: Origin.Content,
    in frame: Frame,
    to changes: inout [SlotChange]
  ) {
    // The boundary carries the environment the body hands to the content in
    // the identity phase, before any modifier of the content itself. The
    // stand-in carries the same for the origin phase.
    guard let boundaryIdentity = frame.parents[content.identity],
      let boundary = subtree(at: boundaryIdentity, root: frame.root, parents: frame.parents),
      boundary.kind == .view(.transitionContent),
      let liveContent = boundary.children.first(where: { $0.identity == content.identity })
    else { return }
    let liveForeground = boundary.environmentSnapshot.style.foregroundStyle
    let liveTint = boundary.environmentSnapshot.style.tintStyle
    let originForeground =
      liveForeground == content.foregroundStyle
      ? nil : AnimatableSnapshot.extractAnimatableShapeStyle(from: content.foregroundStyle)
    let originTint =
      liveTint == content.tintStyle
      ? nil : AnimatableSnapshot.extractAnimatableShapeStyle(from: content.tintStyle)
    guard originForeground != nil || originTint != nil else { return }

    var pending = [liveContent]
    while let node = pending.popLast() {
      pending.append(contentsOf: node.children)
      guard let current = frame.snapshots[node.identity], animates(node.identity, in: frame)
      else { continue }
      var previous = current
      var changed = false
      // A view takes the inherited foreground when it sets none of its own
      // and still sees the value the body wrote.
      if let originForeground,
        let liveValue = current[.foregroundShapeStyle],
        liveValue != originForeground,
        AnimatableSnapshot.extractAnimatableShapeStyle(
          from: node.drawMetadata.baseStyle.foregroundStyle) == nil,
        node.environmentSnapshot.style.foregroundStyle == liveForeground
      {
        previous[.foregroundShapeStyle] = originForeground
        changed = true
      }
      if let originTint,
        let liveValue = current[.tintShapeStyle],
        liveValue != originTint,
        node.environmentSnapshot.style.tintStyle == liveTint
      {
        previous[.tintShapeStyle] = originTint
        changed = true
      }
      if changed {
        changes.append(
          SlotChange(
            identity: node.identity,
            viewNodeID: node.viewNodeID,
            previous: previous,
            current: current
          )
        )
      }
    }
  }

  /// The subtree at `identity` of the tree at `root`, reached along the
  /// parent chain instead of a search of the whole tree.
  private static func subtree(
    at identity: Identity,
    root: ResolvedNode,
    parents: [Identity: Identity]
  ) -> ResolvedNode? {
    var chain: [Identity] = []
    var candidate: Identity? = identity
    while let current = candidate, current != root.identity {
      chain.append(current)
      candidate = parents[current]
    }
    guard candidate == root.identity else { return nil }
    var node = root
    for next in chain.reversed() {
      guard let child = node.children.first(where: { $0.identity == next }) else { return nil }
      node = child
    }
    return node
  }

  /// The issue for views that exist only in the `.willAppear` phase of a
  /// body, which an insertion never displays.
  static func phaseOnlyIssue(
    for registration: TransitionBodyRegistration,
    viewCount: Int
  ) -> RuntimeIssue {
    let views = viewCount == 1 ? "a view" : "\(viewCount) views"
    return RuntimeIssue(
      severity: .warning,
      code: .Transition.phaseOnlyView,
      message:
        "The body of the transition \(registration.transitionTypeDescription) has \(views) "
        + "in its willAppear phase that its identity phase does not have. An insertion "
        + "shows the view structure of the identity phase from its first frame, so a view "
        + "that exists only in the willAppear phase is never displayed. Keep the same "
        + "views in every phase and change their modifiers instead, for example an "
        + "opacity of 0.",
      identity: registration.identity,
      source: "Transition.body(content:phase:)"
    )
  }
}

/// Which root of a transition body holds each `Animatable` view or modifier
/// in it.
///
/// A body can emit several roots. Each root is inserted and removed through
/// a transition of its own, under its own transaction, and a root can come
/// or go without the others. A site of the body animates once, so one root
/// decides whether and how it does. The rule, on insertion and on removal:
///
/// > A site is held by the first root, in the order the body emits them,
/// > that the site is part of: the root has a view at the site's identity
/// > or beneath it, or the site lies beneath the root. A site that is part
/// > of no root is held by the body's first root.
///
/// A modifier around one root's view is held by that root, and so is a view
/// inside it, whether or not it draws anything. A site above several roots
/// is held by the first of them. The site animates under the transaction of
/// the root that holds it, when that root plays, and not at all when it
/// does not. No other root starts, retargets or ends its animation.
///
/// The roots are those of one evaluation of the body, in any phase: every
/// phase resolves under the host's identity, so the sites and the roots
/// have the same names in each.
struct TransitionBodySiteHolders {
  private var rootIdentities: [Identity]
  private var identitiesByRoot: [Set<Identity>]

  init(roots: [ResolvedNode]) {
    rootIdentities = roots.map(\.identity)
    identitiesByRoot = roots.map(AnimationTreeQueries.collectIdentities(in:))
  }

  /// The position of the root that holds the site at `identity`, or `nil`
  /// for a body with no root.
  func holderIndex(ofSiteAt identity: Identity) -> Int? {
    guard !identitiesByRoot.isEmpty else { return nil }
    return identitiesByRoot.indices.first { reaches(identity, rootAt: $0) } ?? 0
  }

  /// Whether the site at `identity` is part of the root at `index`: the
  /// root has a view at the site's identity or beneath it, so what the
  /// site's body produces is part of what the root draws, or the site lies
  /// beneath the root and produces nothing.
  func reaches(_ identity: Identity, rootAt index: Int) -> Bool {
    guard identitiesByRoot.indices.contains(index) else { return false }
    let identities = identitiesByRoot[index]
    return identities.contains(identity)
      || rootIdentities[index].isAncestor(of: identity)
      || identities.contains { identity.isAncestor(of: $0) }
  }
}
