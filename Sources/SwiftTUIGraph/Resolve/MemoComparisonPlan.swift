/// Per-type comparison plans for implicit structural memoization.
///
/// The production memo gate historically compared only `Equatable` view values
/// (author opt-in); every framework container re-descended. A plan widens the
/// gate to types it can prove comparable **without per-compare reflection**:
/// the plan is built once per concrete type (cold, at capture time) and applied
/// with statically-bound closures thereafter. See
/// `docs/plans/2026-08-07-001-implicit-structural-memoization-plan.md` (org
/// root) and the consistency invariant on ``MemoValueComparator``.
///
/// ## Runtime reflection bindings
///
/// The plan builder walks fields via ``RuntimeFieldReflection`` — the
/// package-shared bindings to the runtime entry points backing `_forEachField`
/// and `Mirror` (see that file for the availability story).
///
/// Soundness stance: a plan may report *changed* for equal values (padding
/// bytes, unplannable shapes — a missed skip), but must never report *equal*
/// for observably different values. The sampled `MemoSkipTrace` shadow oracle
/// (`unsoundContentNoReads` must stay 0) alarms on any false-equal.

/// Compares one stored field of two values of the same concrete type, given
/// the two value base pointers. All types are bound at plan-build time; the
/// closure body does no reflection.
@unsafe package struct MemoFieldComparator {
  package let isEqual: @MainActor (UnsafeRawPointer, UnsafeRawPointer) -> Bool

  package init(isEqual: @escaping @MainActor (UnsafeRawPointer, UnsafeRawPointer) -> Bool) {
    unsafe self.isEqual = isEqual
  }
}

/// How the memo gate compares a captured view value of one concrete type.
///
/// `@unsafe` because the field tier carries raw-pointer comparators; the
/// unsafety is in *applying* one to value base pointers, and every
/// application site spells `unsafe`.
@unsafe package enum MemoComparisonPlan {
  /// The type conforms to `Equatable`: compare via its own `==`
  /// (the historical opt-in tier).
  case equatable
  /// `_isPOD` type: whole-value byte compare. False-equal is impossible;
  /// padding can only produce a missed skip.
  case podMemcmp
  /// Field-wise plan whose comparators all witness VALUE bytes (POD spans,
  /// `Equatable` `==`, value-witnessing sub-plans) — equality genuinely
  /// proves the output-defining inputs unchanged.
  case fields([MemoFieldComparator])
  /// Field-wise plan containing at least one class-identity comparator
  /// (directly or in a sub-plan). Identity equality proves only the
  /// reference, not the referenced contents, so this plan may serve ONLY on
  /// invalidation-tracked frames, where a mutation to the referenced object
  /// arrives as an invalidation; an uncertified empty-invalidation frame
  /// (a forced re-render) must deny — the referenced contents are exactly
  /// the out-of-band channel such frames exist to refresh.
  case referenceFields([MemoFieldComparator])
}

/// Diagnostic tier labels for ``MemoSkipTrace``'s Stage-0 population split.
package enum MemoPlanTier: String {
  case equatable
  case pod
  case fields
  case unplannable
}

@MainActor
package enum MemoComparisonPlanCache {
  /// `nil` value = the type was inspected and proven unplannable; cached so
  /// the builder never re-walks it.
  private static var plans: [ObjectIdentifier: MemoComparisonPlan?] = unsafe [:]
  private static let maximumFieldPlanDepth = 8

  /// Build-if-missing. Called from the capture site (cold per type).
  package static func plan(for type: Any.Type) -> MemoComparisonPlan? {
    let key = ObjectIdentifier(type)
    if let cached = unsafe plans[key] {
      return unsafe cached
    }
    let built = unsafe buildPlan(for: type, depth: 0)
    unsafe plans[key] = built
    return unsafe built
  }

  /// Whether the capture site should stash values of `type` for the gate.
  package static func hasPlan(for type: Any.Type) -> Bool {
    unsafe plan(for: type) != nil
  }

  /// Lookup-only. Called from the production gate path; a miss falls back to
  /// the `Equatable`-only comparator (plans are built at capture time, so a
  /// captured value normally has one — trace-mode captures are the exception).
  package static func cachedPlan(for type: Any.Type) -> MemoComparisonPlan?? {
    unsafe plans[ObjectIdentifier(type)]
  }

  package static func diagnosticTier(for type: Any.Type) -> MemoPlanTier {
    switch unsafe plan(for: type) {
    case .equatable: return .equatable
    case .podMemcmp: return .pod
    case .fields, .referenceFields: return .fields
    case nil: return .unplannable
    }
  }

  /// Whether values of `type` may be memo-served on a frame whose invalidation
  /// set is empty and uncertified (a forced re-render). Value-witnessing plans
  /// may (their equality proves the output-defining inputs unchanged — the
  /// historical `Equatable`-tier behavior); reference-identity plans may not.
  package static func mayServeUnderUncertifiedEmptyInvalidation(
    _ type: Any.Type
  ) -> Bool {
    switch unsafe cachedPlan(for: type) {
    case .referenceFields??: return false
    default: return true
    }
  }

  /// Test seam: drops all cached plans.
  package static func resetForTesting() {
    unsafe plans.removeAll(keepingCapacity: false)
  }

  // ───────────────────────────────────────────────────────────────────────
  // Plan building (cold; once per concrete type).
  // ───────────────────────────────────────────────────────────────────────

  private static func buildPlan(for type: Any.Type, depth: Int) -> MemoComparisonPlan? {
    if type is any Equatable.Type {
      return unsafe .equatable
    }
    // Erasing wrappers hide their payload behind a box the comparator must not
    // open (matches the diagnostic comparator's blocked class).
    if MemoValueComparator.isErasingWrapper(type) {
      return nil
    }
    // Whole-value byte compare only when the fields tile the size exactly:
    // interior padding bytes are uninitialized, so a padded POD struct would
    // false-*unequal* essentially always (sound but inert). Padded POD types
    // fall through to the field tier, whose per-field spans never read padding.
    if isExactlyByteComparable(type) {
      return unsafe .podMemcmp
    }
    // Only structs get field plans: enums have no per-case field metadata
    // (a non-POD, non-`Equatable` enum could false-equal across cases), and
    // classes compare by identity at the *field* tier only — a class-typed
    // view value stays unplannable, mirroring the diagnostic comparator's
    // scope.
    guard
      RuntimeFieldReflection.metadataKind(of: type) == RuntimeFieldReflection.structureKind
    else {
      return nil
    }
    guard depth < maximumFieldPlanDepth else {
      return nil
    }
    var comparators: [MemoFieldComparator] = unsafe []
    var witnessesAllValues = true
    let fieldCount = RuntimeFieldReflection.fieldCount(of: type)
    for index in 0..<fieldCount {
      let info = RuntimeFieldReflection.fieldInfo(of: type, at: index)
      // Weak/unowned storage: loading through a plain typed pointer would
      // bypass the reference's ownership semantics — refuse the whole type.
      guard info.isStrong else {
        return nil
      }
      // Property-wrapper storage (`_`-prefixed `DynamicProperty` field) is
      // slot identity, not data: its value classes are covered by the memo
      // gate's dependency guards (`hasNoMemoUncoveredDependencies` and the
      // environment-snapshot compare), exactly as the diagnostic comparator
      // skips them.
      if info.name.hasPrefix("_"), info.fieldType is any DynamicProperty.Type {
        continue
      }
      guard
        let field = unsafe buildFieldComparator(
          for: info.fieldType,
          atOffset: info.offset,
          depth: depth
        )
      else {
        return nil
      }
      unsafe comparators.append(field.comparator)
      witnessesAllValues = unsafe witnessesAllValues && field.witnessesValues
    }
    return witnessesAllValues
      ? unsafe .fields(comparators)
      : unsafe .referenceFields(comparators)
  }

  private static func buildFieldComparator(
    for fieldType: Any.Type,
    atOffset offset: Int,
    depth: Int
  ) -> (comparator: MemoFieldComparator, witnessesValues: Bool)? {
    // Byte tier first: covers scalar fields, payloadless POD enums, and
    // packed POD tuples without opening them. Padded shapes fall through.
    if isExactlyByteComparable(fieldType) {
      let size = sizeOfType(fieldType)
      let comparator = unsafe MemoFieldComparator { lhs, rhs in
        let lhsBytes = unsafe UnsafeRawBufferPointer(start: lhs + offset, count: size)
        let rhsBytes = unsafe UnsafeRawBufferPointer(start: rhs + offset, count: size)
        return unsafe lhsBytes.elementsEqual(rhsBytes)
      }
      return unsafe (comparator, witnessesValues: true)
    }
    if let equatableShim =
      openedShim(MemoEquatableFieldShim<Never>.self, boundTo: fieldType)
      as? any MemoEquatableFieldComparing.Type
    {
      return unsafe (equatableShim.comparator(atOffset: offset), witnessesValues: true)
    }
    if fieldType is AnyObject.Type {
      let comparator = unsafe openedClassIdentityComparator(for: fieldType, atOffset: offset)
      return unsafe (comparator, witnessesValues: false)
    }
    // Nested non-POD, non-`Equatable` struct: recursive sub-plan applied at
    // the field's offset (its reference-identity taint propagates). Any other
    // shape (closures, existentials, non-POD enums/tuples, erasing wrappers)
    // makes the whole type unplannable.
    guard
      RuntimeFieldReflection.metadataKind(of: fieldType)
        == RuntimeFieldReflection.structureKind,
      !MemoValueComparator.isErasingWrapper(fieldType)
    else {
      return nil
    }
    let nested: [MemoFieldComparator]
    let nestedWitnessesValues: Bool
    switch unsafe buildPlan(for: fieldType, depth: depth + 1) {
    case .fields(let comparators)?:
      unsafe nested = comparators
      nestedWitnessesValues = true
    case .referenceFields(let comparators)?:
      unsafe nested = comparators
      nestedWitnessesValues = false
    default:
      return nil
    }
    let comparator = unsafe MemoFieldComparator { lhs, rhs in
      unsafe MemoComparisonPlanCache.fieldsEqual(nested, lhs + offset, rhs + offset)
    }
    return unsafe (comparator, witnessesValues: nestedWitnessesValues)
  }

  /// Applies every field comparator of one plan at the given value bases.
  @MainActor
  package static func fieldsEqual(
    _ comparators: [MemoFieldComparator],
    _ lhsBase: UnsafeRawPointer,
    _ rhsBase: UnsafeRawPointer
  ) -> Bool {
    for unsafe comparator in unsafe comparators {
      guard unsafe comparator.isEqual(lhsBase, rhsBase) else {
        return false
      }
    }
    return true
  }

  private static func isPODType(_ type: Any.Type) -> Bool {
    func open<T>(_ concrete: T.Type) -> Bool {
      _isPOD(concrete)
    }
    return _openExistential(type, do: open)
  }

  /// Whether two values of `type` can be compared as raw bytes over
  /// `MemoryLayout.size` without reading any padding: POD, and every stored
  /// field (recursively) tiles the size contiguously. Leaves with no field
  /// metadata (builtin scalars, payloadless POD enums) are exact by
  /// definition; a payload-bearing POD enum has no per-case field metadata,
  /// so it is exact only when payloadless (field count 0).
  private static func isExactlyByteComparable(_ type: Any.Type) -> Bool {
    guard isPODType(type) else {
      return false
    }
    let fieldCount = RuntimeFieldReflection.fieldCount(of: type)
    if fieldCount == 0 {
      return true
    }
    let kind = RuntimeFieldReflection.metadataKind(of: type)
    guard
      kind == RuntimeFieldReflection.structureKind
        || kind == RuntimeFieldReflection.tupleKind
    else {
      return false
    }
    var covered = 0
    for index in 0..<fieldCount {
      let (fieldType, offset) = RuntimeFieldReflection.fieldTypeAndOffset(of: type, at: index)
      // Declaration order is offset order for Swift structs and tuples; a
      // toolchain that reorders fails this check and falls back to the field
      // tier — conservative, never unsound.
      guard offset == covered,
        isExactlyByteComparable(fieldType)
      else {
        return false
      }
      covered += sizeOfType(fieldType)
    }
    return covered == sizeOfType(type)
  }

  private static func sizeOfType(_ type: Any.Type) -> Int {
    func open<T>(_ concrete: T.Type) -> Int {
      MemoryLayout<T>.size
    }
    return _openExistential(type, do: open)
  }

  /// Rebinds `shim`'s generic parameter to `fieldType` so the conditional
  /// conformance (`where T: Equatable`) can be tested at runtime.
  private static func openedShim(
    _ shim: MemoEquatableFieldShim<Never>.Type,
    boundTo fieldType: Any.Type
  ) -> Any.Type {
    func open<F>(_ concrete: F.Type) -> Any.Type {
      MemoEquatableFieldShim<F>.self
    }
    return _openExistential(fieldType, do: open)
  }

  private static func openedClassIdentityComparator(
    for fieldType: Any.Type,
    atOffset offset: Int
  ) -> MemoFieldComparator {
    func open<F>(_ concrete: F.Type) -> MemoFieldComparator {
      unsafe MemoFieldComparator { lhs, rhs in
        let lhsValue = unsafe (lhs + offset).assumingMemoryBound(to: F.self).pointee
        let rhsValue = unsafe (rhs + offset).assumingMemoryBound(to: F.self).pointee
        return (lhsValue as AnyObject) === (rhsValue as AnyObject)
      }
    }
    return unsafe _openExistential(fieldType, do: open)
  }
}

/// Conditional-conformance shim: `MemoEquatableFieldShim<F>` conforms only
/// when `F: Equatable`, so an `as? any MemoEquatableFieldComparing.Type` cast
/// is the runtime conformance test — and inside the conformance, `T` is bound
/// with its `Equatable` constraint so `==` dispatches statically.
private protocol MemoEquatableFieldComparing {
  @MainActor static func comparator(atOffset offset: Int) -> MemoFieldComparator
}

private enum MemoEquatableFieldShim<T> {}

extension MemoEquatableFieldShim: MemoEquatableFieldComparing where T: Equatable {
  static func comparator(atOffset offset: Int) -> MemoFieldComparator {
    unsafe MemoFieldComparator { lhs, rhs in
      let lhsValue = unsafe (lhs + offset).assumingMemoryBound(to: T.self).pointee
      let rhsValue = unsafe (rhs + offset).assumingMemoryBound(to: T.self).pointee
      return lhsValue == rhsValue
    }
  }
}

extension MemoValueComparator {
  /// Production memo-gate comparison, plan-dispatched. Returns `nil` when the
  /// pair cannot be judged (no plan — the gate recomputes, today's behavior
  /// for non-`Equatable` values without a cached plan).
  package static func compareForReuse(_ lhs: Any, _ rhs: Any) -> MemoComparison? {
    guard type(of: lhs) == type(of: rhs) else {
      return .changed
    }
    guard let cached = unsafe MemoComparisonPlanCache.cachedPlan(for: type(of: lhs)) else {
      // No cache entry (trace-mode capture): the historical Equatable-only path.
      return compareEquatable(lhs, rhs)
    }
    switch unsafe cached {
    case .equatable:
      return compareEquatable(lhs, rhs)
    case .podMemcmp:
      return podBytesEqual(lhs, rhs) ? .equal : .changed
    case .fields(let comparators), .referenceFields(let comparators):
      return unsafe fieldPlanEqual(lhs, rhs, comparators: comparators)
        ? .equal : .changed
    case nil:
      return nil
    }
  }

  /// Type-name probe shared with the diagnostic comparator's blocked class:
  /// `AnyView`/`AnyScene` erase their payloads behind boxes value comparison
  /// must not open. Name-based so Graph does not import SwiftTUIViews.
  package static func isErasingWrapper(_ type: Any.Type) -> Bool {
    let name = String(describing: type)
    return name == "AnyView" || name.hasPrefix("AnyView<") || name == "AnyScene"
  }

  private static func podBytesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
    func open<T>(_ lhsValue: T) -> Bool {
      guard let rhsValue = rhs as? T else { return false }
      return unsafe withUnsafeBytes(of: lhsValue) { lhsBytes in
        unsafe withUnsafeBytes(of: rhsValue) { rhsBytes in
          unsafe lhsBytes.elementsEqual(rhsBytes)
        }
      }
    }
    return _openExistential(lhs, do: open)
  }

  private static func fieldPlanEqual(
    _ lhs: Any,
    _ rhs: Any,
    comparators: [MemoFieldComparator]
  ) -> Bool {
    func open<T>(_ lhsValue: T) -> Bool {
      guard let rhsValue = rhs as? T else { return false }
      return unsafe withUnsafePointer(to: lhsValue) { lhsPointer in
        unsafe withUnsafePointer(to: rhsValue) { rhsPointer in
          unsafe MemoComparisonPlanCache.fieldsEqual(
            comparators,
            UnsafeRawPointer(lhsPointer),
            UnsafeRawPointer(rhsPointer)
          )
        }
      }
    }
    return _openExistential(lhs, do: open)
  }
}
