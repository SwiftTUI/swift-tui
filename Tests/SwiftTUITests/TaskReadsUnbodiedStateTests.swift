import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Pins the contract that bit the gallery "Logo Breaker" demo: an autonomous
/// `.task` loop that *reads* a `@State` flag observes the gesture's live writes
/// **whether or not the view body also reads that flag** during resolve. This
/// matches SwiftUI, where a `.task`'s `@State` read is always live.
///
/// The mechanism that used to make the body read matter: a `.task` runs outside
/// a resolve pass, so its `@State` read resolves through a graph-backed location
/// *remembered* during resolve. A flag the body read got such a location; a flag
/// the body never read (it appeared only inside gesture closures) did not, and
/// the read fell back to the box's seed — which the gesture's write, made
/// through a different box's seed, never updated. The loop then saw a
/// permanently-stale value: in `LogoTab` the `guard !isDragging` silently never
/// fired, so gravity ran underneath an active drag and the held ball fell.
///
/// The framework fix recovers the live owner node from the captured graph scope
/// (`LiveViewGraphRegistry`) when an imperative `@State` access finds no
/// remembered location, so both reads and writes reach the graph slot directly.
/// Both probes below must now freeze the held drag — the body-read variant and
/// the body-never-reads variant alike — so neither the fix nor a regression of
/// it can drift unnoticed.
///
/// Harness note (fixed flake #4 in docs/KNOWN-TEST-FLAKES.md): the two variants
/// run CONCURRENTLY, so all probe bookkeeping lives in a per-run
/// `ProbeGrabState` instance — a shared singleton let one variant read the
/// other's grab values under CI load. The grab offset is captured live inside
/// the gesture closure, never scraped from a presented frame: the tick loop
/// advances on wall-clock sleeps while frame presentation can coalesce, so no
/// frame bearing the exact grab tick is guaranteed to exist.
@MainActor
@Suite("Task observes gesture-written @State")
struct TaskReadsUnbodiedStateTests {
  @Test("a task observes a @State flag the body also reads (held drag freezes)")
  func taskObservesFlagTheBodyReads() async throws {
    let result = try await runHeldProbe(bodyReadsFlag: true)
    #expect(
      result.finalOffset == result.offsetAtGrab,
      """
      With the body reading the flag, the loop must observe the live drag state \
      and freeze: offset stayed \(result.offsetAtGrab) while held (tick \
      \(result.finalTick)).
      """
    )
  }

  @Test("a task observes a @State flag the body never reads (held drag freezes)")
  func taskObservesFlagTheBodyNeverReads() async throws {
    // The body never reads `isDragging`, so no box is ever taught a remembered
    // location for it. The imperative-access fallback recovers the live owner
    // node from the captured graph scope, so the gesture's write reaches the
    // graph slot and the loop's read sees it live — the held drag freezes,
    // exactly as when the body does read the flag.
    let result = try await runHeldProbe(bodyReadsFlag: false)
    #expect(
      result.finalOffset == result.offsetAtGrab,
      """
      Even with the body never reading the flag, the loop must observe the live \
      drag state and freeze: offset stayed \(result.offsetAtGrab) while held \
      (tick \(result.finalTick)). A regression of the imperative-access live \
      resolution would let the offset advance here.
      """
    )
  }
}

private struct HeldProbeResult {
  let offsetAtGrab: Int
  let finalOffset: Int
  let finalTick: Int
}

@MainActor
private func runHeldProbe(bodyReadsFlag: Bool) async throws -> HeldProbeResult {
  let grabState = ProbeGrabState()
  let terminal = RecordingPresentationSurface(surfaceSize: .init(width: 44, height: 6))
  let rootIdentity = testIdentity("TaskReadsUnbodiedStateRoot-\(bodyReadsFlag)")

  let inputReader = ScriptedAutonomousWakeInputReader(
    frameSignal: terminal.frameSignal,
    steps: [
      .awaitCondition { (latestTick(terminal.frames) ?? 0) >= 3 },
      .event(.mouse(.init(kind: .down(.primary), location: Point(x: 4, y: 1)))),
      .awaitCondition {
        guard let grab = grabState.grabbedTick else { return false }
        return (latestTick(terminal.frames) ?? 0) >= grab + 8
      },
    ])

  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    presentationSurface: terminal,
    terminalInputReader: inputReader,
    signalReader: ImmediateFinishSignalReader(),
    stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
    focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
    proposal: .init(width: 44, height: 6),
    viewBuilder: { _, _ in HeldProbe(bodyReadsFlag: bodyReadsFlag, grabState: grabState) }
  )
  _ = try await runLoop.run()

  // The grab offset was captured live inside the gesture closure — the value
  // the frozen loop must hold for the rest of the run.
  let offsetAtGrab = try #require(grabState.offsetAtGrab)
  let lastFrame = try #require(terminal.frames.last)
  let finalOffset = try #require(frameOffset(lastFrame))
  let finalTick = try #require(frameTick(lastFrame))
  return HeldProbeResult(
    offsetAtGrab: offsetAtGrab, finalOffset: finalOffset, finalTick: finalTick)
}

/// Per-run grab bookkeeping. One instance per `runHeldProbe` call: the two
/// suite variants run concurrently, so any shared instance would let one
/// variant's grab clobber the other's (the pre-fix flake #4 mechanism).
@MainActor
private final class ProbeGrabState {
  var grabbedTick: Int?
  var offsetAtGrab: Int?
}

@MainActor
private func latestTick(_ frames: [String]) -> Int? {
  frames.reversed().lazy.compactMap(frameTick).first
}

/// Mirrors `LogoTab`: a `.task` loop advances `offset` only while `isDragging`
/// is false, and a `DragGesture` flips `isDragging` (only inside its closures,
/// never in the body). `bodyReadsFlag` toggles whether the body *also* reads
/// `isDragging` during resolve — the only difference between the two probes.
private struct HeldProbe: View {
  let bodyReadsFlag: Bool
  let grabState: ProbeGrabState
  @State private var tick = 0
  @State private var offset = 0
  @State private var isDragging = false

  var body: some View {
    // The ternary's false branch never evaluates `\(isDragging)`, so with
    // `bodyReadsFlag == false` the body genuinely never reads the flag — exactly
    // the shape `LogoTab` had before its fix.
    let suffix = bodyReadsFlag ? " drag\(isDragging)" : ""
    return Text("tick \(tick) offset \(offset)\(suffix)")
      .frame(width: 44, height: 6, alignment: .topLeading)
      .contentShape(CellRect(origin: .zero, size: CellSize(width: 44, height: 6)))
      .gesture(
        DragGesture()
          .onChanged { _ in
            if !isDragging {
              isDragging = true
              // Record the grab state once, live: the closure's reads go
              // through the same imperative access path as its writes, so
              // these are the values the frozen loop must hold.
              grabState.grabbedTick = tick
              grabState.offsetAtGrab = offset
            }
          }
          .onEnded { _ in isDragging = false }
      )
      .task(id: "hold-loop") {
        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: 5_000_000)
          tick += 1
          guard !isDragging else { continue }
          offset += 1
        }
      }
  }
}

private func frameTick(_ frame: String) -> Int? { scrapeInt(after: "tick", in: frame) }
private func frameOffset(_ frame: String) -> Int? { scrapeInt(after: "offset", in: frame) }

private func scrapeInt(after label: String, in frame: String) -> Int? {
  guard let range = frame.range(of: "\(label) ") else { return nil }
  let rest = frame[range.upperBound...]
  let digits = rest.prefix { $0.isNumber }
  return Int(digits)
}
