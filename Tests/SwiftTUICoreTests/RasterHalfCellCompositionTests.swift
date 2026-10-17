import Testing

@testable import SwiftTUICore

struct RasterHalfCellCompositionTests {
  @Test(arguments: [false, true])
  func oppositeHalfSurvivesWithOneAlphaComposition(reversed: Bool) throws {
    let translucent = Color.red.withAlpha(0.4)
    let underlay = RasterCell(
      character: reversed ? "▄" : "▀",
      style: .init(foregroundColor: .blue, backgroundColor: .green))
    let source = RasterCell(
      character: reversed ? "▀" : "▄",
      style: .init(foregroundColor: translucent))
    let composed = try #require(compositeVerticalBlockCell(source, over: underlay))
    let mixed = Color.green.mixed(with: .red, amount: 0.4)
    #expect(composed.character == source.character)
    #expect(composed.style?.foregroundColor == mixed)
    #expect(composed.style?.backgroundColor == .blue)
  }
}
