import Foundation
import Testing

@testable import Core
@testable import SwiftTUI
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
    let region = CellRect(
      origin: CellPoint(x: 4, y: 2),
      size: CellSize(width: 10, height: 3)
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
    let region = CellRect(
      origin: CellPoint(x: 4, y: 2),
      size: CellSize(width: 10, height: 3)
    )
    let terminalPoint = Point(x: 6, y: 3)
    let resolved = CoordinateSpace.global.resolve(
      terminalPoint: terminalPoint,
      targetRect: region
    )
    #expect(resolved == terminalPoint)
  }

  @Test(".named resolves by subtracting the recorded coordinate-space frame")
  func namedResolution() {
    let target = CellRect(
      origin: CellPoint(x: 8, y: 5),
      size: CellSize(width: 3, height: 2)
    )
    let namedFrame = CellRect(
      origin: CellPoint(x: 4, y: 2),
      size: CellSize(width: 12, height: 6)
    )
    let terminalPoint = Point(x: 6.5, y: 3.25)

    let resolved = CoordinateSpace.named("board").resolve(
      terminalPoint: terminalPoint,
      targetRect: target,
      namedCoordinateSpaces: ["board": namedFrame]
    )

    #expect(resolved == Point(x: 2.5, y: 1.25))
  }

  @Test(".named falls back to global when the frame is absent")
  func missingNamedResolutionFallsBackToGlobal() {
    let target = CellRect(
      origin: CellPoint(x: 8, y: 5),
      size: CellSize(width: 3, height: 2)
    )
    let terminalPoint = Point(x: 6.5, y: 3.25)

    let resolved = CoordinateSpace.named("missing").resolve(
      terminalPoint: terminalPoint,
      targetRect: target,
      namedCoordinateSpaces: [:]
    )

    #expect(resolved == terminalPoint)
  }

  @Test("coordinateSpace modifier records the named frame in semantics")
  func coordinateSpaceModifierRecordsFrame() throws {
    let root = Identity(components: [IdentityComponent(rawValue: "root")])
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 20, height: 5)

    let artifacts = DefaultRenderer().render(
      Text("board")
        .coordinateSpace(name: "board"),
      context: ResolveContext(identity: root, environmentValues: env),
      proposal: .init(width: 20, height: 5)
    )

    let frame = try #require(artifacts.semanticSnapshot.namedCoordinateSpaces["board"])
    #expect(frame.origin == .zero)
    #expect(frame.size.width >= 5)
  }
}
