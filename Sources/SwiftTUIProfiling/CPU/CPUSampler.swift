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
public struct ProcessCPUReading: Sendable, Equatable {
  public var timestampSeconds: Double
  public var userCPUSeconds: Double
  public var systemCPUSeconds: Double
  /// Peak resident set size in bytes, normalized across platforms (`getrusage`
  /// reports bytes on Darwin and kilobytes on Linux).
  public var maxResidentBytes: Int

  /// User plus system CPU time.
  public var totalCPUSeconds: Double {
    userCPUSeconds + systemCPUSeconds
  }

  public init(
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
public struct CPUSample: Sendable, Equatable {
  public var timestampSeconds: Double
  public var userCPUSeconds: Double
  public var systemCPUSeconds: Double
  public var totalCPUSeconds: Double
  /// Wall-clock time the sampling interval spanned.
  public var wallDeltaSeconds: Double
  /// Busy estimate: `totalCPUSeconds / wallDeltaSeconds * 100`. One fully busy
  /// core reads as 100%, so multi-core work can exceed 100%.
  public var estimatedCPUPercent: Double
  /// Peak resident set size in bytes at the end of the interval. See
  /// ``ProcessCPUReading/maxResidentBytes``.
  public var maxResidentBytes: Int

  public init(
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

/// Why a CPU reading could not be taken.
public enum CPUSamplerError: Error, Equatable, CustomStringConvertible {
  /// Process CPU sampling is not supported on this platform (e.g. WASI).
  case unavailable
  /// The underlying `getrusage` call failed with this `errno`.
  case getrusageFailed(errno: Int32)

  public var description: String {
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
public enum CPUSampler {
  public static let defaultSampleInterval: Duration = .milliseconds(250)

  public static func readCurrentUsage() throws -> ProcessCPUReading {
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

  public static func sampleDelta(
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

  public static func deltas(from readings: [ProcessCPUReading]) -> [CPUSample] {
    zip(readings, readings.dropFirst()).map(sampleDelta)
  }

  /// Samples CPU at `interval` across `operation`, returning the per-interval
  /// deltas. Convenience for scripted runs; the periodic profiling signal uses
  /// the lower-level primitives directly.
  @MainActor
  public static func collect(
    interval: Duration = defaultSampleInterval,
    during operation: () async throws -> Void
  ) async throws -> [CPUSample] {
    let collector = CPUSampleCollector(interval: interval)
    try await collector.start()
    do {
      try await operation()
      return try await collector.stop()
    } catch {
      _ = try? await collector.stop()
      throw error
    }
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
public actor CPUSampleCollector {
  private let interval: Duration
  private var readings: [ProcessCPUReading] = []
  private var samplerTask: Task<Void, Never>?

  public init(interval: Duration = CPUSampler.defaultSampleInterval) {
    self.interval = interval
  }

  public func start() throws {
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

  public func stop() throws -> [CPUSample] {
    samplerTask?.cancel()
    samplerTask = nil
    try record()
    return CPUSampler.deltas(from: readings)
  }

  private func record() throws {
    readings.append(try CPUSampler.readCurrentUsage())
  }
}
