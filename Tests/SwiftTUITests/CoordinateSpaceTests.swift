import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Two name types whose cases print identically (`"main"`). Under the old
/// description-keyed identity these named the same coordinate space.
private enum BoardSpace: Hashable, Sendable {
  case main
}

private enum PanelSpace: Hashable, Sendable {
  case main
}

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
      namedCoordinateSpaces: [.named("board"): namedFrame]
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
        .coordinateSpace(.named("board")),
      context: ResolveContext(identity: root, environmentValues: env),
      proposal: .init(width: 20, height: 5)
    )

    let frame = try #require(artifacts.semanticSnapshot.namedCoordinateSpaces[.named("board")])
    #expect(frame.origin == .zero)
    #expect(frame.size.width >= 5)
  }

  // MARK: - Typed identity

  @Test("named spaces are identified by typed value, not by description")
  func namedSpaceIdentityIsTyped() {
    // Same type and value: one space.
    #expect(NamedCoordinateSpace.named(BoardSpace.main) == .named(BoardSpace.main))
    #expect(NamedCoordinateSpace.named("board") == .named("board"))
    #expect(CoordinateSpace.named("board") == CoordinateSpace.named("board"))

    // Equal descriptions, different types: distinct spaces.
    #expect(NamedCoordinateSpace.named(BoardSpace.main) != .named(PanelSpace.main))
    #expect(NamedCoordinateSpace.named(BoardSpace.main) != .named("main"))
    #expect(NamedCoordinateSpace.named(1) != .named("1"))
    #expect(CoordinateSpace.named(BoardSpace.main) != CoordinateSpace.named("main"))
    #expect(CoordinateSpace.named(1) != CoordinateSpace.named("1"))

    // Hashing follows the same identity.
    let distinct: Set<NamedCoordinateSpace> = [
      .named(BoardSpace.main), .named(PanelSpace.main), .named("main"), .named(BoardSpace.main),
    ]
    #expect(distinct.count == 3)

    // The description is the diagnostic spelling and stays shared.
    #expect(NamedCoordinateSpace.named(BoardSpace.main).description == "main")
    #expect(NamedCoordinateSpace.named(PanelSpace.main).description == "main")
    #expect(NamedCoordinateSpace.named("main").description == "main")
    #expect(NamedCoordinateSpace.named(1).description == "1")

    // The bridge into gesture resolution carries the same identity.
    #expect(
      NamedCoordinateSpace.named(BoardSpace.main).coordinateSpace
        == CoordinateSpace.named(BoardSpace.main)
    )
    #expect(
      NamedCoordinateSpace.named(BoardSpace.main).coordinateSpace
        != CoordinateSpace.named(PanelSpace.main)
    )
  }

  @Test("resolution keys on the typed name and reports misses by description")
  func namedResolutionKeysOnTypedName() {
    let target = CellRect(
      origin: CellPoint(x: 8, y: 5),
      size: CellSize(width: 3, height: 2)
    )
    let boardFrame = CellRect(
      origin: CellPoint(x: 4, y: 2),
      size: CellSize(width: 12, height: 6)
    )
    let stringFrame = CellRect(
      origin: CellPoint(x: 1, y: 1),
      size: CellSize(width: 12, height: 6)
    )
    // Built incrementally: a literal would trap on duplicate keys if identity
    // regressed to description, hiding the failure behind a crash.
    var frames: [NamedCoordinateSpace: CellRect] = [:]
    frames[.named(BoardSpace.main)] = boardFrame
    frames[.named("main")] = stringFrame
    #expect(frames.count == 2)
    let terminalPoint = Point(x: 6.5, y: 3.25)
    let recorder = GeometryResolutionDiagnosticsRecorder()

    let board = CoordinateSpace.named(BoardSpace.main).resolve(
      terminalPoint: terminalPoint,
      targetRect: target,
      namedCoordinateSpaces: frames,
      diagnosticsRecorder: recorder
    )
    let string = CoordinateSpace.named("main").resolve(
      terminalPoint: terminalPoint,
      targetRect: target,
      namedCoordinateSpaces: frames,
      diagnosticsRecorder: recorder
    )
    #expect(board == Point(x: 2.5, y: 1.25))
    #expect(string == Point(x: 5.5, y: 2.25))
    #expect(recorder.snapshot.missingNamedCoordinateSpaceCount == 0)

    // Same description as both recorded spaces, but a third type: a miss.
    let panel = CoordinateSpace.named(PanelSpace.main).resolve(
      terminalPoint: terminalPoint,
      targetRect: target,
      namedCoordinateSpaces: frames,
      diagnosticsRecorder: recorder
    )
    #expect(panel == terminalPoint)
    #expect(recorder.snapshot.missingNamedCoordinateSpaceCount == 1)
    #expect(recorder.snapshot.firstMissingNamedCoordinateSpaceName == "main")
  }

  @Test("two spaces with the same description coexist in a rendered frame")
  func sameDescriptionSpacesCoexistInRenderedFrame() throws {
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        Text("Board")
          .frame(width: 10, height: 1)
          .coordinateSpace(.named(BoardSpace.main))
        Text("Panel")
          .frame(width: 10, height: 1)
          .coordinateSpace(.named(PanelSpace.main))
        GeometryReader { proxy in
          let board = proxy.frame(in: .named(BoardSpace.main))
          let panel = proxy.frame(in: .named(PanelSpace.main))
          Text("\(Int(board.origin.y)),\(Int(panel.origin.y))")
        }
        .frame(width: 10, height: 1)
      },
      proposal: .init(width: 20, height: 3)
    )

    // The reader sits on row 2: two rows below the board space, one below the
    // panel space. Description-keyed identity collapsed both onto the last
    // writer and rendered "1,1".
    #expect(
      artifacts.rasterSurface.lines.contains { line in
        line.contains("2,1")
      }
    )

    let spaces = artifacts.semanticSnapshot.namedCoordinateSpaces
    #expect(spaces.count == 2)
    let board = try #require(spaces[.named(BoardSpace.main)])
    let panel = try #require(spaces[.named(PanelSpace.main)])
    #expect(board.origin.y == 0)
    #expect(panel.origin.y == 1)
    #expect(spaces[.named("main")] == nil)
    #expect(Set(spaces.keys.map(\.description)) == ["main"])

    let diagnostics = artifacts.diagnostics.geometryResolutionDiagnostics
    #expect(diagnostics.duplicateNamedCoordinateSpaceCount == 0)
    #expect(diagnostics.missingNamedCoordinateSpaceCount == 0)
  }
}
