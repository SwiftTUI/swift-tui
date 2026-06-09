#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#elseif canImport(WASILibc)
  import WASILibc
#endif

/// Opt-in gate for **reader-attributed** `@State` read tracking.
///
/// Legacy (default) behavior attributes every state read — including the eager
/// read performed when a `$binding` is merely *projected* — to the slot's
/// **owner** node, so a `@State` change re-resolves the owner's entire subtree.
/// That is why toggling `.sheet(isPresented: $flag)` re-resolves the whole
/// background: the presenting view (owner) is an ancestor of it.
///
/// When enabled, a state read is attributed to the node that is *actually
/// evaluating* when the read happens (`ViewNodeContext.current`), projecting a
/// binding records no read, and the owner is dirtied only when it genuinely
/// reads `wrappedValue`. A `@State` change then re-resolves only its real
/// readers, sparing disjoint subtrees — taking sheet/palette open from
/// O(background) to O(overlay).
///
/// Test-settable; defaults from `SWIFTTUI_READER_ATTRIBUTION` at first access.
@MainActor
package enum ReaderAttributionConfiguration {
  package static let environmentVariableName = "SWIFTTUI_READER_ATTRIBUTION"

  /// Whether reads attribute to the evaluating reader rather than the slot
  /// owner. Off by default; the run loop sets it from the environment before the
  /// first render, and tests set it directly.
  package static var isEnabled: Bool = environmentDefault()

  private static func environmentDefault() -> Bool {
    guard let rawValue = environmentValue(named: environmentVariableName) else {
      return false
    }
    return !rawValue.isEmpty && rawValue != "0"
  }

  private static func environmentValue(named name: String) -> String? {
    unsafe name.withCString { cName in
      guard let rawValue = unsafe getenv(cName) else {
        return nil
      }
      return unsafe String(cString: rawValue)
    }
  }
}
