import Observation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct MemoReadReuseTests {
  @Test("unchanged state reads reuse and changed state agrees with fresh evaluation")
  func stateReads() {
    let retained = DefaultRenderer()
    let fresh = DefaultRenderer()
    let probe = ReadProbe()
    let oracle = ReadProbe()
    let root = testIdentity("StateCertificates")
    for tick in 0..<8 {
      if tick == 4 {
        probe.binding?.wrappedValue = 9
        oracle.binding?.wrappedValue = 9
      }
      let context = ResolveContext(identity: root, invalidatedIdentities: tick == 0 ? [] : [root])
      let result = retained.render(
        StateRoot(probe: probe, tick: tick, forceFresh: false), context: context)
      let expected = fresh.render(
        StateRoot(probe: oracle, tick: tick, forceFresh: true), context: context)
      #expect(result.rasterSurface == expected.rasterSurface)
    }
    #expect(probe.evaluations == 2)
    #expect(oracle.evaluations == 8)
  }

  @Test(
    "observable certificates remain live across memo serves and renew after a change",
    arguments: [true, false])
  func observationReads(usesBridge: Bool) {
    let renderer = DefaultRenderer()
    let probe = ReadProbe()
    let model = ReadModel()
    let bridge = ObservationBridge()
    let root = testIdentity("ObservationCertificates")
    for tick in 0..<8 {
      if tick == 4 { model.value = 9 }
      var context = ResolveContext(identity: root, invalidatedIdentities: tick == 0 ? [] : [root])
      context.observationBridge = usesBridge ? bridge : nil
      let frame = renderer.render(
        ObservationRoot(probe: probe, tick: tick).environment(model),
        context: context)
      #expect(frame.rasterSurface.lines.joined().contains("observed \(tick < 4 ? 7 : 9)"))
    }
    #expect(probe.evaluations == (usesBridge ? 2 : 8))
  }
}

@MainActor
private final class ReadProbe {
  var evaluations = 0
  var binding: Binding<Int>?
}

@MainActor @Observable
private final class ReadModel { var value = 7 }

@MainActor
private struct StateRoot: View {
  let probe: ReadProbe
  let tick: Int
  let forceFresh: Bool
  var body: some View {
    VStack {
      StateBoundary(probe: probe, nonce: forceFresh ? tick : 0)
      Text("tick \(tick)")
    }
  }
}

@MainActor
private struct StateBoundary: View, Equatable {
  let probe: ReadProbe
  let nonce: Int
  @State private var value = 7
  nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.nonce == rhs.nonce }
  var body: some View {
    probe.evaluations += 1
    probe.binding = $value
    return Text("state \(value)")
  }
}

@MainActor
private struct ObservationRoot: View {
  let probe: ReadProbe
  let tick: Int
  var body: some View {
    VStack {
      ObservationBoundary(probe: probe)
      Text("tick \(tick)")
    }
  }
}

@MainActor
private struct ObservationBoundary: View, Equatable {
  let probe: ReadProbe
  @Environment(ReadModel.self) private var model
  nonisolated static func == (lhs: Self, rhs: Self) -> Bool { true }
  var body: some View {
    probe.evaluations += 1
    return Text("observed \(model.value)")
  }
}
