import Synchronization
import swift_figlet
import swift_figlet_embedded_fonts

public struct TextFigurePayload: Equatable, Hashable, Sendable {
  public var content: String
  public var font: String

  public init(
    content: String,
    font: String
  ) {
    self.content = content
    self.font = font
  }
}

package struct TextFigureLayoutMetrics: Equatable, Sendable {
  var minimumWidth: Int
  var idealSize: Size
}

package struct TextFigureRenderResult: Equatable, Sendable {
  var lines: [String]
  var size: Size
}

package enum TextFigureSupport {
  private static let fontLibrary = SwiftFigletEmbeddedFonts.library
  private static let fontCache = Mutex<[String: FigletFont]>([:])
  private static let metricsCache = Mutex<[TextFigurePayload: TextFigureLayoutMetrics]>([:])

  package static var availableFonts: [String] {
    Figlet.availableFonts(fontLibraries: [fontLibrary])
  }

  package static func supportsFont(
    named name: String
  ) -> Bool {
    availableFonts.contains(name)
  }

  package static func layoutMetrics(
    for payload: TextFigurePayload
  ) -> TextFigureLayoutMetrics {
    guard !payload.content.isEmpty else {
      return .init(minimumWidth: 0, idealSize: .zero)
    }

    if let cached = metricsCache.withLock({ $0[payload] }) {
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
        "TextFigure could not resolve embedded font '\(payload.font)'"
      )
      resolvedMetrics = fallbackLayoutMetrics(for: payload.content)
    }

    metricsCache.withLock {
      $0[payload] = resolvedMetrics
    }
    return resolvedMetrics
  }

  package static func measuredSize(
    for payload: TextFigurePayload,
    proposal: ProposedSize
  ) -> Size {
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

    if let measured = try? resolvedFiglet(for: payload).measure(payload.content, forWidth: renderedWidth)
    {
      return .init(width: measured.width, height: measured.height)
    }

    reportTextFigureConfigurationError(
      "TextFigure could not measure embedded font '\(payload.font)'"
    )
    return fallbackLayoutMetrics(for: payload.content).idealSize
  }

  package static func render(
    _ payload: TextFigurePayload,
    boundsWidth: Int
  ) -> TextFigureRenderResult {
    guard !payload.content.isEmpty else {
      return .init(lines: [], size: .zero)
    }

    let metrics = layoutMetrics(for: payload)
    let renderWidth = max(1, max(boundsWidth, metrics.minimumWidth))

    guard let text = try? resolvedFiglet(for: payload, width: renderWidth).render(payload.content) else {
      reportTextFigureConfigurationError(
        "TextFigure could not render embedded font '\(payload.font)'"
      )
      return fallbackRenderResult(for: payload.content)
    }

    let lines = renderedLines(from: text).map(trimmedTrailingSpaces)
    return .init(
      lines: lines,
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
    named name: String
  ) throws -> FigletFont {
    if let cached = fontCache.withLock({ $0[name] }) {
      return cached
    }

    let font = try FigletFont(named: name, fontLibrary: fontLibrary)
    fontCache.withLock {
      $0[name] = font
    }
    return font
  }

  private static func renderedLines(
    from text: FigletText
  ) -> [String] {
    var lines = text.rawValue.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if lines.last == "" {
      lines.removeLast()
    }
    return lines
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
    return .init(
      lines: lines,
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

  private static func trimmedTrailingSpaces(
    _ line: String
  ) -> String {
    var characters = Array(line)
    while characters.last == " " {
      characters.removeLast()
    }
    return String(characters)
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
