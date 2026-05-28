#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#endif

/// A single raw reading of the process's accumulated CPU time and peak resident
/// memory, taken from `getrusage(RUSAGE_SELF)`.
package struct ProcessCPUReading: Sendable, Equatable {
  package var timestampSeconds: Double
  package var userCPUSeconds: Double
  package var systemCPUSeconds: Double
  package var maxResidentBytes: Int

  package var totalCPUSeconds: Double {
    userCPUSeconds + systemCPUSeconds
  }

  package init(
    timestampSeconds: Double,
    userCPUSeconds: Double,
    systemCPUSeconds: Double,
    maxResidentBytes: Int
  ) {
    self.timestampSeconds = timestampSeconds
    self.userCPUSeconds = userCPUSeconds
    self.systemCPUSeconds = systemCPUSeconds
    self.maxResidentBytes = maxResidentBytes
  }
}

/// A CPU sample over the interval between two readings: per-kind CPU seconds
/// consumed, the wall time elapsed, and the resulting busy estimate.
package struct CPUSample: Sendable, Equatable {
  package var timestampSeconds: Double
  package var userCPUSeconds: Double
  package var systemCPUSeconds: Double
  package var totalCPUSeconds: Double
  package var wallDeltaSeconds: Double
  package var estimatedCPUPercent: Double
  package var maxResidentBytes: Int

  package init(
    timestampSeconds: Double,
    userCPUSeconds: Double,
    systemCPUSeconds: Double,
    totalCPUSeconds: Double,
    wallDeltaSeconds: Double,
    estimatedCPUPercent: Double,
    maxResidentBytes: Int
  ) {
    self.timestampSeconds = timestampSeconds
    self.userCPUSeconds = userCPUSeconds
    self.systemCPUSeconds = systemCPUSeconds
    self.totalCPUSeconds = totalCPUSeconds
    self.wallDeltaSeconds = wallDeltaSeconds
    self.estimatedCPUPercent = estimatedCPUPercent
    self.maxResidentBytes = maxResidentBytes
  }
}

package enum CPUSamplerError: Error, Equatable, CustomStringConvertible {
  case unavailable
  case getrusageFailed(errno: Int32)

  package var description: String {
    switch self {
    case .unavailable:
      "process CPU sampling is unavailable on this platform."
    case .getrusageFailed(let errno):
      "getrusage failed with errno \(errno)."
    }
  }
}

/// Reads process CPU/RSS via `getrusage`. Available on Darwin/Glibc/Android/
/// Musl; a no-op that throws `.unavailable` on WASI.
package enum CPUSampler {
  package static let defaultSampleInterval: Duration = .milliseconds(250)

  package static func readCurrentUsage() throws -> ProcessCPUReading {
    #if canImport(Darwin) || canImport(Glibc) || canImport(Android) || canImport(Musl)
      var usage = rusage()
      #if canImport(Glibc)
        let result = unsafe getrusage(__rusage_who_t(RUSAGE_SELF.rawValue), &usage)
      #else
        let result = unsafe getrusage(RUSAGE_SELF, &usage)
      #endif
      guard result == 0 else {
        throw CPUSamplerError.getrusageFailed(errno: errno)
      }
      return ProcessCPUReading(
        timestampSeconds: monotonicSeconds(),
        userCPUSeconds: seconds(usage.ru_utime),
        systemCPUSeconds: seconds(usage.ru_stime),
        maxResidentBytes: residentBytes(usage.ru_maxrss)
      )
    #else
      throw CPUSamplerError.unavailable
    #endif
  }

  package static func sampleDelta(
    from start: ProcessCPUReading,
    to end: ProcessCPUReading
  ) -> CPUSample {
    let userDelta = max(0, end.userCPUSeconds - start.userCPUSeconds)
    let systemDelta = max(0, end.systemCPUSeconds - start.systemCPUSeconds)
    let totalDelta = userDelta + systemDelta
    let wallDelta = max(0, end.timestampSeconds - start.timestampSeconds)
    let cpuPercent = wallDelta > 0 ? (totalDelta / wallDelta) * 100 : 0
    return CPUSample(
      timestampSeconds: end.timestampSeconds,
      userCPUSeconds: userDelta,
      systemCPUSeconds: systemDelta,
      totalCPUSeconds: totalDelta,
      wallDeltaSeconds: wallDelta,
      estimatedCPUPercent: cpuPercent,
      maxResidentBytes: end.maxResidentBytes
    )
  }

  package static func deltas(from readings: [ProcessCPUReading]) -> [CPUSample] {
    zip(readings, readings.dropFirst()).map(sampleDelta)
  }

  private static let clockEpoch = ContinuousClock.now

  private static func monotonicSeconds() -> Double {
    let components = clockEpoch.duration(to: .now).components
    return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
  }

  #if canImport(Darwin) || canImport(Glibc) || canImport(Android) || canImport(Musl)
    private static func seconds(_ value: timeval) -> Double {
      Double(value.tv_sec) + Double(value.tv_usec) / 1_000_000
    }

    private static func residentBytes(_ maxResidentSetSize: some BinaryInteger) -> Int {
      // ru_maxrss is bytes on Darwin and kilobytes on Linux.
      #if canImport(Darwin)
        Int(maxResidentSetSize)
      #else
        Int(maxResidentSetSize) * 1024
      #endif
    }
  #endif
}

/// Drives periodic CPU sampling across an async operation, returning the
/// per-interval deltas. The activation layer uses the lower-level
/// ``CPUSampler`` primitives directly for the long-lived periodic signal.
package actor CPUSampleCollector {
  private let interval: Duration
  private var readings: [ProcessCPUReading] = []
  private var samplerTask: Task<Void, Never>?

  package init(interval: Duration = CPUSampler.defaultSampleInterval) {
    self.interval = interval
  }

  package func start() throws {
    readings = [try CPUSampler.readCurrentUsage()]
    samplerTask = Task { [interval] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: interval)
        } catch {
          break
        }
        guard (try? self.record()) != nil else {
          break
        }
      }
    }
  }

  package func stop() throws -> [CPUSample] {
    samplerTask?.cancel()
    samplerTask = nil
    try record()
    return CPUSampler.deltas(from: readings)
  }

  private func record() throws {
    readings.append(try CPUSampler.readCurrentUsage())
  }
}
