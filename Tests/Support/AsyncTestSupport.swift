import Foundation

package enum AsyncTestTimeouts {
  package static let scaleEnvironmentVariable = "SWIFTTUI_TEST_TIMEOUT_SCALE"

  package static var timeoutScale: Double {
    guard
      let rawValue = ProcessInfo.processInfo.environment[scaleEnvironmentVariable],
      let parsedValue = Double(rawValue),
      parsedValue.isFinite,
      parsedValue > 0
    else {
      return 1
    }

    return max(1, parsedValue)
  }

  package static func scaledNanoseconds(_ nanoseconds: UInt64) -> UInt64 {
    let scaled = Double(nanoseconds) * timeoutScale
    guard scaled.isFinite else {
      return UInt64.max
    }
    guard scaled < Double(UInt64.max) else {
      return UInt64.max
    }
    return UInt64(scaled.rounded(.up))
  }
}

package struct AsyncTestTimeout: Error, CustomStringConvertible, Sendable {
  package let label: String
  package let baseTimeoutNanoseconds: UInt64
  package let scaledTimeoutNanoseconds: UInt64
  package let timeoutScale: Double
  package let lastObservation: String?

  package init(
    label: String,
    baseTimeoutNanoseconds: UInt64,
    scaledTimeoutNanoseconds: UInt64,
    timeoutScale: Double,
    lastObservation: String? = nil
  ) {
    self.label = label
    self.baseTimeoutNanoseconds = baseTimeoutNanoseconds
    self.scaledTimeoutNanoseconds = scaledTimeoutNanoseconds
    self.timeoutScale = timeoutScale
    self.lastObservation = lastObservation
  }

  package var description: String {
    var message =
      "Timed out waiting for \(label) after "
      + "\(Self.secondsDescription(scaledTimeoutNanoseconds))s"
    if timeoutScale != 1 {
      message +=
        " (base \(Self.secondsDescription(baseTimeoutNanoseconds))s, "
        + "\(AsyncTestTimeouts.scaleEnvironmentVariable)=\(timeoutScale))"
    }
    if let lastObservation, !lastObservation.isEmpty {
      message += ". Last observation:\n\(lastObservation)"
    }
    return message
  }

  private static func secondsDescription(_ nanoseconds: UInt64) -> String {
    let wholeSeconds = nanoseconds / 1_000_000_000
    let milliseconds = (nanoseconds % 1_000_000_000) / 1_000_000
    let paddedMilliseconds =
      if milliseconds < 10 {
        "00\(milliseconds)"
      } else if milliseconds < 100 {
        "0\(milliseconds)"
      } else {
        "\(milliseconds)"
      }
    return "\(wholeSeconds).\(paddedMilliseconds)"
  }
}

@MainActor
@discardableResult
package func waitUntil(
  timeoutNanoseconds: UInt64 = 5_000_000_000,
  pollNanoseconds: UInt64 = 5_000_000,
  condition: () -> Bool
) async throws -> Bool {
  try await waitUntil(
    "condition",
    timeoutNanoseconds: timeoutNanoseconds,
    pollNanoseconds: pollNanoseconds,
    condition: condition
  )
}

@MainActor
@discardableResult
package func waitUntil(
  _ label: String,
  timeoutNanoseconds: UInt64 = 5_000_000_000,
  pollNanoseconds: UInt64 = 5_000_000,
  condition: () -> Bool
) async throws -> Bool {
  try await waitUntil(
    label,
    timeoutNanoseconds: timeoutNanoseconds,
    pollNanoseconds: pollNanoseconds,
    lastObservation: { nil },
    condition: condition
  )
}

@MainActor
@discardableResult
package func waitUntil(
  _ label: String,
  timeoutNanoseconds: UInt64 = 5_000_000_000,
  pollNanoseconds: UInt64 = 5_000_000,
  lastObservation: () -> String?,
  condition: () -> Bool
) async throws -> Bool {
  let clock = ContinuousClock()
  let start = clock.now
  let scaledTimeoutNanoseconds = AsyncTestTimeouts.scaledNanoseconds(timeoutNanoseconds)
  let timeoutDuration = Duration.nanoseconds(clampingInt64: scaledTimeoutNanoseconds)

  while !condition() {
    if start.duration(to: clock.now) >= timeoutDuration {
      throw AsyncTestTimeout(
        label: label,
        baseTimeoutNanoseconds: timeoutNanoseconds,
        scaledTimeoutNanoseconds: scaledTimeoutNanoseconds,
        timeoutScale: AsyncTestTimeouts.timeoutScale,
        lastObservation: lastObservation()
      )
    }
    try await Task.sleep(nanoseconds: pollNanoseconds)
  }
  return true
}

@MainActor
@discardableResult
package func waitUntil(
  _ label: String,
  timeoutNanoseconds: UInt64 = 5_000_000_000,
  pollNanoseconds: UInt64 = 5_000_000,
  condition: () async -> Bool
) async throws -> Bool {
  try await waitUntil(
    label,
    timeoutNanoseconds: timeoutNanoseconds,
    pollNanoseconds: pollNanoseconds,
    lastObservation: { nil },
    condition: condition
  )
}

@MainActor
@discardableResult
package func waitUntil(
  _ label: String,
  timeoutNanoseconds: UInt64 = 5_000_000_000,
  pollNanoseconds: UInt64 = 5_000_000,
  lastObservation: () async -> String?,
  condition: () async -> Bool
) async throws -> Bool {
  let clock = ContinuousClock()
  let start = clock.now
  let scaledTimeoutNanoseconds = AsyncTestTimeouts.scaledNanoseconds(timeoutNanoseconds)
  let timeoutDuration = Duration.nanoseconds(clampingInt64: scaledTimeoutNanoseconds)

  while !(await condition()) {
    if start.duration(to: clock.now) >= timeoutDuration {
      throw AsyncTestTimeout(
        label: label,
        baseTimeoutNanoseconds: timeoutNanoseconds,
        scaledTimeoutNanoseconds: scaledTimeoutNanoseconds,
        timeoutScale: AsyncTestTimeouts.timeoutScale,
        lastObservation: await lastObservation()
      )
    }
    try await Task.sleep(nanoseconds: pollNanoseconds)
  }
  return true
}

package func valueWithTimeout<Value: Sendable>(
  _ label: String = "operation",
  timeoutNanoseconds: UInt64 = 5_000_000_000,
  _ operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
  let scaledTimeoutNanoseconds = AsyncTestTimeouts.scaledNanoseconds(timeoutNanoseconds)
  return try await withThrowingTaskGroup(of: Value.self) { group in
    group.addTask {
      try await operation()
    }
    group.addTask {
      try await Task.sleep(nanoseconds: scaledTimeoutNanoseconds)
      throw AsyncTestTimeout(
        label: label,
        baseTimeoutNanoseconds: timeoutNanoseconds,
        scaledTimeoutNanoseconds: scaledTimeoutNanoseconds,
        timeoutScale: AsyncTestTimeouts.timeoutScale
      )
    }

    let value = try await group.next()!
    group.cancelAll()
    return value
  }
}

extension Duration {
  fileprivate static func nanoseconds(clampingInt64 nanoseconds: UInt64) -> Duration {
    .nanoseconds(nanoseconds > UInt64(Int64.max) ? Int64.max : Int64(nanoseconds))
  }
}
