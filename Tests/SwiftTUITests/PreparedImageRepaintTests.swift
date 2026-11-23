import Synchronization
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

private enum PreparedImageRead: CaseIterable, Sendable {
  case source, composite

  var shader: CellLayerShader {
    let pass: CellLayerShader
    switch self {
    case .source:
      pass = CellLayerShader { point, _, _ in
        point.x == 2 ? .glyph(CellGlyph("S")) : .empty
      }
    case .composite:
      pass = .compositing { point, _, backdrop, _ in
        guard var glyph = backdrop.glyph(occupying: point) else { return .keepDestination }
        if glyph.character == "T" { glyph.character = "t" }
        return .replace(.glyph(glyph))
      }
    }
    return pass.drawing(
      in: .rect(.init(origin: .init(x: 1, y: 0), size: .init(width: 2, height: 1))))
  }
}

private struct PreparedImageKernel: CellPreparedLayerKernel {
  let read: PreparedImageRead
  func makeState() -> Bool { false }
  func prepare(_ state: inout Bool, source: CellLayer, context: CellPreparationContext)
    -> CellLayerShader
  {
    read.shader
  }
}

private final class PreparedHistory: Sendable {
  let ticks = Mutex<[Duration]>([])
}

private struct PreviousInput: CellPreparedLayerKernel {
  let history: PreparedHistory
  let version: Int

  final class State: Sendable {
    let previous = Mutex<CellLayer?>(nil)
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.history === rhs.history && lhs.version == rhs.version
  }

  func makeState() -> State { State() }
  func prepare(_ state: inout State, source: CellLayer, context: CellPreparationContext)
    -> CellLayerShader
  {
    history.ticks.withLock { $0.append(context.elapsed) }
    let old = state.previous.withLock {
      let previous = $0
      $0 = source
      return previous ?? source
    }
    return .region { _, buffer, _ in
      if case .glyph(let original) = old.sample(at: .zero) {
        buffer.set(original, at: .init(x: 0, y: 1))
      }
    }
  }
}

@MainActor
@Suite("Prepared image placement and raster retries", .serialized)
struct PreparedImageRepaintTests {
  @Test(
    "Only a prepared shader’s actual backdrop reads split lower native placements",
    arguments: PreparedImageRead.allCases)
  fileprivate func imageFragments(_ read: PreparedImageRead) throws {
    let red = try makePNGBytes(
      width: 2, height: 2,
      pixels: Array(repeating: rgbaPixel(red: 230, green: 20, blue: 80), count: 4))
    let blue = try makePNGBytes(
      width: 2, height: 2,
      pixels: Array(repeating: rgbaPixel(red: 25, green: 40, blue: 228), count: 4))
    func scene(prepared: Bool) -> some View {
      ZStack(alignment: .topLeading) {
        Text("0123456")
        Image(data: red).resizable().frame(width: 5, height: 1)
        Image(data: blue).resizable().frame(width: 2, height: 1).offset(x: 5)
        Text("T").offset(x: 1)
        let subject = Spacer(minLength: 0).frame(width: 7, height: 1)
        if prepared {
          subject.layerEffect(PreparedImageKernel(read: read), maxSampleOffset: .zero)
        } else {
          subject.layerEffect(read.shader, maxSampleOffset: .zero)
        }
        Text("H").offset(x: 3)
      }
    }
    let size = ProposedSize(width: 7, height: 1)
    let baseline = DefaultRenderer().render(scene(prepared: false), proposal: size).rasterSurface
    let result = DefaultRenderer().render(scene(prepared: true), proposal: size).rasterSurface
    func stripe(_ x: Int, _ width: Int) -> CellRect {
      .init(origin: .init(x: x, y: 0), size: .init(width: width, height: 1))
    }
    let expected =
      read == .source ? [stripe(0, 5), stripe(5, 2)] : [stripe(0, 1), stripe(3, 2), stripe(5, 2)]
    #expect(baseline.imageAttachments.map(\.visibleBounds) == expected)
    #expect(result.imageAttachments.map(\.visibleBounds) == expected)
    #expect(result.cells == baseline.cells)
    #expect(result.cells[0].map(\.character) == Array(read == .source ? "0TSH456" : "0t▀H456"))
    if read == .composite {
      #expect(result.cells[0][2].style?.foregroundColor?.hexString(format: .rrggbb) == "#E61450")
    }
  }

  @Test(
    "A reference-backed run replays a prior capture after later instants and matches a full repaint on partial damage"
  )
  func retainedUniformAndPartialDamage() {
    let renderer = DefaultRenderer()
    let history = PreparedHistory()
    let bounds = CellSize(width: 8, height: 3)
    let zero = MonotonicInstant(offset: .seconds(100))
    let scope = ResolveContext(identity: testIdentity("retainedInput"))
    func scene(_ glyph: String, _ version: Int) -> some View {
      VStack(alignment: .leading, spacing: 0) {
        Text(glyph).foregroundStyle(version == 1 ? Color.red : Color.blue).bold()
        Text(".")
        Text("static")
      }.frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .layerEffect(
          PreviousInput(history: history, version: version), maxSampleOffset: .layerBounds)
    }
    var raster = Rasterizer(incrementalVerificationPolicy: .verifySoundDamage)
    var prior: RasterSurface?
    var retained: (DrawNode, CellPreparationFrame, RasterSurface)?
    for (i, glyph) in ["A", "B", "C"].enumerated() {
      let instant = zero.advanced(by: .milliseconds(i * 21))
      let snapshot = renderer.render(
        scene(glyph, i), context: scope, proposal: .init(width: 8, height: 3), frameInstant: instant
      )
      let frame = CellPreparationFrame(at: instant)
      raster.cellPreparationFrame = frame
      let full = raster.rasterize(snapshot.drawTree, minimumSize: bounds)
      let partial = raster.rasterizeCollectingVisibleIdentities(
        snapshot.drawTree, minimumSize: bounds, previousSurface: prior,
        damage: prior == nil ? nil : .init(textRows: [.init(row: 0, columnRanges: [0..<1])]))
      #expect(full == snapshot.rasterSurface)
      #expect(full.cells[0][0].character == Character(glyph))
      #expect(full.cells[1][0].character == ["A", "A", "B"][i])
      #expect(full.cells[1][0].style?.foregroundColor == (i == 2 ? .red : .blue))
      #expect(partial.surface == full)
      #expect(partial.incrementalMismatch == nil)
      if prior != nil { #expect(partial.path == .incremental) }
      if i == 1 { retained = (snapshot.drawTree, frame, full) }
      prior = full
    }
    if let (oldTree, oldFrame, oldResult) = retained {
      raster.cellPreparationFrame = oldFrame
      let retry = raster.rasterize(oldTree, minimumSize: bounds)
      #expect(retry == oldResult)
      #expect(retry.cells[1][0].character == "A")
    }
    #expect(history.ticks.withLock { $0 } == [.zero, .milliseconds(21), .milliseconds(42)])
  }
}
