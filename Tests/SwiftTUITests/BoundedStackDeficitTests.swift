import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Bounded stack deficit allocation")
struct BoundedStackDeficitTests {
  @Test("T261: bounded stacks reserve remaining sibling minimums", arguments: [false, true], 0..<4)
  func boundedDeficitFits(horizontal: Bool, scenario: Int) throws {
    let minimum = scenario == 1 ? 40 : 20
    let available = [30, 50, 10, 40][scenario]
    let secondID = testIdentity("T261", "second")
    func child(_ color: Color, minimum: Int, ideal: Int, maximum: Int) -> some View {
      Rectangle().fill(color).frame(
        minWidth: .finite(horizontal ? minimum : 1),
        idealWidth: .finite(horizontal ? ideal : 1),
        maxWidth: .finite(horizontal ? maximum : 1),
        minHeight: .finite(horizontal ? 1 : minimum),
        idealHeight: .finite(horizontal ? 1 : ideal),
        maxHeight: .finite(horizontal ? 1 : maximum)
      )
    }
    let first = child(.red, minimum: 0, ideal: minimum, maximum: minimum).layoutPriority(1)
    let second = child(.blue, minimum: minimum, ideal: minimum * 2, maximum: minimum * 2)
      .layoutPriority(1).id(secondID)
    let reserved = child(.green, minimum: 10, ideal: 10, maximum: 10)
    let context = ResolveContext(identity: testIdentity("T261", "Root"))
    let frame =
      horizontal
      ? DefaultRenderer().render(
        HStack(spacing: 0) {
          first
          second
          if scenario == 3 { reserved }
        },
        context: context, proposal: .init(width: available, height: 1))
      : DefaultRenderer().render(
        VStack(spacing: 0) {
          first
          second
          if scenario == 3 { reserved }
        },
        context: context, proposal: .init(width: 1, height: available))
    let actual =
      horizontal ? frame.measuredTree.measuredSize.width : frame.measuredTree.measuredSize.height
    if scenario == 2 {
      #expect(actual >= minimum)  // Impossible deficits must preserve structural minimums.
    } else {
      #expect(actual == available)
    }
    func findSecond(_ node: PlacedNode) -> PlacedNode? {
      if node.identity == secondID { return node }
      for child in node.children {
        if let found = findSecond(child) { return found }
      }
      return nil
    }
    let placed = try #require(findSecond(frame.placedTree))
    #expect((horizontal ? placed.bounds.size.width : placed.bounds.size.height) >= minimum)
  }
}
