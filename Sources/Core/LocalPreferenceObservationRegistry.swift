package struct PreferenceObservationRegistrationSnapshot: @unchecked Sendable {
  package var identity: Identity
  package var handlerID: String
  fileprivate let box: any PreferenceObservationBox

  fileprivate var keyDebugName: String {
    box.keyDebugName
  }

  fileprivate init(
    identity: Identity,
    handlerID: String,
    box: any PreferenceObservationBox
  ) {
    self.identity = identity
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
  private var registrations: [String: PreferenceObservationRegistrationSnapshot] = [:]

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
    let handlerID = "\(identity)#preference[\(keyDebugName)][\(ordinal)]"
    registrations[handlerID] = .init(
      identity: identity,
      handlerID: handlerID,
      box: TypedPreferenceObservationBox<K>(
        value: value,
        action: action
      )
    )
  }

  package func applyChanges(
    since previous: [PreferenceObservationRegistrationSnapshot]
  ) -> Bool {
    let previousByID = Dictionary(
      uniqueKeysWithValues: previous.map { ($0.handlerID, $0) }
    )

    var appliedChange = false
    for registration in registrations.values.sorted(by: { $0.handlerID < $1.handlerID }) {
      if registration.box.changed(from: previousByID[registration.handlerID]?.box) {
        registration.box.apply()
        appliedChange = true
      }
    }
    return appliedChange
  }

  package func reset() {
    registrations.removeAll(keepingCapacity: true)
  }

  package func snapshot() -> [PreferenceObservationRegistrationSnapshot] {
    registrations.values.sorted(by: { $0.handlerID < $1.handlerID })
  }

  package func restore(
    _ snapshot: [PreferenceObservationRegistrationSnapshot]
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    for registration in snapshot {
      registrations[registration.handlerID] = registration
    }
  }
}
