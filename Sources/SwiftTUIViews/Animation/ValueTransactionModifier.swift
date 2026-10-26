import SwiftTUICore

// MARK: - Public surface

extension View {
  /// Applies a transformation to the transaction seen by this subtree
  /// whenever `value` changes; the iOS 17 `transaction(value:_:)` form.
  ///
  /// The transform runs against the transaction in effect for the resolve
  /// in which `value` changed and its result governs the subtree for that
  /// resolve, like ``View/animation(_:value:)`` with a whole transaction
  /// instead of one animation:
  ///
  /// ```swift
  /// Text("\(count)")
  ///   .foregroundStyle(count.isMultiple(of: 10) ? Color.green : .foreground)
  ///   .transaction(value: count / 10) { transaction in
  ///     transaction.animation = .easeInOut(duration: .milliseconds(600))
  ///   }
  /// ```
  public func transaction<V: Equatable & Sendable>(
    value: V,
    _ transform: @escaping @Sendable (inout Transaction) -> Void
  ) -> some View {
    modifier(ValueTransactionModifier(value: value, transform: transform))
  }
}

// MARK: - ValueTransactionModifier

/// The value-gated sibling of ``TransactionModifier``: shares the gate
/// mechanics of ``ValueAnimationModifier`` and applies a whole-transaction
/// transform when its value changes.
package struct ValueTransactionModifier<Value: Equatable & Sendable>:
  IterativePrimitiveViewModifier,
  Sendable
{
  package var value: Value
  package var transform: @Sendable (inout Transaction) -> Void

  package init(value: Value, transform: @escaping @Sendable (inout Transaction) -> Void) {
    self.value = value
    self.transform = transform
  }

  package func makeResolveWork<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    let gate = ValueGatedTransactionSupport.openGate(value: value, in: context)

    guard gate.valueChanged else {
      return content.resolveElementsWork(in: gate.childContext).map { resolved in
        gate.storeFirstAppearanceBaseline(value, in: context)
        return resolved
      }
    }

    // Carry every observable Transaction field IN and write it BACK, exactly
    // as `TransactionModifier` does (plan 2026-08-04-002 mechanics §5).
    var transaction = Transaction(
      request: context.transaction.animationRequest,
      isContinuous: context.transaction.isContinuous,
      customValues: context.transaction.customValues,
      tracksVelocity: context.transaction.tracksVelocity
    )
    transform(&transaction)

    var childContext = gate.childContext
    childContext.transaction.animationRequest =
      ValueGatedTransactionSupport.registeredRequest(
        for: transaction,
        reduceMotion: context.environmentValues.renderingReduceMotion
      )
    childContext.transaction.isContinuous = transaction.isContinuous
    childContext.transaction.customValues = transaction.customValues
    childContext.transaction.tracksVelocity = transaction.tracksVelocity
    childContext.propagated.authoredTransactionOverride = true
    return content.resolveElementsWork(in: childContext).map { resolved in
      gate.storeFirstAppearanceBaseline(value, in: context)
      return resolved
    }
  }
}

// MARK: - ValueGatedTransactionSupport

/// The value-gate mechanics shared by ``ValueAnimationModifier`` and
/// ``ValueTransactionModifier``: the remembered value each modifier compares
/// against, its outer-first position among stacked modifiers at one
/// identity, and the registration of the request it authors.
package enum ValueGatedTransactionSupport {
  /// One opened gate: whether the value changed since the last resolve, the
  /// child context to resolve under, and whether the value still has to be
  /// recorded once the content resolved.
  package struct Gate {
    package let valueChanged: Bool
    package let childContext: ResolveContext
    let recordsAfterResolve: Bool
    let key: ValueGateRecords.Key

    /// Records the value after the content resolved, for a gate that found
    /// no node to hold it before (a resolve with no evaluating node). A gate
    /// that recorded before resolving does nothing here.
    @MainActor
    package func storeFirstAppearanceBaseline<Value: Equatable & Sendable>(
      _ value: Value,
      in context: ResolveContext
    ) {
      guard recordsAfterResolve, let owner = ValueGateRecords.owner(in: context),
        let viewGraph = context.viewGraph
      else {
        return
      }
      _ = ValueGateRecords.observe(value, at: key, on: owner, in: viewGraph)
    }
  }

  /// Compares `value` with the one this modifier saw before and records it.
  /// The first value a modifier records is not a change: SwiftUI's
  /// value-gated forms apply only when the value changes. Without a node to
  /// hold values (a resolve outside a view graph) every resolve counts as a
  /// change, as before.
  @MainActor
  package static func openGate<Value: Equatable & Sendable>(
    value: Value,
    in context: ResolveContext
  ) -> Gate {
    let key = ValueGateRecords.Key(
      identity: context.identity, position: context.valueAnimationOrdinalCursor)
    let valueChanged: Bool
    let recordsAfterResolve: Bool
    if let owner = ValueGateRecords.owner(in: context), let viewGraph = context.viewGraph {
      valueChanged = ValueGateRecords.observe(value, at: key, on: owner, in: viewGraph)
      recordsAfterResolve = false
    } else {
      // Nothing can hold the value (no graph, or no node yet): treat it as a
      // change, as before, and record it once the content resolved.
      valueChanged = true
      recordsAfterResolve = true
    }

    var childContext = context
    // Advance the cursor so a stacked inner value-gated modifier at this same
    // identity takes the next position. It resets to 0 across every identity
    // boundary (the cursor is a direct `ResolveContext` field, so `child` /
    // `replacingIdentity` drop it).
    childContext.valueAnimationOrdinalCursor = context.valueAnimationOrdinalCursor + 1

    return Gate(
      valueChanged: valueChanged,
      childContext: childContext,
      recordsAfterResolve: recordsAfterResolve,
      key: key
    )
  }

  /// The request a value-gated modifier authors for `animation`: `.disabled`
  /// under reduce motion or for `nil`, otherwise `.animate` with the box
  /// registered on the renderer-owned sink (the `withAnimation` contract:
  /// the controller purges any active animation whose box carries no
  /// registration in the same render pass, so an unregistered curve dies
  /// before its first tick).
  @MainActor
  package static func registeredRequest(
    for animation: Animation?,
    reduceMotion: Bool
  ) -> AnimationRequest {
    guard !reduceMotion, let animation else {
      return .disabled
    }
    let box = animation.animationBox
    AnimationRegistrationStorage.effectiveSink?.registerAnimationBox(box, payload: animation)
    return .animate(box)
  }

  /// The request a transformed transaction authors: its own request, with a
  /// public `Animation` re-registered on the sink so the curve survives its
  /// first tick.
  @MainActor
  package static func registeredRequest(
    for transaction: Transaction,
    reduceMotion: Bool
  ) -> AnimationRequest {
    if reduceMotion {
      return .disabled
    }
    if case .animate(let box) = transaction.request,
      let animation = box.unwrap(as: Animation.self)
    {
      AnimationRegistrationStorage.effectiveSink?.registerAnimationBox(box, payload: animation)
    }
    return transaction.request
  }
}

// MARK: - ValueGateRecords

/// The values the value-gated modifiers resolved in one node's evaluation
/// last saw, held in one silent slot of that node.
///
/// The node is the one evaluating the modifier (`ViewNodeContext.current`),
/// not the node the identity index names. The index moves an identity to the
/// node that absorbs it when a view's body root is a conditional or a
/// `Group` (the absorber's output is the branch), while the evaluation stays
/// with the authored node, so a slot found through the index was a different
/// slot on the next frame and the first change after appearance never
/// animated (STUI-1335). One node's evaluation can resolve modifiers at
/// several identities, the branches of its body-root conditional, so a
/// record is keyed by the identity and the modifier's outer-first position
/// there; a single per-node counter let two branches share one slot, and a
/// branch flip between value types trapped.
///
/// Records are pass-stable like `onChange`'s: the first write in a pass moves
/// the previous value into the baseline, and a same-pass re-resolve (a
/// navigation destination resolves twice in its write frame) compares
/// against that baseline instead of the value the first resolve stored.
///
/// A branch that leaves and comes back is a new view, as in SwiftUI: a
/// record whose identity is neither in the graph's identity index nor in the
/// owner's last committed output is a departed view's and is replaced.
package struct ValueGateRecords {
  package struct Key: Hashable, Sendable {
    let identity: Identity
    let position: Int
  }

  private struct Record {
    /// The value before this pass's first write; `nil` when the record was
    /// created in this pass.
    var baseline: Any?
    var current: Any
    var passID: UInt64
  }

  private var records: [Key: Record] = [:]

  /// The node that holds the records of the modifiers resolving in
  /// `context`: the evaluating node when it belongs to the context's graph,
  /// else the identity's node.
  @MainActor
  static func owner(in context: ResolveContext) -> SwiftTUICore.ViewNode? {
    guard let viewGraph = context.viewGraph else {
      return nil
    }
    if let current = ViewNodeContext.current, current.ownerGraph === viewGraph {
      return current
    }
    return viewGraph.nodeForIdentity(context.identity)
  }

  /// Compares `value` with the value recorded at `key` on `owner` and
  /// records it. Returns whether it changed. A missing or departed record,
  /// or one of another value type, is a first appearance and reports no
  /// change.
  @MainActor
  static func observe<Value: Equatable & Sendable>(
    _ value: Value,
    at key: Key,
    on owner: SwiftTUICore.ViewNode,
    in viewGraph: ViewGraph
  ) -> Bool {
    let pass = viewGraph.resolvePassID
    var gates = records(on: owner)
    if gates.records[key] == nil {
      adoptRecord(at: key, into: &gates, owner: owner, in: viewGraph)
    }
    let changed: Bool
    if var record = gates.records[key], isLive(key.identity, owner: owner, in: viewGraph) {
      let previous: Any? = record.passID == pass ? record.baseline : .some(record.current)
      changed = (previous as? Value).map { $0 != value } ?? false
      if record.passID != pass {
        record.baseline = record.current
        record.passID = pass
      }
      record.current = value
      gates.records[key] = record
    } else {
      changed = false
      gates.records[key] = Record(baseline: nil, current: value, passID: pass)
    }
    owner.setStateSlotSilently(ordinal: StateSlotOrdinals.valueGateRecords, value: gates)
    return changed
  }

  /// Whether the view at `identity` is still the one a record there was
  /// written for: the identity is in the graph's identity index, or in the
  /// output `owner` committed last (a branch content without a node of its
  /// own). A branch that was replaced by its sibling is in neither.
  @MainActor
  private static func isLive(
    _ identity: Identity,
    owner: SwiftTUICore.ViewNode,
    in viewGraph: ViewGraph
  ) -> Bool {
    if viewGraph.nodeForIdentity(identity) != nil {
      return true
    }
    var node = owner.committed
    while node.identity != identity {
      guard node.identity.isAncestor(of: identity),
        let next = node.children.first(where: { $0.identity.isAncestor(of: identity) })
      else {
        return false
      }
      node = next
    }
    return true
  }

  /// Moves the record at `key` to `owner` from another node that held it.
  ///
  /// Flattening can move the evaluation of an identity between the node
  /// authored there and a node that absorbs it: an explicit `.id` inside a
  /// view hosted by its parent's body-root conditional re-routes to the
  /// absorber after the first commit. The candidates are the nodes at the
  /// identities the owner's evaluation spans down to the key's identity
  /// (index occupants and flattening's authored owners).
  @MainActor
  private static func adoptRecord(
    at key: Key,
    into gates: inout ValueGateRecords,
    owner: SwiftTUICore.ViewNode,
    in viewGraph: ViewGraph
  ) {
    var identity: Identity? = key.identity
    while let candidateIdentity = identity {
      for candidate in [
        viewGraph.flattenedAuthoredOwnerNode(for: candidateIdentity),
        viewGraph.nodeForIdentity(candidateIdentity),
      ] {
        guard let candidate, candidate !== owner else {
          continue
        }
        var other = records(on: candidate)
        if let moved = other.records.removeValue(forKey: key) {
          gates.records[key] = moved
          candidate.setStateSlotSilently(ordinal: StateSlotOrdinals.valueGateRecords, value: other)
          return
        }
      }
      // Stop at the owner's own identity, or at once when the owner's
      // evaluation does not span the key (a foreign evaluating node).
      guard candidateIdentity != owner.identity, owner.identity.isAncestor(of: candidateIdentity)
      else {
        return
      }
      identity = candidateIdentity.parent
    }
  }

  @MainActor
  private static func records(on node: SwiftTUICore.ViewNode) -> ValueGateRecords {
    guard let slot = node.stateSlotStorage(ordinal: StateSlotOrdinals.valueGateRecords),
      slot.stores(ValueGateRecords.self)
    else {
      return ValueGateRecords()
    }
    return slot.value(as: ValueGateRecords.self)
  }
}
