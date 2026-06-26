/// Gate for **reader-attributed** `@State` read/write tracking. **On by
/// default**; set `SWIFTTUI_READER_ATTRIBUTION=0` to opt out (the legacy path).
///
/// Legacy behavior attributes every state read — including the eager read
/// performed when a `$binding` is merely *projected* — to the slot's **owner**
/// node, and a `@State` *write* invalidates that same owner identity, so a
/// change re-resolves the owner's entire subtree. That is why toggling
/// `.sheet(isPresented: $flag)` re-resolves the whole background: the presenting
/// view (owner) is an ancestor of it.
///
/// When enabled, a state read is attributed to the node that is *actually
/// evaluating* when the read happens (`ViewNodeContext.current`), projecting a
/// binding records no read, the owner is dirtied only when it genuinely reads
/// `wrappedValue`, and a `@State` *write* invalidates the genuine recorded
/// readers rather than the owner (see `ViewNode.stateChangeInvalidationIdentities`).
/// A `@State` change then re-resolves only its real readers, sparing disjoint
/// subtrees — taking sheet/palette open from O(background) to O(overlay).
///
/// Test-settable; defaults from `SWIFTTUI_READER_ATTRIBUTION` at first access.
@MainActor
package enum ReaderAttributionConfiguration {
  package static let environmentVariableName = "SWIFTTUI_READER_ATTRIBUTION"

  /// Whether reads attribute to the evaluating reader rather than the slot
  /// owner. On by default; `SWIFTTUI_READER_ATTRIBUTION=0` (or empty) opts out.
  /// The run loop sets it from the environment before the first render, and
  /// tests set it directly.
  package static var isEnabled: Bool = FeatureFlags.isEnabledByDefault(environmentVariableName)
}
