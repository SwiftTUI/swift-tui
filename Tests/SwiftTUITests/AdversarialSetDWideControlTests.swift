import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Campaign F2 wide-content interaction cells", .serialized)
struct AdversarialSetDWideControlTests {
  @Test(arguments: Array(11...20))
  func wideContent(id: Int) throws {
    let kind = id - 10
    let model = SetDControlModel()
    if (7...9).contains(kind) { model.text = "a界e\u{301}" }
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setD", String(id)), size: .init(width: 40, height: 8)
    ) { SetDControlForm(kind: kind, model: model, wide: true) }
    defer { h.shutdown() }
    if kind == 1 || kind == 2 || kind == 10 {
      #expect(h.frame.contains("界Target"))
      _ = try h.clickText("界Target")
      if kind == 1 {
        #expect(model.number == 1)
      } else {
        #expect(model.flag)
      }
      if kind == 10 { #expect(h.frame.contains("内容")) }
      #expect(h.frame.contains("界Target"))
    } else if kind == 3 || kind == 4 {
      _ = try h.focusText("界Target")
      _ = try h.pressKey(KeyPress(.arrowRight))
      #expect(model.number == 1)
      #expect(h.frame.contains("界Target"))
    } else if kind == 5 {
      #expect(h.frame.contains("界0") && h.frame.contains("界1"))
      let region = try #require(h.runLoop.focusTracker.focusRegions.first)
      _ = try h.focus(region.identity)
      _ = try h.pressKey(KeyPress(.arrowDown))
      #expect(model.number == 1)
    } else if kind == 6 {
      #expect(h.frame.contains("界0") && h.frame.contains("界1"))
      _ = try h.clickText("界1")
      #expect(model.number == 1)
    } else {
      let region = try #require(h.runLoop.focusTracker.focusRegions.first)
      _ = try h.focus(region.identity)
      _ = try h.pressKey(KeyPress(.home))
      _ = try h.pressKey(KeyPress(.arrowRight))
      _ = try h.pressKey(KeyPress(.delete))
      #expect(model.text == "ae\u{301}")
      #expect(Array(model.text).count == 2)
      if kind == 8 {
        #expect(!h.frame.contains("a界") && !h.frame.contains("ae\u{301}"))
      } else {
        #expect(h.frame.contains("ae\u{301}"))
      }
    }
  }
}
