import Foundation
import Testing

@testable import Core
@testable import View

@MainActor
@Suite
struct CoordinateSpaceTests {
  @Test("CoordinateSpace.local is distinct from .global")
  func localVsGlobal() {
    #expect(CoordinateSpace.local.kind == .local)
    #expect(CoordinateSpace.global.kind == .global)
    #expect(CoordinateSpace.local != CoordinateSpace.global)
  }

  @Test(".local resolves a terminal-global point to a region-relative point")
  func localResolution() {
    let region = Rect(
      origin: Point(x: 4, y: 2),
      size: Size(width: 10, height: 3)
    )
    let terminalPoint = Point(x: 6, y: 3)
    let resolved = CoordinateSpace.local.resolve(
      terminalPoint: terminalPoint,
      targetRect: region
    )
    #expect(resolved == Point(x: 2, y: 1))
  }

  @Test(".global resolves to the raw terminal point")
  func globalResolution() {
    let region = Rect(
      origin: Point(x: 4, y: 2),
      size: Size(width: 10, height: 3)
    )
    let terminalPoint = Point(x: 6, y: 3)
    let resolved = CoordinateSpace.global.resolve(
      terminalPoint: terminalPoint,
      targetRect: region
    )
    #expect(resolved == terminalPoint)
  }
}
