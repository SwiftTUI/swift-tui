import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetCCaptureTests {
  @Test func setC001SharedAuthoredCopyHasDistinctOwners() throws {
    let log = SetCCaptureLog()
    defer { log.entries.removeAll() }
    let leaf = SetCCaptureLeaf(log: log)
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC001"),
      size: .init(width: 40, height: 5)
    ) {
      HStack {
        leaf
        leaf
      }
    }
    defer { h.shutdown() }
    try #require(log.entries.count >= 2)
    let a = log.entries[0]
    let b = log.entries[1]
    a.write(11)
    _ = try h.render()
    #expect(a.read() == 11)
    #expect(b.read() == 0)
    b.write(22)
    _ = try h.render()
    #expect(a.read() == 11)
    #expect(b.read() == 22)
    #expect(h.frame.contains("11:100"))
    #expect(h.frame.contains("22:100"))
  }

  @Test(arguments: [2, 5])
  func independentGraphs(id: Int) throws {
    let log = SetCCaptureLog()
    defer { log.entries.removeAll() }
    let leaf = SetCCaptureLeaf(log: log)
    let a = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC00\(id)"),
      size: .init(width: 30, height: 4)
    ) { leaf }
    defer { a.shutdown() }
    let first = try #require(log.entries.first)
    let b = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC00\(id)"),
      size: .init(width: 30, height: 4)
    ) { leaf }
    defer { b.shutdown() }
    let second = try #require(log.entries.last)
    if id == 5 {
      withImperativeAuthoringContext(second.scope) { first.write(37) }
    } else {
      first.write(37)
    }
    _ = try a.render()
    _ = try b.render()
    #expect(first.read() == 37)
    #expect(second.read() == 0)
    #expect(a.frame.contains("37:100"))
    #expect(b.frame.contains("0:100"))
  }

  @Test(arguments: [3, 4, 9, 10])
  func projectionAndReevaluation(id: Int) throws {
    let log = SetCCaptureLog()
    defer { log.entries.removeAll() }
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC\(id)"),
      size: .init(width: 30, height: 4)
    ) { SetCCaptureLeaf(log: log) }
    defer { h.shutdown() }
    let first = try #require(log.entries.first)
    switch id {
    case 3: first.binding.wrappedValue = 12
    case 4: first.sibling.wrappedValue = 30
    case 9:
      first.write(12)
      first.sibling.wrappedValue = 30
    default:
      _ = try h.renderAfterExternalMutation()
      first.write(12)
    }
    _ = try h.render()
    let value = id == 4 ? 0 : 12
    let sibling = id == 4 || id == 9 ? 30 : 100
    #expect(first.read() == value)
    #expect(first.sibling.wrappedValue == sibling)
    #expect(h.frame.contains("\(value):\(sibling)"))
    let fresh = try #require(log.entries.last)
    #expect(fresh.read() == value)
  }

  @Test func setC006RetiredCallbackDoesNotSeedRemount() throws {
    let log = SetCCaptureLog()
    defer { log.entries.removeAll() }
    let leaf = SetCCaptureLeaf(log: log)
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC006"),
      size: .init(width: 30, height: 4)
    ) {
      if log.visible { leaf } else { Text("absent") }
    }
    defer { h.shutdown() }
    let retired = try #require(log.entries.first)
    retired.write(5)
    _ = try h.render()
    log.visible = false
    _ = try h.renderAfterExternalMutation()
    try #require(h.frame.contains("absent"))
    #if DEBUG
      let capture = try #require(retired.capture)
      let capturedNode = LiveViewGraphRegistry.node(for: capture.owner)
      let occupant = LiveViewGraphRegistry.graph(for: capture.graphScope)?.nodeForIdentity(
        capture.identity)
      try #require(capturedNode == nil, "fixture must retire its original owner")
      try #require(occupant == nil, "the retired write must have no live successor")
    #endif
    // This deliberately exercises an absent owner. Assert its two diagnostics
    // locally, as setB201 does, so the soundness gate still rejects unexpected
    // diagnostics from every other operation in this fixture.
    do {
      let savedTrace = SoundnessProbeConfiguration.isTraceEnabled
      let savedSeed = SoundnessProbeConfiguration.stateSeedFallbackViolationCount
      let savedMiss = SoundnessProbeConfiguration.stateCaptureMissViolationCount
      SoundnessProbeConfiguration.isTraceEnabled = false
      defer {
        SoundnessProbeConfiguration.isTraceEnabled = savedTrace
        SoundnessProbeConfiguration.stateSeedFallbackViolationCount = savedSeed
        SoundnessProbeConfiguration.stateCaptureMissViolationCount = savedMiss
      }
      #expect(ImperativeRuntimeIssueQueue.drain().isEmpty)
      retired.write(99)
      let issues = ImperativeRuntimeIssueQueue.drain()
      #expect(issues.map(\.code) == ["state.imperativeSeedFallback"])
      #expect(SoundnessProbeConfiguration.stateSeedFallbackViolationCount == savedSeed + 1)
      #expect(SoundnessProbeConfiguration.stateCaptureMissViolationCount == savedMiss + 1)
    }
    log.visible = true
    _ = try h.renderAfterExternalMutation()
    let successor = try #require(log.entries.last)
    setCKnown("STUI-1173: retired callback changes the authored seed") {
      #expect(successor.read() == 0)
    }
    setCKnown("STUI-1173: successor renders the retired callback's value") {
      #expect(h.frame.contains("0:100"))
    }
  }

  @Test(arguments: [7, 8])
  func forwardedOwners(id: Int) throws {
    let log = SetCCaptureLog()
    defer { log.entries.removeAll() }
    let leaf = SetCCaptureLeaf(log: log)
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC00\(id)"),
      size: .init(width: 40, height: 8)
    ) {
      if id == 7 {
        VStack {
          leaf.padding(1)
          leaf.frame(width: 20)
        }
      } else {
        List {
          leaf.id("a")
          leaf.id("b")
        }.listStyle(.plain)
      }
    }
    defer { h.shutdown() }
    try #require(log.entries.count >= 2)
    let a = log.entries[0]
    let b = log.entries[1]
    a.write(41)
    _ = try h.render()
    #expect(a.read() == 41)
    #expect(b.read() == 0)
    #expect(h.frame.contains("41:100"))
    #expect(h.frame.contains("0:100"))
  }
}

@MainActor
private final class SetCCaptureLog {
  struct Entry {
    var read: () -> Int
    var write: (Int) -> Void
    var binding: Binding<Int>
    var sibling: Binding<Int>
    var scope: ImperativeAuthoringContextSnapshot?
    var capture: StateCaptureBinding?
  }
  var entries: [Entry] = []
  var visible = true
}

private struct SetCCaptureLeaf: View {
  @State private var value = 0
  @State private var sibling = 100
  let log: SetCCaptureLog
  var body: some View {
    let capture: StateCaptureBinding?
    #if DEBUG
      capture = _value.captureSlotForTesting
    #else
      capture = nil
    #endif
    log.entries.append(
      .init(
        read: { value }, write: { value = $0 },
        binding: $value, sibling: $sibling, scope: currentImperativeAuthoringContextSnapshot(),
        capture: capture))
    return Text("\(value):\(sibling)")
  }
}
