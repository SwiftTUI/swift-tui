import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Campaign F2 modal blocking and focus restoration", .serialized)
struct AdversarialSetDModalControlTests {
  @Test(arguments: Array(51...60))
  func modalControl(id: Int) throws {
    let kind = id - 50
    let model = SetDControlModel()
    let modal = SetDModalModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setD", String(id)), size: .init(width: 40, height: 8)
    ) {
      SetDControlForm(kind: kind, model: model)
        .fullScreenCover(isPresented: modal.binding) {
          Button("Modal action") { modal.actions += 1 }
        }
    }
    defer { h.shutdown() }
    let region = try #require(h.runLoop.focusTracker.focusRegions.first)
    _ = try h.focus(region.identity)
    let before = model.snapshot
    modal.presented = true
    _ = try h.renderAfterExternalMutation()
    try #require(h.frame.contains("Modal action"))
    #expect(h.runLoop.focusTracker.currentFocusIdentity != region.identity)
    for key in [KeyEvent.return, .space, .arrowRight, .arrowDown, .end, .character("z")] {
      _ = try h.pressKey(.init(key))
    }
    _ = try h.click(Point(region.rect.origin))
    #expect(model.snapshot == before)
    _ = try h.pressKey(.init(.escape))
    #expect(!modal.presented)
    #expect(h.runLoop.focusTracker.currentFocusIdentity == region.identity)
    switch kind {
    case 1, 10: _ = try h.pressKey(.init(.return))
    case 2: _ = try h.pressKey(.init(.space))
    case 3, 4, 6: _ = try h.pressKey(.init(.arrowRight))
    case 5: _ = try h.pressKey(.init(.arrowDown))
    default:
      _ = try h.pressKey(.init(.end))
      _ = try h.pressKey(.init(.character("z")))
    }
    #expect(model.mutations == 1)
    switch kind {
    case 1, 3...6: #expect(model.number == 1)
    case 2, 10: #expect(model.flag)
    default:
      #expect(model.text == "seedz")
      if kind == 8 { #expect(!h.frame.contains("seed")) }
    }
  }
}

@MainActor
private final class SetDModalModel {
  var presented = false
  var actions = 0
  var binding: Binding<Bool> { .init(get: { self.presented }, set: { self.presented = $0 }) }
}
