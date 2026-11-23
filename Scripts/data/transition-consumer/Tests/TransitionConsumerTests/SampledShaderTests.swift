import SwiftTUI
import Synchronization
import Testing
import TransitionConsumer

@MainActor
struct SampledShaderTests {
  @Test func preparationAndPlacementValues() {
    let previous = CellRect(origin: .init(x: 2, y: 0), size: .init(width: 6, height: 1))
    let current = CellRect(origin: .init(x: 9, y: 0), size: .init(width: 8, height: 1))
    let geometry = CellEffectContext(
      sourceBounds: current, outputBounds: current, viewport: current, originInRoot: .zero,
      appearance: .fallback)
    let preparation = CellPreparationContext(
      geometry: geometry, elapsed: .milliseconds(85), delta: .milliseconds(35),
      previousSourceBounds: previous)
    #expect(preparation.geometry == geometry)
    #expect(preparation.elapsed == .milliseconds(85))
    #expect(preparation.delta == .milliseconds(35))
    #expect(preparation.previousSourceBounds == previous)
    #expect(
      preparation
        != CellPreparationContext(
          geometry: geometry, elapsed: .milliseconds(85), delta: .milliseconds(35),
          previousSourceBounds: nil))

    let placement = CellPlacementContext(
      previousFrame: previous, currentFrame: current, progress: 1.25)
    #expect(placement.previousFrame == previous)
    #expect(placement.currentFrame == current)
    #expect(placement.progress == 1.25)
    #expect(
      placement
        == CellPlacementContext(previousFrame: previous, currentFrame: current, progress: 1.25))
  }

  @Test func retryAndSkippedInterval() {
    let renderer = DefaultRenderer()
    let journal = SampleJournal()
    let counter = CountPreparations(journal: journal)
    func render(at milliseconds: Int) -> Character {
      renderer.render(
        Text("x").layerEffect(counter, maxSampleOffset: .zero),
        proposal: .init(width: 1, height: 1),
        frameInstant: MonotonicInstant(offset: .milliseconds(milliseconds))
      ).rasterSurface.cells[0][0].character
    }
    #expect(render(at: 0) == "1")
    #expect(render(at: 10) == "2")
    #expect(render(at: 10) == "2")
    #expect(render(at: 45) == "3")
    let samples = journal.entries.withLock { $0 }
    #expect(samples.map(\.elapsed) == [.zero, .milliseconds(10), .milliseconds(45)])
    #expect(samples.map(\.delta) == [.zero, .milliseconds(10), .milliseconds(35)])
    let bounds = CellRect(origin: .zero, size: .init(width: 1, height: 1))
    #expect(samples.map(\.previousSourceBounds) == [nil, bounds, bounds])
    #expect(samples.allSatisfy { $0.geometry.sourceBounds == bounds })
  }

  @Test func retainsAnOffscreenColumnUntilBypass() {
    let renderer = DefaultRenderer()
    func row(_ input: String, _ time: Int, enabled: Bool) -> String {
      let view = Text(input).frame(width: 6, height: 1, alignment: .leading)
        .layerEffect(FirstSampleEcho(), maxSampleOffset: .layerBounds, isEnabled: enabled)
        .frame(width: 2, height: 1, alignment: .leading)
      let surface = renderer.render(
        view, proposal: .init(width: 2, height: 1),
        frameInstant: MonotonicInstant(offset: .milliseconds(time))
      ).rasterSurface
      return String(surface.cells[0].prefix(2).map(\.character))
    }
    #expect(FirstSampleEcho().makeState() == nil)
    #expect(row("A....1", 0, enabled: true) == "A1")
    #expect(row("B....2", 10, enabled: true) == "B1")
    #expect(row("B....2", 10, enabled: true) == "B1")
    #expect(row("C....3", 45, enabled: false) == "C.")
    #expect(row("D....4", 80, enabled: true) == "D4")
  }

  @Test(arguments: [true, false])
  func firstPlacementDrawsAtRestAndStrokeLeavesItsTitleAlone(inline: Bool) {
    func rows(_ enabled: Bool) -> [String] {
      let view = Text("inner").flyBetweenColumns().frame(width: 7, height: 3)
        .starredBorder(isEnabled: enabled, inline: inline).overlay(alignment: .top) { Text("TOP") }
      return DefaultRenderer().render(view, proposal: .init(width: 7, height: 3))
        .rasterSurface.cells.map { String($0.map(\.character)) }
    }
    #expect(rows(true) == ["**TOP**", "*inner*", "*******"])
    #expect(rows(false) == ["┌─TOP─┐", "│inner│", "└─────┘"])
  }
}

private final class SampleJournal: Sendable {
  let entries = Mutex<[CellPreparationContext]>([])
}

private struct CountPreparations: CellPreparedLayerKernel {
  var journal: SampleJournal

  static func == (lhs: Self, rhs: Self) -> Bool { lhs.journal === rhs.journal }
  func makeState() -> Int { 0 }
  func prepare(
    _ state: inout Int, source: CellLayer, context: CellPreparationContext
  ) -> CellLayerShader {
    state += 1
    journal.entries.withLock { $0.append(context) }
    let digit = String(state).first!
    return CellLayerShader { _, _, _ in .glyph(CellGlyph(digit)) }
  }
}
