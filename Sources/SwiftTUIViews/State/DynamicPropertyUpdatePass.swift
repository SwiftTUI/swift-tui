package import SwiftTUIGraph

// The dynamic-property update pass — discovery and execution.
//
// Views (and dynamic properties) declare wrappers as stored properties; the
// framework discovers the ones conforming to `DynamicProperty` with a
// reflect-once-per-type descriptor and runs `update()` on each before the
// body evaluates, under the same ambient authoring context the body will
// observe. Wrapper-free types pay one dictionary lookup per evaluation and no
// reflection after the first (the `.empty`-plan fast path).
//
// Per-evaluation extraction is plan-dispatched: struct containers whose
// discovered fields are statically wrapper-typed get an *offset plan* —
// extractor closures bound once per type via `RuntimeFieldReflection` that
// copy each wrapper straight out of the container's value memory, replacing
// the per-instance `Mirror` walk (which allocated a mirror and boxed every
// child per body evaluation). Exotic shapes (class or enum containers, and
// fields whose *static* type does not conform — e.g. an existential- or
// `Any`-typed field boxing a wrapper) keep the legacy `Mirror` walk, so
// discovery semantics are unchanged; only the extraction mechanism differs.
//
// `update()` runs on an extracted copy of the property: effects that go
// through reference-backed storage (every built-in wrapper) persist; mutations
// to plain stored fields are discarded — the ratified copy-semantics
// divergence recorded in the SwiftTUIViews divergence register.

/// A type's discovered dynamic-property layout: the stored-property indices
/// (in `Mirror` child order) whose values conform to ``DynamicProperty``.
package struct DynamicPropertyDescriptor: Sendable {
  package struct Field: Sendable {
    /// Position in `Mirror(reflecting:).children` order.
    package var index: Int
    /// The stored-property label (`_count` for `@State var count`), for
    /// diagnostics only.
    package var label: String?
  }

  package var fields: [Field]

  package var isEmpty: Bool {
    fields.isEmpty
  }

  package static let empty = DynamicPropertyDescriptor(fields: [])
}

/// Extracts a copy of one discovered dynamic-property field from its
/// container's value memory. The field's concrete type and byte offset are
/// bound at plan-build time; the closure body does no reflection.
///
/// `@unsafe` because applying the extractor to a raw base pointer is the
/// unsafe act; every application site spells `unsafe`.
@unsafe package struct DynamicPropertyFieldExtractor {
  /// Position in `Mirror(reflecting:).children` order — the slot-path
  /// ordinal nested wrappers key their state identity on.
  package let index: Int
  package let extract: @MainActor (UnsafeRawPointer) -> any DynamicProperty

  package init(
    index: Int,
    extract: @escaping @MainActor (UnsafeRawPointer) -> any DynamicProperty
  ) {
    unsafe self.index = index
    unsafe self.extract = extract
  }
}

/// How the update pass reaches one container type's dynamic properties.
@unsafe package enum DynamicPropertyUpdatePlan {
  /// No discovered dynamic properties — the pass returns immediately.
  case empty
  /// Struct container with statically wrapper-typed fields: extract each
  /// through its bound offset extractor.
  case offsets([DynamicPropertyFieldExtractor])
  /// Correctness fallback for shapes the offset tier cannot prove
  /// (class/enum containers, existential-typed fields, weak storage): the
  /// legacy per-instance `Mirror` walk.
  case mirrorWalk(DynamicPropertyDescriptor)
}

/// Diagnostic plan-kind labels for ``DynamicPropertyDescriptorCache``'s safe
/// classification API.
package enum DynamicPropertyPlanKind: String, Sendable {
  case empty
  case offsets
  case mirrorWalk
}

/// Reflect-once-per-type cache of ``DynamicPropertyUpdatePlan``s.
///
/// Struct and class layouts are fixed per type, so their plans cache
/// permanently. Enum values (whose reflected children vary by case) are
/// rebuilt per value and never cached — no view or wrapper in the framework
/// is enum-shaped, so this is a correctness backstop, not a hot path.
/// Computed properties are invisible to `Mirror` and to the runtime field
/// metadata — discovery sees stored properties only, matching SwiftUI.
@MainActor
package enum DynamicPropertyDescriptorCache {
  private static var plansByType: [ObjectIdentifier: DynamicPropertyUpdatePlan] = unsafe [:]

  /// Lookup-only fast path, keyed by the container's concrete type so warm
  /// evaluations never box the container into `Any`.
  package static func cachedUpdatePlan(for type: Any.Type) -> DynamicPropertyUpdatePlan? {
    unsafe plansByType[ObjectIdentifier(type)]
  }

  /// Build-if-missing (cold per type; per value for enum containers).
  package static func updatePlan(reflecting value: Any) -> DynamicPropertyUpdatePlan {
    let key = ObjectIdentifier(type(of: value))
    if let cached = unsafe plansByType[key] {
      return unsafe cached
    }
    let mirror = Mirror(reflecting: value)
    let descriptor = buildDescriptor(from: mirror)
    switch mirror.displayStyle {
    case .struct:
      if descriptor.isEmpty {
        return unsafe cachePlan(.empty, key: key)
      }
      return unsafe cachePlan(
        offsetsPlan(for: type(of: value), descriptor: descriptor)
          ?? .mirrorWalk(descriptor),
        key: key
      )
    case .class:
      // Object fields offset from the object base, not a value pointer —
      // out of the offset tier's scope (no class-shaped view or wrapper in
      // the framework).
      return unsafe cachePlan(
        descriptor.isEmpty ? .empty : .mirrorWalk(descriptor),
        key: key
      )
    default:
      return descriptor.isEmpty ? unsafe .empty : unsafe .mirrorWalk(descriptor)
    }
  }

  private static func cachePlan(
    _ plan: DynamicPropertyUpdatePlan,
    key: ObjectIdentifier
  ) -> DynamicPropertyUpdatePlan {
    unsafe plansByType[key] = plan
    return unsafe plan
  }

  /// Diagnostic classification of the plan a value's type gets (safe API for
  /// tests and traces).
  package static func diagnosticPlanKind(reflecting value: Any) -> DynamicPropertyPlanKind {
    switch unsafe updatePlan(reflecting: value) {
    case .empty: return .empty
    case .offsets: return .offsets
    case .mirrorWalk: return .mirrorWalk
    }
  }

  /// Whether a plan is cached for `type` (safe API for tests; enum
  /// containers never cache).
  package static func hasCachedPlan(for type: Any.Type) -> Bool {
    unsafe cachedUpdatePlan(for: type) != nil
  }

  /// Test seam: drops all cached plans.
  package static func resetForTesting() {
    unsafe plansByType.removeAll(keepingCapacity: false)
  }

  private static func buildDescriptor(from mirror: Mirror) -> DynamicPropertyDescriptor {
    var fields: [DynamicPropertyDescriptor.Field] = []
    for (index, child) in mirror.children.enumerated() where child.value is any DynamicProperty {
      fields.append(.init(index: index, label: child.label))
    }
    guard !fields.isEmpty else {
      return .empty
    }
    return DynamicPropertyDescriptor(fields: fields)
  }

  /// Binds one extractor per discovered field, or `nil` when any field
  /// resists static binding (existential/`Any`-typed storage boxing a
  /// wrapper, weak references, or metadata that disagrees with the `Mirror`
  /// discovery) — those types keep the `Mirror` walk.
  private static func offsetsPlan(
    for containerType: Any.Type,
    descriptor: DynamicPropertyDescriptor
  ) -> DynamicPropertyUpdatePlan? {
    let fieldCount = RuntimeFieldReflection.fieldCount(of: containerType)
    var extractors: [DynamicPropertyFieldExtractor] = unsafe []
    unsafe extractors.reserveCapacity(descriptor.fields.count)
    for field in descriptor.fields {
      guard field.index < fieldCount else {
        return nil
      }
      let info = RuntimeFieldReflection.fieldInfo(of: containerType, at: field.index)
      guard info.isStrong else {
        return nil
      }
      if let label = field.label, label != info.name {
        return nil
      }
      guard
        let extracting = openedExtractorShim(boundTo: info.fieldType)
          as? any DynamicPropertyFieldExtracting.Type
      else {
        // The static field type does not conform (`any DynamicProperty`,
        // `Any`, a supertype) even though this instance's value does.
        return nil
      }
      unsafe extractors.append(
        unsafe extracting.extractor(atOffset: info.offset, index: field.index)
      )
    }
    return unsafe .offsets(extractors)
  }

  /// Rebinds the shim's generic parameter to `fieldType` so the conditional
  /// conformance (`where T: DynamicProperty`) can be tested at runtime.
  private static func openedExtractorShim(boundTo fieldType: Any.Type) -> Any.Type {
    func open<F>(_ concrete: F.Type) -> Any.Type {
      DynamicPropertyFieldShim<F>.self
    }
    return _openExistential(fieldType, do: open)
  }
}

/// Conditional-conformance shim: `DynamicPropertyFieldShim<F>` conforms only
/// when `F: DynamicProperty`, so an `as? any ...Extracting.Type` cast is the
/// runtime conformance test — and inside the conformance, `T` is bound with
/// its constraint so the load is statically typed.
private protocol DynamicPropertyFieldExtracting {
  @MainActor static func extractor(atOffset offset: Int, index: Int)
    -> DynamicPropertyFieldExtractor
}

private enum DynamicPropertyFieldShim<T> {}

extension DynamicPropertyFieldShim: DynamicPropertyFieldExtracting where T: DynamicProperty {
  static func extractor(atOffset offset: Int, index: Int) -> DynamicPropertyFieldExtractor {
    unsafe DynamicPropertyFieldExtractor(index: index) { base in
      unsafe (base + offset).assumingMemoryBound(to: T.self).pointee
    }
  }
}

#if DEBUG
  /// Test-only observation of the update pass: fires once per `update()` call
  /// with the container type hosting the property and the property's own type.
  /// Production behavior is unchanged; tests install the hook to pin pass
  /// coverage on every body-evaluation surface.
  @MainActor
  package enum DynamicPropertyUpdatePassProbe {
    package static var onUpdate: ((_ containerType: Any.Type, _ propertyType: Any.Type) -> Void)?
  }
#endif

/// The ambient discovered-property path while the update pass runs: the
/// field-index path of the dynamic property whose nested properties are
/// currently updating. Built-in wrappers' `update()` implementations read it
/// to claim path-qualified slot identities; it is `.root` outside the pass
/// (and for top-level properties, whose identity must stay the legacy
/// ordinal-only key). A plain save/restore slot, not a task-local: the pass
/// is synchronous main-actor work with no suspension points.
@MainActor
package enum DynamicPropertyPathScope {
  package private(set) static var current: StateSlotPath = .root

  package static func withPath<Result>(
    _ path: StateSlotPath,
    _ apply: () -> Result
  ) -> Result {
    let saved = current
    current = path
    defer { current = saved }
    return apply()
  }
}

/// Runs the dynamic-property update pass over `view`'s discovered stored
/// properties. Call under the ambient authoring context the body will
/// observe — the pass must see exactly the scope the body's own wrapper
/// accesses will bind against (the ambient-wins rule).
@MainActor
package func runDynamicPropertyUpdatePass<V>(on view: V) {
  // Plans key on the DYNAMIC type: for a concrete `V` (every current caller)
  // it equals `V.self`; an existential `V` boxes a differently-typed value,
  // and its plan describes the boxed value's layout — see the offsets case.
  let concreteType = type(of: view)
  let plan =
    unsafe DynamicPropertyDescriptorCache.cachedUpdatePlan(for: concreteType)
    ?? DynamicPropertyDescriptorCache.updatePlan(reflecting: view)
  switch unsafe plan {
  case .empty:
    return
  case .offsets(let fields):
    if V.self == concreteType {
      unsafe withUnsafePointer(to: view) { base in
        unsafe updatePlannedDynamicProperties(
          atBase: UnsafeRawPointer(base),
          containerType: concreteType,
          fields: fields,
          path: .root
        )
      }
    } else {
      // Existential `V`: `withUnsafePointer(to: view)` would point at the
      // existential BOX, not the boxed value the plan's offsets describe —
      // open it first.
      unsafe withOpenedValue(view) { base, openedType in
        unsafe updatePlannedDynamicProperties(
          atBase: base,
          containerType: openedType,
          fields: fields,
          path: .root
        )
      }
    }
  case .mirrorWalk(let descriptor):
    updateDiscoveredDynamicProperties(of: view, descriptor: descriptor, path: .root)
  }
}

/// Installs the primitive dynamic-property authoring scope for `view`'s
/// resolve and runs the update pass inside it. The `ResolvableView` surfaces
/// that build their own scopes via `dynamicPropertyAuthoringContext(for:)`
/// route through this so the pass runs under the exact context their stored
/// wrappers bind against.
@MainActor
package func withDynamicPropertyUpdateScope<V, Result>(
  _ view: V,
  for context: ResolveContext,
  _ apply: () -> Result
) -> Result {
  let scope = dynamicPropertyAuthoringContext(for: context)
  return withAuthoringContext(scope) {
    runDynamicPropertyUpdatePass(on: view)
    return apply()
  }
}

@MainActor
private func updatePlannedDynamicProperties(
  atBase base: UnsafeRawPointer,
  containerType: Any.Type,
  fields: [DynamicPropertyFieldExtractor],
  path: StateSlotPath
) {
  for unsafe field in unsafe fields {
    var property = unsafe field.extract(base)
    updateDynamicProperty(
      &property,
      containerType: containerType,
      containerPath: path,
      fieldIndex: unsafe field.index
    )
  }
}

@MainActor
private func updateDiscoveredDynamicProperties(
  of container: Any,
  descriptor: DynamicPropertyDescriptor,
  path: StateSlotPath
) {
  let containerType = type(of: container)
  let mirror = Mirror(reflecting: container)
  var fieldIterator = descriptor.fields.makeIterator()
  var pendingField = fieldIterator.next()
  var index = 0
  for child in mirror.children {
    guard let field = pendingField else {
      return
    }
    if index == field.index {
      if var property = child.value as? any DynamicProperty {
        updateDynamicProperty(
          &property,
          containerType: containerType,
          containerPath: path,
          fieldIndex: field.index
        )
      }
      pendingField = fieldIterator.next()
    }
    index += 1
  }
}

@MainActor
private func updateDynamicProperty(
  _ property: inout any DynamicProperty,
  containerType: Any.Type,
  containerPath: StateSlotPath,
  fieldIndex: Int
) {
  // Nested dynamic properties update before their container so the
  // container's own update() observes live composed state. The nested pass
  // runs under this property's own field path — that qualification is what
  // gives two instances of one composed wrapper distinct nested slots. The
  // property's own update() runs under the CONTAINER's path: a top-level
  // built-in must bind the legacy empty-path identity.
  let nestedPlan =
    unsafe DynamicPropertyDescriptorCache.cachedUpdatePlan(for: type(of: property))
    ?? DynamicPropertyDescriptorCache.updatePlan(reflecting: property)
  switch unsafe nestedPlan {
  case .empty:
    break
  case .offsets(let fields):
    let nestedPath = containerPath.appending(fieldIndex)
    unsafe withOpenedValue(property) { base, concreteType in
      unsafe updatePlannedDynamicProperties(
        atBase: base,
        containerType: concreteType,
        fields: fields,
        path: nestedPath
      )
    }
  case .mirrorWalk(let descriptor):
    updateDiscoveredDynamicProperties(
      of: property,
      descriptor: descriptor,
      path: containerPath.appending(fieldIndex)
    )
  }
  var updating = property
  DynamicPropertyPathScope.withPath(containerPath) {
    updating.update()
  }
  #if DEBUG
    DynamicPropertyUpdatePassProbe.onUpdate?(containerType, type(of: property))
  #endif
}

/// Opens the existential (or re-monomorphizes a generic value) so the offset
/// walk gets the concrete value's base pointer — a pointer to an existential
/// box would not match the plan's offsets.
@MainActor
private func withOpenedValue<V>(
  _ value: V,
  _ body: (UnsafeRawPointer, Any.Type) -> Void
) {
  func open<P>(_ concrete: P) {
    unsafe withUnsafePointer(to: concrete) { pointer in
      unsafe body(UnsafeRawPointer(pointer), P.self)
    }
  }
  _openExistential(value as Any, do: open)
}
