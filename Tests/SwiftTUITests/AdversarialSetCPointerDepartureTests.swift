@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetCPointerDepartureTests {
  @Test func setC115DepartedHoverCallbackIsReleased() throws {
    let log = SetCDepartureLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC115"),
      size: .init(width: 20, height: 6)
    ) { SetCHoverRoot(log: log) }
    defer { h.shutdown() }
    let target = try #require(h.point(forText: "hover-me"))
    _ = try h.movePointer(to: target)
    try #require(log.phases.count == 1, "\(log.phases)")
    try #require(h.pointerHoverHandlerCount == 1)
    try #require(log.shown).wrappedValue = false
    _ = try h.render()
    try #require(!h.frame.contains("hover-me"))
    let afterRemoval = log.phases.count
    _ = try h.movePointer(to: Point(x: target.x + 1, y: target.y))
    _ = try h.movePointer(to: target)
    #expect(log.phases.count == afterRemoval, "\(log.phases)")
    #expect(h.pointerHoverHandlerCount == 0)
  }

  @Test func setC116DepartedWheelCallbackIsReleased() throws {
    let log = SetCDepartureLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC116"),
      size: .init(width: 20, height: 4)
    ) { SetCWheelRoot(log: log) }
    defer { h.shutdown() }
    let target = try #require(h.point(forText: "wheel-me"))
    _ = try h.scrollPointer(at: target, deltaY: 1)
    try #require(log.wheel == 1)
    try #require(log.outerValue.y == 0, "the handler consumed the notch")
    let before = h.runLoop.localPointerHandlerRegistry.snapshotWheel().count
    try #require(log.shown).wrappedValue = false
    _ = try h.render()
    try #require(!h.frame.contains("wheel-me"))
    _ = try h.scrollPointer(at: target, deltaY: 1)
    #expect(log.wheel == 1)
    #expect(log.outerValue.y == 1, "the notch reaches the enclosing scroll view")
    #expect(h.runLoop.localPointerHandlerRegistry.snapshotWheel().count == before - 1)
  }

  @Test func setC117RemintedViewUnderPointerGetsEntered() throws {
    let log = SetCDepartureLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC117"),
      size: .init(width: 20, height: 6)
    ) { SetCHoverRoot(log: log) }
    defer { h.shutdown() }
    let target = try #require(h.point(forText: "hover-me"))
    _ = try h.movePointer(to: target)
    try #require(log.phases.first?.1.isEntered == true, "\(log.phases)")
    try #require(log.shown).wrappedValue = false
    _ = try h.render()
    try #require(log.generation).wrappedValue = 1
    try #require(log.shown).wrappedValue = true
    _ = try h.render()
    try #require(h.frame.contains("hover-me"))
    _ = try h.movePointer(to: Point(x: target.x + 1, y: target.y))
    let fresh = log.phases.filter { $0.0 == 1 }.map(\.1)
    // Predicted continuation did not occur: the re-minted view receives a
    // fresh `.entered` (PointerHover.swift:5 holds).
    #expect(fresh.first?.isEntered == true, "fresh phases: \(fresh)")
  }

  @Test func setC118LiveDragSurvivesSiblingRemoval() throws {
    let log = SetCDepartureLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC118"),
      size: .init(width: 20, height: 6)
    ) { SetCHoverRoot(log: log) }
    defer { h.shutdown() }
    let start = try #require(h.point(forText: "drag-me"))
    _ = try h.sendMouse(.down(.primary), at: start)
    _ = try h.sendMouse(.dragged(.primary), at: Point(x: start.x + 2, y: start.y))
    try #require(log.shown).wrappedValue = false
    _ = try h.render()
    _ = try h.sendMouse(.dragged(.primary), at: Point(x: start.x + 4, y: start.y))
    _ = try h.sendMouse(.up(.primary), at: Point(x: start.x + 4, y: start.y))
    #expect(log.dragEnded == [4], "\(log.dragEnded)")
  }

  @Test func setC119HoverOnRemovedListRowIsReleased() throws {
    let log = SetCDepartureLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC119"),
      size: .init(width: 20, height: 8)
    ) { SetCListHoverRoot(log: log) }
    defer { h.shutdown() }
    let beta = try #require(h.point(forText: "beta"))
    _ = try h.movePointer(to: beta)
    try #require(log.rowPhases["beta"]?.count == 1, "\(log.rowPhases)")
    let before = h.pointerHoverHandlerCount
    log.items = ["alpha", "gamma"]
    _ = try h.renderAfterExternalMutation()
    try #require(!h.frame.contains("beta"))
    // Departure delivers `.exited` to the removed row; nothing may follow it.
    let departed = log.rowPhases["beta"] ?? []
    try #require(departed.count == 2, "\(log.rowPhases)")
    _ = try h.movePointer(to: Point(x: beta.x + 1, y: beta.y))
    _ = try h.movePointer(to: beta)
    #expect(log.rowPhases["beta"]?.count == 2, "\(log.rowPhases)")
    #expect(log.rowPhases["gamma"]?.isEmpty == false, "\(log.rowPhases)")
    #expect(h.pointerHoverHandlerCount == before - 1)
  }

  @Test func setC120DepartureWhileHoveredSilencesOldCallback() throws {
    let log = SetCDepartureLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC120"),
      size: .init(width: 20, height: 6)
    ) { SetCHoverRoot(log: log) }
    defer { h.shutdown() }
    let target = try #require(h.point(forText: "hover-me"))
    _ = try h.movePointer(to: target)
    try #require(log.phases.count == 1)
    try #require(log.shown).wrappedValue = false
    _ = try h.render()
    let atDeparture = log.phases.map(\.1)
    // Observation only: whether `.exited` was delivered when the view departed.
    print("setC120 phases at departure: \(atDeparture)")
    _ = try h.movePointer(to: Point(x: target.x + 1, y: target.y))
    _ = try h.movePointer(to: Point(x: target.x + 2, y: target.y))
    #expect(log.phases.count == atDeparture.count, "\(log.phases)")
  }

  @Test func setC121RekeyedWheelHostDeliversOnce() throws {
    let log = SetCDepartureLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC121"),
      size: .init(width: 20, height: 4)
    ) { SetCWheelRoot(log: log) }
    defer { h.shutdown() }
    let target = try #require(h.point(forText: "wheel-me"))
    _ = try h.scrollPointer(at: target, deltaY: 1)
    try #require(log.wheelByKey == [0: 1])
    try #require(log.generation).wrappedValue = 1
    _ = try h.render()
    _ = try h.scrollPointer(at: target, deltaY: 1)
    #expect(log.wheelByKey == [0: 1, 1: 1], "\(log.wheelByKey)")
    #expect(log.outerValue.y == 0)
  }
}

extension HoverPhase {
  fileprivate var isEntered: Bool {
    if case .entered = self { return true }
    return false
  }
}

@MainActor
private final class SetCDepartureLog {
  var shown: Binding<Bool>?
  var generation: Binding<Int>?
  var phases: [(Int, HoverPhase)] = []
  var wheel = 0
  var wheelByKey: [Int: Int] = [:]
  var dragEnded: [Double] = []
  var items = ["alpha", "beta", "gamma"]
  var rowPhases: [String: [HoverPhase]] = [:]
  var outerValue = ScrollCellOffset.zero
  var outer: Binding<ScrollCellOffset> {
    .init(get: { self.outerValue }, set: { self.outerValue = $0 })
  }
}

private struct SetCHoverRoot: View {
  @State private var shown = true
  @State private var generation = 0
  let log: SetCDepartureLog

  var body: some View {
    let _ = capture()
    VStack(alignment: .leading, spacing: 0) {
      Text("anchor")
      if shown {
        let key = generation
        Text("hover-me").onPointerHover { phase in log.phases.append((key, phase)) }
      }
      Text("drag-me")
        .gesture(DragGesture().onEnded { log.dragEnded.append($0.translation.dx) })
      Text("tail")
    }
  }

  private func capture() {
    log.shown = $shown
    log.generation = $generation
  }
}

private struct SetCWheelRoot: View {
  @State private var shown = true
  @State private var generation = 0
  let log: SetCDepartureLog

  var body: some View {
    let _ = capture()
    ScrollView(.vertical, position: log.outer) {
      VStack(alignment: .leading, spacing: 0) {
        if shown {
          let key = generation
          Text("wheel-me")
            .onScrollWheel { _ in
              log.wheel += 1
              log.wheelByKey[key, default: 0] += 1
              return .handled
            }
            .id(generation)
        }
        ForEach(0..<10) { i in Text("row \(i)") }
      }
    }.scrollIndicators(.hidden)
  }

  private func capture() {
    log.shown = $shown
    log.generation = $generation
  }
}

private struct SetCListHoverRoot: View {
  let log: SetCDepartureLog

  var body: some View {
    List {
      ForEach(log.items, id: \.self) { item in
        Text(item).onPointerHover { phase in log.rowPhases[item, default: []].append(phase) }
      }
    }.listStyle(.plain)
  }
}
