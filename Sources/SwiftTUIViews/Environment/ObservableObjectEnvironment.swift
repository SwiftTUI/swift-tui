public import Observation

// Type-keyed observable-object environment (F157): SwiftUI's
// `View.environment(_:)` / `@Environment(Model.self)` shape. One generic
// key per model type; reads flow through the standard `EnvironmentValues`
// subscript, so the existing observable dependency tracking
// (`recordObservableEnvironmentRead`) applies unchanged.
//
// The framework's environment storage is `Sendable`-constrained
// (`EnvironmentKey.Value: Sendable`), so models must be `Sendable` —
// in practice a `@MainActor @Observable final class`, which is implicitly
// `Sendable` and the natural authoring shape for this framework.

/// Identity-equatable holder for a type-keyed observable object. The
/// environment entry changes only when the INSTANCE is replaced; property
/// mutations reach readers through observable dependency tracking, not
/// environment invalidation — comparing by identity keeps a model mutation
/// from env-mismatching (and re-resolving) every subtree below the
/// injection point.
package struct ObservableObjectEnvironmentEntry<T: AnyObject & Observable & Sendable>:
  Equatable, Sendable
{
  package let object: T?

  package init(object: T?) {
    self.object = object
  }

  package static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.object === rhs.object
  }
}

extension ObservableObjectEnvironmentEntry: CustomDebugStringConvertible {
  /// Instance-distinguishing snapshot text: the environment's reflected
  /// snapshot comparison must see instance swaps (a bare class reflection
  /// prints only the type name, which would false-equal distinct models).
  package var debugDescription: String {
    object.map { "\(type(of: $0))#\(ObjectIdentifier($0))" } ?? "nil"
  }
}

private struct ObservableObjectEnvironmentKey<T: AnyObject & Observable & Sendable>:
  EnvironmentKey
{
  static var defaultValue: ObservableObjectEnvironmentEntry<T> { .init(object: nil) }
}

extension EnvironmentValues {
  /// Reads or writes an observable model keyed by its type, matching
  /// SwiftUI's type-keyed subscript.
  public subscript<T: AnyObject & Observable & Sendable>(objectType: T.Type) -> T? {
    get { self[ObservableObjectEnvironmentKey<T>.self].object }
    set { self[ObservableObjectEnvironmentKey<T>.self] = .init(object: newValue) }
  }
}

extension View {
  /// Places an observable model into the environment keyed by its type,
  /// matching SwiftUI's `environment(_:)`. Read it back with
  /// `@Environment(Model.self)`.
  public func environment<T: AnyObject & Observable & Sendable>(_ object: T?) -> some View {
    transformEnvironment(\.self) { values in
      values[T.self] = object
    }
  }
}

extension Environment {
  /// Reads a type-keyed observable model from the environment, or `nil`
  /// when no ancestor injected one.
  public init<T>(_ objectType: T.Type)
  where Value == T?, T: AnyObject & Observable & Sendable {
    self.init(read: { $0[T.self] })
  }

  /// Reads a type-keyed observable model from the environment, trapping
  /// when no ancestor injected one — matching SwiftUI's non-optional
  /// `@Environment(Model.self)` contract. Use the optional form when the
  /// model may legitimately be absent.
  public init(_ objectType: Value.Type)
  where Value: AnyObject & Observable & Sendable {
    self.init(read: { values in
      guard let object = values[Value.self] else {
        fatalError(
          """
          No Observable object of type \(Value.self) found. \
          A View.environment(_:) for \(Value.self) may be missing as an \
          ancestor of this view.
          """
        )
      }
      return object
    })
  }
}
