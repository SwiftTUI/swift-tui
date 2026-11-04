/// Identifies a probe counter across graph snapshots, traces and runtime issue reporting.
package enum SoundnessViolationKind: String, CaseIterable, Sendable {
  case actionDispatchMiss = "action-dispatch-miss"
  case ambientEnvironmentFallback = "ambient-environment-fallback"
  case checkpointStore = "checkpoint-store"
  case committedHandlerResolution = "committed-handler-resolution"
  case deltaCheckpoint = "delta-checkpoint"
  case duplicateRegistration = "duplicate-registration"
  case dynamicPropertyMutationDiscarded = "dynamic-property-mutation-discarded"
  case handlerResolutionAction = "handler-resolution-action"
  case handlerResolutionCommand = "handler-resolution-command"
  case handlerResolutionDrop = "handler-resolution-drop"
  case handlerResolutionGesture = "handler-resolution-gesture"
  case handlerResolutionKey = "handler-resolution-key"
  case layoutShadowDivergence = "layout-shadow-divergence"
  case lifecycleHandlerSkip = "lifecycle-handler-skip"
  case memoUnsoundSkip = "memo-unsound-skip"
  case plannerTargetlessFrontier = "planner-targetless-frontier"
  case rasterDamage = "raster-damage"
  case registrationPublication = "registration-publication"
  case resolveLifetimeScopeUnclassified = "resolve-lifetime-scope-unclassified"
  case stampCoherence = "stamp-coherence"
  case stateCaptureMiss = "state-capture-miss"
  case stateSeedFallback = "state-seed-fallback"
  case stateSlotRestorationDrop = "state-slot-restoration-drop"
  case strandedListing = "stranded-listing"
  case teardownBarrierNonConvergence = "teardown-barrier-non-convergence"
  case teardownCoherence = "teardown-coherence"
  case teardownCoherenceLeak = "teardown-coherence-leak"

  /// Runtime issues publish the camel-case rendering of the stable trace token.
  package var issueName: String {
    let words = rawValue.split(separator: "-")
    return words.dropFirst().reduce(String(words[0])) { result, word in
      result + word.prefix(1).uppercased() + word.dropFirst()
    }
  }
}
