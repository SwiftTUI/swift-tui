/// A public diagnostic reason that prevents a completed frame from being dropped as
/// visual-only work.
public enum FrameDropBlocker: String, Sendable, CaseIterable, Hashable {
  case lifecycleAppear
  case lifecycleDisappear
  case lifecycleChange
  case taskStart
  case taskCancel
  case handlerInstallations
  case customLayoutFallback
  case focusGraph
  case focusBindingSync
  case focusedValueSync
  case scrollSync
  case preferenceObservationDelta
  case animationCompletion
  case animationTransition
  case animationTransaction
  case workerCustomLayoutCacheUpdate
  case retainedLayoutBaseline
  case retainedRasterBaseline
  case presentationFullRepaint
  case graphicsReplay
  /// Presented-Progress Guard (opt-in via `SWIFTTUI_PRESENTED_PROGRESS_GUARD`):
  /// the completed frame carries a non-empty presentation diff against the
  /// last presented surface. If the runtime drops it, those pixels stay undelivered.
  /// A later frame must repaint them.
  /// The browser 0.1.9 incident exposed this bounded-starvation coalescing class. With the guard on,
  /// undelivered pixels are never droppable, uniformly for every host.
  case undeliveredPresentationDamage
  case diagnosticsFullRecord
  case unobservable
}
