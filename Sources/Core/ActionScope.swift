/// A tree-authored focus region that owns a set of commands.
///
/// ActionScope conformance is deliberately opt-in. A conforming type
/// participates in the focus topology at least as strongly as a focus
/// section: the framework can answer "is this scope on the current
/// focus chain?" by checking whether its identity appears in the
/// `scopePath` of the currently focused region.
///
/// The activation predicate for any ActionScope is:
/// _this scope's identity is on the current focus chain_ (i.e. present
/// in the currently focused region's `scopePath`).
///
/// See `docs/proposals/ACTION_SCOPES_AND_COMMANDS.md` for the full
/// design.
public protocol ActionScope: Identifiable {
}

/// A type-erased `Hashable & Sendable` identity.
///
/// Used as the `ID` type for scopes whose identity is framework-derived
/// rather than consumer-supplied (e.g. the pseudonymous variant of
/// `Panel` produced by `.panel()` without an explicit id).
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

private protocol AnyIDBox: Sendable {
  func hash(into hasher: inout Hasher)
  func isEqual(to other: any AnyIDBox) -> Bool
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
}
