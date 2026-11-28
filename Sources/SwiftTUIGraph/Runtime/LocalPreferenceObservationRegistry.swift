package struct PreferenceObservationKeySuffix: Hashable, Sendable,
  CustomStringConvertible
{
  private let keyType: Any.Type
  package var preferenceKeyID: ObjectIdentifier { ObjectIdentifier(keyType) }

  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.preferenceKeyID == rhs.preferenceKeyID && lhs.ordinal == rhs.ordinal
  }
  package func hash(into hasher: inout Hasher) {
    hasher.combine(preferenceKeyID)
    hasher.combine(ordinal)
  }
  package var ordinal: Int

  package init<K: PreferenceKey>(
    key: K.Type,
    ordinal: Int
  ) {
    keyType = key
    self.ordinal = ordinal
  }

  package var description: String {
    "preference[\(String(reflecting: keyType))][\(ordinal)]"
  }
}

package typealias PreferenceObservationKey =
  ViewNodeRuntimeKey<PreferenceObservationKeySuffix>

package struct PreferenceObservationRegistrationSnapshot: Sendable {
  package var identity: Identity
  package var key: PreferenceObservationKey
  package var handlerID: String { "\(identity)#\(key.suffix)" }
  fileprivate var box: any PreferenceObservationBox
  fileprivate let observedSubtree: Boxed<ResolvedNode>?

  fileprivate init(
    identity: Identity,
    key: PreferenceObservationKey,
    box: any PreferenceObservationBox, observedSubtree: ResolvedNode? = nil
  ) {
    self.identity = identity
    self.key = key
    self.box = box
    self.observedSubtree = observedSubtree.map(Boxed.init)
  }
}

private protocol PreferenceObservationBox: Sendable {
  func value<Value>(as type: Value.Type) -> Value?
  func changed(
    from previous: (any PreferenceObservationBox)?
  ) -> Bool
  func reading(_ preferences: PreferenceValues) -> any PreferenceObservationBox
  @MainActor func apply()
}

private struct TypedPreferenceObservationBox<Key: PreferenceKey>: PreferenceObservationBox
where Key.Value: Equatable {
  let value: Key.Value
  let action: @MainActor (Key.Value) -> Void

  func value<Value>(as type: Value.Type) -> Value? {
    value as? Value
  }

  func changed(
    from previous: (any PreferenceObservationBox)?
  ) -> Bool {
    guard let previous else {
      return value != Key.defaultValue
    }
    guard let previousValue: Key.Value = previous.value(as: Key.Value.self) else {
      return true
    }
    return previousValue != value
  }

  func reading(_ preferences: PreferenceValues) -> any PreferenceObservationBox {
    Self(value: preferences[Key.self], action: action)
  }

  @MainActor
  func apply() {
    action(value)
  }
}

@MainActor
package final class LocalPreferenceObservationRegistry: Equatable {
  private var registrations: [PreferenceObservationKey: PreferenceObservationRegistrationSnapshot] =
    [:]

  package init() {}

  nonisolated package static func == (
    lhs: LocalPreferenceObservationRegistry,
    rhs: LocalPreferenceObservationRegistry
  ) -> Bool {
    lhs === rhs
  }

  package func register<K: PreferenceKey>(
    identity: Identity,
    key: K.Type,
    value: K.Value,
    observedSubtree: ResolvedNode? = nil,
    action: @escaping @MainActor (K.Value) -> Void
  ) where K.Value: Equatable {
    let keyID = ObjectIdentifier(key)
    let ordinal = registrations.values.count { registration in
      registration.identity == identity
        && registration.key.suffix.preferenceKeyID == keyID
    }
    let registrationKey = PreferenceObservationKey(
      ownerNodeID: ViewNodeContext.current?.viewNodeID,
      suffix: .init(
        key: key,
        ordinal: ordinal
      )
    )
    let registration = PreferenceObservationRegistrationSnapshot(
      identity: identity,
      key: registrationKey,
      box: TypedPreferenceObservationBox<K>(
        value: value,
        action: action
      ), observedSubtree: observedSubtree
    )
    registrations[registrationKey] = registration
    ViewNodeContext.current?.recordPreferenceObservationRegistration(
      registration
    )
  }

  package func applyChanges(
    since previous: [PreferenceObservationRegistrationSnapshot],
    committedTree: ResolvedNode? = nil
  ) -> Bool {
    let previousByID = Dictionary(
      uniqueKeysWithValues: previous.map { ($0.key, $0) }
    )

    // The render head registers the value it can read then. GeometryReader
    // supplies its children during layout, including on a resize that reuses
    // the observer. Re-fold the observer's own subtree so preferences on
    // modifiers outside that observation stay outside its value.
    var realizations: [Identity: [ResolvedNode]] = [:]
    if let committedTree, registrations.values.contains(where: { $0.observedSubtree != nil }) {
      var pending = [committedTree]
      while let node = pending.popLast() {
        guard node.customLayoutFallbackSummary.layoutRealizedContentCount > 0 else { continue }
        if node.layoutRealizedContent != nil { realizations[node.identity] = node.children }
        pending.append(contentsOf: node.children)
      }
    }
    var appliedChange = false
    for var registration in sortedRegistrations() {
      if let observed = registration.observedSubtree, !realizations.isEmpty {
        let realized = observed.value.applyingLayoutDependentRealizations(realizations)
        registration.box = registration.box.reading(realized.preferenceValues)
        registrations[registration.key] = registration
      }
      if registration.box.changed(from: previousByID[registration.key]?.box) {
        registration.box.apply()
        appliedChange = true
      }
    }
    return appliedChange
  }

  package func reset() {
    registrations.removeAll(keepingCapacity: true)
  }

  package func removeSubtrees(
    rootedAt roots: [Identity]
  ) {
    guard !roots.isEmpty else {
      return
    }

    for (registrationKey, _) in registrations.filter({
      identityMatchesAnySubtreeRoot($0.value.identity, roots: roots)
    }) {
      registrations.removeValue(forKey: registrationKey)
    }
  }

  package func snapshot() -> [PreferenceObservationRegistrationSnapshot] {
    sortedRegistrations()
  }

  package func restore(
    _ snapshot: [PreferenceObservationRegistrationSnapshot]
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    for registration in snapshot {
      registrations[registration.key] = registration
    }
  }

  private func sortedRegistrations() -> [PreferenceObservationRegistrationSnapshot] {
    registrations.values.sorted { lhs, rhs in
      let left = lhs.key.ownerNodeID?.rawValue
      let right = rhs.key.ownerNodeID?.rawValue
      if left != right { return left.map { l in right.map { l < $0 } ?? false } ?? true }
      if lhs.key.suffix.ordinal != rhs.key.suffix.ordinal {
        return lhs.key.suffix.ordinal < rhs.key.suffix.ordinal
      }
      return lhs.handlerID < rhs.handlerID
    }
  }
}
