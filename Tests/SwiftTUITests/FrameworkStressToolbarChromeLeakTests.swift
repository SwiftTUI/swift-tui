import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// The F04 teardown-coherence leak residual (gallery fuzzer case-139):
/// toolbar-strip button chrome interiors (`ButtonBody/false/base`,
/// `/overlay`) were reachable only through hosted-detached anchors to a
/// per-generation evaluated host. When strip churn (item title/enabled
/// signature changes) or toolbar-host teardown (the hosting branch flips
/// away) retired that host generation, the interiors lost every anchor but
/// stayed in the node store — one stranded interior generation per departed
/// entry. The style-seam root fix resolves style bodies through their own
/// view node, so the interiors are committed children and the ordinary
/// teardown cascade reclaims them.
@MainActor
@Suite("Toolbar button chrome teardown coherence", .serialized)
struct FrameworkStressToolbarChromeLeakTests {
  @Test("toolbar strip churn and host teardown leave no teardown-coherence orphans")
  func toolbarStripChurnLeavesNoOrphans() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ToolbarChromeChurnRoot"),
      size: .init(width: 72, height: 20)
    ) {
      ToolbarChromeChurnFixture()
    }
    defer { harness.shutdown() }

    for cycle in 1...4 {
      var frame = try harness.clickText("Bump Count")
      #expect(frame.contains("Count \(cycle)"))
      frame = try harness.clickText("Swap Tab")
      #expect(frame.contains("Other body"))
      frame = try harness.clickText("Swap Tab")
      #expect(frame.contains("Tools body"))
      let violation = harness.runLoop.renderer.viewGraph.debugTeardownCoherenceViolation()
      #expect(
        violation == nil,
        """
        toolbar button chrome stranded stored node(s) on cycle \(cycle): \
        \(violation?.detail ?? "")
        """
      )
    }
  }
}

private struct ToolbarChromeChurnFixture: View {
  @State private var count = 0
  @State private var showsToolbarTab = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Count \(count)")
      Button("Bump Count") { count += 1 }
      Button("Swap Tab") { showsToolbarTab.toggle() }
      if showsToolbarTab {
        Panel(id: "tools") {
          Text("Tools body")
            .toolbarItem(.init(title: "Item \(count)", action: {}))
            .toolbarItem(
              .init(
                title: "Extra",
                isEnabled: count.isMultiple(of: 2),
                action: {}
              )
            )
        }
        .toolbar(style: DefaultBottomToolbarStyle())
      } else {
        Text("Other body")
      }
    }
    .frame(width: 72, height: 20, alignment: .topLeading)
  }
}
