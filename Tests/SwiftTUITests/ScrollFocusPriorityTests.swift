import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct ScrollFocusPriorityTests {
  @Test
  func explicitOffsetWinsOverSimultaneousRelocation() throws {
    let position = FocusPriorityOffset()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("FocusPriority"), size: CellSize(width: 48, height: 12)
    ) { FocusPriorityFixture(position: position) }
    defer { harness.shutdown() }
    _ = try harness.focus(FocusPriorityFixture.targetIdentity)
    try #require(harness.frame.contains("TARGET"))
    _ = try harness.pressKey(KeyPress(.character("m")))
    #expect(position.value.y == 30)
    #expect(!harness.frame.contains("TARGET"))
    #expect(
      harness.runLoop.focusTracker.currentFocusIdentity == FocusPriorityFixture.targetIdentity)
    _ = try harness.render()
    #expect(position.value.y == 30)
  }

  @Test
  func sameOffsetCommandWinsOverSimultaneousRelocation() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SameOffsetFocusPriority"),
      size: CellSize(width: 48, height: 12)
    ) { SameOffsetFocusPriorityFixture() }
    defer { harness.shutdown() }
    _ = try harness.focusText("TARGET")
    let originalFocus = try #require(harness.runLoop.focusTracker.currentFocusIdentity)
    _ = try harness.pressKey(KeyPress(.character("m"), modifiers: .ctrl))
    try #require(harness.frame.contains("CHANGED"))
    #expect(harness.frame.contains("Offset: 0"))
    #expect(!harness.frame.contains("TARGET"))
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == originalFocus)
    _ = try harness.render()
    #expect(harness.frame.contains("Offset: 0"))
  }

  @Test(arguments: [false, true])
  func exactIdentityInsideNestedScrollRevealsBothViewports(crossesAxes: Bool) throws {
    let outer = FocusPriorityOffset()
    let inner = FocusPriorityOffset()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("NestedFocusPriority"), size: CellSize(width: 48, height: 12)
    ) { NestedFocusPriorityFixture(outer: outer, inner: inner, crossesAxes: crossesAxes) }
    defer { harness.shutdown() }
    _ = try harness.focusText("Away")
    try #require(!harness.frame.contains("TARGET"))
    _ = try harness.focus(NestedFocusPriorityFixture.targetIdentity)
    #expect(harness.frame.contains("TARGET"))
    #expect(outer.value.y > 0)
    if crossesAxes {
      #expect(inner.value.x > 0)
    } else {
      #expect(inner.value.y > 0)
    }
    #expect(
      harness.runLoop.focusTracker.currentFocusIdentity == NestedFocusPriorityFixture.targetIdentity
    )
  }

  @Test(arguments: [false, true])
  func scrollingInnerViewportDoesNotMoveOuterViewport(crossesAxes: Bool) throws {
    let outer = FocusPriorityOffset()
    let inner = FocusPriorityOffset()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("NestedInnerScrollPriority", String(crossesAxes)),
      size: CellSize(width: 48, height: 12)
    ) { NestedFocusPriorityFixture(outer: outer, inner: inner, crossesAxes: crossesAxes) }
    defer { harness.shutdown() }
    _ = try harness.focusText("Away")
    _ = try harness.focus(NestedFocusPriorityFixture.targetIdentity)
    try #require(harness.frame.contains("TARGET"))
    let previousOuterOffset = outer.value
    let target = try #require(
      harness.runLoop.latestSemanticSnapshot.scrollTargets.first {
        $0.identity == NestedFocusPriorityFixture.targetIdentity
      })
    try #require(
      harness.runLoop.localScrollPositionRegistry.scrollTo(
        x: 0, y: 0, scopeIdentity: target.scrollIdentity))
    _ = try harness.renderAfterExternalMutation()
    #expect(outer.value == previousOuterOffset)
    #expect(!harness.frame.contains("TARGET"))
    #expect(
      harness.runLoop.focusTracker.currentFocusIdentity == NestedFocusPriorityFixture.targetIdentity
    )
    _ = try harness.render()
    #expect(outer.value == previousOuterOffset)
  }

}

@MainActor
private final class FocusPriorityOffset {
  var value = ScrollCellOffset.zero

  var binding: Binding<ScrollCellOffset> {
    Binding(get: { self.value }, set: { self.value = $0 })
  }
}

private struct FocusPriorityFixture: View {
  static let targetIdentity = testIdentity("FocusPriorityTarget")
  let position: FocusPriorityOffset
  @State private var moved = false

  var body: some View {
    ScrollView(.vertical, position: position.binding) {
      VStack(alignment: .leading, spacing: 0) {
        if !moved { target }
        ForEach(0..<16, id: \.self) { row in Text("Before \(row)") }
        if moved { target }
        ForEach(0..<30, id: \.self) { row in Text("After \(row)") }
      }
    }
    .scrollIndicators(.hidden)
    .frame(width: 32, height: 5, alignment: .topLeading)
  }

  private var target: some View {
    Text("TARGET")
      .id(Self.targetIdentity)
      .focusable()
      .onKeyPress(.character("m")) { _ in
        moved = true
        position.value = ScrollCellOffset(x: 0, y: 30)
        return .handled
      }
  }
}

private struct NestedFocusPriorityFixture: View {
  static let targetIdentity = testIdentity("NestedFocusPriorityTarget")
  let outer: FocusPriorityOffset
  let inner: FocusPriorityOffset
  let crossesAxes: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Away") {}
      ScrollView(.vertical, position: outer.binding) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(0..<16, id: \.self) { row in Text("Outer \(row)") }
          ScrollView(crossesAxes ? .horizontal : .vertical, position: inner.binding) {
            if crossesAxes {
              HStack(alignment: .top, spacing: 0) { innerRows }
            } else {
              VStack(alignment: .leading, spacing: 0) { innerRows }
            }
          }
          .scrollIndicators(.hidden)
          .frame(width: 28, height: 4, alignment: .topLeading)
          Text("End")
        }
      }
      .scrollIndicators(.hidden)
      .frame(width: 32, height: 6, alignment: .topLeading)
    }
  }

  @ViewBuilder
  private var innerRows: some View {
    ForEach(0..<12, id: \.self) { row in Text("Inner \(row)") }
    Text("TARGET").id(Self.targetIdentity).focusable()
    Text("Tail")
  }

}

private struct SameOffsetFocusPriorityFixture: View {
  @State private var changed = false
  @State private var position = ScrollCellOffset.zero

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        ScrollView(.vertical, position: $position) {
          VStack(alignment: .leading, spacing: 0) {
            Text("Before").frame(height: changed ? 12 : 1, alignment: .topLeading)
            Button("TARGET") {}
            ForEach(0..<30, id: \.self) { row in Text("After \(row)") }
          }
        }
        .scrollIndicators(.hidden)
        .frame(width: 32, height: 5, alignment: .topLeading)
        Text(changed ? "CHANGED" : "INITIAL")
        Text("Offset: \(position.y)")
      }
      .onKeyPress(.character("m"), modifiers: .ctrl) { _ in
        changed = true
        _ = proxy.scrollTo(y: 0)
        return .handled
      }
    }
  }
}
