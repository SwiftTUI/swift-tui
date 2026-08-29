/// The result of a key press handler.
public enum KeyPressResult: Equatable, Sendable {
  /// The handler did not consume the key event, so the event continues to the next handler.
  case ignored
  /// The key event was consumed.
  case handled
}

/// Keyboard modifier flags shared across key and mouse events.
public struct EventModifiers: OptionSet, Equatable, Hashable, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let shift = Self(rawValue: 1 << 0)
  public static let alt = Self(rawValue: 1 << 1)
  /// The primary editing modifier: Control in terminals, and Control or Command in native hosts.
  public static let ctrl = Self(rawValue: 1 << 2)
}

/// A key identity paired with modifier flags.
public struct KeyPress: Equatable, Hashable, Sendable {
  public var key: KeyEvent
  public var modifiers: EventModifiers

  public init(_ key: KeyEvent, modifiers: EventModifiers = []) {
    self.key = key
    self.modifiers = modifiers
  }
}

public enum KeyEvent: Equatable, Hashable, Sendable {
  case character(Character)
  case `return`
  case space
  case tab
  case arrowLeft
  case arrowRight
  case arrowUp
  case arrowDown
  case backspace
  case escape
  case home
  case end
  case insert
  /// Forward delete (the VT220 `Delete` key, `ESC [ 3 ~`). Backward delete
  /// remains ``backspace``.
  case delete
  case pageUp
  case pageDown
  /// A function key, 1-based (`F1` = `.functionKey(1)`). Terminals deliver
  /// F1...F4 as SS3 (`ESC O P…S`) or modified CSI, and F5+ as VT220 tilde
  /// sequences. The parser normalizes all of them here.
  case functionKey(Int)
}

@MainActor
package final class LocalKeyHandlerRegistry: Equatable {
  package typealias KeyPressHandler = @MainActor (KeyPress) -> Bool
  package typealias PasteHandler = @MainActor (String) -> Bool

  /// One contributing owner's stacked handlers plus the persisted ordinal of
  /// the bucket's first registration. The ordinal — not the owner's
  /// `ViewNodeID` — carries dispatch priority between buckets: node IDs
  /// re-allocate when a level's node re-mints, so an order inferred from them
  /// inverts which stacked handler consumes first as soon as only part of the
  /// stack republishes, while a recorded ordinal survives scoped restores
  /// unchanged.
  private struct ContributedBucket<H> {
    var ordinal: UInt64
    var handlers: [H]
  }

  /// One identity's handlers can be contributed by SEVERAL live nodes: stacked
  /// modifiers register at the same resolved identity while each level captures
  /// on its own evaluation node. The registry therefore buckets handlers per
  /// contributing owner instead of holding one flat list per identity — a
  /// per-node restore replaces only that node's bucket, so restoring node A
  /// cannot wipe node B's stacked sibling handler, and repeated restores of one
  /// node stay idempotent.
  private struct ContributedHandlers<H> {
    var byOwner: [RuntimeRegistrationOwnerKey: ContributedBucket<H>] = [:]

    var flattened: [H] {
      // Ascending ordinal order mirrors in-frame registration order: inner
      // modifier levels resolve — and register — before outer levels. The
      // owner tiebreak (descending, nil owners last) only orders buckets whose
      // ordinals collide, which unique minting makes effectively unreachable.
      byOwner
        .sorted { lhs, rhs in
          if lhs.value.ordinal != rhs.value.ordinal {
            return lhs.value.ordinal < rhs.value.ordinal
          }
          return lhs.key > rhs.key
        }
        .flatMap(\.value.handlers)
    }

    var isEmpty: Bool {
      byOwner.isEmpty
    }
  }

  private var keyPressHandlers: [Identity: ContributedHandlers<KeyPressHandler>] = [:]
  private var pasteHandlers: [Identity: ContributedHandlers<PasteHandler>] = [:]
  private var ownersByIdentity: [Identity: RuntimeRegistrationOwnerKey] = [:]
  /// Monotonic mint for ``ContributedBucket/ordinal``. Never reset: ordinals
  /// only need a stable relative order, and reuse after `reset()` could pair a
  /// fresh bucket with a restored one's recorded ordinal.
  private var nextContributionOrdinal: UInt64 = 0

  package init() {}

  nonisolated package static func == (lhs: LocalKeyHandlerRegistry, rhs: LocalKeyHandlerRegistry)
    -> Bool
  {
    lhs === rhs
  }

  package func register(
    identity: Identity,
    keyPressHandler: @escaping KeyPressHandler
  ) {
    let owner = RuntimeRegistrationOwnerKey.current(identity: identity)
    let ordinal =
      keyPressHandlers[identity]?.byOwner[owner]?.ordinal ?? claimContributionOrdinal()
    keyPressHandlers[identity, default: .init()]
      .byOwner[owner, default: ContributedBucket(ordinal: ordinal, handlers: [])]
      .handlers.append(keyPressHandler)
    ownersByIdentity[identity] = owner
    ViewNodeContext.current?.recordKeyPressHandlerRegistration(
      identity: identity,
      ordinal: ordinal,
      handler: keyPressHandler
    )
  }

  package func register(
    identity: Identity,
    pasteHandler: @escaping PasteHandler
  ) {
    let owner = RuntimeRegistrationOwnerKey.current(identity: identity)
    let ordinal =
      pasteHandlers[identity]?.byOwner[owner]?.ordinal ?? claimContributionOrdinal()
    pasteHandlers[identity, default: .init()]
      .byOwner[owner, default: ContributedBucket(ordinal: ordinal, handlers: [])]
      .handlers.append(pasteHandler)
    ownersByIdentity[identity] = owner
    ViewNodeContext.current?.recordPasteHandlerRegistration(
      identity: identity,
      ordinal: ordinal,
      handler: pasteHandler
    )
  }

  private func claimContributionOrdinal() -> UInt64 {
    defer { nextContributionOrdinal += 1 }
    return nextContributionOrdinal
  }

  @discardableResult
  package func dispatch(
    identity: Identity,
    keyPress: KeyPress
  ) -> Bool {
    guard let contributions = keyPressHandlers[identity] else {
      return false
    }
    for handler in contributions.flattened.reversed() {
      if handler(keyPress) {
        return true
      }
    }
    return false
  }

  @discardableResult
  package func dispatchPaste(
    identity: Identity,
    content: String
  ) -> Bool {
    guard let contributions = pasteHandlers[identity] else {
      return false
    }

    for handler in contributions.flattened.reversed() {
      if handler(content) {
        return true
      }
    }
    return false
  }

  package func hasHandler(
    identity: Identity
  ) -> Bool {
    keyPressHandlers[identity]?.isEmpty == false
  }

  package func hasPasteHandler(
    identity: Identity
  ) -> Bool {
    pasteHandlers[identity]?.isEmpty == false
  }

  package func reset() {
    keyPressHandlers.removeAll(keepingCapacity: true)
    pasteHandlers.removeAll(keepingCapacity: true)
    ownersByIdentity.removeAll(keepingCapacity: true)
  }

  package func removeSubtrees(
    rootedAt roots: [Identity]
  ) {
    guard !roots.isEmpty else {
      return
    }

    removeContributionSubtrees(from: &keyPressHandlers, roots: roots)
    removeContributionSubtrees(from: &pasteHandlers, roots: roots)
    pruneOwnerMap()
  }

  private func removeContributionSubtrees<H>(
    from contributions: inout [Identity: ContributedHandlers<H>],
    roots: [Identity]
  ) {
    for (identity, contribution) in contributions {
      let remaining = contribution.byOwner.filter { owner, _ in
        !owner.matchesAnySubtreeRoot(roots)
      }
      if remaining.isEmpty {
        contributions.removeValue(forKey: identity)
      } else if remaining.count != contribution.byOwner.count {
        contributions[identity]?.byOwner = remaining
      }
    }
  }

  package func snapshotKeyPressHandlers() -> [Identity: [KeyPressHandler]] {
    keyPressHandlers.mapValues(\.flattened)
  }

  package func snapshotPasteHandlers() -> [Identity: [PasteHandler]] {
    pasteHandlers.mapValues(\.flattened)
  }

  package func restoreKeyPressHandlers(
    _ snapshot: [Identity: [KeyPressHandler]],
    ownersByIdentity: [Identity: RuntimeRegistrationOwnerKey] = [:],
    ordinalsByIdentity: [Identity: UInt64] = [:]
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    for (identity, handlers) in snapshot {
      let owner = ownersByIdentity[identity] ?? .init(identity: identity)
      // The recorded ordinal keeps the restored bucket's dispatch priority
      // where it was originally registered; only a snapshot predating the
      // record (none in practice) falls back to a fresh mint. The mint always
      // advances past restored ordinals so a genuinely fresh registration
      // joins the back of the stack instead of colliding into a tie.
      let ordinal =
        ordinalsByIdentity[identity]
        ?? keyPressHandlers[identity]?.byOwner[owner]?.ordinal
        ?? claimContributionOrdinal()
      nextContributionOrdinal = max(nextContributionOrdinal, ordinal + 1)
      keyPressHandlers[identity, default: .init()].byOwner[owner] =
        ContributedBucket(ordinal: ordinal, handlers: handlers)
      self.ownersByIdentity[identity] = owner
    }
  }

  package func restorePasteHandlers(
    _ snapshot: [Identity: [PasteHandler]],
    ownersByIdentity: [Identity: RuntimeRegistrationOwnerKey] = [:],
    ordinalsByIdentity: [Identity: UInt64] = [:]
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    for (identity, handlers) in snapshot {
      let owner = ownersByIdentity[identity] ?? .init(identity: identity)
      let ordinal =
        ordinalsByIdentity[identity]
        ?? pasteHandlers[identity]?.byOwner[owner]?.ordinal
        ?? claimContributionOrdinal()
      nextContributionOrdinal = max(nextContributionOrdinal, ordinal + 1)
      pasteHandlers[identity, default: .init()].byOwner[owner] =
        ContributedBucket(ordinal: ordinal, handlers: handlers)
      self.ownersByIdentity[identity] = owner
    }
  }

  private func matchesAnySubtreeRoot(
    _ identity: Identity,
    roots: [Identity]
  ) -> Bool {
    (ownersByIdentity[identity] ?? .init(identity: identity)).matchesAnySubtreeRoot(roots)
  }

  /// Evicts contributed buckets whose owning node has departed.
  ///
  /// One identity's handlers are contributed by several *live* nodes, so a
  /// bucket keyed to a node that is no longer live is garbage. Nothing else
  /// reaches it: `removeSubtrees(rootedAt:)` matches on the owner's identity,
  /// which an `.id(_:)`-re-rooted control keeps stable across generations
  /// while its registering node re-mints — so without this leg the control
  /// accumulates one bucket per generation and `flattened` grows without
  /// bound. Buckets whose owner carries no node ID are kept: departure cannot
  /// be proven for them (the pointer family's `removeUnpairedGestureFamilyRoutes`
  /// keeps them for the same reason).
  package func prune(keeping liveNodeIDs: Set<ViewNodeID>) {
    pruneContributions(&keyPressHandlers, keeping: liveNodeIDs)
    pruneContributions(&pasteHandlers, keeping: liveNodeIDs)
    pruneOwnerMap()
  }

  /// The node axis of teardown — see
  /// ``RuntimeRegistry/removeUnjustifiedRegistrations(_:)``. The stacked
  /// families check per CONTRIBUTED BUCKET, not per identity: one identity's
  /// handlers can be contributed by several nodes (stacked modifier levels),
  /// and the residual this closes is precisely a bucket whose owner no longer
  /// backs it standing beside one whose owner does.
  package func removeUnjustifiedRegistrations(
    _ record: (ViewNodeID) -> NodeHandlers?
  ) {
    removeUnjustifiedContributions(&keyPressHandlers) { viewNodeID, identity in
      record(viewNodeID)?.keyHandler.keyPress.handlers[identity] != nil
    }
    removeUnjustifiedContributions(&pasteHandlers) { viewNodeID, identity in
      record(viewNodeID)?.keyHandler.paste.handlers[identity] != nil
    }
    pruneOwnerMap()
  }

  private func removeUnjustifiedContributions<H>(
    _ contributions: inout [Identity: ContributedHandlers<H>],
    _ isJustified: (ViewNodeID, Identity) -> Bool
  ) {
    for (identity, contribution) in contributions {
      let surviving = contribution.byOwner.filter { owner, _ in
        // An entry restored without an owner carries no node claim to check.
        guard let viewNodeID = owner.viewNodeID else {
          return true
        }
        return isJustified(viewNodeID, identity)
      }
      guard surviving.count != contribution.byOwner.count else {
        continue
      }
      if surviving.isEmpty {
        contributions.removeValue(forKey: identity)
      } else {
        var pruned = contribution
        pruned.byOwner = surviving
        contributions[identity] = pruned
      }
    }
  }

  private func pruneContributions<H>(
    _ contributions: inout [Identity: ContributedHandlers<H>],
    keeping liveNodeIDs: Set<ViewNodeID>
  ) {
    for (identity, contribution) in contributions {
      let surviving = contribution.byOwner.filter { owner, _ in
        guard let viewNodeID = owner.viewNodeID else {
          return true
        }
        return liveNodeIDs.contains(viewNodeID)
      }
      guard surviving.count != contribution.byOwner.count else {
        continue
      }
      if surviving.isEmpty {
        contributions.removeValue(forKey: identity)
      } else {
        var pruned = contribution
        pruned.byOwner = surviving
        contributions[identity] = pruned
      }
    }
  }

  private func pruneOwnerMap() {
    let liveIdentities = Set(keyPressHandlers.keys)
      .union(pasteHandlers.keys)
    ownersByIdentity = ownersByIdentity.filter { liveIdentities.contains($0.key) }
  }
}
