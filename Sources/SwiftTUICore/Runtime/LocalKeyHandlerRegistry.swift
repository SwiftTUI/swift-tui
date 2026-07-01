/// The result of a key press handler.
public enum KeyPressResult: Equatable, Sendable {
  /// The key event was not handled and should propagate.
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
}

@MainActor
package final class LocalKeyHandlerRegistry: Equatable {
  package typealias Handler = @MainActor (KeyEvent) -> Bool
  package typealias KeyPressHandler = @MainActor (KeyPress) -> Bool
  package typealias PasteHandler = @MainActor (String) -> Bool

  /// One identity's handlers can be contributed by SEVERAL live nodes: stacked
  /// modifiers register at the same resolved identity while each level captures
  /// on its own evaluation node. The registry therefore buckets handlers per
  /// contributing owner instead of holding one flat list per identity — a
  /// per-node restore replaces only that node's bucket, so restoring node A
  /// cannot wipe node B's stacked sibling handler, and repeated restores of one
  /// node stay idempotent.
  private struct ContributedHandlers<H> {
    var byOwner: [RuntimeRegistrationOwnerKey: [H]] = [:]

    var flattened: [H] {
      // Descending owner order (nil owners last) mirrors in-frame registration
      // order: inner modifier levels resolve — and register — before outer
      // levels, and their evaluation nodes are allocated after them.
      byOwner
        .sorted { lhs, rhs in lhs.key > rhs.key }
        .flatMap(\.value)
    }

    var isEmpty: Bool {
      byOwner.isEmpty
    }
  }

  private var handlers: [Identity: Handler] = [:]
  private var keyPressHandlers: [Identity: ContributedHandlers<KeyPressHandler>] = [:]
  private var pasteHandlers: [Identity: ContributedHandlers<PasteHandler>] = [:]
  private var ownersByIdentity: [Identity: RuntimeRegistrationOwnerKey] = [:]

  package init() {}

  nonisolated package static func == (lhs: LocalKeyHandlerRegistry, rhs: LocalKeyHandlerRegistry)
    -> Bool
  {
    lhs === rhs
  }

  package func register(
    identity: Identity,
    handler: @escaping Handler
  ) {
    handlers[identity] = handler
    ownersByIdentity[identity] = .current(identity: identity)
    ViewNodeContext.current?.recordKeyHandlerRegistration(
      identity: identity,
      handler: handler
    )
  }

  package func register(
    identity: Identity,
    keyPressHandler: @escaping KeyPressHandler
  ) {
    let owner = RuntimeRegistrationOwnerKey.current(identity: identity)
    keyPressHandlers[identity, default: .init()]
      .byOwner[owner, default: []]
      .append(keyPressHandler)
    ownersByIdentity[identity] = owner
    ViewNodeContext.current?.recordKeyPressHandlerRegistration(
      identity: identity,
      handler: keyPressHandler
    )
  }

  package func register(
    identity: Identity,
    pasteHandler: @escaping PasteHandler
  ) {
    let owner = RuntimeRegistrationOwnerKey.current(identity: identity)
    pasteHandlers[identity, default: .init()]
      .byOwner[owner, default: []]
      .append(pasteHandler)
    ownersByIdentity[identity] = owner
    ViewNodeContext.current?.recordPasteHandlerRegistration(
      identity: identity,
      handler: pasteHandler
    )
  }

  @discardableResult
  package func dispatch(
    identity: Identity,
    event: KeyEvent
  ) -> Bool {
    handlers[identity]?(event) ?? false
  }

  @discardableResult
  package func dispatch(
    identity: Identity,
    keyPress: KeyPress
  ) -> Bool {
    if let contributions = keyPressHandlers[identity] {
      for handler in contributions.flattened.reversed() {
        if handler(keyPress) {
          return true
        }
      }
    }
    return handlers[identity]?(keyPress.key) ?? false
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
    handlers[identity] != nil || keyPressHandlers[identity]?.isEmpty == false
  }

  package func hasPasteHandler(
    identity: Identity
  ) -> Bool {
    pasteHandlers[identity]?.isEmpty == false
  }

  package func reset() {
    handlers.removeAll(keepingCapacity: true)
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

    for identity in handlers.keys.filter({ matchesAnySubtreeRoot($0, roots: roots) }) {
      handlers.removeValue(forKey: identity)
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

  package func snapshot() -> [Identity: Handler] {
    handlers
  }

  package func snapshotKeyPressHandlers() -> [Identity: [KeyPressHandler]] {
    keyPressHandlers.mapValues(\.flattened)
  }

  package func snapshotPasteHandlers() -> [Identity: [PasteHandler]] {
    pasteHandlers.mapValues(\.flattened)
  }

  package func restore(
    _ snapshot: [Identity: Handler],
    ownersByIdentity: [Identity: RuntimeRegistrationOwnerKey] = [:]
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    for (identity, handler) in snapshot {
      handlers[identity] = handler
      self.ownersByIdentity[identity] = ownersByIdentity[identity] ?? .init(identity: identity)
    }
  }

  package func restoreKeyPressHandlers(
    _ snapshot: [Identity: [KeyPressHandler]],
    ownersByIdentity: [Identity: RuntimeRegistrationOwnerKey] = [:]
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    for (identity, handlers) in snapshot {
      let owner = ownersByIdentity[identity] ?? .init(identity: identity)
      keyPressHandlers[identity, default: .init()].byOwner[owner] = handlers
      self.ownersByIdentity[identity] = owner
    }
  }

  package func restorePasteHandlers(
    _ snapshot: [Identity: [PasteHandler]],
    ownersByIdentity: [Identity: RuntimeRegistrationOwnerKey] = [:]
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    for (identity, handlers) in snapshot {
      let owner = ownersByIdentity[identity] ?? .init(identity: identity)
      pasteHandlers[identity, default: .init()].byOwner[owner] = handlers
      self.ownersByIdentity[identity] = owner
    }
  }

  private func matchesAnySubtreeRoot(
    _ identity: Identity,
    roots: [Identity]
  ) -> Bool {
    (ownersByIdentity[identity] ?? .init(identity: identity)).matchesAnySubtreeRoot(roots)
  }

  private func pruneOwnerMap() {
    let liveIdentities = Set(handlers.keys)
      .union(keyPressHandlers.keys)
      .union(pasteHandlers.keys)
    ownersByIdentity = ownersByIdentity.filter { liveIdentities.contains($0.key) }
  }
}
