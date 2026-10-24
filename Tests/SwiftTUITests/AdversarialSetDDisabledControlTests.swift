import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Campaign F2 disabled-control interaction cells", .serialized)
struct AdversarialSetDDisabledControlTests {
  @Test(arguments: Array(1...10))
  func disabledControl(id: Int) throws {
    let model = SetDControlModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setD", String(id)), size: .init(width: 40, height: 8)
    ) {
      SetDControlForm(kind: id, model: model).disabled(model.disabled)
    }
    defer { h.shutdown() }
    let initialRegion = try #require(h.runLoop.focusTracker.focusRegions.first)
    _ = try h.focus(initialRegion.identity)
    let oldPoint = Point(initialRegion.rect.origin)
    let before = model.snapshot
    model.disabled = true
    _ = try h.renderAfterExternalMutation()
    #expect(h.runLoop.focusTracker.currentFocusIdentity == nil)
    for key in [KeyPress(.return), KeyPress(.space), KeyPress(.arrowRight), KeyPress(.arrowDown)] {
      _ = try h.pressKey(key)
    }
    _ = try h.paste("ignored")
    _ = try h.click(oldPoint)
    #expect(model.snapshot == before)
    model.disabled = false
    _ = try h.renderAfterExternalMutation()
    let restored = try #require(h.runLoop.focusTracker.focusRegions.first)
    _ = try h.focus(restored.identity)
    switch id {
    case 1:
      _ = try h.pressKey(KeyPress(.return))
      #expect(model.number == 1)
    case 2:
      _ = try h.pressKey(KeyPress(.space))
      #expect(model.flag)
    case 3, 4, 6:
      _ = try h.pressKey(KeyPress(.arrowRight))
      #expect(model.number == 1)
    case 5:
      _ = try h.pressKey(KeyPress(.arrowDown))
      #expect(model.number == 1)
    case 7...9:
      _ = try h.pressKey(KeyPress(.end))
      _ = try h.pressKey(KeyPress(.character("z")))
      #expect(model.text == "seedz")
      if id == 8 { #expect(!h.frame.contains("seed")) }
    default:
      _ = try h.pressKey(KeyPress(.return))
      #expect(model.flag)
      #expect(h.frame.contains("expanded body"))
    }
  }
}
