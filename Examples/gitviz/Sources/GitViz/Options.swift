import ArgumentParser
import Foundation
import SwiftTUI

/// Shared option group flattened into every gitviz subcommand.
///
/// Inherits the SwiftTUI framework's color / glyph / motion flags via
/// `SwiftTUIOptions`, and adds path / date-window / scan-size / output-width
/// options that belong to gitviz itself.
struct GitVizOptions: ParsableArguments {
  @Option(name: .long, help: "Repository path (defaults to cwd).")
  var path: String = "."

  @Option(name: .long, help: "Only consider commits since this date (YYYY-MM-DD).")
  var since: String?

  @Option(name: .long, help: "Only consider commits until this date (YYYY-MM-DD).")
  var until: String?

  @Option(name: .long, help: "Limit each scan to the last N commits (default: 10000).")
  var maxCommits: Int = 10_000

  @Option(name: .long, help: "Top-N for ranking subcommands (default: 10).")
  var top: Int = 10

  @Option(name: .long, help: "Output width in cells (defaults to terminal width).")
  var width: Int?

  @OptionGroup(title: "SwiftTUI Options")
  var swiftTUIOptions: SwiftTUIOptions
}

extension GitVizOptions {
  /// Repository path, resolved against the process cwd.
  var resolvedPath: URL {
    let expanded = (path as NSString).expandingTildeInPath
    let url = URL(fileURLWithPath: expanded)
    if url.path.hasPrefix("/") {
      return url
    }
    let cwd = FileManager.default.currentDirectoryPath
    return URL(fileURLWithPath: cwd).appendingPathComponent(path)
  }

  /// `--since` parsed as a `Date` (or nil if absent / malformed).
  var sinceDate: Date? { parseDate(since) }

  /// `--until` parsed as a `Date` (or nil if absent / malformed).
  var untilDate: Date? { parseDate(until) }

  private func parseDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    return formatter.date(from: value)
  }

  /// Eagerly resolves the effective output width. Used by chart primitives
  /// that lock their internal plot width at construction time (LineChart,
  /// for instance) — without this they fall back to a 60-cell default and
  /// look "disjoint" from their title chrome on wider terminals.
  func resolvedWidth(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Int {
    width ?? RenderOnce.resolveTerminalWidth(environment: environment)
  }
}
