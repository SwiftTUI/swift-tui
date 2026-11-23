import Synchronization
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

private struct PreparedIdentity: CellPreparedLayerKernel {
  func makeState() -> Int { 0 }
  func prepare(_ state: inout Int, source: CellLayer, context: CellPreparationContext)
    -> CellLayerShader
  {
    CellLayerShader { point, layer, _ in layer.sample(at: point) }
  }
}

@MainActor
@Suite("Prepared capture geometry and lifetime")
struct PreparedCaptureIsolationTests {}

private struct PreparedWindow: CellPreparedLayerKernel {
  func makeState() -> Int { 0 }
  func prepare(_ state: inout Int, source: CellLayer, context: CellPreparationContext)
    -> CellLayerShader
  {
    let bounds = context.geometry.outputBounds
    return CellLayerShader { point, _, _ in
      bounds.contains(point) ? .glyph(CellGlyph("X")) : .empty
    }
  }
}
extension PreparedCaptureIsolationTests {
  @Test("A prepared kernel sees the whole masked output geometry across disjoint paint runs")
  func clippedPreparedWindow() {
    let subject = Text("xxxxxx\nxxxxxx\nxxxxxx\nxxxxxx\nxxxxxx\nxxxxxx").fixedSize()
    let ordinary = subject.layerEffect(maxSampleOffset: .zero) { point, _, geometry in
      geometry.outputBounds.contains(point) ? .glyph(CellGlyph("X")) : .empty
    }.clipShape(Circle())
    let prepared = subject.layerEffect(PreparedWindow(), maxSampleOffset: .zero).clipShape(Circle())
    let expected = DefaultRenderer().render(ordinary, proposal: .init(width: 6, height: 6))
      .rasterSurface.lines
    let actual = DefaultRenderer().render(prepared, proposal: .init(width: 6, height: 6))
      .rasterSurface.lines
    #expect(expected.contains(where: { $0.contains("X") }))
    #expect(actual == expected)
  }

  @Test("An enclosing viewport gather can read an offscreen prepared source")
  func offscreenPreparedIdentity() {
    func run(_ enable: Bool) -> [String] {
      let scene = ZStack(alignment: .topLeading) {
        Text(".....")
        Text("A").fixedSize()
          .layerEffect(PreparedIdentity(), maxSampleOffset: .zero, isEnabled: enable)
          .layerEffect(
            CellLayerShader { p, layer, _ in
              p.x == -8 ? layer.sample(at: .zero) : .empty
            }.drawing(in: .viewport), maxSampleOffset: .layerBounds
          )
          .offset(x: 8)
      }.frame(width: 5, height: 1, alignment: .topLeading)
      return DefaultRenderer().render(scene, proposal: .init(width: 5, height: 1)).rasterSurface
        .lines
    }
    #expect(run(false) == ["A...."])
    #expect(run(true) == run(false))
  }
}
private final class FrameMarker: Sendable {}
private struct SourceRetainingKernel: CellPreparedLayerKernel {
  struct WeakMarker: Sendable { weak var value: FrameMarker? }
  final class Markers: Sendable { let weakMarker = Mutex<WeakMarker?>(nil) }
  let markers: Markers
  static func == (lhs: Self, rhs: Self) -> Bool { lhs.markers === rhs.markers }
  func makeState() -> Int { 0 }
  func prepare(_ state: inout Int, source: CellLayer, context: CellPreparationContext)
    -> CellLayerShader
  {
    let marker = FrameMarker()
    let weakMarker = WeakMarker(value: marker)
    markers.weakMarker.withLock { $0 = weakMarker }
    return CellLayerShader { p, _, _ in
      withExtendedLifetime(marker) { source.sample(at: p) }
    }
  }
}
extension PreparedCaptureIsolationTests {
  @Test("Retaining the source does not keep the prepared frame alive after release")
  func releasesRetainedTileSource() {
    func sample(width: Int) -> SourceRetainingKernel.Markers {
      let markers = SourceRetainingKernel.Markers()
      let view = Text("X").frame(width: width, height: 1, alignment: .leading)
        .layerEffect(SourceRetainingKernel(markers: markers), maxSampleOffset: .layerBounds)
        .frame(width: 1, height: 1, alignment: .leading).clipped()
      _ = DefaultRenderer().render(view, proposal: .init(width: 1, height: 1))
      return markers
    }
    for width in [8, 65_540] {
      let markers = sample(width: width)
      #expect(markers.weakMarker.withLock { $0 != nil }, "prepared at width \(width)")
      #expect(markers.weakMarker.withLock { $0?.value == nil }, "released at width \(width)")
    }
  }
}
private struct InnerValue: CellPreparedLayerKernel {
  let value: Character
  func makeState() -> Int { 0 }
  func prepare(_ state: inout Int, source: CellLayer, context: CellPreparationContext)
    -> CellLayerShader
  {
    let selected = value
    return CellLayerShader { _, _, _ in .glyph(CellGlyph(selected)) }
  }
}
private struct SamplePast: CellPreparedLayerKernel {
  let value: Character
  func makeState() -> CellLayer? { nil }
  func prepare(_ state: inout CellLayer?, source: CellLayer, context: CellPreparationContext)
    -> CellLayerShader
  {
    let past = state
    state = source
    return CellLayerShader { p, _, _ in
      guard let past else { return .empty }
      if p.x == 0 { return source.sample(at: .zero) }
      return past.sample(at: .zero)
    }
  }
}
extension PreparedCaptureIsolationTests {
  @Test("Lazy capture of a nested prepared shader retains the earlier sample")
  func unvisitedSourceIsASnapshot() {
    func verify(_ width: Int) -> [String] {
      let renderer = DefaultRenderer()
      let id = testIdentity("oldTiledLayer")
      func sample(_ ch: Character, _ ms: Int) -> [String] {
        let subject = Text("X").frame(width: width, height: 1, alignment: .leading)
          .layerEffect(InnerValue(value: ch), maxSampleOffset: .zero)
          .layerEffect(SamplePast(value: ch), maxSampleOffset: .layerBounds)
          .frame(width: 2, height: 1, alignment: .leading).clipped()
        return renderer.render(
          subject, context: .init(identity: id), proposal: .init(width: 2, height: 1),
          frameInstant: .init(offset: .milliseconds(ms))
        ).rasterSurface.lines
      }
      _ = sample("A", 100)
      return sample("B", 200)
    }
    #expect(verify(8) == ["BA"])
    #expect(verify(65_540) == ["BA"])
  }
}
private struct ProbeReach: CellPreparedLayerKernel {
  func makeState() -> Int { 0 }
  func prepare(_ state: inout Int, source: CellLayer, context: CellPreparationContext)
    -> CellLayerShader
  {
    let far = CellPoint(x: 6, y: 0)
    let readable = source.readableBounds.contains(far)
    return CellLayerShader { _, _, _ in .glyph(CellGlyph(readable ? "Y" : "N")) }
  }
}
extension PreparedCaptureIsolationTests {
  @Test("The preparation source honors bounded and full-layer reads across a clip")
  func preparedReadReach() {
    func frame(_ offset: CellSampleOffset) -> [String] {
      let subject = Text("01234567").fixedSize().layerEffect(ProbeReach(), maxSampleOffset: offset)
        .frame(width: 2, height: 1, alignment: .leading).clipped()
      return DefaultRenderer().render(subject, proposal: .init(width: 2, height: 1)).rasterSurface
        .lines
    }
    #expect(frame(.zero) == ["NN"])
    #expect(frame(.layerBounds) == ["YY"])
  }
}
