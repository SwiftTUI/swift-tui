/// Package-shared bindings to the Swift runtime's field-reflection entry
/// points.
///
/// The stdlib's `@_spi(Reflection) _forEachField` is unavailable when the
/// Swift module is built from its public swiftinterface (the Xcode SDK case),
/// so this file binds the runtime entry points that back both `_forEachField`
/// and `Mirror` directly. They are exported by the Swift runtime on every
/// platform this framework targets (macOS/Linux/WASI/Android); the fixture
/// tests in `MemoComparisonPlanTests` pin their behavior per toolchain bump.
/// Reflection metadata must stay enabled (it is the default everywhere).
///
/// Consumers: the memo comparison-plan builder (`MemoComparisonPlan.swift`)
/// and the dynamic-property update pass's offset plans (SwiftTUIViews). Both
/// walk fields once per concrete type on a cold path and bind everything they
/// learn into closures — no per-use reflection.

private typealias FieldNameFreeFunc = @convention(c) (UnsafePointer<CChar>?) -> Void

@unsafe private struct FieldReflectionMetadata {
  let name: UnsafePointer<CChar>? = nil
  let freeFunc: FieldNameFreeFunc? = nil
  let isStrong: Bool = false
  let isVar: Bool = false
}

@_silgen_name("swift_reflectionMirror_recursiveCount")
private func runtimeFieldCount(_: Any.Type) -> Int

@_silgen_name("swift_reflectionMirror_recursiveChildMetadata")
private func runtimeChildMetadata(
  _: Any.Type,
  index: Int,
  fieldMetadata: UnsafeMutablePointer<FieldReflectionMetadata>
) -> Any.Type

@_silgen_name("swift_reflectionMirror_recursiveChildOffset")
private func runtimeChildOffset(_: Any.Type, index: Int) -> Int

@_silgen_name("swift_getMetadataKind")
private func runtimeMetadataKind(_: Any.Type) -> UInt

package enum RuntimeFieldReflection {
  /// `swift_getMetadataKind` values dispatch sites compare against (from the
  /// runtime's `MetadataKind.def`; pinned by `MemoComparisonPlanTests`).
  package static let structureKind: UInt = 512
  package static let tupleKind: UInt = 769

  /// One stored field's static metadata: the substituted concrete field type,
  /// its byte offset from the aggregate's base, and its declared name
  /// (`_count` for `@State var count`).
  package struct FieldInfo {
    package let name: String
    package let fieldType: Any.Type
    package let offset: Int
    package let isStrong: Bool
  }

  package static func metadataKind(of type: Any.Type) -> UInt {
    runtimeMetadataKind(type)
  }

  package static func fieldCount(of type: Any.Type) -> Int {
    runtimeFieldCount(type)
  }

  package static func fieldInfo(of type: Any.Type, at index: Int) -> FieldInfo {
    var metadata = unsafe FieldReflectionMetadata()
    let fieldType = unsafe runtimeChildMetadata(
      type,
      index: index,
      fieldMetadata: &metadata
    )
    let name = unsafe metadata.name.map { unsafe String(cString: $0) } ?? ""
    unsafe metadata.freeFunc?(metadata.name)
    return FieldInfo(
      name: name,
      fieldType: fieldType,
      offset: runtimeChildOffset(type, index: index),
      isStrong: unsafe metadata.isStrong
    )
  }

  /// Name-free variant for walks that never read the name (skips the `String`
  /// conversion; still frees the runtime-allocated name buffer).
  package static func fieldTypeAndOffset(
    of type: Any.Type,
    at index: Int
  ) -> (fieldType: Any.Type, offset: Int) {
    var metadata = unsafe FieldReflectionMetadata()
    let fieldType = unsafe runtimeChildMetadata(
      type,
      index: index,
      fieldMetadata: &metadata
    )
    unsafe metadata.freeFunc?(metadata.name)
    return (fieldType, runtimeChildOffset(type, index: index))
  }
}
