import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct NestedLayoutRealizationTeardownTests {
  @Test("nested geometry commits the current rows when a collection shrinks")
  func nestedGeometryRetiresDepartedRows() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("NestedGeometryRows"), size: .init(width: 50, height: 12)
    ) {
      NestedGeometryRows()
    }
    defer { harness.shutdown() }

    for _ in 0..<3 {
      #expect(harness.frame.contains("row 3"))
      let shrunk = try harness.clickText("Toggle rows")
      #expect(shrunk.contains("row 1"))
      #expect(!shrunk.contains("row 2"))
      let violation = harness.runLoop.renderer.viewGraph.debugTeardownCoherenceViolation()
      #expect(violation == nil, "\(violation?.detail ?? "")")
      _ = try harness.clickText("Toggle rows")
    }
  }
}

private struct NestedGeometryRows: View {
  @State private var expanded = true

  var body: some View {
    let count = expanded ? 4 : 2
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle rows") { expanded.toggle() }
      GeometryReader { outer in
        VStack(alignment: .leading, spacing: 0) {
          Text("Activity")
          GeometryReader { inner in
            VStack(alignment: .leading, spacing: 0) {
              ForEach(0..<count, id: \.self) { Text("row \($0)") }
            }
            .frame(width: inner.size.width, height: inner.size.height, alignment: .topLeading)
          }
        }
        .frame(width: outer.size.width, height: outer.size.height, alignment: .topLeading)
      }
    }
  }
}
