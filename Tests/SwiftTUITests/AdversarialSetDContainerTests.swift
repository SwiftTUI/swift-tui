import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Campaign F2 container environment and wide pointer targets", .serialized)
struct AdversarialSetDContainerTests {
  @Test(arguments: Array(61...70))
  func disabledContainer(id: Int) throws {
    let model = SetDControlModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setD", String(id)), size: .init(width: 50, height: 12)
    ) {
      SetDContainer(kind: id - 60, model: model, wide: false).disabled(model.disabled)
    }
    defer { h.shutdown() }
    let first = try #require(h.point(forText: "Target"))
    let second = try #require(h.point(forText: "Neighbor"))
    _ = try h.focusText("Target")
    model.disabled = true
    _ = try h.renderAfterExternalMutation()
    #expect(h.focusRegionCount == 0)
    _ = try h.pressKey(.init(.return))
    _ = try h.pressKey(.init(.space))
    _ = try h.click(first)
    _ = try h.click(second)
    #expect(model.mutations == 0)
    #expect(model.number == 0)
    model.disabled = false
    _ = try h.renderAfterExternalMutation()
    #expect(h.focusRegionCount == 2)
    _ = try h.focusText("Target")
    _ = try h.pressKey(.init(.return))
    _ = try h.clickText("Neighbor")
    #expect(model.mutations == 2)
    #expect(model.number == 11)
  }

  @Test(arguments: Array(71...80))
  func wideContainer(id: Int) throws {
    let model = SetDControlModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setD", String(id)), size: .init(width: 50, height: 12)
    ) { SetDContainer(kind: id - 70, model: model, wide: true) }
    defer { h.shutdown() }
    #expect(h.focusRegionCount == 2)
    #expect(h.frame.contains("界Target"))
    #expect(h.frame.contains("隣Neighbor"))
    _ = try h.clickText("界Target")
    #expect(model.number == 1)
    _ = try h.clickText("隣Neighbor")
    #expect(model.number == 11)
    #expect(model.mutations == 2)
  }
}

private struct SetDContainer: View {
  let kind: Int
  let model: SetDControlModel
  let wide: Bool
  private var target: some View { Button(wide ? "界Target" : "Target") { model.number += 1 } }
  private var neighbor: some View { Button(wide ? "隣Neighbor" : "Neighbor") { model.number += 10 } }
  var body: some View {
    switch kind {
    case 1:
      VStack {
        target
        neighbor
      }
    case 2:
      HStack {
        target
        neighbor
      }
    case 3:
      ZStack(alignment: .topLeading) {
        target
        neighbor.offset(y: 2)
      }
      .frame(width: 30, height: 4, alignment: .topLeading)
    case 4:
      VStack {
        Group {
          target
          neighbor
        }
      }
    case 5:
      ViewThatFits {
        VStack {
          target
          neighbor
        }
        Button("Unused") { model.number += 100 }.frame(width: 100, height: 30)
      }
    case 6:
      Section("Envelope") {
        VStack {
          target
          neighbor
        }
      }
    case 7:
      GroupBox("Envelope") {
        VStack {
          target
          neighbor
        }
      }
    case 8:
      ControlGroup("Envelope") {
        target
        neighbor
      }
    case 9:
      LabeledContent("Envelope") {
        VStack {
          target
          neighbor
        }
      }
    default:
      VStack {
        ForEach(0..<2) { index in
          Button(index == 0 ? (wide ? "界Target" : "Target") : (wide ? "隣Neighbor" : "Neighbor")) {
            model.number += index == 0 ? 1 : 10
          }
        }
      }
    }
  }
}
