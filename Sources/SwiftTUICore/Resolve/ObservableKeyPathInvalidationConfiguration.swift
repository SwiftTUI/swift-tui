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

/// Gate for **key-path-grained observable invalidation**. **Off by default**;
/// set `SWIFTTUI_OBSERVABLE_KEYPATH_INVALIDATION=1` to opt in.
///
/// A *more conservative* narrowing than ``PreciseObservationFiringConfiguration``
/// (which drops the co-reader union entirely). Instead of dirtying only the
/// firing node, this narrows the legacy object-token union to co-readers that
/// recorded the **same `(object, keyPath)`** the firing node read — so a `\.hot`
/// mutation stops dirtying `\.cold`/`\.rare` peers, while still re-dirtying
/// genuine `\.hot` co-readers from the durable key-path index (covering a reader
/// whose one-shot `onChange` was consumed without re-arming).
///
/// It is **additive and safe by construction**: the key-path index
/// (``DependencySet/observableKeyPathReads``) is recorded *alongside* the object
/// token, never replacing it, and the narrowing only applies when **every**
/// object co-reader of the firing object is key-path-attributed. If any
/// co-reader read the object without a key path (a plain `body` read or an
/// `@Environment`-injected observable), the narrowing falls back to the full
/// object-token union for that object — over-invalidate, never under.
///
/// When enabled, the key-path holding seams (`@Bindable`) record
/// `(object, keyPath)`; when off, they record only the object token, so the
/// key-path index stays empty and behavior is byte-identical to the legacy
/// union. Mutually exclusive with ``PreciseObservationFiringConfiguration``,
/// which takes precedence when both are enabled.
///
/// Test-settable; defaults from `SWIFTTUI_OBSERVABLE_KEYPATH_INVALIDATION` at
/// first access.
@MainActor
package enum ObservableKeyPathInvalidationConfiguration {
  package static let environmentVariableName = "SWIFTTUI_OBSERVABLE_KEYPATH_INVALIDATION"

  /// Whether observable change invalidation narrows the co-reader union to
  /// same-key-path readers. Off by default; `=1` opts in. The run loop reads
  /// this from the environment before the first render, and tests set it
  /// directly.
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
