public import SwiftTUI

public struct MillerLayout: Layout, Sendable {
  public static let preferredColumnWidth = 30

  public init() {}

  public static func columnWidths(
    totalWidth: Int,
    columnCount: Int
  ) -> [Int] {
    guard columnCount > 0 else {
      return []
    }
    guard totalWidth > 0 else {
      return Array(repeating: 0, count: columnCount)
    }
    guard columnCount > 1 else {
      return [totalWidth]
    }

    let nonLastWidth = min(preferredColumnWidth, totalWidth / columnCount)
    let leftWidths = Array(repeating: nonLastWidth, count: columnCount - 1)
    let lastWidth = max(0, totalWidth - leftWidths.reduce(0, +))
    return leftWidths + [lastWidth]
  }

  public func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    guard !subviews.isEmpty else {
      return .zero
    }

    let width = finiteDimension(proposal.width) ?? intrinsicWidth(for: subviews)
    let widths = Self.columnWidths(totalWidth: width, columnCount: subviews.count)
    let height = finiteDimension(proposal.height) ?? intrinsicHeight(for: subviews, widths: widths)
    return .init(width: width, height: height)
  }

  public func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    let widths = Self.columnWidths(totalWidth: bounds.size.width, columnCount: subviews.count)
    var x = bounds.origin.x

    for (index, subview) in subviews.enumerated() {
      let width = widths[index]
      subview.place(
        at: .init(x: x, y: bounds.origin.y),
        anchor: .topLeading,
        proposal: .init(width: width, height: bounds.size.height)
      )
      x += width
    }
  }

  private func intrinsicWidth(for subviews: LayoutSubviews) -> Int {
    subviews
      .map { $0.sizeThatFits(.unspecified).width }
      .reduce(0, +)
  }

  private func intrinsicHeight(
    for subviews: LayoutSubviews,
    widths: [Int]
  ) -> Int {
    zip(subviews, widths)
      .map { subview, width in
        subview.sizeThatFits(.init(width: width, height: nil)).height
      }
      .max() ?? 0
  }

  private func finiteDimension(_ dimension: ProposedDimension) -> Int? {
    switch dimension {
    case .finite(let value):
      return max(0, value)
    case .infinity, .unspecified:
      return nil
    }
  }
}
