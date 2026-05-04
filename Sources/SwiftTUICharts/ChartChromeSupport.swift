import SwiftTUICore
import SwiftTUIViews

/// Semantic tone used by chart banners, badges, and accent surfaces.
public struct BannerTone: Hashable, Sendable {
  private let rawValue: String

  private init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public static let automatic = Self("automatic")
  public static let info = Self("info")
  public static let success = Self("success")
  public static let warning = Self("warning")
  public static let critical = Self("critical")
}

func metricAccentStyle(
  for tone: BannerTone
) -> AnyShapeStyle {
  toneAccentStyle(for: tone)
}

func sparklineGlyphString(
  _ values: [Double]
) -> String {
  guard !values.isEmpty else {
    return "[]"
  }

  let minimum = values.min() ?? 0
  let maximum = values.max() ?? 0
  guard maximum > minimum else {
    return String(repeating: "▄", count: values.count)
  }

  let glyphs = Array("▁▂▃▄▅▆▇█")
  return values.map { value in
    let normalized = min(max((value - minimum) / (maximum - minimum), 0), 1)
    let index = min(
      glyphs.count - 1,
      max(0, Int((normalized * Double(glyphs.count - 1)).rounded()))
    )
    return String(glyphs[index])
  }.joined()
}

func sparklineSummaryText(
  _ values: [Double]
) -> String {
  guard let minimum = values.min(), let maximum = values.max() else {
    return "no data"
  }

  return "lo \(metricValueString(minimum)) hi \(metricValueString(maximum))"
}

func trendTone(
  value: Double,
  preferred: BannerTone
) -> BannerTone {
  guard preferred == .automatic else {
    return preferred
  }

  if value > 0 {
    return .success
  }
  if value < 0 {
    return .warning
  }
  return .info
}

private func toneAccentStyle(
  for tone: BannerTone
) -> AnyShapeStyle {
  switch tone {
  case .success:
    return AnyShapeStyle(.success)
  case .warning:
    return AnyShapeStyle(.warning)
  case .critical:
    return AnyShapeStyle(.warning)
  case .info:
    return AnyShapeStyle(.info)
  default:
    return AnyShapeStyle(.tint)
  }
}
