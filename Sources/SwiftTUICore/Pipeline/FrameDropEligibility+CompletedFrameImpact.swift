extension FrameDropEligibility {
  /// Closed non-visual impact categories used for completed-frame drop
  /// decisions.
  ///
  /// ``Blocker`` remains the diagnostics vocabulary. This product is the
  /// smaller correctness surface: every blocker must map through the exhaustive
  /// switch in ``init(blocker:)`` before a completed frame can be considered
  /// visual-only.
  package struct CompletedFrameImpact: Equatable, Sendable {
    package var lifecycle = false
    package var runtimeRegistrations = false
    package var focus = false
    package var scroll = false
    package var preferences = false
    package var animation = false
    package var workerOrCache = false
    package var retainedBaselines = false
    package var presentationRecovery = false
    package var diagnostics = false
    package var unclassified = false

    package init() {}

    package init(blocker: Blocker) {
      self.init()
      switch blocker {
      case .lifecycleAppear, .lifecycleDisappear, .lifecycleChange, .taskStart, .taskCancel:
        lifecycle = true
      case .handlerInstallations:
        runtimeRegistrations = true
      case .customLayoutFallback, .workerCustomLayoutCacheUpdate:
        workerOrCache = true
      case .focusGraph, .focusBindingSync, .focusedValueSync:
        focus = true
      case .scrollSync:
        scroll = true
      case .preferenceObservationDelta:
        preferences = true
      case .animationCompletion, .animationTransition, .animationTransaction:
        animation = true
      case .retainedLayoutBaseline, .retainedRasterBaseline:
        retainedBaselines = true
      case .presentationFullRepaint, .graphicsReplay:
        presentationRecovery = true
      case .diagnosticsFullRecord:
        diagnostics = true
      case .unobservable:
        unclassified = true
      }
    }

    package init(blockers: Set<Blocker>) {
      self.init()
      for blocker in blockers {
        formUnion(Self(blocker: blocker))
      }
    }

    package var isVisualOnly: Bool {
      !lifecycle
        && !runtimeRegistrations
        && !focus
        && !scroll
        && !preferences
        && !animation
        && !workerOrCache
        && !retainedBaselines
        && !presentationRecovery
        && !diagnostics
        && !unclassified
    }

    package mutating func formUnion(_ other: Self) {
      lifecycle = lifecycle || other.lifecycle
      runtimeRegistrations = runtimeRegistrations || other.runtimeRegistrations
      focus = focus || other.focus
      scroll = scroll || other.scroll
      preferences = preferences || other.preferences
      animation = animation || other.animation
      workerOrCache = workerOrCache || other.workerOrCache
      retainedBaselines = retainedBaselines || other.retainedBaselines
      presentationRecovery = presentationRecovery || other.presentationRecovery
      diagnostics = diagnostics || other.diagnostics
      unclassified = unclassified || other.unclassified
    }
  }
}
