import SwiftTUICore

extension View {
  /// Prints a best-effort explanation of this body's current evaluation.
  ///
  /// Call `let _ = Self._printChanges()` inside `body`. Reused bodies are
  /// silent. Output describes an evaluation attempt, not a displayed frame.
  /// Debug bundles receive `changes.log`; otherwise the host selects a safe
  /// diagnostic destination. Available in all builds; inert without `DEBUG`.
  @_documentation(visibility: public)
  public static func _printChanges() {
    #if DEBUG
      emitBodyChanges(Self.self, kind: "view", format: .text)
    #endif
  }

  /// Logs the same body explanation as ``_printChanges()`` as a structured
  /// diagnostic record. Bundles receive `changes.jsonl`; host adapters may
  /// use the system log. The diagnostic schema is not a public data API.
  @_documentation(visibility: public)
  public static func _logChanges() {
    #if DEBUG
      emitBodyChanges(Self.self, kind: "view", format: .json)
    #endif
  }
}

extension ViewModifier {
  /// Prints why this custom modifier's `body(content:)` is being evaluated.
  /// Call `let _ = Self._printChanges()` inside that method. Inert in release.
  @_documentation(visibility: public)
  public static func _printChanges() {
    #if DEBUG
      emitBodyChanges(Self.self, kind: "modifier", format: .text)
    #endif
  }

  /// Logs a structured explanation of this custom modifier's evaluation.
  /// Causes match ``_printChanges()``; no application values are included.
  @_documentation(visibility: public)
  public static func _logChanges() {
    #if DEBUG
      emitBodyChanges(Self.self, kind: "modifier", format: .json)
    #endif
  }
}

#if DEBUG
  @MainActor
  private func emitBodyChanges(_ type: Any.Type, kind: String, format: BodyChangeFormat) {
    let record: BodyChangeRecord
    if let scope = BodyChangeScope.current,
      scope.key.type == ObjectIdentifier(type), scope.key.kind == kind
    {
      record = scope.record()
    } else {
      record = BodyChangeRecord(
        typeName: BodyChangeRecord.name(of: type), kind: kind,
        causes: [.init("context-unavailable", precision: "unavailable")])
    }
    BodyChangeOutput.emit(record, format: format)
  }

  @MainActor
  package func withBodyChangeScope<Value, Result>(
    _ value: Value, kind: String, _ apply: () -> Result
  ) -> Result {
    guard let node = ViewNodeContext.current, let graph = node.ownerGraph else {
      let saved = BodyChangeScope.current
      BodyChangeScope.current = nil
      defer { BodyChangeScope.current = saved }
      return apply()
    }
    let scope = graph.debugBodyChanges.makeScope(type: Value.self, kind: kind, node: node)
    scope.names = { bodyChangePropertyNames(in: value) }
    return scope.run(apply)
  }

  /// Framework-only wrapper metadata. Implementations may inspect declaration
  /// and capture tokens, never wrappedValue or an application's computed data.
  @MainActor
  package protocol BodyDebugStateDeclaring {
    func bodyDebugStateSlot(path: StateSlotPath) -> StateSlotKey?
  }

  @MainActor
  private func bodyChangePropertyNames<Value>(in value: Value) -> [StateSlotKey: String] {
    var result: [StateSlotKey: String] = [:]
    var visited = 0
    @MainActor func visit<T>(_ value: T, path: StateSlotPath, labels: [String], depth: Int) {
      guard depth < 16, visited < 256,
        RuntimeFieldReflection.metadataKind(of: T.self) == RuntimeFieldReflection.structureKind
      else { return }
      let owner = value as? any AdditionalDynamicPropertyUpdating
      withUnsafePointer(to: value) { pointer in
        for index in 0..<min(256, RuntimeFieldReflection.fieldCount(of: T.self)) {
          guard visited < 256 else { break }
          visited += 1
          let info = RuntimeFieldReflection.fieldInfo(of: T.self, at: index)
          guard info.isStrong, info.fieldType is any DynamicProperty.Type,
            owner?.ownsDynamicPropertyTraversal(ofStoredFieldAt: index) != true
          else { continue }
          @MainActor func open<Field>(_ type: Field.Type) {
            let field = unsafe UnsafeRawPointer(pointer).advanced(by: info.offset)
              .assumingMemoryBound(to: Field.self).pointee
            let name = labels + [info.name]
            if let declaration = field as? any BodyDebugStateDeclaring,
              let slot = declaration.bodyDebugStateSlot(path: path)
            {
              result[slot] = name.joined(separator: ".")
            } else if let declaration = field as? any HotReloadSlotDeclaring,
              let (slot, _) = declaration.hotReloadDeclaration(path: path),
              let owner = currentAuthoringContext()?.stateOwnerHandle
            {
              result[.init(owner: owner.ownerLifetime, slot: slot)] = name.joined(separator: ".")
            } else {
              visit(field, path: path.appending(index), labels: name, depth: depth + 1)
            }
          }
          _openExistential(info.fieldType, do: open)
        }
      }
    }
    visit(value, path: .root, labels: [], depth: 0)
    return result
  }
#endif
