/// A public diagnostic reason a completed frame could not be dropped as
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
  case diagnosticsFullRecord
  case unobservable
}
