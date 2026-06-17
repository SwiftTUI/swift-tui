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

/// Gates memoized-body reuse: skipping a recomputed node's body when its view
/// value is structurally unchanged and it passes the retained-reuse guards.
///
/// **Default off** (`SWIFTTUI_MEMO_REUSE` to enable). Stage 2 of the
/// memoized-body design lands the gate behind this flag for the conservative
/// safe subset (no recorded dependencies, fully comparable view value) so the
/// win can be measured and the reuse-equivalence oracle can verify it before it
/// becomes the default. Mirrors ``ReaderAttributionConfiguration``.
@MainActor
package enum MemoReuseConfiguration {
  package static let environmentVariableName = "SWIFTTUI_MEMO_REUSE"

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
