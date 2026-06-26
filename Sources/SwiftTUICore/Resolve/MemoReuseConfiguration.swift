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

  package static var isEnabled: Bool = FeatureFlags.isEnabledByDefault(environmentVariableName)
}
