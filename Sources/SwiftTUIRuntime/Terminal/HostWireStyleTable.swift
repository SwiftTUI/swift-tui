import SwiftTUICore

/// A first-appearance-ordered, encoded-appearance-keyed style epoch.
///
/// The table keeps lookup constant-time and bounds retained history to the
/// largest style set one frame of the current grid can require. Slot zero is
/// always the explicit nil style.
package struct HostWireStyleTable: Sendable {
  private struct HostWireStyleKey: Hashable, Sendable {
    let encoded: String
  }

  private var elements: [String]
  private var indexes: [HostWireStyleKey: Int]
  private let budget: Int

  package init(gridSize: CellSize?) {
    elements = ["null"]
    indexes = [HostWireStyleKey(encoded: "null"): 0]
    budget = Self.epochBudget(for: gridSize)
  }

  package var count: Int {
    elements.count
  }

  package var encodedElements: [String] {
    elements
  }

  /// Returns the stable index for `style`, or `nil` when adding it would
  /// exceed this epoch's area-bounded budget.
  package mutating func index(
    for style: ResolvedTextStyle?
  ) -> Int? {
    let encoded = Self.encodeStyle(style)
    let key = HostWireStyleKey(encoded: encoded)
    if let existing = indexes[key] {
      return existing
    }
    guard elements.count < budget else {
      return nil
    }
    let index = elements.count
    elements.append(encoded)
    indexes[key] = index
    return index
  }

  private static func epochBudget(
    for gridSize: CellSize?
  ) -> Int {
    guard let gridSize else {
      return 1_024
    }
    let width = max(0, gridSize.width)
    let height = max(0, gridSize.height)
    let (area, areaOverflow) = width.multipliedReportingOverflow(by: height)
    guard !areaOverflow else {
      return Int.max
    }
    let (frameBudget, additionOverflow) = area.addingReportingOverflow(1)
    return max(1_024, additionOverflow ? Int.max : frameBudget)
  }

  private static func encodeStyle(
    _ style: ResolvedTextStyle?
  ) -> String {
    guard let style else {
      return "null"
    }

    var fields: [String] = []
    if let foregroundColor = style.foregroundColor {
      fields.append(
        "\"fg\":\(WebSurfaceFrameEncoder.jsonString(foregroundColor.hexString(format: .rrggbbaa)))"
      )
    }
    if let backgroundColor = style.backgroundColor {
      fields.append(
        "\"bg\":\(WebSurfaceFrameEncoder.jsonString(backgroundColor.hexString(format: .rrggbbaa)))"
      )
    }
    if !style.emphasis.isEmpty {
      fields.append("\"em\":\(style.emphasis.rawValue)")
    }
    if let underlineStyle = style.underlineStyle {
      fields.append("\"underline\":\(encodeLineStyle(underlineStyle))")
    }
    if let strikethroughStyle = style.strikethroughStyle {
      fields.append("\"strikethrough\":\(encodeLineStyle(strikethroughStyle))")
    }
    if style.opacity < 1 {
      fields.append("\"opacity\":\(style.opacity)")
    }

    return "{" + fields.joined(separator: ",") + "}"
  }

  private static func encodeLineStyle(
    _ style: TextLineStyle
  ) -> String {
    var fields = [
      "\"pattern\":\(WebSurfaceFrameEncoder.jsonString(style.pattern.rawValue))"
    ]
    if let color = style.color {
      fields.append(
        "\"color\":\(WebSurfaceFrameEncoder.jsonString(color.hexString(format: .rrggbbaa)))"
      )
    }
    return "{" + fields.joined(separator: ",") + "}"
  }
}
