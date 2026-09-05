@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Written before the style-driven hosting change. These assertions are the
// acceptance boundary for moving authored controls into a compact menu.
@MainActor
struct ControlGroupRelocationTests {
  @Test("replacing an identified child while dormant starts fresh state")
  func dormantReplacement() {
    let probe = CapturedValueProbe()
    let renderer = DefaultRenderer()
    let context = ResolveContext(identity: testIdentity("CapturedReplacement"))
    _ = renderer.render(
      CapturedReplacementFixture(hidden: false, id: 0, probe: probe), context: context)
    probe.binding?.wrappedValue = 7
    _ = renderer.render(
      CapturedReplacementFixture(hidden: true, id: 0, probe: probe), context: context)
    _ = renderer.render(
      CapturedReplacementFixture(hidden: true, id: 1, probe: probe), context: context)
    let replacement = renderer.render(
      CapturedReplacementFixture(hidden: false, id: 1, probe: probe), context: context)
    #expect(replacement.rasterSurface.lines.joined(separator: "\n").contains("Retained 0"))
  }

  @Test("departing content retains writes made during an async tail", arguments: [false, true])
  func departingTailWrite(discard: Bool) async {
    let probe = CapturedValueProbe()
    let renderer = DefaultRenderer()
    let context = ResolveContext(identity: testIdentity("CapturedContentTail"))
    let initial = renderer.render(
      CapturedValueFixture(hidden: false, probe: probe), context: context)
    #expect(initial.rasterSurface.lines.joined(separator: "\n").contains("Retained 0"))
    probe.binding?.wrappedValue = 1
    let updated = renderer.render(
      CapturedValueFixture(hidden: false, probe: probe), context: context)
    #expect(updated.rasterSurface.lines.joined(separator: "\n").contains("Retained 1"))

    let gate = AsyncFrameTailBlockingGate()
    renderer.setFrameTailRenderHooks(.init(beforeRaster: { gate.beforeRaster() }))
    defer {
      gate.release()
      renderer.setFrameTailRenderHooks(nil)
    }
    let draft = renderer.prepareFrameHeadForCancellationTesting(
      CapturedValueFixture(hidden: true, probe: probe), context: context)
    let departure = Task { @MainActor in
      if discard {
        let dropped = await renderer.discardPreparedFrameTailForReconciliationTesting(
          draft,
          decision: .dropVisualOnly(
            eligibility: FrameDropEligibility(decision: .canDropVisualOnly)))
        #expect(dropped)
      } else {
        _ = await renderer.resolveCompletedFrameCandidateForTesting(draft)
      }
    }
    await gate.waitUntilBlocked()
    probe.binding?.wrappedValue = 2
    #expect(probe.binding?.wrappedValue == 2)
    gate.release()
    await departure.value
    renderer.setFrameTailRenderHooks(nil)
    if discard {
      _ = renderer.render(CapturedValueFixture(hidden: true, probe: probe), context: context)
    }
    let restored = renderer.render(
      CapturedValueFixture(hidden: false, probe: probe), context: context)
    // DefaultRenderer's discarded checkpoint rolls back the candidate's late
    // value, matching DormantTabStateTests. An accepted departure captures it
    // before preview materializes the prepared checkpoint.
    let expected = discard ? 1 : 2
    #expect(restored.rasterSurface.lines.joined(separator: "\n").contains("Retained \(expected)"))
  }

  @Test(
    "compact menu relocation preserves child identities, state, and actions",
    arguments: [false, true], [false, true])
  func relocation(vertical: Bool, selective: Bool) throws {
    let probe = ControlGroupRelocationProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GroupRelocation"),
      size: .init(width: 60, height: 16), selectiveEvaluation: selective
    ) {
      ControlGroupRelocationFixture(vertical: vertical, probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Count 0")
    #expect(harness.frame.contains("Count 1"))
    let counterID = try harness.focusIdentity(forText: "Count")
    let editorID = try harness.focusIdentity(forText: "seed")
    _ = try harness.focus(editorID)
    _ = try harness.pressKey(KeyPress(.end))
    _ = try harness.paste("!")
    #expect(harness.frame.contains("seed!"))
    #expect(probe.activations == 1)
    #expect(probe.appearances == 1)

    // The closed menu must not expose focus targets for its dormant controls.
    _ = try harness.pressKey(KeyPress(.character("g"), modifiers: .ctrl))
    #expect(!harness.frame.contains("Count"))
    #expect(!harness.runLoop.focusTracker.focusRegions.contains { $0.identity == counterID })
    #expect(!harness.runLoop.focusTracker.focusRegions.contains { $0.identity == editorID })
    #expect(!harness.runLoop.localActionRegistry.dispatch(identity: counterID))
    #expect(probe.disappearances == 1)

    _ = try harness.clickText("Commands")
    #expect(harness.frame.contains("Count 1"))
    #expect(harness.frame.contains("seed!"))
    #expect(try harness.focusIdentity(forText: "Count") == counterID)
    #expect(try harness.focusIdentity(forText: "seed") == editorID)
    #expect(probe.appearances == 2)
    _ = try harness.clickText("Count")
    #expect(probe.activations == 2)
    #expect(harness.frame.contains("Count 2"))

    // Relocate directly out of an open portal, exercising teardown and the
    // replacement inline host in the same committed runtime frame.
    _ = try harness.pressKey(KeyPress(.character("g"), modifiers: .ctrl))
    #expect(harness.frame.contains("Count 2"))
    #expect(harness.frame.contains("seed!"))
    #expect(try harness.focusIdentity(forText: "Count") == counterID)
    #expect(try harness.focusIdentity(forText: "seed") == editorID)
    _ = try harness.clickText("Count")
    #expect(probe.activations == 3)
    #expect(harness.frame.contains("Count 3"))
    #expect(probe.appearances == 2)
    #expect(probe.disappearances == 1)

    // A close/reopen cycle while compact must preserve the same authored
    // control lifetime, without leaving it eligible for focus while closed.
    _ = try harness.pressKey(KeyPress(.character("g"), modifiers: .ctrl))
    #expect(!harness.frame.contains("Count"))
    _ = try harness.clickText("Commands")
    _ = try harness.pressKey(KeyPress(.escape))
    #expect(!harness.frame.contains("Count"))
    #expect(!harness.runLoop.focusTracker.focusRegions.contains { $0.identity == counterID })
    #expect(!harness.runLoop.localActionRegistry.dispatch(identity: counterID))
    _ = try harness.clickText("Commands")
    #expect(harness.frame.contains("Count 3"))
    #expect(harness.frame.contains("seed!"))
    #expect(try harness.focusIdentity(forText: "Count") == counterID)
    #expect(try harness.focusIdentity(forText: "seed") == editorID)
    #expect(probe.appearances == 4)
    #expect(probe.disappearances == 3)
  }
}

private struct ControlGroupRelocationFixture: View {
  @State private var compact = false
  let vertical: Bool
  let probe: ControlGroupRelocationProbe

  var body: some View {
    VStack(alignment: .leading) {
      Text("Ctrl-G changes layout")
      ControlGroup("Commands") {
        RelocatedCounter(probe: probe).id("counter")
        RelocatedEditor().id("editor")
      }
      .controlGroupStyle(
        compact ? AnyControlGroupStyle.compactMenu : vertical ? .vertical : .horizontal)
    }
    .panel(id: "group-relocation")
    .keyCommand("Change layout", key: .character("g"), modifiers: .ctrl) {
      compact.toggle()
    }
  }
}

private struct RelocatedCounter: View {
  @State private var count = 0
  let probe: ControlGroupRelocationProbe

  var body: some View {
    Button("Count \(count)") {
      count += 1
      probe.activations += 1
    }
    .onAppear { probe.appearances += 1 }
    .onDisappear { probe.disappearances += 1 }
  }
}

private struct RelocatedEditor: View {
  @State private var draft = "seed"
  var body: some View { TextField("Draft", text: $draft) }
}

@MainActor
private final class ControlGroupRelocationProbe {
  var activations = 0
  var appearances = 0
  var disappearances = 0
}

@MainActor
private final class CapturedValueProbe {
  var binding: Binding<Int>?
}

private struct CapturedValueFixture: View {
  let hidden: Bool
  let probe: CapturedValueProbe
  var body: some View {
    ControlGroup("Values") { CapturedValue(probe: probe) }
      .controlGroupStyle(hidden ? AnyControlGroupStyle.compactMenu : .horizontal)
  }
}

private struct CapturedValue: View {
  @State private var value = 0
  let probe: CapturedValueProbe
  var body: some View {
    probe.binding = $value
    return Text("Retained \(value)")
  }
}

private struct CapturedReplacementFixture: View {
  let hidden: Bool
  let id: Int
  let probe: CapturedValueProbe
  var body: some View {
    ControlGroup("Values") { CapturedValue(probe: probe).id(id) }
      .controlGroupStyle(hidden ? AnyControlGroupStyle.compactMenu : .horizontal)
  }
}
