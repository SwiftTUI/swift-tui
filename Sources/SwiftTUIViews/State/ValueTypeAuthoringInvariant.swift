import SwiftTUIGraph

// The value-type authoring invariant's runtime floor (plan 2026-08-29-001).
//
// `View`, `ViewModifier`, the four style protocols, `DynamicProperty`,
// `Scene`, and `App` each declare an unavailable-for-classes witness, so a
// class container cannot conform from Swift source — the compile-time
// diagnostic is the contract. This is the belt-and-braces floor beneath it,
// installed in the two cold, reflect-once-per-type plan builders both state
// passes funnel every authored container through
// (`DynamicPropertyDescriptorCache.updatePlan(reflecting:)` and
// `DynamicPropertyCaptureBindPlanCache.buildPlan(for:)`).
//
// It costs nothing warm — a cached plan never re-enters the builder — and it
// keeps the deleted class arms honest against the shapes the witness cannot
// see: a future toolchain that changes the unavailable-witness diagnostic, a
// `@testable` bypass, or a metadata shape reflection reports as a class where
// the type checker did not.
package enum ValueTypeAuthoringInvariant {
  /// Native Swift class (`0`), foreign class (`0x203`), and the
  /// Objective-C class wrapper (`0x305`) — the same class kinds the update
  /// pass's value-dependent field scan enumerates.
  @inline(__always)
  package static func isClassKind(_ kind: UInt) -> Bool {
    kind == 0 || kind == 0x203 || kind == 0x305
  }

  /// Traps for a class container that reached an authoring plan builder.
  package static func rejectClassContainer(_ type: Any.Type) -> Never {
    preconditionFailure(
      "SwiftTUI views, view modifiers, styles, and dynamic properties must be value types "
        + "(a struct or an enum); \(type) is a class."
    )
  }

  /// Cold-path guard for a container type about to be given a plan.
  @inline(__always)
  package static func requireValueTypeContainer(_ type: Any.Type) {
    if isClassKind(RuntimeFieldReflection.metadataKind(of: type)) {
      rejectClassContainer(type)
    }
  }
}
