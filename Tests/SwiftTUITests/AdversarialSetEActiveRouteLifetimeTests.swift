import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Campaign F3 active pointer route departure", .serialized)
struct AdversarialSetEActiveRouteLifetimeTests {
  @Test(arguments: Array(91...95))
  func activeRouteLifetime(id: Int) throws {
    // STUI-1128 also reaches the publication oracle. Attribute its exact
    // diagnostics locally, like setC006, without a repository-wide allowance.
    // Every other violation counter and detail must remain unchanged.
    let expectedDiagnostics = [91: 5, 92: 2, 95: 5][id] ?? 0
    let before = SoundnessCounterSnapshot.current()
    let savedTrace = SoundnessProbeConfiguration.isTraceEnabled
    let savedEnabled = SoundnessProbeConfiguration.isEnabled
    let savedSample = SoundnessProbeConfiguration.sampleEveryNFrames
    let savedSampledFrame = SoundnessProbeConfiguration.isSampledFrame
    let savedDetail = SoundnessProbeConfiguration.lastViolationDetail
    SoundnessProbeConfiguration.isEnabled = true
    SoundnessProbeConfiguration.sampleEveryNFrames = 1
    if expectedDiagnostics > 0 { SoundnessProbeConfiguration.isTraceEnabled = false }
    defer {
      var after = SoundnessCounterSnapshot.current()
      let observed =
        after.registrationPublicationViolationCount
        - before.registrationPublicationViolationCount
      #expect(observed == expectedDiagnostics)
      if expectedDiagnostics > 0 {
        let family = id == 92 ? "hover" : "wheel"
        let detail = after.lastViolationDetailByKind["registration-publication"] ?? ""
        #expect(detail.contains("\(family)|setE/\(id)/"))
        #expect(detail.contains("live=1 rebuilt=0"))
        print("F3_LOCAL_SOUNDNESS setE\(id) registration-publication=\(observed) STUI-1128")
        after.registrationPublicationViolationCount = before.registrationPublicationViolationCount
        after.lastViolationDetailByKind["registration-publication"] =
          before.lastViolationDetailByKind["registration-publication"]
        SoundnessProbeConfiguration.registrationPublicationViolationCount =
          before.registrationPublicationViolationCount
        SoundnessProbeConfiguration.lastViolationDetailByKind["registration-publication"] =
          before.lastViolationDetailByKind["registration-publication"]
        SoundnessProbeConfiguration.lastViolationDetail = savedDetail
      }
      // These are documented informational/census currencies, not violations.
      after.automaticLifetimeAnchorCount = before.automaticLifetimeAnchorCount
      after.layoutShadowWindowedExclusionCount = before.layoutShadowWindowedExclusionCount
      after.layoutShadowDepthExclusionCount = before.layoutShadowDepthExclusionCount
      after.lastTeardownLeakUnreachableCount = before.lastTeardownLeakUnreachableCount
      #expect(after == before)
      SoundnessProbeConfiguration.isTraceEnabled = savedTrace
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
      var actual = setECensus(h)
      var expected = baseline
      if [91, 92, 95].contains(id) {
        let family = id == 92 ? "hover" : "wheel"
        setEKnown(
          "STUI-1128: the paired cleanup sweep must retire ownerless wheel and hover routes"
        ) {
          #expect(actual[family, default: 0] == expected[family, default: 0])
        }
        actual.removeValue(forKey: family)
        expected.removeValue(forKey: family)
      }
      #expect(actual == expected)
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
