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
/// value is `Equatable`-equal to last frame's and it passes the retained-reuse
/// guards.
///
/// **Default on** as of Stage 3. The gate is `Equatable`-only — a view
/// participates only by conforming to `Equatable` (directly or via
/// ``EquatableView``), so it is inert on trees that do not opt in (measured
/// ±1–3%, noise) and a large win on those that do (−86% on the boundary
/// scenario). `SWIFTTUI_MEMO_REUSE=0` disables it. Mirrors
/// ``ReaderAttributionConfiguration``.
@MainActor
package enum MemoReuseConfiguration {
  package static let environmentVariableName = "SWIFTTUI_MEMO_REUSE"

  package static var isEnabled: Bool = environmentDefault()

  private static func environmentDefault() -> Bool {
    guard let rawValue = environmentValue(named: environmentVariableName) else {
      return true
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
