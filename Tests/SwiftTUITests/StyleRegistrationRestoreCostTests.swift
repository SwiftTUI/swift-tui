import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct StyleRegistrationRestoreCostTests {
  @Test(
    "tab strip registration restoration matches a full publication at increasing content sizes",
    arguments: [0, 20, 200])
  func tabStripCost(rows: Int) throws {
    let tabs = testIdentity("MeasuredTabs")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("RegistrationCost"), size: .init(width: 50, height: 15)
    ) {
      VStack {
        Text("Outside the tabs")
        TabView(selection: .constant(0)) {
          Tab("First", value: 0) {
            VStack {
              ForEach(0..<rows, id: \.self) { row in Button("Row \(row)") {} }
            }
          }
          Tab("Second", value: 1) { Text("Other content") }
        }.id(tabs)
      }
    }
    defer { harness.shutdown() }
    let graph = harness.runLoop.renderer.viewGraph
    let frontier = [tabItemIdentity(for: tabs, index: 0)]
    let roots = graph.runtimeRegistrationResetRoots(for: frontier)
    let restored = graph.runtimeRegistrationSubtreeNodeCount(rootedAt: roots)
    let live = RuntimeRegistrationSet.scratch()
    graph.restoreCurrentFrameRuntimeRegistrations(into: live)
    let expected = live.publicationOracleFingerprint()
    #expect(!expected.isEmpty)
    let clock = ContinuousClock()
    let elapsed = clock.measure {
      for _ in 0..<20 {
        let reset = graph.runtimeRegistrationResetRoots(for: frontier)
        live.removeSubtrees(rootedAt: reset)
        graph.restoreRuntimeRegistrationSubtrees(rootedAt: reset, into: live)
      }
    }
    #expect(live.publicationOracleFingerprint() == expected)
    let components = elapsed.components
    let microseconds =
      (Double(components.seconds) * 1_000_000
        + Double(components.attoseconds) / 1_000_000_000_000) / 20
    print(
      "style-registration rows=\(rows) roots=\(roots.count) restored=\(restored) "
        + "live=\(graph.runtimeRegistrationLiveNodeCount) mean_us=\(microseconds)")
  }
}
