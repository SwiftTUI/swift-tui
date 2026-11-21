extension RunLoop {
  /// Ends the lifecycle work of a run loop that a caller drives frame by
  /// frame with `renderPendingFrames(renderedFrames:eventPump:drainPolicy:)`
  /// and that never enters `run()`.
  ///
  /// `run()` shuts the lifecycle coordinator down when it returns: the tasks
  /// the scene started are cancelled, and a later frame starts none. A manual
  /// driver has no `run()` to return from, and the coordinator's own
  /// `shutdown()` is internal to this module, so a driver in another module
  /// of the package (the run-loop test harness in `SwiftTUITestSupport`)
  /// ends its session here. Calling it again does nothing.
  package func endManuallyDrivenSession() {
    lifecycleCoordinator.shutdown()
  }
}
