import SwiftTUI
import Testing
import TransitionConsumer

/// The six demonstrations through `View.transition(_:)` (STUI-1546).
///
/// A real conditional inserts and removes the panel. One renderer draws
/// every frame of a test, each at an instant the test names, so a frame at
/// 400 ms of an 800 ms linear animation is the demonstration at a progress
/// of 0.5, whatever the machine is doing.
@MainActor
@Suite("Demonstration transitions through View.transition")
struct DemonstrationTransitionTests {
  private static let linear = Animation.linear(duration: .milliseconds(800))
  private static let spring = Animation.spring(duration: .milliseconds(600), bounce: 0.5)

  /// Checks one frame against the demonstration at `progress`.
  private func expect(
    _ snapshot: RenderSnapshot, shows demonstration: Demonstration, at progress: Double,
    _ label: String
  ) {
    let reading = snapshot.panel(
      origin: TransitionHost.panelOrigin, rowsDown: demonstration.rowsDown(at: progress))
    let expected = demonstration.cells(at: progress)
    #expect(snapshot.rasterSurface.lines.first == "HEADER", "\(label)")
    #expect(reading.problems.isEmpty, "\(label): \(reading.problems.prefix(4))")
    #expect(
      reading.visible.isSuperset(of: expected.must),
      "\(label): missing \(expected.must.subtracting(reading.visible).sorted().prefix(8))")
    #expect(
      reading.visible.isSubset(of: expected.may),
      "\(label): extra \(reading.visible.subtracting(expected.may).sorted().prefix(8))")
    #expect(snapshot.issues.isEmpty, "\(label): \(snapshot.issues)")
  }

  @Test(
    "an insertion starts from nothing, passes the middle and ends on the whole panel",
    arguments: Demonstration.allCases)
  func insertion(demonstration: Demonstration) {
    let stage = Stage(demonstration, animation: Self.linear)
    expect(stage.frame(shown: false, at: -33), shows: demonstration, at: 0, "at rest")
    // The first frame that has the panel presents the origin of the
    // transition, not the panel.
    expect(stage.frame(shown: true, at: 0), shows: demonstration, at: 0, "0 ms")
    expect(stage.frame(shown: true, at: 200), shows: demonstration, at: 0.25, "200 ms")
    expect(stage.frame(shown: true, at: 400), shows: demonstration, at: 0.5, "400 ms")
    expect(stage.frame(shown: true, at: 600), shows: demonstration, at: 0.75, "600 ms")
    expect(stage.frame(shown: true, at: 800), shows: demonstration, at: 1, "800 ms")
    expect(stage.frame(shown: true, at: 833), shows: demonstration, at: 1, "833 ms")
  }

  @Test(
    "a removal starts from the whole panel, passes the middle and ends on nothing",
    arguments: Demonstration.allCases)
  func removal(demonstration: Demonstration) {
    let stage = Stage(demonstration, animation: Self.linear)
    // The panel arrives and comes to rest.
    _ = stage.frame(shown: false, at: -33)
    _ = stage.frame(shown: true, at: 0)
    expect(stage.frame(shown: true, at: 900), shows: demonstration, at: 1, "at rest")
    // The first frame without the panel still draws all of it: the removal
    // starts from what is on screen.
    expect(stage.frame(shown: false, at: 2000), shows: demonstration, at: 1, "0 ms")
    expect(stage.frame(shown: false, at: 2200), shows: demonstration, at: 0.75, "200 ms")
    expect(stage.frame(shown: false, at: 2400), shows: demonstration, at: 0.5, "400 ms")
    expect(stage.frame(shown: false, at: 2600), shows: demonstration, at: 0.25, "600 ms")
    expect(stage.frame(shown: false, at: 2800), shows: demonstration, at: 0, "800 ms")
    expect(stage.frame(shown: false, at: 2833), shows: demonstration, at: 0, "833 ms")
  }

  @Test("the wipe fades the ink of the departing panel too")
  func removalFadesTheInk() {
    // On removal the panel is the view as it was last drawn. The foreground
    // style the transition writes for it still reaches it.
    let stage = Stage(.wipe, animation: Self.linear)
    _ = stage.frame(shown: false, at: -33)
    _ = stage.frame(shown: true, at: 0)
    _ = stage.frame(shown: true, at: 900)
    _ = stage.frame(shown: false, at: 2000)
    let reading = stage.frame(shown: false, at: 2400).panel(origin: TransitionHost.panelOrigin)
    #expect(reading.visible.count == 240)
    for cell in reading.visible.sorted() {
      // As at a fixed progress of 0.5: the front at column 24, a fade of 8.
      let expected = min(1, max(0, (24 - (Double(cell.column) + 0.5)) / 8))
      let alpha = reading.inks[cell]?.alpha ?? -1
      #expect(abs(alpha - expected) < 1e-9, "\(cell): \(alpha), expected \(expected)")
    }
  }

  @Test(
    "an insertion under a spring with bounce stays inside the panel",
    arguments: Demonstration.allCases)
  func springInsertion(demonstration: Demonstration) {
    let stage = Stage(demonstration, animation: Self.spring)
    _ = stage.frame(shown: false, at: -33)
    var counts: [Int] = []
    // 41 frames, 33 ms apart: the spring is at rest after about thirty.
    for tick in 0...40 {
      let snapshot = stage.frame(shown: true, at: tick * 33)
      // Whatever the spring's value is, the frame draws only glyphs of the
      // panel, each in a cell of the panel. The rise moves the panel by
      // whole rows, so its glyphs are read at each distance it can be at.
      let readings = (0...demonstration.rowsDown(at: 0)).map {
        snapshot.panel(origin: TransitionHost.panelOrigin, rowsDown: $0)
      }
      let reading = readings.first { $0.problems.isEmpty }
      #expect(reading != nil, "\(tick * 33) ms: \(readings[0].problems.prefix(4))")
      #expect(snapshot.rasterSurface.lines.first == "HEADER", "\(tick * 33) ms")
      #expect(snapshot.issues.isEmpty, "\(tick * 33) ms: \(snapshot.issues)")
      counts.append(reading?.visible.count ?? -1)
    }
    #expect(counts.first == 0, "\(counts)")
    #expect(counts.last == 400, "\(counts)")
  }

  @Test("the spring passes its target and comes back, and the reveal follows it")
  func springBouncesTheReveal() {
    // The typewriter draws a number of cells that follows the progress. A
    // spring with bounce takes the progress past 1, where the count stays
    // at the whole panel, then below 1 again, where cells go, then back.
    let stage = Stage(.typewriter, animation: Self.spring)
    _ = stage.frame(shown: false, at: -33)
    let counts = (0...40).map { tick in
      stage.frame(shown: true, at: tick * 33).panel(origin: TransitionHost.panelOrigin)
        .visible.count
    }
    let firstWhole = counts.firstIndex(of: 400)
    #expect(firstWhole != nil, "\(counts)")
    if let firstWhole {
      let after = counts[firstWhole...]
      #expect(after.contains { $0 < 400 }, "the count never fell back: \(counts)")
      #expect(after.allSatisfy { $0 > 360 }, "\(counts)")
    }
    #expect(counts.last == 400, "\(counts)")
  }
}
