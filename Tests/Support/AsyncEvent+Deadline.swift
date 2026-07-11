extension AsyncEvent {
  /// Returns an event that fires after a wall-clock deadline.
  ///
  /// Use this only when the deadline itself is the behavior under test, such
  /// as comparing replacement timer lifetimes. Ordinary test synchronization
  /// should fire an event directly from the producer being observed.
  @_spi(Testing) public static func firing(after duration: Duration) -> AsyncEvent {
    let event = AsyncEvent()
    Task {
      try? await Task.sleep(for: duration)
      event.fire()
    }
    return event
  }
}
