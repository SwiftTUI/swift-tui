@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Campaign two F3 pass 2 (setE109–setE113): main-actor writes while a tab
// switch's offloaded relayout is suspended. While a frame's tail is
// suspended, including an offloaded relayout of layout-dependent content, its
// uncommitted removals are not visible and a write reaches the departing
// view's live state (Runtime.md, STUI-1233); a write while the departing
// tab's tail is suspended is captured into its archive (Dormant-Tab-State.md).

@MainActor
@Suite("Campaign F3 pass 2 writes during an offloaded relayout", .serialized)
struct AdversarialSetELayoutHopTests {
  static let newThree =
    "NEW-3: in a tab switch whose arriving tab realizes layout-dependent content (GeometryReader), a write to the departing tab's State while the frame tail is suspended (offloaded relayout or raster) reaches the live owner but not the tab archive, so the returning tab shows the pre-write value; suspected: the layout-dependent realization rebuilds canonicalResolved (LatePreferenceReconciliation.swift:186-216) and the departing tab's archive refresh request no longer reaches captureDormantTabArchiveCommitRefreshes (DefaultRenderer+CompletedFrameCandidates.swift:17-22); contract: Dormant-Tab-State.md:166-169, Runtime.md:127-130; adjacent STUI-1233"

  @Test(arguments: Array(109...113))
  func layoutHopWrite(id: Int) async {
    let model = SetEHopModel()
    let probe = SetEHopProbe()
    let renderer = DefaultRenderer()
    let root = testIdentity("setE", String(id))
    func render() async -> String {
      let snapshot = await renderer.renderAsync(
        SetEHopRoot(model: model, probe: probe),
        context: ResolveContext(
          identity: root, localActionRegistry: LocalActionRegistry(),
          localKeyHandlerRegistry: nil, applyEnvironmentValues: true))
      return snapshot.rasterSurface.lines.joined(separator: "\n")
    }
    #expect(await render().contains("A count 0"))
    for cycle in 1...(id == 113 ? 2 : 1) {
      let realized = SetEHopRealization()
      probe.realized = realized
      let layoutGate = AsyncFrameTailBlockingGate()
      let rasterGate = AsyncFrameTailBlockingGate()
      renderer.setFrameTailRenderHooks(
        .init(
          beforeLayout: { if realized.isSet { layoutGate.beforeRaster() } },
          beforeRaster: { rasterGate.beforeRaster() }))
      model.selection = "B"
      let finished = AsyncEvent()
      let switchTask = Task { @MainActor in
        let surface = await render()
        finished.fire()
        return surface
      }
      let blocked = await firstFrameTailSignal(blocked: layoutGate, orFinished: finished)
      #expect(blocked, "the arriving GeometryReader relayout never left the main actor")
      if blocked {
        switch id {
        case 110:
          probe.writeRoot?(1)
        case 111:
          probe.writeA?(1)
          probe.writeRoot?(1)
        default:
          probe.writeA?(id == 113 ? cycle : 1)
        }
        if id != 110 { #expect(probe.readA?() == (id == 113 ? cycle : 1)) }
      }
      layoutGate.release()
      if blocked {
        await rasterGate.waitUntilBlocked()
        if id == 112 { probe.writeA?(2) }
      }
      rasterGate.release()
      let switched = await switchTask.value
      renderer.setFrameTailRenderHooks(nil)
      #expect(switched.contains("B width"), "\(switched)")
      if id == 110 || id == 111 {
        let next = await render()
        #expect(next.contains("root 1"), "the surviving write was rewound: \(next)")
      }
      if id != 110 {
        model.selection = "A"
        let returned = await render()
        let expected = id == 112 ? 2 : (id == 113 ? cycle : 1)
        setEKnown(Self.newThree) {
          #expect(
            returned.contains("A count \(expected)"),
            "the departing tab's hop write missed its archive: \(returned)")
        }
      }
    }
  }
}

@MainActor
private final class SetEHopModel {
  var selection = "A"
  var binding: Binding<String> {
    Binding(get: { self.selection }, set: { self.selection = $0 })
  }
}

@MainActor
private final class SetEHopProbe {
  var writeA: ((Int) -> Void)?
  var readA: (() -> Int)?
  var writeRoot: ((Int) -> Void)?
  var realized = SetEHopRealization()
}

/// Set by the arriving tab's GeometryReader when the inline layout pass
/// realizes it; read by the frame-tail layout hook on any thread.
private final class SetEHopRealization: Sendable {
  private let state = Mutex(false)
  var isSet: Bool { state.withLock { $0 } }
  func set() { state.withLock { $0 = true } }
}

private struct SetEHopRoot: View {
  let model: SetEHopModel
  let probe: SetEHopProbe
  @State private var rootValue = 0

  var body: some View {
    probe.writeRoot = { rootValue = $0 }
    return VStack(alignment: .leading, spacing: 0) {
      Text("root \(rootValue)")
      TabView(selection: model.binding) {
        Tab("A", value: "A") { SetEHopDeparting(probe: probe) }
        Tab("B", value: "B") {
          GeometryReader { proxy in
            probe.realized.set()
            return Text("B width \(proxy.size.width)")
          }
        }
      }
    }
  }
}

private struct SetEHopDeparting: View {
  let probe: SetEHopProbe
  @State private var value = 0

  var body: some View {
    probe.writeA = { value = $0 }
    probe.readA = { value }
    return Text("A count \(value)")
  }
}
