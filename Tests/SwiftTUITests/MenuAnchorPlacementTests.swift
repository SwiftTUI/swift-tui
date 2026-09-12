import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct MenuAnchorPlacementTests {
  @Test("an open menu follows its source and clamps above the lower viewport edge")
  func sourcePlacement() throws {
    let renderer = DefaultRenderer()
    let actions = LocalActionRegistry()
    let id = testIdentity("AnchoredMenu")
    let context = ResolveContext(
      identity: testIdentity("MenuAnchorRoot"), localActionRegistry: actions,
      applyEnvironmentValues: true)
    func frame(x: Int, y: Int) -> RenderSnapshot {
      renderer.render(
        Menu("Trigger") { Button("Run action") {} }.id(id)
          .offset(x: x, y: y)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading),
        context: context, proposal: .init(width: 40, height: 16))
    }
    _ = frame(x: 8, y: 3)
    #expect(actions.dispatch(identity: id))
    let first = frame(x: 8, y: 3)
    let moved = frame(x: 18, y: 7)
    func point(_ snapshot: RenderSnapshot) throws -> CellPoint {
      let lines = snapshot.rasterSurface.lines
      let y = try #require(lines.firstIndex { $0.contains("Run action") })
      let index = try #require(lines[y].range(of: "Run action")?.lowerBound)
      return CellPoint(x: lines[y].distance(from: lines[y].startIndex, to: index), y: y)
    }
    let firstPoint = try point(first)
    let movedPoint = try point(moved)
    #expect(firstPoint.x >= 8)
    #expect(firstPoint.y > 3)
    #expect(movedPoint.x - firstPoint.x == 10)
    #expect(movedPoint.y - firstPoint.y == 4)
    let edge = frame(x: 34, y: 15)
    let edgePoint = try point(edge)
    #expect(edgePoint.y < 15)
    #expect(edgePoint.x + "Run action".count <= 40)
  }
}
