/// Whether a state slot is part of the persistent value state that a lazy
/// container may carry while its payload is dormant.
///
/// Transient is the conservative default. Runtime registrations, dependency
/// edges, and lifecycle bookkeeping live outside state slots altogether; the
/// default also keeps gesture values, animation baselines, and control chrome
/// scratch out of a dormant archive unless their owning subsystem explicitly
/// certifies otherwise.
package enum DormantStateSlotPolicy: Equatable, Sendable {
  case transient
  case persistent
}

/// Resolve-time provenance for a slot's first materialization. A slot keeps
/// the policy it was born with across later writes, so an imperative write
/// outside the wrapper's resolve scope cannot accidentally reclassify it.
package enum DormantStateSlotPolicyScope {
  @TaskLocal package static var current: DormantStateSlotPolicy = .transient
}

@MainActor
package func withPersistentDormantStateSlot<Result>(
  _ body: () throws -> Result
) rethrows -> Result {
  try DormantStateSlotPolicyScope.$current.withValue(.persistent, operation: body)
}

@MainActor
package func withTransientDormantStateSlot<Result>(
  _ body: () throws -> Result
) rethrows -> Result {
  try DormantStateSlotPolicyScope.$current.withValue(.transient, operation: body)
}

/// Closure-free reconstruction payload for one persistent state slot. The
/// stored value has already passed the recursive value-only audit below.
package struct DormantStateSlotSnapshot {
  fileprivate var value: Any
  fileprivate var valueType: Any.Type
}

package struct AnyStateSlot {
  private enum Storage {
    case uninitialized
    case value(Any, Any.Type, (Any, Any) -> Bool)
  }

  private var storage: Storage
  package let dormantPolicy: DormantStateSlotPolicy

  package init() {
    storage = .uninitialized
    dormantPolicy = DormantStateSlotPolicyScope.current
  }

  /// Creates an initialized slot. If `T` conforms to `Equatable` at
  /// runtime, the slot stores a type-safe equality comparator so later
  /// `set(_:)` calls can report `didChange` correctly. Otherwise the
  /// comparator conservatively reports every write as a change.
  ///
  /// Historically this type had both an `init<T>` and an
  /// `init<T: Equatable>` overload, but the Equatable overload was
  /// unreachable from most callers (including `initializeIfNeeded` and
  /// `set`) because Swift resolves overloads based on statically-known
  /// constraints. Every slot silently ended up with the always-false
  /// comparator, which in turn caused `setStateSlot` to treat every
  /// write as a change — a latent source of spurious invalidations
  /// (notably: `@GestureState` reset-on-teardown writing the same seed
  /// value to a slot whose previous value was already seed would still
  /// dirty the view and schedule another frame, producing an infinite
  /// resolve loop). The fix: detect Equatable via `any Equatable`
  /// existential opening at init time and build the right comparator
  /// regardless of static constraint context.
  package init<T>(_ value: T) {
    storage = Self.makeStorage(value: value, valueType: T.self)
    dormantPolicy = DormantStateSlotPolicyScope.current
  }

  package init(restoringDormant snapshot: DormantStateSlotSnapshot) {
    storage = Self.makeStorage(value: snapshot.value, valueType: snapshot.valueType)
    dormantPolicy = .persistent
  }

  private static func makeStorage<T>(
    value: T,
    valueType: Any.Type
  ) -> Storage {
    if let equatable = value as? any Equatable {
      return .value(value, valueType, makeEquatableComparator(equatable))
    }
    return .value(value, valueType, { _, _ in false })
  }

  /// Accepts an `any Equatable` existential and returns a comparator
  /// closure bound to the existential's concrete static type via
  /// Swift's implicit existential opening.
  private static func makeEquatableComparator(
    _ sample: any Equatable
  ) -> (Any, Any) -> Bool {
    return makeEquatableComparatorImpl(sample)
  }

  /// The implicit-existential-opening trampoline: when called with an
  /// `any Equatable` argument, Swift 5.7+ binds `T` to the concrete
  /// underlying type, so the returned closure captures a proper
  /// type-safe `==`.
  private static func makeEquatableComparatorImpl<T: Equatable>(
    _ sample: T
  ) -> (Any, Any) -> Bool {
    return { lhs, rhs in
      guard let l = lhs as? T, let r = rhs as? T else {
        return false
      }
      return l == r
    }
  }

  package func stores<T>(_ type: T.Type) -> Bool {
    guard case .value(_, let valueType, _) = storage else {
      return false
    }
    return valueType == T.self
  }

  /// Whether the slot has been given a value. A fresh slot is uninitialized
  /// until its first store; distinguishing the two lets callers store into an
  /// empty slot while leaving a foreign-typed occupant untouched.
  package var isInitialized: Bool {
    if case .value = storage {
      return true
    }
    return false
  }

  package var storedTypeDescription: String {
    switch storage {
    case .uninitialized:
      return "uninitialized"
    case .value(_, let valueType, _):
      return String(reflecting: valueType)
    }
  }

  /// Returns a closure-free, value-only reconstruction payload. Persistent
  /// provenance is necessary but not sufficient: `State` is generic and may
  /// contain a class, task handle, binding closure, or another live runtime
  /// edge. Such values remain transient instead of leaking that edge through
  /// a dormant archive.
  package func dormantSnapshot() -> DormantStateSlotSnapshot? {
    guard dormantPolicy == .persistent,
      case .value(let value, let valueType, _) = storage,
      Self.isDormantValueOnly(value)
    else {
      return nil
    }
    return DormantStateSlotSnapshot(value: value, valueType: valueType)
  }

  /// Test-only invariant probe for the framework-owned nested-archive envelope.
  /// The envelope's metatype is trusted only when it exactly identifies the
  /// enclosed value.
  package static func malformedDormantSnapshotIsRejectedForTesting() -> Bool {
    let malformed = DormantStateSlotSnapshot(value: 1, valueType: String.self)
    return !isDormantValueOnly(malformed)
  }

  private static func isDormantValueOnly(_ value: Any) -> Bool {
    var remainingNodes = 4_096
    return isDormantValueOnly(
      value,
      depth: 0,
      remainingNodes: &remainingNodes
    )
  }

  private static func isDormantValueOnly(
    _ value: Any,
    depth: Int,
    remainingNodes: inout Int
  ) -> Bool {
    guard depth <= 128, remainingNodes > 0 else {
      return false
    }
    remainingNodes -= 1

    // A nested dormant archive contains these framework-created reconstruction
    // envelopes. The metatype is trusted only as envelope metadata and must
    // exactly describe the already-audited payload; a user-authored metatype
    // stored as state still reaches the direct rejection below.
    if let snapshot = value as? DormantStateSlotSnapshot {
      guard snapshot.valueType == type(of: snapshot.value) else {
        return false
      }
      return isDormantValueOnly(
        snapshot.value,
        depth: depth + 1,
        remainingNodes: &remainingNodes
      )
    }

    let valueType = type(of: value)
    if value is Any.Type {
      // Metatypes are process-local runtime identity handles. Their empty
      // mirrors do not make them reconstructible dormant values.
      return false
    }
    switch RuntimeFieldReflection.metadataKind(of: valueType) {
    case 0, 0x203:
      // Runtime type metadata is authoritative. A CustomReflectable class can
      // report a struct-shaped mirror, but cannot change its metadata kind.
      return false
    default:
      break
    }

    let typeName = String(reflecting: valueType)

    // A user-defined custom mirror can omit reference-bearing fields or
    // recursively yield itself. Standard-library value containers have
    // trusted mirrors that expose their logical payloads; every other custom
    // mirror is conservatively ineligible for dormant storage.
    if value is any CustomReflectable, !typeName.hasPrefix("Swift.") {
      return false
    }

    if typeName.contains("->")
      // Builtin leaves are compiler/runtime handles, not reconstructible
      // values. Their empty mirrors describe an opaque token, not safety.
      || typeName.hasPrefix("Builtin.")
      || typeName.contains("Builtin.")
      || typeName.hasPrefix("Swift.Task<")
      || typeName == "Swift.ObjectIdentifier"
      || typeName == "Swift.UnsafeRawPointer"
      || typeName == "Swift.UnsafeMutableRawPointer"
      || typeName.contains("UnsafePointer<")
      || typeName.contains("UnsafeMutablePointer<")
      || typeName.contains("OpaquePointer")
      || typeName.contains("Unmanaged<")
      // Continuations and the standard library's unowned executor/job values
      // are opaque runtime resumptions or scheduling handles. Their mirrors
      // intentionally expose no reconstructible payload, so a leaf-shaped
      // mirror is not evidence that they are safe to archive. Match the Swift
      // runtime families precisely: user value types named Job or Executor
      // remain eligible after their children pass this audit.
      || typeName.contains("Continuation<")
      || typeName.contains(">.Continuation")
      || typeName.hasPrefix("Swift.UnownedSerialExecutor")
      || typeName.hasPrefix("Swift.UnownedTaskExecutor")
      || typeName.hasPrefix("Swift.UnownedJob")
      || typeName.hasPrefix("Swift.ExecutorJob")
    {
      return false
    }

    let mirror = Mirror(reflecting: value)
    for child in mirror.children {
      guard
        isDormantValueOnly(
          child.value,
          depth: depth + 1,
          remainingNodes: &remainingNodes
        )
      else {
        return false
      }
    }
    return true
  }

  package func value<T>(as type: T.Type) -> T {
    guard case .value(let value, let valueType, _) = storage else {
      fatalError("State slot accessed before initialization.")
    }
    guard valueType == T.self, let typed = value as? T else {
      fatalError(
        "State slot type mismatch. Expected \(T.self), found \(valueType)."
      )
    }
    return typed
  }

  package mutating func set<T>(_ value: T) -> Bool {
    guard case .value(let existingValue, let valueType, let equals) = storage else {
      self = AnyStateSlot(value)
      return true
    }
    guard valueType == T.self else {
      fatalError(
        "State slot type mismatch. Expected \(valueType), found \(T.self)."
      )
    }

    let didChange = !equals(existingValue, value)
    // Preserve the existing `equals` closure — equality semantics are
    // fixed at initial-store time and must not be reset to the
    // non-Equatable always-false comparator when the value updates.
    storage = .value(value, valueType, equals)
    return didChange
  }

  package mutating func initializeIfNeeded<T>(
    with value: @autoclosure () -> T
  ) {
    guard case .uninitialized = storage else {
      return
    }
    self = AnyStateSlot(value())
  }
}
