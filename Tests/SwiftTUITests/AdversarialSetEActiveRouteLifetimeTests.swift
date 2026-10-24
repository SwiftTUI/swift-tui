import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Campaign F3 active pointer route departure", .serialized)
struct AdversarialSetEActiveRouteLifetimeTests {
  @Test(arguments: Array(91...95))
  func activeRouteLifetime(id: Int) throws {
    // Active preservation and departed-owner cleanup must agree with the
    // independent full-publication oracle, without a diagnostic allowance.
    let before = SoundnessCounterSnapshot.current()
    let savedEnabled = SoundnessProbeConfiguration.isEnabled
    let savedSample = SoundnessProbeConfiguration.sampleEveryNFrames
    let savedSampledFrame = SoundnessProbeConfiguration.isSampledFrame
    SoundnessProbeConfiguration.isEnabled = true
    SoundnessProbeConfiguration.sampleEveryNFrames = 1
    defer {
      var after = SoundnessCounterSnapshot.current()
      let observed =
        after.registrationPublicationViolationCount
        - before.registrationPublicationViolationCount
      #expect(observed == 0)
      // These are documented informational/census currencies, not violations.
      after.automaticLifetimeAnchorCount = before.automaticLifetimeAnchorCount
      after.layoutShadowWindowedExclusionCount = before.layoutShadowWindowedExclusionCount
      after.layoutShadowDepthExclusionCount = before.layoutShadowDepthExclusionCount
      after.lastTeardownLeakUnreachableCount = before.lastTeardownLeakUnreachableCount
      #expect(after == before)
      SoundnessProbeConfiguration.isEnabled = savedEnabled
      SoundnessProbeConfiguration.sampleEveryNFrames = savedSample
      SoundnessProbeConfiguration.isSampledFrame = savedSampledFrame
    }
    let probe = SetEActiveRouteProbe()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setE", String(id)), size: .init(width: 40, height: 10)
    ) { SetEActiveRouteRoot(kind: id, probe: probe) }
    defer { h.shutdown() }
    let baseline = setECensus(h)
    let rootBodies = probe.rootBodies
    for cycle in 1...3 {
      _ = try h.clickText("Open")
      try #require(h.frame.contains("Subject"))
      try #require(probe.rootBodies == rootBodies)
      try #require(h.gestureRecognizerCount > 0)
      let point = try #require(h.point(forText: "Subject"))
      if [91, 94, 95].contains(id) {
        _ = try h.scrollPointer(at: point, deltaY: 1)
        #expect(probe.wheels == cycle)
      }
      _ = try h.sendMouse(.down(.primary), at: point)
      _ = try h.sendMouse(.up(.primary), at: point)
      try #require(!h.frame.contains("Subject"))
      try #require(probe.rootBodies == rootBodies)
      try #require(h.gestureRecognizerCount == 0)
      try #require(h.runLoop.localGestureRegistry.activeIdentitySnapshot().isEmpty)
      #expect(setECensus(h) == baseline)
      let callbacks = probe.changes + probe.wheels + probe.hovers
      _ = try h.scrollPointer(at: point, deltaY: 1)
      _ = try h.movePointer(to: point)
      _ = try h.click(point)
      #expect(probe.changes + probe.wheels + probe.hovers == callbacks)
    }
  }
}

@MainActor
private final class SetEActiveRouteProbe {
  var rootBodies = 0
  var changes = 0
  var wheels = 0
  var hovers = 0
}

private struct SetEActiveRouteRoot: View {
  let kind: Int
  let probe: SetEActiveRouteProbe
  var body: some View {
    let _ = probe.rootBodies += 1
    VStack(alignment: .leading, spacing: 1) {
      Text("Persistent sibling")
      SetEActiveRouteMount(kind: kind, probe: probe)
    }
  }
}

private struct SetEActiveRouteMount: View {
  let kind: Int
  let probe: SetEActiveRouteProbe
  @State private var mounted = false
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Button("Open") { mounted = true }
      if mounted { subject }
    }
  }
  private var drag: some Gesture {
    DragGesture(minimumDistance: 0).onChanged { _ in
      probe.changes += 1
      mounted = false
    }
  }
  @ViewBuilder private var subject: some View {
    switch kind {
    case 91:
      Text("Subject").gesture(drag).onScrollWheel { _ in
        probe.wheels += 1
        return .handled
      }
    case 92:
      Text("Subject").gesture(drag).onPointerHover { _ in probe.hovers += 1 }
    case 93:
      Text("Subject").gesture(drag)
    case 94:
      Text("Subject").gesture(
        TapGesture().onEnded {
          probe.changes += 1
          mounted = false
        }
      )
      .onScrollWheel { _ in
        probe.wheels += 1
        return .handled
      }
    default:
      Text("Subject").id("explicit-subject").gesture(drag)
        .onScrollWheel { _ in
          probe.wheels += 1
          return .handled
        }
    }
  }
}
