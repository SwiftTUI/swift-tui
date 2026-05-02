import Dispatch
import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#endif

public struct ProcessCPUReading: Equatable, Sendable {
  public var timestampSeconds: Double
  public var userCPUSeconds: Double
  public var systemCPUSeconds: Double

  public var totalCPUSeconds: Double {
    userCPUSeconds + systemCPUSeconds
  }

  public init(timestampSeconds: Double, userCPUSeconds: Double, systemCPUSeconds: Double) {
    self.timestampSeconds = timestampSeconds
    self.userCPUSeconds = userCPUSeconds
    self.systemCPUSeconds = systemCPUSeconds
  }
}

public enum CPUSamplerError: Error, Equatable, CustomStringConvertible {
  case unavailable
  case getrusageFailed(errno: Int32)

  public var description: String {
    switch self {
    case .unavailable:
      return "process CPU sampling is unavailable on this platform."
    case .getrusageFailed(let errno):
      return "getrusage failed with errno \(errno)."
    }
  }
}

public enum CPUSampler {
  public static let defaultSampleInterval: Duration = .milliseconds(50)

  public static func readCurrentUsage() throws -> ProcessCPUReading {
    #if canImport(Darwin) || canImport(Glibc) || canImport(Android) || canImport(Musl)
      var usage = rusage()
      let result = getrusage(RUSAGE_SELF, &usage)
      guard result == 0 else {
        throw CPUSamplerError.getrusageFailed(errno: errno)
      }

      return ProcessCPUReading(
        timestampSeconds: monotonicSeconds(),
        userCPUSeconds: seconds(usage.ru_utime),
        systemCPUSeconds: seconds(usage.ru_stime)
      )
    #else
      throw CPUSamplerError.unavailable
    #endif
  }

  public static func sampleDelta(
    from start: ProcessCPUReading,
    to end: ProcessCPUReading
  ) -> PerfCPUSample {
    let userDelta = max(0, end.userCPUSeconds - start.userCPUSeconds)
    let systemDelta = max(0, end.systemCPUSeconds - start.systemCPUSeconds)
    let totalDelta = userDelta + systemDelta
    let wallDelta = max(0, end.timestampSeconds - start.timestampSeconds)
    let cpuPercent = wallDelta > 0 ? (totalDelta / wallDelta) * 100 : 0

    return PerfCPUSample(
      timestampSeconds: end.timestampSeconds,
      userCPUSeconds: userDelta,
      systemCPUSeconds: systemDelta,
      totalCPUSeconds: totalDelta,
      wallDeltaSeconds: wallDelta,
      estimatedCPUPercent: cpuPercent
    )
  }

  public static func deltas(from readings: [ProcessCPUReading]) -> [PerfCPUSample] {
    zip(readings, readings.dropFirst()).map(sampleDelta)
  }

  @MainActor
  public static func collect(
    interval: Duration = defaultSampleInterval,
    during operation: () async throws -> Void
  ) async throws -> [PerfCPUSample] {
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

  private static func monotonicSeconds() -> Double {
    Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
  }

  private static func seconds(_ value: timeval) -> Double {
    Double(value.tv_sec) + Double(value.tv_usec) / 1_000_000
  }
}

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
        do {
          try record()
        } catch {
          break
        }
      }
    }
  }

  public func stop() async throws -> [PerfCPUSample] {
    samplerTask?.cancel()
    await samplerTask?.value
    samplerTask = nil
    try record()
    return CPUSampler.deltas(from: readings)
  }

  private func record() throws {
    readings.append(try CPUSampler.readCurrentUsage())
  }
}
