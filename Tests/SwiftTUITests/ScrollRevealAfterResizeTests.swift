import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct ScrollRevealAfterResizeTests {
  @Test("unanchored commands still reveal targets after an ordinary viewport grows")
  func scrollToAfterViewportGrowth() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ScrollRevealAfterResize"), size: .init(width: 40, height: 14)
    ) { ScrollRevealAfterResizeFixture() }
    defer { harness.shutdown() }

    _ = try harness.clickText("Bottom")
    #expect(harness.frame.contains("ROW19"))
    _ = try harness.clickText("Grow")
    #expect(harness.frame.contains("ROW12"))
    #expect(!harness.frame.contains("ROW11"))
    _ = try harness.clickText("Near")
    #expect(harness.frame.contains("ROW18"))
    _ = try harness.clickText("Above")
    #expect(harness.frame.contains("ROW11"), "scrollTo must reveal its target:\n\(harness.frame)")
  }

  @Test("backward focus traversal still reveals rows after an ordinary viewport grows")
  func focusTraversalAfterViewportGrowth() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ScrollRevealAfterResizeFocus"), size: .init(width: 40, height: 14)
    ) { ScrollRevealAfterResizeFixture() }
    defer { harness.shutdown() }
    _ = try harness.clickText("Bottom")
    _ = try harness.clickText("Grow")
    _ = try harness.focusText("ROW18")
    for row in stride(from: 17, through: 10, by: -1) {
      _ = try harness.pressKey(KeyPress(.tab, modifiers: .shift))
      #expect(harness.frame.contains("ROW\(row)"), "focused row must be visible:\n\(harness.frame)")
      let identity = try harness.focusIdentity(forText: "ROW\(row)")
      #expect(harness.runLoop.focusTracker.currentFocusIdentity == identity)
    }
  }
}

@MainActor
private struct ScrollRevealAfterResizeFixture: View {
  @State private var grown = false

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 1) {
          Button("Bottom") { _ = proxy.scrollTo(edge: .bottom) }
          Button("Grow") { grown = true }
          Button("Near") { _ = proxy.scrollTo("row18") }
          Button("Above") { _ = proxy.scrollTo("row11") }
        }
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<20, id: \.self) { row in
              Text("ROW\(row)").id("row\(row)").focusable()
            }
          }
        }
        .scrollIndicators(.hidden)
        .frame(width: 30, height: grown ? 8 : 4, alignment: .topLeading)
      }
    }
  }
}
