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

/// Centralized access for the framework's `SWIFTTUI_*` feature gates.
///
/// Every perf gate and trace sink used to carry its own copy-pasted `getenv`
/// wrapper and default-on parser (plus the five-arm libc `#if` import). That
/// meant a parsing fix — or the WASILibc compile-out seam that has shipped
/// green-but-broken twice — had to be applied N times. This collapses the
/// duplication into one place; the per-gate configs keep only their flag name
/// and `isEnabled` latch and delegate the reading here.
package enum FeatureFlags {
  /// Reads a process environment variable. First access wins (the value is
  /// latched by each gate's `static var`), matching the prior getenv semantics.
  package static func environmentValue(named name: String) -> String? {
    unsafe name.withCString { cName in
      guard let rawValue = unsafe getenv(cName) else {
        return nil
      }
      return unsafe String(cString: rawValue)
    }
  }

  /// Parses a flag that is **on unless explicitly disabled**: absent → `true`;
  /// `"0"` or empty → `false`; anything else → `true`. This is the exact shape
  /// every default-on perf gate used.
  package static func isEnabledByDefault(_ name: String) -> Bool {
    guard let rawValue = environmentValue(named: name) else {
      return true
    }
    return !rawValue.isEmpty && rawValue != "0"
  }
}
