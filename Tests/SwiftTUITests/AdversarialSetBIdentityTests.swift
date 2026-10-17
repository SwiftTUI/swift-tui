@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Adversarial set B, identity and state (061–070). Motivated by the October
// 2026 reports where structural position and authored identity disagreed after
// churn: destination state leaking across sibling modifiers, ForEach rows
// losing state in dormant tabs, and key handlers mutating identity mid-frame.
// SwiftUI semantics are the oracle: state follows identity, never position.
@MainActor
@Suite("Adversarial set B: identity and state", .serialized)
struct AdversarialSetBIdentityTests {
  @Test func setB061DoubleIDFlipInOneActionIsANoOp() throws {
    let h = try harness("Flip") { SetBFlipRows() }
    defer { h.shutdown() }
    _ = try h.clickText("row1 Increment")
    _ = try h.clickText("row1 Increment")
    _ = try h.clickText("Double flip")
    do {
      #expect(h.frame.contains("row1 Count 2"), "\(h.frame)")
    }
    #expect(h.frame.contains("row0 Count 0"), "\(h.frame)")
    #expect(h.runLoop.renderer.viewGraph.debugTeardownCoherenceViolation() == nil)
    _ = try h.clickText("Single flip")
    #expect(h.frame.contains("row1 Count 0"), "\(h.frame)")
  }

  @Test func setB062ReorderInsideDormantTabFollowsIdentity() throws {
    let h = try harness("DormantReorder") { SetBDormantReorder() }
    defer { h.shutdown() }
    _ = try h.clickText("r1 Increment")
    _ = try h.clickText("r1 Increment")
    _ = try h.clickText("r2 Increment")
    _ = try h.clickText("Go B")
    try #require(h.frame.contains("B body"), "\(h.frame)")
    _ = try h.clickText("Reverse")
    _ = try h.clickText("Go A")
    let frame = h.frame
    let r2 = try #require(frame.firstRange(of: "r2 Count 1"), "\(frame)")
    let r1 = try #require(frame.firstRange(of: "r1 Count 2"), "\(frame)")
    #expect(r2.lowerBound < r1.lowerBound, "\(frame)")
  }

  @Test func setB063SameTypeBranchFlipInsideDestinationIsADistinctIdentity() throws {
    let h = try harness("BranchFlip") { SetBBranchFlipStack() }
    defer { h.shutdown() }
    _ = try h.clickText("Push")
    _ = try h.clickText("Outer +")
    _ = try h.clickText("inner Increment")
    _ = try h.clickText("inner Increment")
    try #require(h.frame.contains("inner Count 2"), "\(h.frame)")
    _ = try h.clickText("Flip")
    #expect(h.frame.contains("inner Count 0"), "\(h.frame)")
    #expect(h.frame.contains("outer 1"), "\(h.frame)")
    _ = try h.clickText("Flip")
    #expect(h.frame.contains("inner Count 0"), "\(h.frame)")
    #expect(h.frame.contains("outer 1"), "\(h.frame)")
  }

  @Test func setB064SiblingBooleanDestinationsOfOneTypeStartFresh() throws {
    let h = try harness("SiblingDestinations") { SetBSiblingDestinations() }
    defer { h.shutdown() }
    let baseline = h.actionRegistrationCount
    _ = try h.clickText("Open A")
    for _ in 0..<3 { _ = try h.clickText("D Increment") }
    try #require(h.frame.contains("D Count 3"), "\(h.frame)")
    _ = try h.pressKey(KeyPress(.escape))
    #expect(!h.frame.contains("D Count"), "\(h.frame)")
    #expect(h.actionRegistrationCount == baseline)
    _ = try h.clickText("Open B")
    #expect(h.frame.contains("D Count 0"), "\(h.frame)")
    _ = try h.pressKey(KeyPress(.escape))
    #expect(h.actionRegistrationCount == baseline)
    _ = try h.clickText("Open A")
    #expect(h.frame.contains("D Count 0"), "\(h.frame)")
  }

  @Test func setB065EqualPathReassignmentKeepsStateButPopPushResets() throws {
    let h = try harness("TypedPath") { SetBTypedPath() }
    defer { h.shutdown() }
    _ = try h.clickText("Push 1")
    _ = try h.clickText("P Increment")
    _ = try h.clickText("P Increment")
    _ = try h.clickText("Reassign")
    #expect(h.frame.contains("P Count 2"), "\(h.frame)")
    _ = try h.clickText("Pop")
    try #require(!h.frame.contains("P Count"), "\(h.frame)")
    _ = try h.clickText("Push 1")
    #expect(h.frame.contains("P Count 0"), "\(h.frame)")
    _ = try h.clickText("P Increment")
    _ = try h.clickText("Swap")
    #expect(h.frame.contains("P Count 0"), "\(h.frame)")
    #expect(h.frame.contains("detail 2"), "\(h.frame)")
  }

  @Test func setB066SiblingNavigationStacksPopIndependently() throws {
    let h = try harness("TwoStacks") { SetBTwoStacks() }
    defer { h.shutdown() }
    _ = try h.clickText("L push")
    _ = try h.clickText("L Increment")
    _ = try h.clickText("L Increment")
    _ = try h.clickText("R push")
    try #require(h.frame.contains("R dest"), "\(h.frame)")
    _ = try h.focusText("R dest")
    _ = try h.pressKey(KeyPress(.escape))
    #expect(!h.frame.contains("R dest"), "\(h.frame)")
    #expect(h.frame.contains("L Count 2"), "\(h.frame)")
    #expect(h.frame.contains("left 1"), "\(h.frame)")
    #expect(h.frame.contains("right 0"), "\(h.frame)")
  }

  @Test func setB067AbsentTabSelectionKeepsTheOtherTabsState() throws {
    let h = try harness("AbsentTab") { SetBAbsentTab() }
    defer { h.shutdown() }
    _ = try h.clickText("Go b")
    _ = try h.clickText("b Increment")
    _ = try h.clickText("b Increment")
    try #require(h.frame.contains("b Count 2"), "\(h.frame)")
    _ = try h.clickText("Vanish")
    #expect(h.runLoop.renderer.viewGraph.debugTeardownCoherenceViolation() == nil)
    #expect(h.frame.contains("selection zzz"), "\(h.frame)")
    _ = try h.clickText("Back b")
    #expect(h.frame.contains("b Count 2"), "\(h.frame)")
  }

  @Test func setB068SheetRepresentationStartsFreshAtTheSameRegistrationFootprint() throws {
    let h = try harness("Sheet") { SetBSheet() }
    defer { h.shutdown() }
    _ = try h.clickText("Open Sheet")
    let actions = h.actionRegistrationCount
    let regions = h.focusRegionCount
    let modal = h.focusModalRestorationStackCount
    _ = try h.clickText("S Increment")
    _ = try h.clickText("S Increment")
    try #require(h.frame.contains("S Count 2"), "\(h.frame)")
    _ = try h.clickText("Close Sheet", chooseLast: true)
    try #require(!h.frame.contains("S Count"), "\(h.frame)")
    _ = try h.clickText("Open Sheet")
    #expect(h.frame.contains("S Count 0"), "\(h.frame)")
    #expect(h.actionRegistrationCount == actions)
    #expect(h.focusRegionCount == regions)
    #expect(h.focusModalRestorationStackCount == modal)
  }

  @Test func setB069TaskIDInsideADestinationSurvivesRegenerationAndPopPush() throws {
    let h = try harness("DestinationTask") { SetBDestinationTask() }
    defer { h.shutdown() }
    #expect(h.activeTaskCount == 0)
    _ = try h.clickText("Push")
    #expect(h.activeTaskCount == 1)
    for _ in 0..<3 {
      _ = try h.clickText("Regen")
      #expect(h.activeTaskCount == 1)
      #expect(h.runLoop.lifecycleCoordinator.taskStartSupersededCount == 0)
    }
    _ = try h.clickText("Pop")
    #expect(h.activeTaskCount == 0)
    _ = try h.clickText("Push")
    #expect(h.activeTaskCount == 1)
    #expect(h.frame.contains("dest 0"), "\(h.frame)")
  }

  @Test func setB070KeyCommandDoubleToggleInOneDispatchKeepsTheBranch() throws {
    let h = try harness("DoubleToggle") { SetBDoubleToggle() }
    defer { h.shutdown() }
    _ = try h.clickText("K Increment")
    _ = try h.clickText("K Increment")
    _ = try h.pressKey(KeyPress(.character("t"), modifiers: .ctrl))
    #expect(h.frame.contains("K Count 2"), "\(h.frame)")
    _ = try h.pressKey(KeyPress(.character("o"), modifiers: .ctrl))
    #expect(h.frame.contains("gone"), "\(h.frame)")
    #expect(!h.frame.contains("K Count"), "\(h.frame)")
    _ = try h.pressKey(KeyPress(.character("o"), modifiers: .ctrl))
    #expect(h.frame.contains("K Count 0"), "\(h.frame)")
  }

  private func harness<V: View>(
    _ name: String, @ViewBuilder content: @escaping () -> V
  ) throws -> StressRuntimeHarness<V> {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBIdentity", name), size: .init(width: 64, height: 14),
      content: content)
  }
}

private struct SetBCounter: View {
  let label: String
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("\(label) Count \(count)")
      Button("\(label) Increment") { count += 1 }
    }
  }
}

@MainActor
private struct SetBFlipRows: View {
  @State private var flips = [false, false]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(0..<2, id: \.self) { index in
        SetBCounter(label: "row\(index)").id("row-\(index)-\(flips[index])")
      }
      Button("Double flip") {
        flips[1].toggle()
        flips[1].toggle()
      }
      Button("Single flip") { flips[1].toggle() }
    }
  }
}

@MainActor
private struct SetBDormantReorder: View {
  @State private var selection = "a"
  @State private var order = [1, 2]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Button("Go A") { selection = "a" }
        Button("Go B") { selection = "b" }
        Button("Reverse") { order.reverse() }
      }
      TabView(selection: $selection) {
        Tab("A", value: "a") {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(order, id: \.self) { row in
              SetBCounter(label: "r\(row)")
            }
          }
        }
        Tab("B", value: "b") {
          Text("B body")
        }
      }
      .tabViewStyle(.literalTabs)
    }
  }
}

private enum SetBRoute: Hashable, Sendable {
  case detail(Int)

  var value: Int {
    switch self {
    case .detail(let value): value
    }
  }
}

@MainActor
private struct SetBBranchFlipStack: View {
  @State private var path: [SetBRoute] = []

  var body: some View {
    NavigationStack(path: $path) {
      Button("Push") { path = [.detail(1)] }
        .navigationDestination(for: SetBRoute.self) { _ in
          SetBBranchFlipDestination()
        }
    }
  }
}

@MainActor
private struct SetBBranchFlipDestination: View {
  @State private var outer = 0
  @State private var flag = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("outer \(outer)")
      Button("Outer +") { outer += 1 }
      Button("Flip") { flag.toggle() }
      if flag {
        SetBCounter(label: "inner")
      } else {
        SetBCounter(label: "inner")
      }
    }
  }
}

@MainActor
private struct SetBSiblingDestinations: View {
  @State private var a = false
  @State private var b = false

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 0) {
        Button("Open A") { a = true }
        Button("Open B") { b = true }
        Text("src")
          .navigationDestination(isPresented: $a) { SetBCounter(label: "D") }
          .navigationDestination(isPresented: $b) { SetBCounter(label: "D") }
      }
    }
  }
}

@MainActor
private struct SetBTypedPath: View {
  @State private var path: [SetBRoute] = []

  var body: some View {
    NavigationStack(path: $path) {
      VStack(alignment: .leading, spacing: 0) {
        Text("typed root")
        Button("Push 1") { path.append(.detail(1)) }
      }
      .navigationDestination(for: SetBRoute.self) { route in
        VStack(alignment: .leading, spacing: 0) {
          Text("detail \(route.value)")
          SetBCounter(label: "P")
          Button("Reassign") { path = [.detail(1)] }
          Button("Swap") { path = [.detail(2)] }
          Button("Pop") { path.removeLast() }
        }
      }
    }
  }
}

@MainActor
private struct SetBTwoStacks: View {
  @State private var left: [Int] = []
  @State private var right: [Int] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("left \(left.count) right \(right.count)")
      HStack(alignment: .top, spacing: 2) {
        NavigationStack(path: $left) {
          Button("L push") { left = [1] }
            .navigationDestination(for: Int.self) { _ in SetBCounter(label: "L") }
        }
        .frame(width: 28, alignment: .topLeading)
        NavigationStack(path: $right) {
          Button("R push") { right = [1] }
            .navigationDestination(for: Int.self) { _ in Text("R dest").focusable() }
        }
        .frame(width: 28, alignment: .topLeading)
      }
    }
  }
}

@MainActor
private struct SetBAbsentTab: View {
  @State private var selection = "a"

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("selection \(selection)")
      HStack {
        Button("Go b") { selection = "b" }
        Button("Vanish") { selection = "zzz" }
        Button("Back b") { selection = "b" }
      }
      TabView(selection: $selection) {
        Tab("A", value: "a") { SetBCounter(label: "a") }
        Tab("B", value: "b") { SetBCounter(label: "b") }
      }
      .tabViewStyle(.literalTabs)
    }
  }
}

@MainActor
private struct SetBSheet: View {
  @State private var presented = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("root")
      Button("Open Sheet") { presented = true }
    }
    .sheet("Set B Sheet", isPresented: $presented) {
      VStack(alignment: .leading, spacing: 0) {
        SetBCounter(label: "S")
        Button("Close Sheet") { presented = false }
      }
    }
  }
}

@MainActor
private struct SetBDestinationTask: View {
  @State private var path: [SetBRoute] = []

  var body: some View {
    NavigationStack(path: $path) {
      Button("Push") { path = [.detail(1)] }
        .navigationDestination(for: SetBRoute.self) { _ in
          SetBTaskDestination(pop: { path.removeAll() })
        }
    }
  }
}

@MainActor
private struct SetBTaskDestination: View {
  let pop: @MainActor () -> Void
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("dest \(generation)")
        .task(id: generation) {
          await suspendUntilCancelled()
        }
      Button("Regen") { generation += 1 }
      Button("Pop", action: pop)
    }
  }
}

@MainActor
private struct SetBDoubleToggle: View {
  @State private var show = true

  var body: some View {
    Panel(id: "setb-double-toggle") {
      if show {
        SetBCounter(label: "K")
      } else {
        Text("gone")
      }
    }
    .keyCommand("twice", key: .character("t"), modifiers: .ctrl) {
      show.toggle()
      show.toggle()
    }
    .keyCommand("once", key: .character("o"), modifiers: .ctrl) {
      show.toggle()
    }
  }
}
