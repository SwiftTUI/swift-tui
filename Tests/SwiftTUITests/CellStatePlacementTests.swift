import Synchronization
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

private final class SampleLog: Sendable {
  struct Tick: Equatable, Sendable {
    var run: Int
    var count: Int
    var context: CellPreparationContext
  }
  let ticks = Mutex<[Tick]>([])
  let counter = Mutex(0)
  let travel = Mutex<[CellPlacementContext]>([])
}

private struct CountingSample: CellPreparedLayerKernel {
  var log: SampleLog
  var value: Int
  final class State: Sendable {
    let id: Int
    let advances = Mutex(0)
    init(_ id: Int) { self.id = id }
  }
  static func == (lhs: Self, rhs: Self) -> Bool { lhs.log === rhs.log && lhs.value == rhs.value }
  func makeState() -> State {
    State(
      log.counter.withLock {
        $0 += 1
        return $0
      })
  }
  func prepare(_ state: inout State, source: CellLayer, context: CellPreparationContext)
    -> CellLayerShader
  {
    let number = state.advances.withLock {
      $0 += 1
      return $0
    }
    let id = state.id
    log.ticks.withLock { $0.append(.init(run: id, count: number, context: context)) }
    // Retain the immutable capture, including during incremental verification.
    return CellLayerShader { point, _, _ in
      guard var glyph = source.glyph(occupying: point) else { return .empty }
      if glyph.character == "x" { glyph.character = Character(String(number % 10)) }
      return .glyph(glyph)
    }
  }
}

private struct PreparedPanel: View {
  let log: SampleLog
  let value: Int
  let width: Int
  let enabled: Bool
  var body: some View {
    Text("x").frame(width: width, height: 1, alignment: .leading)
      .layerEffect(
        CountingSample(log: log, value: value), maxSampleOffset: .layerBounds,
        isEnabled: enabled)
  }
}

private struct TravelingPanel: View {
  let indent: Int
  let text: String
  let log: SampleLog
  var body: some View {
    ZStack(alignment: .topLeading) {
      HStack(spacing: 0) {
        Text(String(repeating: ".", count: indent))
        Text(text).placementEffect(maxSampleOffset: .layerBounds) { sample in
          log.travel.withLock { $0.append(sample) }
          let x = Int(
            (Double(sample.previousFrame.origin.x - sample.currentFrame.origin.x)
              * (1 - sample.progress)).rounded())
          return CellLayerShader { p, source, _ in
            source.sample(at: CellPoint(x: p.x - x, y: p.y))
          }.drawing(in: .viewport)
        }
      }
      Text("|").offset(x: 5)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}

@MainActor
@Suite("Mounted cell preparation, placement and border drawing", .serialized)
struct CellStatePlacementTests {
  private let start = MonotonicInstant(offset: .seconds(100))

  @Test(
    "repeated instants share prepared reference state, skipped samples include the full delta, and disabling ends a run"
  )
  func preparedSamples() throws {
    let log = SampleLog()
    let renderer = DefaultRenderer()
    let scope = ResolveContext(identity: testIdentity("preparedTicks"))
    func sample(_ ms: Int, _ value: Int, width: Int = 4, enabled: Bool = true) -> Character {
      renderer.render(
        PreparedPanel(log: log, value: value, width: width, enabled: enabled),
        context: scope, proposal: .init(width: 12, height: 1),
        frameInstant: start.advanced(by: .milliseconds(ms))
      ).rasterSurface.cells[0][0].character
    }
    #expect(sample(0, 0) == "1")
    #expect(sample(10, 1) == "2")
    #expect(sample(10, 2) == "2")
    #expect(sample(45, 3, width: 7) == "3")
    #expect(sample(50, 4, enabled: false) == "x")
    #expect(sample(90, 5) == "1")
    let ticks = log.ticks.withLock { $0 }
    #expect(ticks.map(\.run) == [1, 1, 1, 2])
    #expect(ticks.map(\.context.elapsed) == [.zero, .milliseconds(10), .milliseconds(45), .zero])
    #expect(ticks.map(\.context.delta) == [.zero, .milliseconds(10), .milliseconds(35), .zero])
    #expect(ticks.map { $0.context.previousSourceBounds?.size.width } == [nil, 4, 4, nil])
    #expect(ticks.map { $0.context.geometry.sourceBounds.size.width } == [4, 4, 7, 4])
  }

  @Test(
    "flight uses new content, preserves higher paint, restarts from last target, and snaps on viewport resize"
  )
  func placement() throws {
    let log = SampleLog()
    let renderer = DefaultRenderer()
    let id = testIdentity("realPlacement")
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(Animation.linear(duration: .seconds(1)).animationBox)
    func sample(_ ms: Int, indent: Int, text: String, animate: Bool = false, width: Int = 15)
      -> String
    {
      renderer.render(
        TravelingPanel(indent: indent, text: text, log: log),
        context: .init(identity: id, transaction: animate ? transaction : .init()),
        proposal: .init(width: width, height: 1),
        frameInstant: start.advanced(by: .milliseconds(ms))
      ).rasterSurface.lines[0]
    }
    withAnimationSinks(renderer.internalAnimationController) {
      #expect(sample(0, indent: 1, text: "A").hasPrefix(".A"))
      #expect(log.travel.withLock { $0.isEmpty })
      let begin = sample(10, indent: 9, text: "BC", animate: true)
      #expect(begin.hasPrefix(".BC..|"), "\(begin)")
      let mid = sample(510, indent: 9, text: "BC")
      #expect(mid.hasPrefix(".....|C"), "\(mid)")
      let back = sample(510, indent: 2, text: "D", animate: true)
      #expect(Array(back)[9] == "D", "\(back)")
      let resized = sample(550, indent: 2, text: "D", width: 13)
      #expect(resized.hasPrefix("..D  |"), "\(resized)")
      #expect(renderer.internalAnimationController.activeAnimationCount == 0)
      #expect(!renderer.internalAnimationController.lastTickResult.hasPendingWork)
      let callbacks = log.travel.withLock { $0 }
      #expect(
        callbacks.contains {
          $0.previousFrame.origin.x == 1 && $0.currentFrame.origin.x == 9
            && abs($0.progress - 0.5) < 0.00001
        })
      #expect(
        callbacks.contains { $0.previousFrame.origin.x == 9 && $0.currentFrame.origin.x == 2 })
    }
  }

  @Test("a bound stroke sees real joined line arms without promoting content into its source")
  func borderDrawing() throws {
    let renderer = DefaultRenderer()
    let source = Mutex<[String]>([])
    let shader = CellLayerShader.region { layer, _, _ in
      let rows = (0..<layer.bounds.size.height).map { y in
        String(
          (0..<layer.bounds.size.width).map { x in
            layer.glyph(occupying: .init(x: x, y: y))?.character ?? "."
          })
      }
      source.withLock { $0 = rows }
    }
    let panel = ZStack(alignment: .topLeading) {
      VStack(alignment: .leading, spacing: 0) {
        Text(" title")
        Divider()
        Text(" ┼ok")
      }.padding(.vertical, 1)
        .border(Color.red, effect: shader, maxSampleOffset: .layerBounds)
      Text("Hi").offset(x: 2)
    }.frame(width: 9, height: 5, alignment: .topLeading)
    let cells = renderer.render(
      panel, context: .init(identity: testIdentity("boundStroke")),
      proposal: .init(width: 9, height: 5)
    ).rasterSurface.lines
    #expect(
      source.withLock { $0 } == ["┌───────┐", "│.......│", "├.......┤", "│.......│", "└───────┘"])
    #expect(cells == ["┌─Hi────┐", "│title  │", "├───────┤", "│┼ok    │", "└───────┘"])
  }
}

private struct PreparingRemoval: Transition {
  let log: SampleLog
  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .layerEffect(
        CountingSample(log: log, value: phase.isIdentity ? 1 : 2), maxSampleOffset: .zero
      )
      .opacity(phase.isIdentity ? 1 : 0.15)
  }
}

private struct RemovalPanel: View {
  var visible: Bool
  let log: SampleLog
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("steady")
      if visible { Text("x").transition(PreparingRemoval(log: log)) }
    }
  }
}

extension CellStatePlacementTests {
  @Test("the departing transition body keeps its prepared run and reinsertion owns a fresh run")
  func removalAndReinsertion() throws {
    let log = SampleLog()
    let renderer = DefaultRenderer()
    let id = testIdentity("statefulRemoval")
    let animation = Animation.linear(duration: .seconds(1))
    var tx = TransactionSnapshot()
    tx.animationRequest = .animate(animation.animationBox)
    func frame(_ ms: Int, _ visible: Bool, animated: Bool = false) -> String {
      renderer.render(
        RemovalPanel(visible: visible, log: log),
        context: .init(identity: id, transaction: animated ? tx : .init()),
        proposal: .init(width: 8, height: 3), frameInstant: start.advanced(by: .milliseconds(ms))
      ).rasterSurface.lines.joined()
    }
    withAnimationSinks(renderer.internalAnimationController) {
      renderer.internalAnimationController.register(animation)
      #expect(frame(0, true).contains("1"))
      #expect(frame(20, false, animated: true).contains("2"))
      #expect(frame(320, false).contains("3"))
      #expect(frame(320, false).contains("3"))
      #expect(frame(400, true, animated: true).contains("1"))
      let ticks = log.ticks.withLock { $0 }
      #expect(ticks.map(\.run) == [1, 1, 1, 2])
      #expect(ticks.map(\.context.delta) == [.zero, .milliseconds(20), .milliseconds(300), .zero])
    }
  }

  @Test(
    "stacked prepared kernels of the same type have distinct lifetimes and a bypass arms no deadline"
  )
  func modifierPositions() {
    let log = SampleLog()
    let renderer = DefaultRenderer()
    func frame(_ ms: Int, _ enabled: Bool) {
      let kernel = CountingSample(log: log, value: ms)
      _ = renderer.render(
        Text("x")
          .layerEffect(kernel, maxSampleOffset: .zero)
          .layerEffect(kernel, maxSampleOffset: .zero, isEnabled: enabled),
        context: .init(identity: testIdentity("position")), proposal: .init(width: 5, height: 1),
        frameInstant: start.advanced(by: .milliseconds(ms)))
    }
    frame(0, true)
    frame(10, true)
    frame(20, false)
    frame(30, true)
    let ticks = log.ticks.withLock { $0 }
    #expect(ticks.map(\.run) == [1, 2, 1, 2, 1, 1, 3])
    #expect(!renderer.internalAnimationController.requiresContinuedAnimationFrames)
  }
}

private struct ReparentedTravel: View {
  let right: Bool
  let log: SampleLog
  var subject: some View {
    Text("X").id("traveler").placementEffect(maxSampleOffset: .zero) { context in
      log.travel.withLock { $0.append(context) }
      return CellLayerShader { point, source, _ in source.sample(at: point) }
    }
    .transition(.identity)
  }
  var body: some View {
    HStack(spacing: 0) {
      VStack { if !right { subject } }.frame(width: 3, height: 1)
      VStack { if right { subject } }.frame(width: 3, height: 1)
    }
  }
}

extension CellStatePlacementTests {
  @Test(
    "a reparented identity, reduced motion and an inner disabled transaction cannot start a flight")
  func bypassAndReparenting() {
    var tx = TransactionSnapshot()
    tx.animationRequest = .animate(Animation.linear(duration: .seconds(1)).animationBox)

    // Each independent scene has its own mounted root. Keep it across both frames.
    func check<V: View>(_ id: String, content: (Bool, SampleLog) -> V) {
      let log = SampleLog()
      let renderer = DefaultRenderer()
      let leaks = SoundnessProbeConfiguration.teardownCoherenceLeakCount
      withAnimationSinks(renderer.internalAnimationController) {
        for moved in [false, true] {
          _ = renderer.render(
            content(moved, log),
            context: .init(identity: testIdentity(id), transaction: moved ? tx : .init()),
            proposal: .init(width: 15, height: 1),
            frameInstant: start.advanced(by: .milliseconds(moved ? 10 : 0)))
        }
        #expect(log.travel.withLock { $0.isEmpty })
        #expect(!renderer.internalAnimationController.requiresContinuedAnimationFrames)
        #expect(SoundnessProbeConfiguration.teardownCoherenceLeakCount == leaks)
      }
    }

    check("reparent") { moved, log in ReparentedTravel(right: moved, log: log) }
    check("reduce") { moved, log in
      TravelingPanel(indent: moved ? 8 : 1, text: "X", log: log)
        .environment(\.accessibilityReduceMotion, true)
    }
    check("disable") { moved, log in
      TravelingPanel(indent: moved ? 8 : 1, text: "X", log: log)
        .transaction { $0.animation = nil }
    }
  }

  @Test(
    "shading either of two real strokes retains their native shared corner",
    arguments: [false, true])
  func joinedStroke(_ inner: Bool) {
    let copy = CellLayerShader { p, layer, _ in layer.sample(at: p) }
    let view = Text(" ").frame(width: 5, height: 3)
      .border(Color.red, sides: .top, effect: copy, maxSampleOffset: .zero, isEnabled: inner)
      .border(Color.blue, sides: .leading, effect: copy, maxSampleOffset: .zero, isEnabled: !inner)
    let surface = DefaultRenderer().render(view, proposal: .init(width: 5, height: 3)).rasterSurface
    #expect(surface.cells.map { String($0.map(\.character)) } == ["┌────", "│    ", "│    "])
    #expect(surface.cells[0][0].style?.foregroundColor == .blue)
  }
}

private struct OvershootingTravel: CustomAnimation {
  func animate<V: VectorArithmetic>(
    value: V, time: Duration, context: inout AnimationContext<V>
  ) -> V? {
    guard time < .seconds(1) else { return nil }
    return value.scaled(by: time == .zero ? 0 : 1.25)
  }
}

extension CellStatePlacementTests {
  @Test("a placement shader receives the owning curve's unclamped overshoot")
  func overshoot() {
    let log = SampleLog()
    let renderer = DefaultRenderer()
    let txAnimation = Animation(OvershootingTravel())
    var tx = TransactionSnapshot()
    tx.animationRequest = .animate(txAnimation.animationBox)
    let id = testIdentity("placementOvershoot")
    withAnimationSinks(renderer.internalAnimationController) {
      renderer.internalAnimationController.register(txAnimation)
      for (ms, indent) in [(0, 1), (10, 9), (110, 9), (1200, 9)] {
        _ = renderer.render(
          TravelingPanel(indent: indent, text: "N", log: log),
          context: .init(identity: id, transaction: ms == 10 ? tx : .init()),
          proposal: .init(width: 16, height: 1), frameInstant: start.advanced(by: .milliseconds(ms))
        )
      }
      #expect(log.travel.withLock { $0.contains { $0.progress == 1.25 } })
      #expect(!renderer.internalAnimationController.requiresContinuedAnimationFrames)
    }
  }
}
