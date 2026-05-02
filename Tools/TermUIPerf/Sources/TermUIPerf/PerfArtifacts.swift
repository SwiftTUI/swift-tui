import Foundation
import TerminalUI

public struct PerfTerminalSize: Codable, Equatable, Sendable {
  public var columns: Int
  public var rows: Int

  public init(columns: Int, rows: Int) {
    self.columns = columns
    self.rows = rows
  }
}

public struct PerfRunMetadata: Codable, Equatable, Sendable {
  public static let harnessVersion = 1

  public var harnessVersion: Int
  public var gitSHA: String
  public var dirty: Bool
  public var renderMode: String
  public var scenario: String
  public var iterationCount: Int
  public var configuration: String
  public var swiftVersion: String
  public var osVersion: String
  public var hardwareModel: String?
  public var processorCount: Int?
  public var terminalSize: PerfTerminalSize
  public var startedAt: String
  public var endedAt: String?

  public init(
    gitSHA: String,
    dirty: Bool,
    renderMode: RuntimeRenderMode,
    scenario: PerfScenarioName,
    iterationCount: Int,
    configuration: String,
    swiftVersion: String,
    osVersion: String,
    hardwareModel: String? = nil,
    processorCount: Int? = nil,
    terminalSize: PerfTerminalSize,
    startedAt: String,
    endedAt: String? = nil,
    harnessVersion: Int = Self.harnessVersion
  ) {
    self.harnessVersion = harnessVersion
    self.gitSHA = gitSHA
    self.dirty = dirty
    self.renderMode = renderMode.rawValue
    self.scenario = scenario.rawValue
    self.iterationCount = iterationCount
    self.configuration = configuration
    self.swiftVersion = swiftVersion
    self.osVersion = osVersion
    self.hardwareModel = hardwareModel
    self.processorCount = processorCount
    self.terminalSize = terminalSize
    self.startedAt = startedAt
    self.endedAt = endedAt
  }

  private enum CodingKeys: String, CodingKey {
    case harnessVersion = "harness_version"
    case gitSHA = "git_sha"
    case dirty
    case renderMode = "render_mode"
    case scenario
    case iterationCount = "iteration_count"
    case configuration
    case swiftVersion = "swift_version"
    case osVersion = "os_version"
    case hardwareModel = "hardware_model"
    case processorCount = "processor_count"
    case terminalSize = "terminal_size"
    case startedAt = "started_at"
    case endedAt = "ended_at"
  }
}

public struct PerfEventRecord: Codable, Equatable, Sendable {
  public var eventID: String
  public var eventType: String
  public var dispatchTimeSeconds: Double
  public var expectedVisualMarker: String
  public var firstMatchingFrame: Int?
  public var firstMatchingTimeSeconds: Double?
  public var finalSettledFrame: Int?
  public var finalSettledTimeSeconds: Double?

  public init(
    eventID: String,
    eventType: String,
    dispatchTimeSeconds: Double,
    expectedVisualMarker: String,
    firstMatchingFrame: Int? = nil,
    firstMatchingTimeSeconds: Double? = nil,
    finalSettledFrame: Int? = nil,
    finalSettledTimeSeconds: Double? = nil
  ) {
    self.eventID = eventID
    self.eventType = eventType
    self.dispatchTimeSeconds = dispatchTimeSeconds
    self.expectedVisualMarker = expectedVisualMarker
    self.firstMatchingFrame = firstMatchingFrame
    self.firstMatchingTimeSeconds = firstMatchingTimeSeconds
    self.finalSettledFrame = finalSettledFrame
    self.finalSettledTimeSeconds = finalSettledTimeSeconds
  }

  private enum CodingKeys: String, CodingKey {
    case eventID = "event_id"
    case eventType = "event_type"
    case dispatchTimeSeconds = "dispatch_time_seconds"
    case expectedVisualMarker = "expected_visual_marker"
    case firstMatchingFrame = "first_matching_frame"
    case firstMatchingTimeSeconds = "first_matching_time_seconds"
    case finalSettledFrame = "final_settled_frame"
    case finalSettledTimeSeconds = "final_settled_time_seconds"
  }
}

public struct PerfCPUSample: Codable, Equatable, Sendable {
  public var timestampSeconds: Double
  public var userCPUSeconds: Double
  public var systemCPUSeconds: Double
  public var totalCPUSeconds: Double
  public var wallDeltaSeconds: Double
  public var estimatedCPUPercent: Double

  public init(
    timestampSeconds: Double,
    userCPUSeconds: Double,
    systemCPUSeconds: Double,
    totalCPUSeconds: Double? = nil,
    wallDeltaSeconds: Double,
    estimatedCPUPercent: Double
  ) {
    self.timestampSeconds = timestampSeconds
    self.userCPUSeconds = userCPUSeconds
    self.systemCPUSeconds = systemCPUSeconds
    self.totalCPUSeconds = totalCPUSeconds ?? userCPUSeconds + systemCPUSeconds
    self.wallDeltaSeconds = wallDeltaSeconds
    self.estimatedCPUPercent = estimatedCPUPercent
  }

  private enum CodingKeys: String, CodingKey {
    case timestampSeconds = "timestamp_seconds"
    case userCPUSeconds = "user_cpu_seconds"
    case systemCPUSeconds = "system_cpu_seconds"
    case totalCPUSeconds = "total_cpu_seconds"
    case wallDeltaSeconds = "wall_delta_seconds"
    case estimatedCPUPercent = "estimated_cpu_percent"
  }
}

public enum PerfTSVWriter {
  public static let eventHeader = [
    "event_id",
    "event_type",
    "dispatch_time_seconds",
    "expected_visual_marker",
    "first_matching_frame",
    "first_matching_time_seconds",
    "final_settled_frame",
    "final_settled_time_seconds",
  ]

  public static let cpuHeader = [
    "timestamp_seconds",
    "user_cpu_seconds",
    "system_cpu_seconds",
    "total_cpu_seconds",
    "wall_delta_seconds",
    "estimated_cpu_percent",
  ]

  public static func eventsTSV(_ records: [PerfEventRecord]) -> String {
    rows(
      header: eventHeader,
      records: records.map { record in
        [
          record.eventID,
          record.eventType,
          format(record.dispatchTimeSeconds),
          record.expectedVisualMarker,
          record.firstMatchingFrame.map(String.init) ?? "-",
          record.firstMatchingTimeSeconds.map(format) ?? "-",
          record.finalSettledFrame.map(String.init) ?? "-",
          record.finalSettledTimeSeconds.map(format) ?? "-",
        ]
      })
  }

  public static func cpuTSV(_ records: [PerfCPUSample]) -> String {
    rows(
      header: cpuHeader,
      records: records.map { record in
        [
          format(record.timestampSeconds),
          format(record.userCPUSeconds),
          format(record.systemCPUSeconds),
          format(record.totalCPUSeconds),
          format(record.wallDeltaSeconds),
          format(record.estimatedCPUPercent),
        ]
      })
  }

  private static func rows(header: [String], records: [[String]]) -> String {
    ([header] + records)
      .map { row in row.map(sanitize).joined(separator: "\t") }
      .joined(separator: "\n") + "\n"
  }

  private static func sanitize(_ field: String) -> String {
    field
      .replacingOccurrences(of: "\t", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
  }

  private static func format(_ value: Double) -> String {
    String(format: "%.6f", value)
  }
}
