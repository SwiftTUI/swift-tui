/// Structural value-equality for view values, used by the Stage-0 memoization
/// diagnostics (and, in later stages, by the memoized-body reuse gate).
///
/// The goal is SwiftUI's input-equality model: decide whether a freshly
/// constructed view value is *the same* as the one a node was last resolved
/// with. The comparator is layered, fast path first:
///
/// 1. `Equatable` — opened via the same implicit-existential trampoline
///    `StateSlot` uses (`makeEquatableComparatorImpl<T: Equatable>`). Sound and
///    cheap; covers value-typed leaves and author-`Equatable` views.
/// 2. Reference / `@Observable` fields — compared by `ObjectIdentifier`; a
///    different instance reads as changed, and same-instance mutation is tracked
///    independently by reader attribution.
/// 3. Field-wise `Mirror` descent for non-`Equatable` structs.
/// 4. Anything the comparator cannot reason about — closures, `AnyView`
///    payloads, opaque existentials — is reported `.blocked`, which the caller
///    treats as "changed / cannot memoize." This quantifies the interactive-leaf
///    ceiling.
///
/// Foundation-free (`Mirror` is `Swift.Mirror`) and `unsafe`-free by design — no
/// POD/`memcmp` path. See
/// `docs/plans/2026-06-17-002-memoized-body-reevaluation-proposal.md`.
package enum MemoComparison: Equatable {
  case equal
  case changed
  case blocked(MemoBlockReason)
}

package enum MemoBlockReason: String, Equatable, Sendable {
  case closure
  case anyView
  case existential
}

package enum MemoValueComparator {
  /// Compares two view values that are expected to be the same concrete type.
  package static func compare(_ lhs: Any, _ rhs: Any) -> MemoComparison {
    // A type change is a structural change. (Should not happen for the same
    // node across frames, but stay total.)
    guard type(of: lhs) == type(of: rhs) else {
      return .changed
    }

    // 1. Equatable fast path.
    if let equatable = lhs as? any Equatable {
      return openEquatable(equatable, rhs) ? .equal : .changed
    }

    // 2. Reference types: identity compare. Mutation of an `@Observable` model
    //    is caught by the dependency gate, not the value compare.
    if type(of: lhs) is AnyClass {
      let lhsObject = lhs as AnyObject
      let rhsObject = rhs as AnyObject
      return ObjectIdentifier(lhsObject) == ObjectIdentifier(rhsObject)
        ? .equal : .changed
    }

    // 3 / 4. Structural descent (or a blocked leaf).
    return compareStructurally(lhs, rhs)
  }

  /// The implicit-existential-opening trampoline (Swift 5.7+): binds `T` to the
  /// existential's concrete type so the `==` is type-safe. Mirrors
  /// `StateSlot.makeEquatableComparatorImpl`.
  private static func openEquatable(_ lhs: any Equatable, _ rhs: Any) -> Bool {
    func compare<T: Equatable>(_ l: T) -> Bool {
      guard let r = rhs as? T else { return false }
      return l == r
    }
    return compare(lhs)
  }

  private static func compareStructurally(_ lhs: Any, _ rhs: Any) -> MemoComparison {
    let lhsMirror = Mirror(reflecting: lhs)
    let rhsMirror = Mirror(reflecting: rhs)

    // `AnyView` and other erasing wrappers expose a payload the comparator
    // cannot open — treat as blocked (the escape-hatch population).
    if isAnyView(type(of: lhs)) {
      return .blocked(.anyView)
    }

    // Enums need case-aware comparison: the generic field-wise descent below
    // ignores child *labels*, but for an enum the single child's label IS the
    // case name — so `.loaded(x)` and `.failed(x)` would otherwise false-equal.
    // (`Equatable` enums never reach here; they take the fast path in `compare`.)
    if lhsMirror.displayStyle == .enum {
      return compareEnumCase(lhsMirror, rhsMirror)
    }

    // A non-Equatable, non-class, non-enum value with no children is either a
    // genuinely empty value type (struct / tuple — a single inhabitant, so two
    // instances are equivalent) or an opaque/function leaf there is nothing to
    // compare (treat as blocked).
    if lhsMirror.children.isEmpty {
      switch lhsMirror.displayStyle {
      case .struct, .tuple:
        return .equal
      case .none:
        return .blocked(.closure)
      default:
        return .blocked(.existential)
      }
    }

    // Field count mismatch ⇒ structural change (e.g. enum case change).
    guard lhsMirror.children.count == rhsMirror.children.count else {
      return .changed
    }

    var result: MemoComparison = .equal
    for (lhsChild, rhsChild) in zip(lhsMirror.children, rhsMirror.children) {
      // Property-wrapper storage (`@State`/`@Binding`/`@Environment` …) is
      // exposed under a `_`-prefixed label; it is slot identity, not data, and
      // its value is handled by the dependency gate — skip it.
      if let label = lhsChild.label, label.hasPrefix("_"),
        isDynamicPropertyWrapperStorage(type(of: lhsChild.value))
      {
        continue
      }
      switch compare(lhsChild.value, rhsChild.value) {
      case .equal:
        continue
      case .changed:
        return .changed
      case .blocked(let reason):
        // Remember the block but keep scanning: a later field may prove the
        // value actually changed, which is the stronger signal.
        result = .blocked(reason)
      }
    }
    return result
  }

  /// Case-aware comparison for a non-`Equatable` enum. `Mirror` reflects a
  /// payload case as a single child whose `label` is the case name and whose
  /// `value` is the associated value (grouped into a tuple when there are
  /// several); a no-payload case reflects to zero children.
  ///
  /// - Different child *arity* ⇒ different case (e.g. `.loading` vs `.loaded(x)`).
  /// - Both empty ⇒ two no-payload cases with no recoverable discriminator
  ///   (`Mirror` does not expose a no-payload case's name). We cannot tell
  ///   `.collapsed` from `.expanded`, so deny reuse — conservative and sound.
  ///   Authors regain precision by making the enum `Equatable` (fast path).
  /// - Matching arity with payload ⇒ compare the case-name labels, then recurse
  ///   on the associated value(s).
  private static func compareEnumCase(_ lhsMirror: Mirror, _ rhsMirror: Mirror) -> MemoComparison {
    let lhsChildren = Array(lhsMirror.children)
    let rhsChildren = Array(rhsMirror.children)
    guard lhsChildren.count == rhsChildren.count else {
      return .changed
    }
    guard !lhsChildren.isEmpty else {
      return .changed
    }
    var result: MemoComparison = .equal
    for (lhsChild, rhsChild) in zip(lhsChildren, rhsChildren) {
      guard lhsChild.label == rhsChild.label else {
        return .changed
      }
      switch compare(lhsChild.value, rhsChild.value) {
      case .equal:
        continue
      case .changed:
        return .changed
      case .blocked(let reason):
        result = .blocked(reason)
      }
    }
    return result
  }

  private static func isAnyView(_ type: Any.Type) -> Bool {
    // Type-name probe (DEBUG diagnostics only): AnyView and AnyScene erase their
    // payloads. Matching by name avoids importing SwiftTUIViews into core.
    let name = String(describing: type)
    return name == "AnyView" || name.hasPrefix("AnyView<") || name == "AnyScene"
  }

  private static func isDynamicPropertyWrapperStorage(_ type: Any.Type) -> Bool {
    // The dynamic property wrappers store their value behind a reference box and
    // change identity every `init`; comparing them is meaningless. Detect by the
    // wrapper type name (DEBUG diagnostics only).
    let name = String(describing: type)
    for wrapper in ["State<", "Binding<", "Environment<", "FocusState<", "GestureState<"]
    where name.hasPrefix(wrapper) {
      return true
    }
    return false
  }
}
