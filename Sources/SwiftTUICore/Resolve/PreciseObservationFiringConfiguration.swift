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

/// Gate for **precise observation firing**. **On by default**; set
/// `SWIFTTUI_PRECISE_OBSERVATION_FIRING=0` to opt out (the legacy object-token
/// co-reader union).
///
/// Swift's `Observation` bridge is already key-path precise at the firing seam:
/// a `withObservationTracking` `onChange` fires only for the view identities
/// whose last tracking pass read the mutated property (a `cold` write does not
/// fire a `hot`-only reader). SwiftTUI then re-coarsens that precise signal in
/// ``ViewGraphInvalidationPlanner/observationChangeDirtyNodeIDs(observedBy:nodesByNodeID:observableDependents:)``,
/// which unions the firing node with **every co-reader of the same object
/// token** via `observableDependents`. That union is the only source of
/// observable over-invalidation, and it only ever reaches the two seams that
/// record an object token — `@Bindable` (`Bindable.subscript`) and the
/// `@Environment`-injected observable read — because plain `body` reads of an
/// `@Observable` record no object token and already fire precisely.
///
/// When enabled, `observationChangeDirtyNodeIDs` returns **only the precise
/// firing node**, dropping the co-reader union. A `\.hot` mutation then stops
/// dirtying `\.cold`/`\.rare` `@Bindable`/`@Environment` peers on the same
/// object. The firing node is always kept, so a genuine reader of the mutated
/// property is never dropped; and a node that records an object token cannot be
/// memo-reused (see ``ViewNode/hasNoMemoUncoveredDependencies(uncoveredEnvironmentKeys:)``),
/// so it always re-resolves and re-arms its tracking — it cannot go deaf.
///
/// The residual hazard is identical to the one the `@State` path mitigates
/// behind ``ReaderAttributionConfiguration``: a co-reader that reads the mutated
/// property only on a branch not taken during the last tracking pass has no live
/// edge and would not be re-dirtied. This flag stays off by default until a soak
/// proves that residual benign, after which it flips on (with `=0` as the
/// opt-out, mirroring ``ReaderAttributionConfiguration``).
///
/// Test-settable; defaults from `SWIFTTUI_PRECISE_OBSERVATION_FIRING` at first
/// access.
@MainActor
package enum PreciseObservationFiringConfiguration {
  package static let environmentVariableName = "SWIFTTUI_PRECISE_OBSERVATION_FIRING"

  /// Whether observable change invalidation dirties only the precise firing
  /// node rather than every co-reader of the same object token. On by default;
  /// `SWIFTTUI_PRECISE_OBSERVATION_FIRING=0` (or empty) opts out. The run loop
  /// reads this from the environment before the first render, and tests set it
  /// directly.
  package static var isEnabled: Bool = environmentDefault()

  private static func environmentDefault() -> Bool {
    guard let rawValue = environmentValue(named: environmentVariableName) else {
      // Default ON: precise firing is the standard path. An explicit `=0`/empty
      // value is the opt-out (legacy object-token co-reader union).
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
