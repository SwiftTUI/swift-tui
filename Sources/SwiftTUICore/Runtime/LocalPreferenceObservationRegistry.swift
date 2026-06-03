package struct PreferenceObservationKeySuffix: Hashable, Sendable,
  CustomStringConvertible
{
  package var preferenceKeyID: ObjectIdentifier
  package var keyDebugName: String
  package var ordinal: Int

  package init<K: PreferenceKey>(
    key: K.Type,
    keyDebugName: String,
    ordinal: Int
  ) {
    preferenceKeyID = ObjectIdentifier(key)
    self.keyDebugName = keyDebugName
    self.ordinal = ordinal
  }

  package var description: String {
    "preference[\(keyDebugName)][\(ordinal)]"
  }
}

package typealias PreferenceObservationKey =
  ViewNodeRuntimeKey<PreferenceObservationKeySuffix>

package struct PreferenceObservationRegistrationSnapshot: Sendable {
  package var identity: Identity
  package var key: PreferenceObservationKey
  package var handlerID: String
  fileprivate let box: any PreferenceObservationBox

  fileprivate var keyDebugName: String {
    box.keyDebugName
  }

  fileprivate init(
    identity: Identity,
    key: PreferenceObservationKey,
    handlerID: String,
    box: any PreferenceObservationBox
  ) {
    self.identity = identity
    self.key = key
    self.handlerID = handlerID
    self.box = box
  }
}

private protocol PreferenceObservationBox: Sendable {
  var keyDebugName: String { get }
  var valueSnapshot: String { get }

  func value<Value>(as type: Value.Type) -> Value?
  func changed(
    from previous: (any PreferenceObservationBox)?
  ) -> Bool
  @MainActor func apply()
}

private struct TypedPreferenceObservationBox<Key: PreferenceKey>: PreferenceObservationBox
where Key.Value: Equatable {
  let value: Key.Value
  let action: @MainActor (Key.Value) -> Void

  var keyDebugName: String {
    String(reflecting: Key.self)
  }

  var valueSnapshot: String {
    String(reflecting: value)
  }

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
    action: @escaping @MainActor (K.Value) -> Void
  ) where K.Value: Equatable {
    let keyDebugName = String(reflecting: key)
    let ordinal = registrations.values.count { registration in
      registration.identity == identity
        && registration.keyDebugName == keyDebugName
    }
    let registrationKey = PreferenceObservationKey(
      ownerNodeID: ViewNodeContext.current?.viewNodeID,
      suffix: .init(
        key: key,
        keyDebugName: keyDebugName,
        ordinal: ordinal
      )
    )
    let handlerID = "\(identity)#preference[\(keyDebugName)][\(ordinal)]"
    let registration = PreferenceObservationRegistrationSnapshot(
      identity: identity,
      key: registrationKey,
      handlerID: handlerID,
      box: TypedPreferenceObservationBox<K>(
        value: value,
        action: action
      )
    )
    registrations[registrationKey] = registration
    ViewNodeContext.current?.recordPreferenceObservationRegistration(
      registration
    )
  }

  package func applyChanges(
    since previous: [PreferenceObservationRegistrationSnapshot]
  ) -> Bool {
    let previousByID = Dictionary(
      uniqueKeysWithValues: previous.map { ($0.key, $0) }
    )

    var appliedChange = false
    for registration in sortedRegistrations() {
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
      if lhs.handlerID != rhs.handlerID {
        return lhs.handlerID < rhs.handlerID
      }
      return String(describing: lhs.key) < String(describing: rhs.key)
    }
  }
}

private func identityMatchesAnySubtreeRoot(
  _ identity: Identity,
  roots: [Identity]
) -> Bool {
  roots.contains { root in
    identity == root || identity.isDescendant(of: root)
  }
}
