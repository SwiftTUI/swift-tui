@_exported import EmbeddedFonts
import DequeModule
import SwiftFiglet
import Synchronization

public typealias TextFigureFont = EmbeddedFigletFont

public struct TextFigureColorMode: Equatable, Sendable {
  enum Storage: Equatable, Sendable {
    case authored
    case fillUnstyled(AnyShapeStyle?)
    case monochrome
    case override(AnyShapeStyle?)
    case tinted(AnyShapeStyle?)
  }

  var storage: Storage

  public static let authored = Self(storage: .authored)
  public static let fillUnstyled = Self(storage: .fillUnstyled(nil))
  public static let monochrome = Self(storage: .monochrome)
  public static let `override` = Self(storage: .override(nil))
  public static let tinted = Self(storage: .tinted(nil))

  public static func fillUnstyled<S: ShapeStyle>(_ style: S) -> Self {
    Self(storage: .fillUnstyled(AnyShapeStyle(style)))
  }

  public static func `override`<S: ShapeStyle>(_ style: S) -> Self {
    Self(storage: .override(AnyShapeStyle(style)))
  }

  public static func tinted<S: ShapeStyle>(_ style: S) -> Self {
    Self(storage: .tinted(AnyShapeStyle(style)))
  }
}

public struct TextFigurePayload: Equatable, Hashable, Sendable {
  public var content: String
  public var font: TextFigureFont
  public var colorMode: TextFigureColorMode

  public init(
    content: String,
    font: TextFigureFont,
    colorMode: TextFigureColorMode = .authored
  ) {
    self.content = content
    self.font = font
    self.colorMode = colorMode
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(content)
    hasher.combine(font)
  }
}

package struct TextFigureLayoutMetrics: Equatable, Sendable {
  var minimumWidth: Int
  var idealSize: CellSize
}

package struct TextFigureRenderResult: Equatable, Sendable {
  var lines: [String]
  var styledLines: [PreformattedTextLine]
  var size: CellSize
}

package enum TextFigureSupport {

  private struct MetricsCacheEntry: Sendable {
    var metrics: TextFigureLayoutMetrics
    var generation: UInt64
  }

  private struct MetricsCacheAccessRecord: Sendable {
    var payload: TextFigurePayload
    var generation: UInt64
  }

  private struct MetricsCacheStorage: Sendable {
    var entries: [TextFigurePayload: MetricsCacheEntry] = [:]
    var order: Deque<MetricsCacheAccessRecord> = []
    var nextGeneration: UInt64 = 0
  }

  private static let fontCache = Mutex<[TextFigureFont: FigletFont]>([:])
  private static let metricsCacheCapacity = 256
  private static let metricsCache = Mutex<MetricsCacheStorage>(.init())

  package static var availableFonts: [TextFigureFont] {
    TextFigureFont.allCases
  }

  package static func layoutMetrics(
    for payload: TextFigurePayload
  ) -> TextFigureLayoutMetrics {
    guard !payload.content.isEmpty else {
      return .init(minimumWidth: 0, idealSize: .zero)
    }

    if let cached = metricsCache.withLock({ storage -> TextFigureLayoutMetrics? in
      guard var cached = storage.entries[payload] else {
        return nil
      }
      cached.generation = nextMetricsCacheGeneration(in: &storage)
      storage.entries[payload] = cached
      storage.order.append(.init(payload: payload, generation: cached.generation))
      return cached.metrics
    }) {
      return cached
    }

    let resolvedMetrics: TextFigureLayoutMetrics
    if let metrics = try? resolvedFiglet(for: payload).layoutMetrics(for: payload.content) {
      resolvedMetrics = TextFigureLayoutMetrics(
        minimumWidth: metrics.minimumWidth,
        idealSize: .init(
          width: metrics.idealSize.width,
          height: metrics.idealSize.height
        )
      )
    } else {
      reportTextFigureConfigurationError(
        "TextFigure could not resolve embedded font '\(payload.font.rawValue)'"
      )
      resolvedMetrics = fallbackLayoutMetrics(for: payload.content)
    }

    metricsCache.withLock { storage in
      if var cached = storage.entries[payload] {
        cached.generation = nextMetricsCacheGeneration(in: &storage)
        storage.entries[payload] = cached
        storage.order.append(.init(payload: payload, generation: cached.generation))
        return
      }

      let generation = nextMetricsCacheGeneration(in: &storage)
      storage.entries[payload] = .init(metrics: resolvedMetrics, generation: generation)
      storage.order.append(.init(payload: payload, generation: generation))
      evictMetricsCacheIfNeeded(in: &storage)
    }
    return resolvedMetrics
  }

  package static func measuredSize(
    for payload: TextFigurePayload,
    proposal: ProposedSize
  ) -> CellSize {
    let metrics = layoutMetrics(for: payload)

    let renderedWidth: Int? =
      switch proposal.width {
      case .finite(let width):
        max(metrics.minimumWidth, max(0, width))
      case .unspecified, .infinity:
        nil
      }

    guard let renderedWidth else {
      return metrics.idealSize
    }

    if let measured = try? resolvedFiglet(for: payload).measure(
      payload.content, forWidth: renderedWidth)
    {
      return .init(width: measured.width, height: measured.height)
    }

    reportTextFigureConfigurationError(
      "TextFigure could not measure embedded font '\(payload.font.rawValue)'"
    )
    return fallbackLayoutMetrics(for: payload.content).idealSize
  }

  package static func render(
    _ payload: TextFigurePayload,
    boundsWidth: Int,
    environment: StyleEnvironmentSnapshot
  ) -> TextFigureRenderResult {
    guard !payload.content.isEmpty else {
      return .init(lines: [], styledLines: [], size: .zero)
    }

    let metrics = layoutMetrics(for: payload)
    let renderWidth = max(1, max(boundsWidth, metrics.minimumWidth))

    guard
      let surface = try? resolvedFiglet(for: payload, width: renderWidth)
        .renderSurface(payload.content)
    else {
      reportTextFigureConfigurationError(
        "TextFigure could not render embedded font '\(payload.font.rawValue)'"
      )
      return fallbackRenderResult(for: payload.content)
    }

    let styledLines = renderedLines(
      from: surface,
      colorMode: payload.colorMode,
      environment: environment
    )
    let lines = styledLines.map(\.content)
    return .init(
      lines: lines,
      styledLines: styledLines,
      size: .init(
        width: lines.map { layoutText(for: $0, width: nil).size.width }.max() ?? 0,
        height: lines.count
      )
    )
  }

  private static func resolvedFiglet(
    for payload: TextFigurePayload,
    width: Int = 80
  ) throws -> Figlet {
    Figlet(
      font: try cachedFont(named: payload.font),
      configuration: .init(width: width)
    )
  }

  private static func cachedFont(
    named font: TextFigureFont
  ) throws -> FigletFont {
    if let cached = fontCache.withLock({ $0[font] }) {
      return cached
    }

    let resolvedFont = try FigletFont(
      named: font.rawValue,
      fontLibrary: EmbeddedFigletFont.library
    )
    fontCache.withLock {
      $0[font] = resolvedFont
    }
    return resolvedFont
  }


  private static func nextMetricsCacheGeneration(
    in storage: inout MetricsCacheStorage
  ) -> UInt64 {
    storage.nextGeneration &+= 1
    return storage.nextGeneration
  }

  private static func evictMetricsCacheIfNeeded(
    in storage: inout MetricsCacheStorage
  ) {
    while storage.entries.count > metricsCacheCapacity {
      guard let victim = storage.order.popFirst() else {
        break
      }
      guard let entry = storage.entries[victim.payload] else {
        continue
      }
      guard entry.generation == victim.generation else {
        continue
      }
      storage.entries.removeValue(forKey: victim.payload)
    }
  }
  private static func renderedLines(
    from surface: FigletSurface,
    colorMode: TextFigureColorMode,
    environment: StyleEnvironmentSnapshot
  ) -> [PreformattedTextLine] {
    surface.rows.map { row in
      let trimmedRow = trimmingTrailingSpaces(row)
      var runs: [PreformattedTextRun] = []
      runs.reserveCapacity(trimmedRow.count)

      for cell in trimmedRow {
        let style = textStyle(
          for: cell,
          colorMode: colorMode,
          environment: environment
        )
        let content = String(cell.character)
        if var previous = runs.last, previous.style == style {
          previous.content += content
          runs[runs.count - 1] = previous
        } else {
          runs.append(.init(content: content, style: style))
        }
      }

      return PreformattedTextLine(runs: runs)
    }
  }

  private static func textStyle(
    for cell: FigletCell,
    colorMode: TextFigureColorMode,
    environment: StyleEnvironmentSnapshot
  ) -> TextStyle {
    switch colorMode.storage {
    case .authored:
      return authoredTextStyle(from: cell.style, environment: environment)
    case .fillUnstyled(let fillStyle):
      if cell.style == .plain {
        return fillStyle.map { TextStyle(foregroundStyle: $0) } ?? TextStyle()
      }
      return authoredTextStyle(from: cell.style, environment: environment)
    case .monochrome:
      return TextStyle()
    case .override(let overrideStyle):
      return overrideStyle.map { TextStyle(foregroundStyle: $0) } ?? TextStyle()
    case .tinted(let tintStyle):
      let authoredStyle = authoredTextStyle(from: cell.style, environment: environment)
      guard !authoredStyle.isDefault,
        let tintColor = tintColor(for: tintStyle, environment: environment)
      else {
        return authoredStyle
      }
      let tinted = ResolvedTextStyle(authoredStyle, theme: environment.theme)
        .tinted(with: tintColor)
      return TextStyle(
        foregroundStyle: tinted.foregroundColor.map(AnyShapeStyle.init),
        backgroundStyle: tinted.backgroundColor.map(AnyShapeStyle.init),
        emphasis: tinted.emphasis,
        underlineStyle: tinted.underlineStyle,
        strikethroughStyle: tinted.strikethroughStyle,
        opacity: tinted.opacity
      )
    }
  }

  private static func authoredTextStyle(
    from style: FigletStyle,
    environment: StyleEnvironmentSnapshot
  ) -> TextStyle {
    TextStyle(
      foregroundStyle: style.foreground
        .flatMap { color in terminalColor(for: color, environment: environment) }
        .map(AnyShapeStyle.init),
      backgroundStyle: style.background
        .flatMap { color in terminalBackgroundColor(for: color, environment: environment) }
        .map(AnyShapeStyle.init)
    )
  }

  private static func terminalColor(
    for color: FigletTerminalColor,
    environment: StyleEnvironmentSnapshot
  ) -> Color? {
    let paletteIndex = [
      0, 4, 2, 6, 1, 5, 3, 7,
      8, 12, 10, 14, 9, 13, 11, 15,
    ][color.rawValue]
    return environment.appearance.palette[paletteIndex]
  }

  private static func terminalBackgroundColor(
    for color: FigletTerminalColor,
    environment: StyleEnvironmentSnapshot
  ) -> Color? {
    let paletteIndex = [0, 4, 2, 6, 1, 5, 3, 7][min(color.rawValue, 7)]
    return environment.appearance.palette[paletteIndex]
  }

  private static func tintColor(
    for style: AnyShapeStyle?,
    environment: StyleEnvironmentSnapshot
  ) -> Color? {
    let effectiveStyle = style ?? environment.tintStyle ?? .semantic(.tint)
    return resolveStyleColor(
      style: effectiveStyle,
      theme: environment.theme,
      appearance: environment.appearance
    )
  }

  private static func fallbackLayoutMetrics(
    for content: String
  ) -> TextFigureLayoutMetrics {
    let lines = plainTextLines(from: content)
    let widths = lines.map { layoutText(for: $0, width: nil).size.width }
    return .init(
      minimumWidth: widths.max() ?? 0,
      idealSize: .init(width: widths.max() ?? 0, height: lines.count)
    )
  }

  private static func fallbackRenderResult(
    for content: String
  ) -> TextFigureRenderResult {
    let lines = plainTextLines(from: content)
    let widths = lines.map { layoutText(for: $0, width: nil).size.width }
    let styledLines = lines.map { line in
      PreformattedTextLine(runs: [.init(content: line)])
    }
    return .init(
      lines: lines,
      styledLines: styledLines,
      size: .init(width: widths.max() ?? 0, height: lines.count)
    )
  }

  private static func plainTextLines(
    from content: String
  ) -> [String] {
    if content.isEmpty {
      return []
    }
    return content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  }

  private static func trimmingTrailingSpaces(
    _ row: [FigletCell]
  ) -> [FigletCell] {
    var cells = row
    while cells.last?.character == " " {
      cells.removeLast()
    }
    return cells
  }
}

package func reportTextFigureConfigurationError(
  _ message: String
) {
  #if DEBUG
    if isRunningUnderSwiftTest() {
      return
    }
    assertionFailure(message)
  #else
    _ = message
  #endif
}

private func isRunningUnderSwiftTest() -> Bool {
  CommandLine.arguments.contains { argument in
    argument.contains("swift-test") || argument.contains("xctest")
  }
}
