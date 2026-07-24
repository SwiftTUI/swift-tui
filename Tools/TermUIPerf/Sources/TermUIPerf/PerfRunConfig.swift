import Foundation
import SwiftTUI

public enum TermUIPerfCommand: Equatable, Sendable {
  case run(PerfRunConfig)
  case compare(PerfCompareConfig)
  case listScenarios
}

public struct PerfRunConfig: Equatable, Sendable {
  public static let defaultIterations = 20
  public static let defaultArtifactsRoot = ".perf/runs"
  public static let defaultConfiguration = "release"
  public static let defaultModes: [RuntimeRenderMode] = [.async]

  public var scenario: PerfScenarioName
  public var modes: [RuntimeRenderMode]
  public var iterations: Int
  public var artifactsRoot: String
  public var configuration: String
  public var terminalSize: PerfTerminalSize?

  public init(
    scenario: PerfScenarioName,
    modes: [RuntimeRenderMode] = defaultModes,
    iterations: Int = defaultIterations,
    artifactsRoot: String = defaultArtifactsRoot,
    configuration: String = defaultConfiguration,
    terminalSize: PerfTerminalSize? = nil
  ) {
    self.scenario = scenario
    self.modes = modes
    self.iterations = iterations
    self.artifactsRoot = artifactsRoot
    self.configuration = configuration
    self.terminalSize = terminalSize
  }
}

public struct PerfCompareConfig: Equatable, Sendable {
  public var baseRunDirectory: String
  public var candidateRunDirectory: String
  /// When `true` (or when `requireImprovement` is non-empty), `compare`
  /// interprets its two arguments as aggregate summaries and exits non-zero on
  /// a regression or an unmet improvement requirement.
  public var gate: Bool
  /// Metric names that must each show a `.real` improvement for the gate to
  /// pass. Matched case/punctuation-insensitively against the aggregate metric
  /// names (e.g. `cpu-seconds-per-frame` matches `CPU seconds/frame`).
  public var requireImprovement: [String]
  /// Standard-deviation multiplier for the noise band used by the gate.
  public var sigma: Double

  public init(
    baseRunDirectory: String,
    candidateRunDirectory: String,
    gate: Bool = false,
    requireImprovement: [String] = [],
    sigma: Double = CompareCommand.defaultNoiseSigma
  ) {
    self.baseRunDirectory = baseRunDirectory
    self.candidateRunDirectory = candidateRunDirectory
    self.gate = gate
    self.requireImprovement = requireImprovement
    self.sigma = sigma
  }

  /// `true` when the gate should run (an explicit `--gate` or any
  /// `--require-improvement` metric).
  public var gateEnabled: Bool {
    gate || !requireImprovement.isEmpty
  }
}

public enum PerfScenarioName: String, CaseIterable, Equatable, Sendable {
  case exampleAppShellWorkflow = "example-app-shell-workflow"
  case galleryAnimationClick = "gallery-animation-click"
  case layoutScrollBurst = "layout-scroll-burst"
  case syntheticOffscreenPhaseAnimator = "synthetic-offscreen-phase-animator"
  case syntheticContinuousAnimation = "synthetic-continuous-animation"
  case syntheticSingleTween = "synthetic-single-tween"
  case syntheticTextShimmer = "synthetic-text-shimmer"
  case syntheticNarrowInvalidation = "synthetic-narrow-invalidation"
  case syntheticObservableFanout = "synthetic-observable-fanout"
  case syntheticMeshGradient = "synthetic-mesh-gradient"
  case sheetOpenLatency = "sheet-open-latency"
  case galleryTabSwitch = "gallery-tab-switch"
  case fileBrowserSelection = "file-browser-selection"
  case textInputEditing = "text-input-editing"
  case memoEquatableBoundary = "memo-equatable-boundary"
  case canvasPartialReuse = "canvas-partial-reuse"
  case gifPlayback = "gif-playback"
  case lazyList1K = "lazy-list-1k"
  case table1Kx4 = "table-1kx4"
  case lazyVStackScroll = "lazy-vstack-scroll"

  public static var allNames: [String] {
    allCases.map(\.rawValue).sorted()
  }
}

public enum PerfParseError: Error, Equatable, CustomStringConvertible {
  case missingCommand
  case unknownCommand(String)
  case missingRequiredOption(String)
  case missingValue(String)
  case unknownOption(String)
  case unexpectedArgument(String)
  case invalidIterations(String)
  case unknownMode(String)
  case emptyModeList
  case unknownScenario(String)
  case compareArgumentCount(Int)
  case invalidSigma(String)
  case invalidTerminalSize(String)

  public var description: String {
    switch self {
    case .missingCommand:
      return "missing command. Use run, compare, or list-scenarios."
    case .unknownCommand(let command):
      return "unknown command '\(command)'. Use run, compare, or list-scenarios."
    case .missingRequiredOption(let option):
      return "missing required option \(option)."
    case .missingValue(let option):
      return "missing value for \(option)."
    case .unknownOption(let option):
      return "unknown option \(option)."
    case .unexpectedArgument(let argument):
      return "unexpected argument '\(argument)'."
    case .invalidIterations(let value):
      return "invalid iterations '\(value)'. Use a positive integer."
    case .unknownMode(let mode):
      return "unknown render mode '\(mode)'. Known modes: \(knownModeList)."
    case .emptyModeList:
      return "mode list is empty."
    case .unknownScenario(let scenario):
      return "unknown scenario '\(scenario)'. Known scenarios: \(knownScenarioList)."
    case .compareArgumentCount(let count):
      return "compare expects 2 run directories, got \(count)."
    case .invalidSigma(let value):
      return "invalid sigma '\(value)'. Use a non-negative number."
    case .invalidTerminalSize(let value):
      return "invalid terminal size '\(value)'. Use positive CxR dimensions."
    }
  }

  private var knownModeList: String {
    [
      RuntimeRenderMode.sync,
      .async,
      .asyncNoCancel,
      .asyncNoDrop,
    ]
    .map(\.rawValue)
    .joined(separator: ", ")
  }

  private var knownScenarioList: String {
    PerfScenarioName.allNames.joined(separator: ", ")
  }
}

public enum PerfCommandParser {
  public static func parse(_ arguments: [String]) throws -> TermUIPerfCommand {
    guard let command = arguments.first else {
      throw PerfParseError.missingCommand
    }

    let remainingArguments = Array(arguments.dropFirst())
    switch command {
    case "run":
      return .run(try parseRun(remainingArguments))
    case "compare":
      return .compare(try parseCompare(remainingArguments))
    case "list-scenarios":
      try rejectArguments(remainingArguments)
      return .listScenarios
    default:
      throw PerfParseError.unknownCommand(command)
    }
  }

  private static func parseRun(_ arguments: [String]) throws -> PerfRunConfig {
    var scenario: PerfScenarioName?
    var modes = PerfRunConfig.defaultModes
    var iterations = PerfRunConfig.defaultIterations
    var artifactsRoot = PerfRunConfig.defaultArtifactsRoot
    var configuration = PerfRunConfig.defaultConfiguration
    var terminalSize: PerfTerminalSize?

    var index = arguments.startIndex
    while index < arguments.endIndex {
      let argument = arguments[index]
      switch argument {
      case "--scenario":
        let value = try value(after: argument, in: arguments, at: &index)
        guard let parsedScenario = PerfScenarioName(rawValue: value) else {
          throw PerfParseError.unknownScenario(value)
        }
        scenario = parsedScenario
      case "--mode", "--modes":
        let value = try value(after: argument, in: arguments, at: &index)
        modes = try parseModes(value)
      case "--iterations":
        let value = try value(after: argument, in: arguments, at: &index)
        guard let parsedIterations = Int(value), parsedIterations > 0 else {
          throw PerfParseError.invalidIterations(value)
        }
        iterations = parsedIterations
      case "--artifacts-root":
        artifactsRoot = try value(after: argument, in: arguments, at: &index)
      case "--configuration":
        configuration = try value(after: argument, in: arguments, at: &index)
      case "--terminal-size":
        let value = try value(after: argument, in: arguments, at: &index)
        terminalSize = try parseTerminalSize(value)
      default:
        if argument.hasPrefix("-") {
          throw PerfParseError.unknownOption(argument)
        }
        throw PerfParseError.unexpectedArgument(argument)
      }
      index = arguments.index(after: index)
    }

    guard let scenario else {
      throw PerfParseError.missingRequiredOption("--scenario")
    }

    return PerfRunConfig(
      scenario: scenario,
      modes: modes,
      iterations: iterations,
      artifactsRoot: artifactsRoot,
      configuration: configuration,
      terminalSize: terminalSize
    )
  }

  private static func parseCompare(_ arguments: [String]) throws -> PerfCompareConfig {
    var positionals: [String] = []
    var gate = false
    var requireImprovement: [String] = []
    var sigma = CompareCommand.defaultNoiseSigma

    var index = arguments.startIndex
    while index < arguments.endIndex {
      let argument = arguments[index]
      switch argument {
      case "--gate":
        gate = true
      case "--require-improvement":
        let value = try value(after: argument, in: arguments, at: &index)
        requireImprovement.append(
          contentsOf:
            value
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        )
      case "--sigma":
        let value = try value(after: argument, in: arguments, at: &index)
        guard let parsedSigma = Double(value), parsedSigma >= 0 else {
          throw PerfParseError.invalidSigma(value)
        }
        sigma = parsedSigma
      default:
        if argument.hasPrefix("-") {
          throw PerfParseError.unknownOption(argument)
        }
        positionals.append(argument)
      }
      index = arguments.index(after: index)
    }

    guard positionals.count == 2 else {
      throw PerfParseError.compareArgumentCount(positionals.count)
    }

    return PerfCompareConfig(
      baseRunDirectory: positionals[0],
      candidateRunDirectory: positionals[1],
      gate: gate,
      requireImprovement: requireImprovement,
      sigma: sigma
    )
  }

  private static func rejectArguments(_ arguments: [String]) throws {
    guard arguments.isEmpty else {
      throw PerfParseError.unexpectedArgument(arguments[0])
    }
  }

  private static func parseTerminalSize(_ value: String) throws -> PerfTerminalSize {
    let parts = value.split(
      omittingEmptySubsequences: false,
      whereSeparator: { $0 == "x" || $0 == "X" }
    )
    guard
      parts.count == 2,
      let columns = Int(parts[0]),
      let rows = Int(parts[1]),
      columns > 0,
      rows > 0
    else {
      throw PerfParseError.invalidTerminalSize(value)
    }
    return PerfTerminalSize(columns: columns, rows: rows)
  }

  private static func value(
    after option: String,
    in arguments: [String],
    at index: inout Array<String>.Index
  ) throws -> String {
    let valueIndex = arguments.index(after: index)
    guard valueIndex < arguments.endIndex else {
      throw PerfParseError.missingValue(option)
    }
    index = valueIndex
    return arguments[valueIndex]
  }

  private static func parseModes(_ rawValue: String) throws -> [RuntimeRenderMode] {
    let components =
      rawValue
      .split(separator: ",", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    guard components.allSatisfy({ !$0.isEmpty }) else {
      throw PerfParseError.emptyModeList
    }

    return try components.map { component in
      guard let mode = RuntimeRenderMode(rawValue: component) else {
        throw PerfParseError.unknownMode(component)
      }
      return mode
    }
  }
}
