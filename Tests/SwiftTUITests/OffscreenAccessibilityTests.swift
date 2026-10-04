import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct OffscreenAccessibilityTests {
  private struct OutlineRecord: Identifiable {
    let id: Int
    var children: [OutlineRecord] = []
  }

  @Test(
    "disabled collections remain readable offscreen without enabling row operations",
    arguments: [false, true])
  func disabledReview(table: Bool) throws {
    var writes = 0
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DisabledReview"), size: .init(width: 35, height: 10)
    ) {
      Group {
        if table {
          Table(0..<1000, id: \.self, columns: [.init("Record")]) { id in
            Button("Record \(id)") { writes += 1 }
          }
        } else {
          List(0..<1000, id: \.self) { id in Button("Record \(id)") { writes += 1 } }
        }
      }.disabled(true)
    }
    defer { harness.shutdown() }
    let target = try #require(
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
        $0.label == "Review items"
      }?.actionTarget)
    #expect(
      harness.runLoop.handleAccessibilityAction(.init(target: target, action: .custom("Last item")))
        == .accepted)
    _ = try harness.render()
    let row = try #require(
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
        $0.label == "Record 999"
      })
    #expect(!row.isEnabled)
    #expect(
      harness.runLoop.handleAccessibilityAction(
        .init(target: try #require(row.actionTarget), action: .activate)) == .disabled)
    #expect(writes == 0)
  }

  @Test(
    "logical traversal keeps realized graph and handlers bounded as data grows",
    arguments: [1_000, 10_000, 100_000])
  func scale(count: Int) throws {
    var realized = 0
    let clock = ContinuousClock()
    let initial = clock.now
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ReviewScale"), size: .init(width: 40, height: 12)
    ) {
      List(0..<count, id: \.self) { id in
        let _ = { realized += 1 }()
        Button("Record \(id)") {}
      }
    }
    defer { harness.shutdown() }
    let initialDuration = initial.duration(to: clock.now)
    let initialRealized = realized
    let target = try #require(
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
        $0.label == "Review items"
      }?.actionTarget)
    let reveal = clock.now
    #expect(
      harness.runLoop.handleAccessibilityAction(.init(target: target, action: .custom("Last item")))
        == .accepted)
    _ = try harness.render()
    let revealDuration = reveal.duration(to: clock.now)
    let nodes = harness.runLoop.renderer.viewGraph.runtimeRegistrationLiveNodeCount
    #expect(
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.contains {
        $0.label == "Record \(count - 1)"
      })
    #expect(realized < 150 && nodes < 250 && harness.actionRegistrationCount < 150)
    print(
      "OFFSCREEN_METRICS count=\(count) initial=\(initialDuration) reveal=\(revealDuration) initialRealizations=\(initialRealized) revealRealizations=\(realized - initialRealized) liveNodes=\(nodes) handlers=\(harness.actionRegistrationCount)"
    )
  }

  @Test("horizontal page and edge commands target one viewport without keyboard movement")
  func horizontalScroll() throws {
    var offset = ScrollCellOffset.zero
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("HorizontalReview"), size: .init(width: 32, height: 3)
    ) {
      ScrollView(.horizontal, position: Binding(get: { offset }, set: { offset = $0 })) {
        LazyHStack(spacing: 0) {
          ForEach(0..<1000, id: \.self) { Button("H\($0)") {}.frame(width: 8, height: 1) }
        }
      }.accessibilityLabel("Horizontal records")
    }
    defer { harness.shutdown() }
    func send(_ command: String) throws {
      let target = try #require(
        harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
          $0.label == "Horizontal records"
        }?.actionTarget)
      #expect(
        harness.runLoop.handleAccessibilityAction(.init(target: target, action: .custom(command)))
          == .accepted)
      _ = try harness.render()
    }
    let keyboard = harness.runLoop.focusTracker.currentFocusIdentity
    try send("Scroll to right edge")
    #expect(
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.contains {
        $0.label == "H999"
      })
    let end = offset.x
    try send("Scroll left one page")
    #expect(offset.x < end && offset.x > 0 && offset.y == 0)
    try send("Scroll to left edge")
    #expect(offset == .zero)
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == keyboard)
  }

  @Test("a ready authored request wins over a prepared collection reveal")
  func authoredRequestPriority() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ReviewPriority"), size: .init(width: 45, height: 14)
    ) {
      OffscreenFocusPriorityFixture()
    }
    defer { harness.shutdown() }
    func send(_ label: String, _ action: AccessibilityAction) throws {
      let target = try #require(
        harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
          $0.label == label
        }?.actionTarget)
      #expect(
        harness.runLoop.handleAccessibilityAction(.init(target: target, action: action))
          == .accepted)
      _ = try harness.render()
    }
    try send("Review items", .custom("Last item"))
    try send("Review items", .custom("Read item"))
    try send("Reorder and read heading", .activate)
    _ = try harness.renderAfterExternalMutation()
    #expect(
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.contains {
        $0.label == "Requested heading" && $0.isAccessibilityFocused
      })
  }

  @Test(
    "a large outline reveals logical rows and retains disclosure state across recycling",
    arguments: [false, true])
  func outline(hosted: Bool) throws {
    var realized = 0
    var writes = 0
    var selection: Int? = nil
    var offset = ScrollCellOffset.zero
    let records = (0..<100).map { root in
      OutlineRecord(id: -root - 1, children: (0..<100).map { .init(id: root * 100 + $0) })
    }
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("OutlineReview"), size: .init(width: 50, height: 12)
    ) {
      Group {
        if hosted {
          List(
            records, selection: Binding(get: { selection }, set: { selection = $0 }),
            children: \.children
          ) { record in
            let _ = { realized += 1 }()
            Button("Record \(record.id)") { writes += 1 }
          }
        } else {
          ScrollView(.vertical, position: Binding(get: { offset }, set: { offset = $0 })) {
            OutlineGroup(records, children: \.children) { record in
              let _ = { realized += 1 }()
              Button("Record \(record.id)") { writes += 1 }
            }
          }.accessibilityLabel("Outline viewport")
        }
      }
    }
    defer { harness.shutdown() }
    func nodes() -> [AccessibilityNode] {
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes
    }
    func send(_ label: String, _ action: AccessibilityAction) throws {
      let target = try #require(nodes().first { $0.label == label }?.actionTarget)
      #expect(
        harness.runLoop.handleAccessibilityAction(.init(target: target, action: action))
          == .accepted)
      _ = try harness.render()
    }
    #expect(!nodes().contains { $0.label == "Record 9999" })
    #expect(realized < 150)
    try send("Collapse item 1 at level 1", .activate)
    #expect(!nodes().contains { $0.label == "Record 0" })
    let before = realized
    try send(
      hosted ? "Review items" : "Outline viewport",
      .custom(hosted ? "Last item" : "Scroll to bottom"))
    #expect(nodes().contains { $0.label == "Record 9999" })
    #expect(realized - before < 150)
    if hosted {
      try send("Review items", .custom("Read item"))
      let focused = try #require(nodes().first { $0.isAccessibilityFocused })
      #expect(focused.properties?.level == 2)
      #expect(focused.properties?.positionInSet == 100 && focused.properties?.setSize == 100)
    }
    let stale = try #require(nodes().first { $0.label == "Record 9999" }?.actionTarget)
    try send("Record 9999", .activate)
    #expect(writes == 1 && selection == nil)
    try send(
      hosted ? "Review items" : "Outline viewport", .custom(hosted ? "First item" : "Scroll to top")
    )
    #expect(nodes().contains { $0.label == "Expand item 1 at level 1" })
    #expect(!nodes().contains { $0.label == "Record 0" })
    #expect(
      harness.runLoop.handleAccessibilityAction(.init(target: stale, action: .activate))
        == .staleTarget)
    try send("Expand item 1 at level 1", .activate)
    #expect(nodes().contains { $0.label == "Record 0" })
    #expect(nodes().count < 200 && harness.actionRegistrationCount < 150)
    let items = nodes().filter { $0.role == .custom("listitem") }
    let itemIDs = Set(items.map(\.identity))
    #expect(items.allSatisfy { $0.parentIdentity.map { !itemIDs.contains($0) } ?? true })
  }

  @Test("a reordered background collection cannot reveal through an opening modal")
  func modalRevealScope() throws {
    var ids = Array(0..<100)
    var modal = false
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ModalReview"), size: .init(width: 40, height: 12)
    ) {
      List(ids, id: \.self) { Text("Record \($0)") }
        .sheet(isPresented: Binding(get: { modal }, set: { modal = $0 })) {
          Button("Close modal") { modal = false }
        }
    }
    defer { harness.shutdown() }
    func nodes() -> [AccessibilityNode] {
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes
    }
    func send(_ action: AccessibilityAction) throws {
      let target = try #require(nodes().first { $0.label == "Review items" }?.actionTarget)
      #expect(
        harness.runLoop.handleAccessibilityAction(.init(target: target, action: action))
          == .accepted)
      _ = try harness.render()
    }
    try send(.custom("Last item"))
    try send(.custom("Read item"))
    #expect(nodes().contains { $0.isAccessibilityFocused })
    ids.reverse()
    modal = true
    _ = try harness.renderAfterExternalMutation()
    #expect(!nodes().contains { $0.label == "Review items" })
    modal = false
    _ = try harness.renderAfterExternalMutation()
    #expect(!nodes().contains { $0.label == "Record 99" })
    #expect(!nodes().contains { $0.isAccessibilityFocused })
    try send(.custom("Read item"))
    #expect(nodes().contains { $0.label == "Record 99" })
    #expect(nodes().contains { $0.isAccessibilityFocused && $0.properties?.positionInSet == 1 })
  }

  @Test("named scrolling reaches lazy nested content and leaves the outer viewport and focus alone")
  func nestedScroll() throws {
    var outer = ScrollCellOffset.zero
    var inner = ScrollCellOffset.zero
    var realized = 0
    var activations = 0
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("NestedReview"), size: .init(width: 40, height: 14)
    ) {
      VStack {
        Button("Keep keyboard focus") {}
        ScrollView(.vertical, position: Binding(get: { outer }, set: { outer = $0 })) {
          VStack {
            Text("Outer introduction")
            ScrollView(.vertical, position: Binding(get: { inner }, set: { inner = $0 })) {
              LazyVStack {
                ForEach(0..<10_000, id: \.self) { id in
                  let _ = { realized += 1 }()
                  Button("Inner \(id)") { activations += 1 }
                }
              }
            }.frame(height: 5).accessibilityLabel("Inner records")
            ForEach(0..<30, id: \.self) { Text("Outer \($0)") }
          }
        }.frame(height: 10).accessibilityLabel("Outer records")
      }
    }
    defer { harness.shutdown() }
    func nodes() -> [AccessibilityNode] {
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes
    }
    func send(_ label: String, _ action: AccessibilityAction) throws {
      let target = try #require(nodes().first { $0.label == label }?.actionTarget)
      #expect(
        harness.runLoop.handleAccessibilityAction(.init(target: target, action: action))
          == .accepted)
      _ = try harness.render()
    }
    let keyboardFocus = harness.runLoop.focusTracker.currentFocusIdentity
    #expect(!nodes().contains { $0.label == "Inner 9999" })
    try send("Inner records", .custom("Scroll to bottom"))
    #expect(nodes().contains { $0.label == "Inner 9999" })
    #expect(inner.y > 0 && outer == .zero)
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == keyboardFocus)
    #expect(realized < 200)
    try send("Inner 9999", .activate)
    #expect(activations == 1)
    try send("Inner records", .custom("Scroll to top"))
    #expect(inner == .zero && outer == .zero)
    #expect(nodes().contains { $0.label == "Inner 0" })
    try send("Outer records", .custom("Scroll down one page"))
    #expect(outer.y > 0 && inner == .zero)
  }

  @Test(
    "logical review reveals and operates an unmounted record without selection",
    arguments: [false, true])
  func farRecord(table: Bool) throws {
    var realized = 0
    var activations: [Int] = []
    var selection: Int? = nil
    var selectionWrites = 0
    let binding = Binding(
      get: { selection },
      set: {
        selection = $0
        selectionWrites += 1
      })
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("Offscreen"), size: .init(width: 50, height: 12)
    ) {
      Group {
        if table {
          Table(0..<10_000, id: \.self, selection: binding, columns: [.init("Record")]) { id in
            let _ = { realized += 1 }()
            Button("Inspect \(id)") { activations.append(id) }
          }
        } else {
          List(0..<10_000, id: \.self, selection: binding) { id in
            let _ = { realized += 1 }()
            Button("Inspect \(id)") { activations.append(id) }
          }
        }
      }
    }
    defer { harness.shutdown() }
    func nodes() -> [AccessibilityNode] {
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes
    }
    func target(_ label: String) throws -> String {
      try #require(nodes().first { $0.label == label }?.actionTarget)
    }
    func send(_ label: String, _ action: AccessibilityAction) throws {
      #expect(
        harness.runLoop.handleAccessibilityAction(.init(target: try target(label), action: action))
          == .accepted)
      _ = try harness.render()
    }
    let firstTarget = try target("Inspect 0")
    #expect(!nodes().contains { $0.label == "Inspect 9999" })
    #expect(realized < 100)
    let before = realized
    try send("Review items", .setValue(.number(10_000)))
    #expect(nodes().contains { $0.label == "Inspect 9999" })
    #expect(realized - before < 100)
    #expect(selection == nil && selectionWrites == 0)
    let keyboardFocus = harness.runLoop.focusTracker.currentFocusIdentity
    try send("Review items", .custom("Read item"))
    let reviewed = try #require(nodes().first { $0.isAccessibilityFocused })
    #expect(
      table ? reviewed.properties?.rowIndex == 10_001 : reviewed.properties?.positionInSet == 10_000
    )
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == keyboardFocus)
    try send("Inspect 9999", .activate)
    #expect(activations == [9999])
    let farTarget = try target("Inspect 9999")
    try send("Review items", .custom("Return to previous item"))
    #expect(nodes().contains { $0.label == "Inspect 0" })
    #expect(
      harness.runLoop.handleAccessibilityAction(.init(target: farTarget, action: .activate))
        == .staleTarget)
    #expect(
      harness.runLoop.handleAccessibilityAction(.init(target: firstTarget, action: .activate))
        == .staleTarget)
    try send("Inspect 0", .activate)
    #expect(activations == [9999, 0])
    #expect(selection == nil && selectionWrites == 0)
    #expect(nodes().count < 150)
    #expect(harness.actionRegistrationCount < 150)
  }

  @Test("review tracks logical identity across reorder and retires stale ordinal requests")
  func reorder() throws {
    var ids = Array(0..<100)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ReviewReorder"), size: .init(width: 30, height: 8)
    ) {
      List(ids, id: \.self) { Text("Record \($0)") }
    }
    defer { harness.shutdown() }
    func nodes() -> [AccessibilityNode] {
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes
    }
    func navigator() throws -> AccessibilityNode {
      try #require(nodes().first { $0.label == "Review items" })
    }
    func send(_ action: AccessibilityAction) throws {
      let current = try navigator()
      let target = try #require(current.actionTarget)
      #expect(
        harness.runLoop.handleAccessibilityAction(.init(target: target, action: action))
          == .accepted)
      _ = try harness.render()
    }
    try send(.setValue(.number(100)))
    try send(.custom("Read item"))
    #expect(nodes().contains { $0.isAccessibilityFocused && $0.properties?.positionInSet == 100 })
    let current = try navigator()
    let stale = try #require(current.actionTarget)
    ids.reverse()
    _ = try harness.renderAfterExternalMutation()
    #expect(try navigator().control?.value == .number(1))
    #expect(nodes().contains { $0.label == "Record 99" })
    #expect(nodes().contains { $0.isAccessibilityFocused && $0.properties?.positionInSet == 1 })
    #expect(
      harness.runLoop.handleAccessibilityAction(
        .init(target: stale, action: .setValue(.number(50)))) == .staleTarget)
    ids.removeFirst()
    _ = try harness.renderAfterExternalMutation()
    #expect(try navigator().control?.maximum == 99)
    #expect(nodes().contains { $0.label == "Record 98" })
    #expect(!nodes().contains { $0.label == "Record 99" })
    #expect(nodes().contains { $0.isAccessibilityFocused && $0.properties?.positionInSet == 1 })
  }
}

private struct OffscreenFocusPriorityFixture: View {
  @State private var ids = Array(0..<100)
  @AccessibilityFocusState private var heading: Bool
  var body: some View {
    VStack {
      List(ids, id: \.self) { Text("Record \($0)") }.frame(height: 8)
      Text("Requested heading").accessibilityFocused($heading)
      Button("Reorder and read heading") {
        ids.reverse()
        heading = true
      }
    }
  }
}
