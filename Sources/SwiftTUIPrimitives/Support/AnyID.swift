/// A type-erased `Hashable & Sendable` identity.
///
/// Used as the `ID` type for scopes with framework-derived identities.
/// One example is the pseudonymous `Panel` variant from `.panel()` without an explicit identifier.
///
/// Consumers supply their own `Hashable & Sendable` values through
/// `.panel(id:)` rather than constructing `AnyID` directly.
///
/// The initializer is `package`-scoped: framework code constructs
/// `AnyID` from derived identities, while consumers supply their own
/// `Hashable & Sendable` values through `.panel(id:)`.
// `AnyID` is intentionally distinct from `AnyHashableSendable`. They both wrap
// Hashable & Sendable values, but `AnyHashableSendable` exposes `unwrap` for
// animation-value access; `AnyID` is an opaque identity tag with no unwrap
// surface. Keeping them separate preserves the intent at each call site.
public struct AnyID: Hashable, Sendable {
  private let box: any AnyIDBox

  package init<Value: Hashable & Sendable>(_ value: Value) {
    self.box = AnyIDConcreteBox(value: value)
  }

  public static func == (lhs: AnyID, rhs: AnyID) -> Bool {
    lhs.box.isEqual(to: rhs.box)
  }

  public func hash(into hasher: inout Hasher) {
    box.hash(into: &hasher)
  }
}

/// An identity derived from another identity, such as a binding's member
/// projection of its source. ``AnyID/derivationRoot`` peels these layers.
package protocol AnyIDDerivation: Hashable, Sendable {
  /// The identity this one was derived from.
  var derivationBase: AnyID { get }
}

extension AnyID {
  /// The identity this one derives from through every ``AnyIDDerivation``
  /// layer, or `self` when it is not derived. The root is itself an opaque
  /// tag: this exposes no wrapped value.
  package var derivationRoot: AnyID {
    var current = self
    while let base = current.box.derivationBase {
      current = base
    }
    return current
  }
}

private protocol AnyIDBox: Sendable {
  func hash(into hasher: inout Hasher)
  func isEqual(to other: any AnyIDBox) -> Bool
  var derivationBase: AnyID? { get }
}

private struct AnyIDConcreteBox<Value: Hashable & Sendable>: AnyIDBox {
  let value: Value

  init(value: Value) {
    self.value = value
  }

  func hash(into hasher: inout Hasher) {
    value.hash(into: &hasher)
  }

  func isEqual(to other: any AnyIDBox) -> Bool {
    guard let other = other as? AnyIDConcreteBox<Value> else {
      return false
    }
    return value == other.value
  }

  var derivationBase: AnyID? {
    (value as? any AnyIDDerivation)?.derivationBase
  }
}
