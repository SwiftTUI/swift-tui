package import SwiftTUIGraph

// The dynamic-property update pass — discovery and execution.
//
// Views (and dynamic properties) declare wrappers as stored properties; the
// framework discovers the ones conforming to `DynamicProperty` with a
// reflect-once-per-type descriptor and runs `update(in:)` on each before the
// body evaluates, under the same ambient authoring context the body will
// observe. Wrapper-free types pay one dictionary lookup per evaluation and no
// reflection after the first (the `.empty`-plan fast path).
//
// Per-evaluation extraction is plan-dispatched: struct containers whose
// discovered fields are statically wrapper-typed get an *offset plan* —
// extractor closures bound once per type via `RuntimeFieldReflection` that
// copy each wrapper straight out of the container's value memory, replacing
// the per-instance `Mirror` walk (which allocated a mirror and boxed every
// child per body evaluation). Exotic shapes (enum containers, and fields
// whose *static* type does not conform — e.g. an existential- or `Any`-typed
// field boxing a wrapper) keep the legacy `Mirror` walk, so discovery
// semantics are unchanged; only the extraction mechanism differs. A class
// container is not an exotic shape but an invariant violation: authored
// containers are value types, and the builder traps on one (see
// `ValueTypeAuthoringInvariant`).
//
// The public contract is nonmutating and reference-backed, so extracting a
// property value cannot silently discard a promised value mutation.

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
/// Struct and class layouts are fixed per type, so their plans normally cache
/// permanently. Static fields that permit dynamically conforming values are
/// included proactively in a stable Mirror-walk plan even when the first
/// instance is plain. Enum values (whose reflected children vary by case)
/// are rebuilt per value and never cached — no view or wrapper in the framework
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
    let descriptor = descriptorIncludingValueDependentStorage(
      buildDescriptor(from: mirror),
      containerType: type(of: value)
    )
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
      // Unreachable from Swift source: every authoring protocol a container
      // can reach this builder through rejects class conformers at compile
      // time. See ValueTypeAuthoringInvariant.
      ValueTypeAuthoringInvariant.rejectClassContainer(type(of: value))
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

  /// Adds every stored field whose concrete value can change type and gain a
  /// DynamicProperty conformance without changing the container type. The
  /// resulting stable Mirror plan runtime-checks those fields each evaluation,
  /// so both plain-first and DynamicProperty-first orderings are sound.
  private static func descriptorIncludingValueDependentStorage(
    _ descriptor: DynamicPropertyDescriptor,
    containerType: Any.Type
  ) -> DynamicPropertyDescriptor {
    var fieldsByIndex = Dictionary(
      uniqueKeysWithValues: descriptor.fields.map { ($0.index, $0) }
    )
    let fieldCount = RuntimeFieldReflection.fieldCount(of: containerType)
    for index in 0..<fieldCount {
      let field = RuntimeFieldReflection.fieldInfo(
        of: containerType,
        at: index
      )
      switch RuntimeFieldReflection.metadataKind(of: field.fieldType) {
      case 0, 0x203, 0x303, 0x305:
        // Native/foreign classes, existential storage (`Any`, `AnyObject`,
        // protocol values), and Objective-C class wrappers can all carry a
        // later concrete value whose conformance differs from this instance.
        fieldsByIndex[index] = .init(index: index, label: field.name)
      default:
        continue
      }
    }
    return DynamicPropertyDescriptor(
      fields: fieldsByIndex.values.sorted { $0.index < $1.index }
    )
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

@MainActor
package protocol AdditionalDynamicPropertyUpdating {
  /// True when this transparent container forwards the stored field itself.
  /// Outer discovery must not also traverse that field under the container's
  /// scope and path.
  func ownsDynamicPropertyTraversal(ofStoredFieldAt index: Int) -> Bool

  func updateAdditionalDynamicProperties(
    in context: AdditionalDynamicPropertyUpdateContext
  ) -> DynamicPropertyUpdateResult

  /// Whether the explicitly forwarded payload currently carries any update
  /// surface. Containers answer recursively so a wrapper-free transparent
  /// value does not turn a local fail-closed policy into an enclosing reuse
  /// denial merely because it participates in forwarding.
  func hasAdditionalDynamicPropertyUpdateSurface() -> Bool
}

@MainActor
package struct AdditionalDynamicPropertyUpdateContext {
  package let resolveContext: ResolveContext
  package let graphNode: SwiftTUICore.ViewNode?

  package var destinationAuthoringContext: AuthoringContext {
    makeAuthoringContext(for: resolveContext, viewNode: graphNode)
  }
}

/// One synchronous `resolveView` invocation's forwarded-preparation entries.
///
/// Transparent primitive modifiers prepare their base before the modifier's
/// own reuse door. The later nested central resolve consumes that preparation
/// instead of clearing the same node's lease census and walking the value a
/// second time. Frames form a strict synchronous stack: an entry is scoped to
/// the exact graph node, resolve identity/path, value type, producer
/// generation, and LIFO occurrence. Unconsumed entries disappear with the
/// producer frame on memo service, early return, or abort.
@MainActor
package enum ForwardedDynamicPropertyPreparationScope {
  private final class Frame {
    let generation: UInt64
    var entries: [Entry] = []

    init(generation: UInt64) {
      self.generation = generation
    }
  }

  private struct Entry {
    let producerGeneration: UInt64
    let occurrence: UInt64
    let graphID: ObjectIdentifier?
    let graphNodeID: ViewNodeID?
    let identity: Identity
    let structuralPath: StructuralPath
    let valueType: ObjectIdentifier
    let context: ResolveContext
    let result: DynamicPropertyUpdateResult
  }

  package struct Token {
    fileprivate let generation: UInt64
  }

  private static var frames: [Frame] = []
  private static var nextGeneration: UInt64 = 0
  private static var nextOccurrence: UInt64 = 0

  package static func begin() -> Token {
    nextGeneration &+= 1
    let frame = Frame(generation: nextGeneration)
    frames.append(frame)
    return Token(generation: frame.generation)
  }

  package static func end(_ token: Token) {
    precondition(frames.last?.generation == token.generation)
    _ = frames.popLast()
  }

  package static func record<V>(
    _ value: V,
    context: ResolveContext,
    graphNode: SwiftTUICore.ViewNode?,
    result: DynamicPropertyUpdateResult
  ) {
    guard let frame = frames.last else { return }
    nextOccurrence &+= 1
    frame.entries.append(
      Entry(
        producerGeneration: frame.generation,
        occurrence: nextOccurrence,
        graphID: context.viewGraph.map(ObjectIdentifier.init),
        graphNodeID: graphNode?.viewNodeID,
        identity: context.identity,
        structuralPath: context.structuralPath,
        valueType: ObjectIdentifier(type(of: value)),
        context: context,
        result: result
      )
    )
  }

  package static func preparedContext<V>(
    for value: V,
    fallback: ResolveContext,
    graphNode: SwiftTUICore.ViewNode?
  ) -> ResolveContext? {
    matchingProducerEntry(
      value,
      context: fallback,
      graphNode: graphNode
    )?.context
  }

  package static func take<V>(
    _ value: V,
    context: ResolveContext,
    graphNode: SwiftTUICore.ViewNode?
  ) -> DynamicPropertyUpdateResult? {
    guard
      let index = matchingFrameIndex(
        value,
        context: context,
        graphNode: graphNode
      )
    else { return nil }
    // Strict LIFO is the occurrence proof for nested same-identity/same-type
    // transparent layers. Never search past a mismatching latest entry.
    return frames[index].entries.removeLast().result
  }

  private static func matchingProducerEntry<V>(
    _ value: V,
    context: ResolveContext,
    graphNode: SwiftTUICore.ViewNode?
  ) -> Entry? {
    guard
      let index = matchingFrameIndex(
        value,
        context: context,
        graphNode: graphNode,
        includesCurrentFrame: true
      )
    else { return nil }
    return frames[index].entries.last
  }

  private static func matchingFrameIndex<V>(
    _ value: V,
    context: ResolveContext,
    graphNode: SwiftTUICore.ViewNode?,
    includesCurrentFrame: Bool = false
  ) -> Int? {
    let start = frames.count - (includesCurrentFrame ? 1 : 2)
    guard start >= 0 else { return nil }
    let graphID = context.viewGraph.map(ObjectIdentifier.init)
    let valueType = ObjectIdentifier(type(of: value))
    // The current frame is the consumer. Only an active ancestor may have
    // prepared it, and the nearest ancestor with pending work owns the next
    // occurrence.
    for index in stride(from: start, through: 0, by: -1) {
      guard let entry = frames[index].entries.last else { continue }
      guard entry.producerGeneration == frames[index].generation,
        entry.occurrence <= nextOccurrence,
        entry.graphID == graphID,
        entry.graphNodeID == graphNode?.viewNodeID,
        entry.identity == context.identity,
        entry.structuralPath == context.structuralPath,
        entry.valueType == valueType
      else {
        return nil
      }
      return index
    }
    return nil
  }
}

@MainActor
package func prepareDynamicProperties<V>(
  of view: V,
  in context: ResolveContext,
  routeIdentity: EntityIdentity?,
  authoringContextOverride: AuthoringContext?
) -> DynamicPropertyUpdateResult {
  let existingGraphNode: SwiftTUICore.ViewNode?
  if let routeIdentity,
    let routed = context.viewGraph?.nodeForEntityIdentity(routeIdentity)
  {
    existingGraphNode = routed
  } else {
    existingGraphNode = context.viewGraph?.nodeForIdentity(context.identity)
  }
  if let prepared = ForwardedDynamicPropertyPreparationScope.take(
    view,
    context: context,
    graphNode: existingGraphNode
  ) {
    return prepared
  }
  let plan =
    unsafe DynamicPropertyDescriptorCache.cachedUpdatePlan(for: type(of: view))
    ?? DynamicPropertyDescriptorCache.updatePlan(reflecting: view)
  let hasDirectProperties: Bool
  switch unsafe plan {
  case .empty: hasDirectProperties = false
  case .offsets, .mirrorWalk: hasDirectProperties = true
  }
  let additional = view as? any AdditionalDynamicPropertyUpdating
  let graphNode = context.viewGraph?.prepareDynamicPropertyUpdate(
    identity: context.identity,
    entityIdentity: routeIdentity
  )
  guard hasDirectProperties || additional != nil else {
    return .unchanged
  }
  let scope =
    authoringContextOverride.map { rebasedAuthoringContext($0, viewNode: graphNode) }
    ?? dynamicPropertyAuthoringContext(
      for: context,
      current: currentAuthoringContext(),
      viewNode: graphNode
    )
  let additionalContext = AdditionalDynamicPropertyUpdateContext(
    resolveContext: context,
    graphNode: graphNode
  )

  return EnvironmentValuesStorage.binding(context.environmentValues) {
    ViewNodeContext.withCurrentValue(graphNode) {
      withAuthoringContext(scope) {
        runDynamicPropertyUpdates(on: view, in: additionalContext)
      }
    }
  }
}

/// Runs every update source carried directly by `value`: discovered stored
/// properties plus a transparent container's explicitly forwarded payload.
/// Callers own graph preparation and the authoring scope.
@MainActor
package func runDynamicPropertyUpdates<V>(
  on value: V,
  in context: AdditionalDynamicPropertyUpdateContext
) -> DynamicPropertyUpdateResult {
  let additional = value as? any AdditionalDynamicPropertyUpdating
  var result = runDynamicPropertyUpdatePass(
    on: value,
    excludingFieldsOwnedBy: additional
  )
  if let additional {
    result = result.merging(
      additional.updateAdditionalDynamicProperties(in: context)
    )
  }
  return result
}

/// Whether `value` has a direct or explicitly forwarded update surface.
///
/// Containers use this before conservatively denying an enclosing reuse door.
/// Wrapper-free values must not turn a local fail-closed traversal policy into
/// a global reuse shutdown.
@MainActor
package func hasDynamicPropertyUpdateSurface<V>(_ value: V) -> Bool {
  if value is any DynamicProperty {
    return true
  }
  if let additional = value as? any AdditionalDynamicPropertyUpdating {
    return additional.hasAdditionalDynamicPropertyUpdateSurface()
  }
  let plan =
    unsafe DynamicPropertyDescriptorCache.cachedUpdatePlan(for: type(of: value))
    ?? DynamicPropertyDescriptorCache.updatePlan(reflecting: value)
  switch unsafe plan {
  case .empty:
    return false
  case .offsets, .mirrorWalk:
    return true
  }
}

/// Runs a transparent payload as its own root value. Its stored properties use
/// root-relative paths, and a payload that is itself DynamicProperty receives
/// its own update after those nested properties.
@MainActor
package func runForwardedDynamicPropertyUpdates<V>(
  on value: V,
  in context: AdditionalDynamicPropertyUpdateContext
) -> DynamicPropertyUpdateResult {
  var result = runDynamicPropertyUpdates(on: value, in: context)
  if let property = value as? any DynamicProperty {
    result = result.merging(
      updateDynamicPropertyValue(
        property,
        containerType: type(of: value),
        propertyPath: .root,
        updatePath: .root
      )
    )
  }
  return result
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
  /// Test-only observation of the update pass: fires once per `update(in:)` call
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
/// currently updating. Built-in wrappers' `update(in:)` implementations read it
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
@discardableResult
package func runDynamicPropertyUpdatePass<V>(on view: V) -> DynamicPropertyUpdateResult {
  runDynamicPropertyUpdatePass(on: view, excludingFieldsOwnedBy: nil)
}

@MainActor
private func runDynamicPropertyUpdatePass<V>(
  on view: V,
  excludingFieldsOwnedBy owner: (any AdditionalDynamicPropertyUpdating)?
) -> DynamicPropertyUpdateResult {
  // Plans key on the DYNAMIC type: for a concrete `V` (every current caller)
  // it equals `V.self`; an existential `V` boxes a differently-typed value,
  // and its plan describes the boxed value's layout — see the offsets case.
  let concreteType = type(of: view)
  let plan =
    unsafe DynamicPropertyDescriptorCache.cachedUpdatePlan(for: concreteType)
    ?? DynamicPropertyDescriptorCache.updatePlan(reflecting: view)
  switch unsafe plan {
  case .empty:
    return .unchanged
  case .offsets(let fields):
    if V.self == concreteType {
      return unsafe withUnsafePointer(to: view) { base in
        unsafe updatePlannedDynamicProperties(
          atBase: UnsafeRawPointer(base),
          containerType: concreteType,
          fields: fields,
          path: .root,
          excludingFieldsOwnedBy: owner
        )
      }
    } else {
      // Existential `V`: `withUnsafePointer(to: view)` would point at the
      // existential BOX, not the boxed value the plan's offsets describe —
      // open it first.
      return unsafe withOpenedValue(view) { base, openedType in
        unsafe updatePlannedDynamicProperties(
          atBase: base,
          containerType: openedType,
          fields: fields,
          path: .root,
          excludingFieldsOwnedBy: owner
        )
      }
    }
  case .mirrorWalk(let descriptor):
    return updateDiscoveredDynamicProperties(
      of: view,
      descriptor: descriptor,
      path: .root,
      excludingFieldsOwnedBy: owner
    )
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
    return apply()
  }
}

@MainActor
private func updatePlannedDynamicProperties(
  atBase base: UnsafeRawPointer,
  containerType: Any.Type,
  fields: [DynamicPropertyFieldExtractor],
  path: StateSlotPath,
  excludingFieldsOwnedBy owner: (any AdditionalDynamicPropertyUpdating)? = nil
) -> DynamicPropertyUpdateResult {
  var result = DynamicPropertyUpdateResult.unchanged
  for unsafe field in unsafe fields {
    if owner?.ownsDynamicPropertyTraversal(ofStoredFieldAt: unsafe field.index) == true {
      continue
    }
    let property = unsafe field.extract(base)
    result = result.merging(
      updateDynamicProperty(
        property,
        containerType: containerType,
        containerPath: path,
        fieldIndex: unsafe field.index
      ))
  }
  return result
}

@MainActor
private func updateDiscoveredDynamicProperties(
  of container: Any,
  descriptor: DynamicPropertyDescriptor,
  path: StateSlotPath,
  excludingFieldsOwnedBy owner: (any AdditionalDynamicPropertyUpdating)? = nil
) -> DynamicPropertyUpdateResult {
  let containerType = type(of: container)
  let mirror = Mirror(reflecting: container)
  var result = DynamicPropertyUpdateResult.unchanged
  var fieldIterator = descriptor.fields.makeIterator()
  var pendingField = fieldIterator.next()
  var index = 0
  for child in mirror.children {
    guard let field = pendingField else {
      return result
    }
    if index == field.index {
      if owner?.ownsDynamicPropertyTraversal(ofStoredFieldAt: field.index) == true {
        pendingField = fieldIterator.next()
        index += 1
        continue
      }
      if let property = child.value as? any DynamicProperty {
        result = result.merging(
          updateDynamicProperty(
            property,
            containerType: containerType,
            containerPath: path,
            fieldIndex: field.index
          ))
      }
      pendingField = fieldIterator.next()
    }
    index += 1
  }
  return result
}

@MainActor
private func updateDynamicProperty(
  _ property: any DynamicProperty,
  containerType: Any.Type,
  containerPath: StateSlotPath,
  fieldIndex: Int
) -> DynamicPropertyUpdateResult {
  // Nested dynamic properties update before their container so the
  // container's own update(in:) observes live composed state. The nested pass
  // runs under this property's own field path — that qualification is what
  // gives two instances of one composed wrapper distinct nested slots. The
  // property's own update(in:) runs under the CONTAINER's path: a top-level
  // built-in must bind the legacy empty-path identity.
  let nestedPlan =
    unsafe DynamicPropertyDescriptorCache.cachedUpdatePlan(for: type(of: property))
    ?? DynamicPropertyDescriptorCache.updatePlan(reflecting: property)
  let nestedResult: DynamicPropertyUpdateResult
  switch unsafe nestedPlan {
  case .empty:
    nestedResult = .unchanged
  case .offsets(let fields):
    let nestedPath = containerPath.appending(fieldIndex)
    nestedResult = unsafe withOpenedValue(property) { base, concreteType in
      unsafe updatePlannedDynamicProperties(
        atBase: base,
        containerType: concreteType,
        fields: fields,
        path: nestedPath
      )
    }
  case .mirrorWalk(let descriptor):
    nestedResult = updateDiscoveredDynamicProperties(
      of: property,
      descriptor: descriptor,
      path: containerPath.appending(fieldIndex)
    )
  }
  let propertyPath = containerPath.appending(fieldIndex)
  let ownResult = updateDynamicPropertyValue(
    property,
    containerType: containerType,
    propertyPath: propertyPath,
    updatePath: containerPath
  )
  return nestedResult.merging(ownResult)
}

@MainActor
private func updateDynamicPropertyValue(
  _ property: any DynamicProperty,
  containerType: Any.Type,
  propertyPath: StateSlotPath,
  updatePath: StateSlotPath
) -> DynamicPropertyUpdateResult {
  let result = DynamicPropertyPathScope.withPath(updatePath) {
    let context: DynamicPropertyContext
    if property is any DynamicPropertyLeaseIndependent {
      context = .leaseIndependent
    } else {
      context = DynamicPropertyContext.current(
        containerType: containerType,
        structuralPath: currentAuthoringContext()?.structuralPath.description ?? "",
        fieldPath: propertyPath.description
      )
    }
    return property.update(
      in: context
    )
  }
  #if DEBUG
    DynamicPropertyUpdatePassProbe.onUpdate?(containerType, type(of: property))
  #endif
  return result
}

/// Opens the existential (or re-monomorphizes a generic value) so the offset
/// walk gets the concrete value's base pointer — a pointer to an existential
/// box would not match the plan's offsets.
@MainActor
private func withOpenedValue<V>(
  _ value: V,
  _ body: (UnsafeRawPointer, Any.Type) -> DynamicPropertyUpdateResult
) -> DynamicPropertyUpdateResult {
  func open<P>(_ concrete: P) -> DynamicPropertyUpdateResult {
    unsafe withUnsafePointer(to: concrete) { pointer in
      unsafe body(UnsafeRawPointer(pointer), P.self)
    }
  }
  return _openExistential(value as Any, do: open)
}
