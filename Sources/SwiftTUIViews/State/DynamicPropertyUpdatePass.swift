package import SwiftTUIGraph

// The dynamic-property update pass — discovery and execution.
//
// Views (and dynamic properties) declare wrappers as stored properties; the
// framework discovers the ones conforming to `DynamicProperty` with a
// reflect-once-per-type descriptor cache and runs `update()` on each before
// the body evaluates, under the same ambient authoring context the body will
// observe. Wrapper-free types pay one dictionary lookup per evaluation and no
// reflection after the first (the empty-descriptor fast path).
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

/// Reflect-once-per-type cache of ``DynamicPropertyDescriptor``s.
///
/// Struct and class layouts are fixed per type, so their descriptors cache
/// permanently. Enum values (whose reflected children vary by case) are
/// rebuilt per value and never cached — no view or wrapper in the framework
/// is enum-shaped, so this is a correctness backstop, not a hot path.
/// Computed properties are invisible to `Mirror` — discovery sees stored
/// properties only, matching SwiftUI.
@MainActor
package enum DynamicPropertyDescriptorCache {
  private static var descriptorsByType: [ObjectIdentifier: DynamicPropertyDescriptor] = [:]

  package static func descriptor(reflecting value: Any) -> DynamicPropertyDescriptor {
    let key = ObjectIdentifier(type(of: value))
    if let cached = descriptorsByType[key] {
      return cached
    }
    let mirror = Mirror(reflecting: value)
    let descriptor = buildDescriptor(from: mirror)
    switch mirror.displayStyle {
    case .struct, .class:
      descriptorsByType[key] = descriptor
    default:
      break
    }
    return descriptor
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
  let descriptor = DynamicPropertyDescriptorCache.descriptor(reflecting: view)
  guard !descriptor.isEmpty else {
    return
  }
  updateDiscoveredDynamicProperties(of: view, descriptor: descriptor, path: .root)
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
  let nested = DynamicPropertyDescriptorCache.descriptor(reflecting: property)
  if !nested.isEmpty {
    updateDiscoveredDynamicProperties(
      of: property,
      descriptor: nested,
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
