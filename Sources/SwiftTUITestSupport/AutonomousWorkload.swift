/// Paces an autonomous workload whose periodic state writes are the behavior
/// under test. This is not a readiness wait: tests must observe that workload
/// through a signal or a bounded condition, rather than wait a fixed duration
/// and assume it ran. Cancellation stops the producer's next tick.
package func paceAutonomousWorkload(for interval: Duration) async throws {
  try await Task.sleep(for: interval)
}
