import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Testing
import TransitionConsumer

/// Two demonstrations on the framework's run loop (STUI-1571).
///
/// `DemonstrationTransitionTests` draws each frame with a one-shot renderer,
/// at an instant the test names. These tests build the host on a real run
/// loop with `RunLoopTestHarness`, the run-loop harness of the ratified
/// Testing SPI, and move its virtual clock. The state changes as it changes
/// in an app, the run loop's scheduler arms the frames of the transition,
/// and the test renders them deadline by deadline. Nothing waits.
///
/// The animation lasts 1320 ms, which is forty frames of the run loop's
/// 33 ms cadence, so each quarter of it ends on a frame: the frame at 330 ms
/// is the demonstration at a progress of 0.25.
@MainActor
@Suite("Demonstration transitions on the run loop")
struct DemonstrationRunLoopTests {
  private static let linear = Animation.linear(duration: .milliseconds(1320))
  /// A quarter of the animation: ten frames of the 33 ms cadence.
  private static let quarter = Duration.milliseconds(330)

  @Test(
    "an insertion plays on the run loop, a quarter every ten frames",
    arguments: [Demonstration.iris, .rise])
  func insertion(demonstration: Demonstration) throws {
    let (harness, switchboard) = try stage(demonstration)
    defer { harness.shutdown() }
    expect(harness, shows: demonstration, at: 0, "before")
    #expect(harness.nextWake == nil)

    // The state changes outside the run loop, through the binding, and
    // `render()` draws the frame of the change: the origin of the
    // transition, not the panel.
    try show(true, in: harness, switchboard)
    expect(harness, shows: demonstration, at: 0, "0 ms")
    for quarter in 1...4 {
      // Ten deadlines, each rendered at its own instant. The clock then
      // stands on the last of them.
      #expect(try harness.advance(by: Self.quarter) == 10, "quarter \(quarter)")
      expect(harness, shows: demonstration, at: Double(quarter) / 4, "\(330 * quarter) ms")
    }
    #expect(harness.now == MonotonicInstant(offset: .milliseconds(1320)))

    // The panel is whole and stays whole. The transition has ended, so the
    // run loop has no frame armed and renders none.
    #expect(harness.nextWake == nil)
    #expect(try harness.advance(by: Self.quarter) == 0)
    expect(harness, shows: demonstration, at: 1, "at rest")
  }

  @Test(
    "a removal plays on the run loop, from the whole panel to nothing",
    arguments: [Demonstration.iris, .rise])
  func removal(demonstration: Demonstration) throws {
    let (harness, switchboard) = try stage(demonstration)
    defer { harness.shutdown() }
    // The panel arrives and comes to rest. 1650 ms is fifty frames of the
    // cadence, so the clock stands on a frame of it.
    try show(true, in: harness, switchboard)
    try harness.advance(by: .milliseconds(1650))
    expect(harness, shows: demonstration, at: 1, "at rest")

    // The first frame without the panel still draws all of it: the removal
    // starts from what is on screen.
    try show(false, in: harness, switchboard)
    expect(harness, shows: demonstration, at: 1, "0 ms")
    for quarter in 1...4 {
      #expect(try harness.advance(by: Self.quarter) == 10, "quarter \(quarter)")
      expect(harness, shows: demonstration, at: 1 - Double(quarter) / 4, "\(330 * quarter) ms")
    }

    // Nothing of the panel is left, and the run loop comes to rest.
    try harness.advance(by: .seconds(1))
    expect(harness, shows: demonstration, at: 0, "after")
    #expect(harness.nextWake == nil)
  }

  @Test(
    "a removal half way through an insertion starts from the frame on screen",
    arguments: [Demonstration.iris, .rise])
  func interruption(demonstration: Demonstration) throws {
    let (harness, switchboard) = try stage(demonstration)
    defer { harness.shutdown() }
    try show(true, in: harness, switchboard)
    try harness.advance(by: .milliseconds(660))
    expect(harness, shows: demonstration, at: 0.5, "insertion, 660 ms")

    // Half way. The frame of the removal shows what was on screen: not the
    // whole panel, and not nothing.
    try show(false, in: harness, switchboard)
    expect(harness, shows: demonstration, at: 0.5, "removal, 0 ms")

    // The removal runs its own 1320 ms from there, toward nothing. After
    // half of it the demonstration is half way from 0.5 to 0: at 0.25.
    var counts = [visibleCells(harness)]
    for quarter in 1...4 {
      #expect(try harness.advance(by: Self.quarter) == 10, "quarter \(quarter)")
      #expect(harness.lines.first == "HEADER", "quarter \(quarter)")
      counts.append(visibleCells(harness))
      if quarter == 2 {
        expect(harness, shows: demonstration, at: 0.25, "removal, 660 ms")
      }
    }
    expect(harness, shows: demonstration, at: 0, "removal, 1320 ms")
    // No frame on the way shows more of the panel than the frame before it.
    #expect(counts == counts.sorted(by: >), "\(counts)")
    #expect(counts.last == 0, "\(counts)")

    try harness.advance(by: .seconds(1))
    expect(harness, shows: demonstration, at: 0, "after")
    #expect(harness.nextWake == nil)
  }

  @Test("a key press starts a transition and a second one interrupts it")
  func keyPressesDriveTheTransition() throws {
    let (harness, _) = try stage(.rise)
    defer { harness.shutdown() }
    let toggle = KeyPress(.character("t"))

    // The header has the focus, and its key handler changes the state. The
    // key goes through the run loop's input dispatch and does not move the
    // clock.
    try harness.press(toggle)
    #expect(harness.now == .zero)
    expect(harness, shows: .rise, at: 0, "insertion, 0 ms")
    try harness.advance(by: .milliseconds(660))
    expect(harness, shows: .rise, at: 0.5, "insertion, 660 ms")

    try harness.press(toggle)
    #expect(harness.now == MonotonicInstant(offset: .milliseconds(660)))
    expect(harness, shows: .rise, at: 0.5, "removal, 0 ms")
    try harness.advance(by: .milliseconds(660))
    expect(harness, shows: .rise, at: 0.25, "removal, 660 ms")
    try harness.advance(by: .milliseconds(660))
    expect(harness, shows: .rise, at: 0, "removal, 1320 ms")
  }

  // MARK: - Helpers

  /// The host under `demonstration`, on a run loop whose surface is the
  /// host's size. The transition carries the animation, so a plain change
  /// of the state plays it.
  private func stage(
    _ demonstration: Demonstration
  ) throws -> (RunLoopTestHarness<LiveTransitionHost>, Switchboard) {
    let switchboard = Switchboard()
    let transition = demonstration.transition.animation(Self.linear)
    let harness = try RunLoopTestHarness(size: TransitionHost.size) {
      LiveTransitionHost(transition: transition, switchboard: switchboard)
    }
    return (harness, switchboard)
  }

  /// Writes the host's state through its binding, outside the run loop, and
  /// renders the frame of the change.
  private func show(
    _ isShown: Bool, in harness: RunLoopTestHarness<LiveTransitionHost>, _ switchboard: Switchboard
  ) throws {
    let binding = try #require(switchboard.isShown)
    binding.wrappedValue = isShown
    try harness.render()
  }

  /// What the frame the harness presented last shows of the panel.
  private func panelReading(
    _ harness: RunLoopTestHarness<LiveTransitionHost>, rowsDown: Int
  ) -> PanelReading {
    RenderSnapshot(rasterSurface: harness.frame, semanticSnapshot: SemanticSnapshot())
      .panel(origin: TransitionHost.panelOrigin, rowsDown: rowsDown)
  }

  /// How many cells below the header show a glyph.
  private func visibleCells(_ harness: RunLoopTestHarness<LiveTransitionHost>) -> Int {
    var count = 0
    for line in harness.frame.cells.dropFirst(TransitionHost.panelOrigin.y) {
      count += line.count(where: { $0.character != " " })
    }
    return count
  }

  /// Checks the frame the harness presented last against the demonstration
  /// at `progress`.
  private func expect(
    _ harness: RunLoopTestHarness<LiveTransitionHost>, shows demonstration: Demonstration,
    at progress: Double, _ label: String
  ) {
    let reading = panelReading(harness, rowsDown: demonstration.rowsDown(at: progress))
    let expected = demonstration.cells(at: progress)
    #expect(harness.lines.first == "HEADER", "\(label)")
    #expect(reading.problems.isEmpty, "\(label): \(reading.problems.prefix(4))")
    #expect(
      reading.visible.isSuperset(of: expected.must),
      "\(label): missing \(expected.must.subtracting(reading.visible).sorted().prefix(8))")
    #expect(
      reading.visible.isSubset(of: expected.may),
      "\(label): extra \(reading.visible.subtracting(expected.may).sorted().prefix(8))")
  }
}

/// Where a test reaches the host's state from outside the run loop.
@MainActor
private final class Switchboard {
  var isShown: Binding<Bool>?
}

/// `TransitionHost` with state of its own: a header, and below it the panel
/// under a transition while `isShown`. The header takes the focus, and its
/// `t` key flips the state. The host also hands its binding to the test.
private struct LiveTransitionHost: View {
  @State private var isShown = false
  let transition: AnyTransition
  let switchboard: Switchboard

  var body: some View {
    let _ = connect()
    VStack(alignment: .leading, spacing: 0) {
      Text("HEADER")
        .focusable()
        .onKeyPress(.character("t")) { _ in
          isShown.toggle()
          return .handled
        }
      if isShown {
        PanelView().transition(transition)
      }
    }
    .frame(
      width: TransitionHost.size.width, height: TransitionHost.size.height,
      alignment: .topLeading)
  }

  private func connect() {
    switchboard.isShown = $isShown
  }
}
