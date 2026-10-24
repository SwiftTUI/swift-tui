@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetCScrollGeometryTests {
  @Test func setC043OuterWheelHandlerWaitsForInnerRefusal() throws {
    let box = SetCGeometryBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC043"),
      size: .init(width: 24, height: 6)
    ) {
      ScrollView(.vertical, position: box.outer) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<2) { i in Text("header \(i)") }
          ScrollView(.vertical, position: box.inner) {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(0..<10) { i in Text("inner \(i)") }
            }
          }.scrollIndicators(.hidden).frame(height: 3)
          ForEach(0..<10) { i in Text("tail \(i)") }
        }
      }.scrollIndicators(.hidden)
        .onScrollWheel { _ in
          box.calls += 1
          return .ignored
        }
    }
    defer { h.shutdown() }
    let point = try #require(h.point(forText: "inner 0"))
    for _ in 0..<3 { _ = try h.scrollPointer(at: point, deltaY: 1) }
    #expect(box.calls == 0)
    #expect(box.outerValue.y == 0)
    box.innerValue.y = 7
    _ = try h.renderAfterExternalMutation()
    _ = try h.scrollPointer(at: point, deltaY: 1)
    #expect(box.calls == 1)
    #expect(box.outerValue.y == 1)
  }

  @Test(arguments: 0..<4)
  func setC045WrappedLazyWindowsRetainOffsets(wrapper: Int) throws {
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC045", "\(wrapper)"),
      size: .init(width: 80, height: 32)
    ) {
      VStack(alignment: .leading, spacing: 0) {
        Text("window")
        ScrollView {
          Group {
            switch wrapper {
            case 0: Group { SetCWindowRows() }
            case 1: AnyView(SetCWindowRows())
            case 2: SetCWindowRows().equatable()
            default: SetCPassthroughLayout { SetCWindowRows() }
            }
          }.padding(1)
        }.frame(height: 24).border(.separator)
      }.padding(1)
    }
    defer { h.shutdown() }
    for burst in 1...6 {
      _ = try h.scrollPointer(at: .init(x: 5.5, y: 5.5), deltaY: 30)
      #expect(h.frame.contains("vrow \(burst * 30)"), "\(h.frame)")
      let route = try #require(
        h.runLoop.localScrollPositionRegistry.routesWithCurrentOffsets(
          h.runLoop.latestSemanticSnapshot.scrollRoutes
        ).first)
      #expect(route.contentOffset.y == min(burst * 30, 178))
    }
  }

  @Test(arguments: [1, 2])
  func setC046IndicatorBoundaryFocusRecovery(growth: Int) throws {
    let box = SetCGeometryBox()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC046", "\(growth)"),
      size: .init(width: 16, height: 6)
    ) {
      ScrollView(.vertical, position: box.outer) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<20) { i in
            Button("R\(i < 10 ? "0" : "")\(i)") { box.activated = i }
              .buttonStyle(.plain).frame(height: i == 0 ? 1 + box.growth : 1)
          }
        }
      }
    }
    defer { h.shutdown() }
    _ = try h.focusText("R04")
    let focus = h.runLoop.focusTracker.currentFocusIdentity
    box.growth = growth
    _ = try h.renderAfterExternalMutation()
    #expect(box.outerValue.y == max(0, growth - 1))
    #expect(h.frame.contains("R04"))
    #expect(h.runLoop.focusTracker.currentFocusIdentity == focus)
    _ = try h.pressKey(.init(.return))
    #expect(box.activated == 4)
  }

  @Test func setC047NestedLazyFocusSurvivesOuterShrink() throws {
    let box = SetCGeometryBox()
    let target = testIdentity("setC047-target")
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC047"),
      size: .init(width: 40, height: 12)
    ) {
      VStack(alignment: .leading, spacing: 0) {
        Button("Away") {}
        ScrollView(.vertical, position: box.outer) {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<16) { i in Text("outer \(i)") }
            ScrollView(.vertical, position: box.inner) {
              VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<12) { i in Text("inner \(i)") }
                Text("TARGET").id(target).focusable()
                Text("tail")
              }
            }.scrollIndicators(.hidden).frame(width: 28, height: 4)
          }
        }.scrollIndicators(.hidden).frame(width: 32, height: box.height)
      }
    }
    defer { h.shutdown() }
    _ = try h.focusText("Away")
    // Materialize the lazy nested row before requesting its focus. An
    // undiscovered offscreen identity is not itself a valid focus request.
    box.outerValue.y = 16
    _ = try h.renderAfterExternalMutation()
    _ = try h.focus(target)
    try #require(h.frame.contains("TARGET"), "target must be visible before geometry change")
    box.height = 3
    _ = try h.renderAfterExternalMutation()
    #expect(h.frame.contains("TARGET"), "\(h.frame)")
    #expect(h.runLoop.focusTracker.currentFocusIdentity == target)
  }

  @Test(arguments: [1, 2])
  func setC050IndicatorDoesNotConsumeOnlyContentColumn(width: Int) throws {
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC050", "\(width)"),
      size: .init(width: width, height: 3)
    ) {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<6) { _ in Text("ab") }
        }
      }
    }
    defer { h.shutdown() }
    #expect(h.frame.contains("a"))
    #expect(!h.frame.contains("ab"))
    let route = try #require(h.runLoop.latestSemanticSnapshot.scrollRoutes.first)
    #expect(route.viewportRect.size.width == 1)
  }
}

private struct SetCWindowRows: View, Equatable {
  var body: some View {
    LazyVStack(alignment: .leading, spacing: 0) {
      ForEach(0..<200) { i in Text("vrow \(i)") }
    }
  }
}

private struct SetCPassthroughLayout: Layout {
  func sizeThatFits(
    proposal: ProposedViewSize, subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    subviews.first?.sizeThatFits(proposal) ?? .zero
  }
  func placeSubviews(
    in bounds: LayoutRect, proposal: ProposedViewSize,
    subviews: LayoutSubviews, cache _: inout Void
  ) {
    for subview in subviews {
      subview.place(at: bounds.origin, anchor: .topLeading, proposal: proposal)
    }
  }
}

@MainActor
private final class SetCGeometryBox {
  var outerValue = ScrollCellOffset.zero
  var innerValue = ScrollCellOffset.zero
  var calls = 0
  var growth = 0
  var height = 6
  var activated: Int?
  var outer: Binding<ScrollCellOffset> {
    .init(get: { self.outerValue }, set: { self.outerValue = $0 })
  }
  var inner: Binding<ScrollCellOffset> {
    .init(get: { self.innerValue }, set: { self.innerValue = $0 })
  }
}
