@_spi(Testing) import SwiftTUITestSupport
// Adversarial set B, pass 4: navigation views and builder control flow
// (391–400).
//
// The navigation guide fixes the contract: the bound data is the whole
// story, Escape pops exactly one value, the visible surface supplies the
// title, and a push that cannot be served fails loud. Tabs are declared
// structurally and discovered by peeking, and the register promises that
// exclusion from a tab is never silent. These probes mix the Boolean and
// typed forms on one stack, pop past the depth limit, push beneath a titled
// root with toolbar items, register one type at two depths, wrap a Tab in an
// opaque body, declare tabs through ForEach, scroll inside a dormant tab,
// and pin the builder artifacts that resolve to nothing.
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: navigation and builder control flow", .serialized)
struct AdversarialSetBNavigationTests {
  private func harness<V: View>(
    _ name: String, width: Int = 48, height: Int = 12, @ViewBuilder content: @escaping () -> V
  ) throws -> StressRuntimeHarness<V> {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBNavigation", name), size: .init(width: width, height: height),
      content: content)
  }

  // A Boolean destination declared on the root pushes even while the typed
  // path holds values; the stack must not ignore the activation silently.
  @Test func setB391RootBooleanDestinationPushesWhileTypedPathIsActive() throws {
    let h = try harness("MixedForms") { SetBMixedFormsStack() }
    defer { h.shutdown() }
    _ = try h.clickText("Push")
    try #require(h.frame.contains("typed 1"), "\(h.frame)")
    _ = try h.clickText("Flag")
    let codes = h.runLoop.renderer.viewGraph.frameRuntimeIssues.map(\.code)
    do {
      #expect(h.frame.contains("flag dest"), "\(h.frame)")
      #expect(!codes.contains("navigation.missingValueDestination"), "\(codes)")
    }
    _ = try h.clickText("Pop")
    #expect(h.frame.contains("flag dest"), "the binding is still true: \(h.frame)")
    #expect(!h.frame.contains("typed 1"), "\(h.frame)")
  }

  // A typed path deeper than the 32-destination safety limit reports the
  // depth-limit issue, and Escape then pops exactly one path value.
  @Test func setB392EscapeBeyondTheDepthLimitPopsOneValue() throws {
    let h = try harness("DeepPath", width: 40, height: 6) { SetBDeepPathStack() }
    defer { h.shutdown() }
    try #require(h.frame.contains("d 32 of 34"), "\(h.frame)")
    let codes = h.runLoop.renderer.viewGraph.frameRuntimeIssues.map(\.code)
    let staticCodes = DefaultRenderer().render(
      SetBDeepPathStack(),
      context: .init(identity: testIdentity("SetBNavigation", "DeepPathStatic")),
      proposal: .init(width: 40, height: 6)
    ).diagnostics.runtime.issues.map(\.code)
    #expect(staticCodes.contains("navigation.depthLimitExceeded"), "\(staticCodes)")
    do {
      #expect(codes.contains("navigation.depthLimitExceeded"), "\(codes)")
    }
    _ = try h.pressKey(KeyPress(.escape))
    do {
      #expect(h.frame.contains("d 32 of 33"), "\(h.frame)")
    }
    #expect(!h.frame.contains("of 34"), "\(h.frame)")
  }

  // A pushed destination without its own navigationTitle shows no title: the
  // root's title does not leak onto it, and a destination title replaces it.
  @Test func setB393RootNavigationTitleDoesNotLeakOntoAnUntitledDestination() {
    func lines(_ name: String, titled: Bool) -> String {
      DefaultRenderer().render(
        setBTitledStack(titled: titled).toolbar().toolbarStyle(DefaultTopToolbarStyle()),
        context: .init(identity: testIdentity("SetBNavigation", name)),
        proposal: .init(width: 40, height: 8)
      ).rasterSurface.lines.joined(separator: "\n")
    }
    let titled = lines("TitleTitled", titled: true)
    #expect(titled.contains("DestTitle"), "\(titled)")
    #expect(!titled.contains("RootTitle"), "\(titled)")
    let untitled = lines("TitleUntitled", titled: false)
    #expect(untitled.contains("dest 1"), "\(untitled)")
    do {
      #expect(!untitled.contains("RootTitle"), "\(untitled)")
    }
  }

  // Toolbar items contributed by the root belong to the root surface; the
  // strip above a pushed destination shows the destination's items only.
  @Test func setB394RootToolbarItemsLeaveTheStripWhileADestinationIsPushed() {
    let frame = DefaultRenderer().render(
      setBToolbarItemStack().toolbar().toolbarStyle(DefaultTopToolbarStyle()),
      context: .init(identity: testIdentity("SetBNavigation", "ToolbarLeak")),
      proposal: .init(width: 40, height: 8)
    ).rasterSurface.lines.joined(separator: "\n")
    #expect(frame.contains("DestItem"), "\(frame)")
    #expect(frame.contains("dest 1"), "\(frame)")
    #expect(!frame.contains("RootItem"), "\(frame)")
  }

  // When the root and a pushed destination both register a destination for
  // one type, the declaration closest to the root serves deeper values.
  @Test func setB395RootDeclarationWinsOverANestedSameTypeDeclaration() {
    let frame = DefaultRenderer().render(
      NavigationStack(path: .constant([1, 2])) {
        Text("root").navigationDestination(for: Int.self) { n in
          Text("root-dest \(n)")
            .navigationDestination(for: Int.self) { Text("inner-dest \($0)") }
        }
      },
      context: .init(identity: testIdentity("SetBNavigation", "NestedWins")),
      proposal: .init(width: 40, height: 6)
    ).rasterSurface.lines.joined(separator: "\n")
    #expect(frame.contains("-dest 2"), "\(frame)")
    do {
      #expect(frame.contains("root-dest 2"), "\(frame)")
    }
  }

  // A custom view whose body is a Tab is either discovered as a tab or
  // reported; it must not vanish silently while its sibling keeps its slot.
  @Test func setB396ACustomViewWrappingATabIsDiscoveredOrReported() {
    let snapshot = DefaultRenderer().render(
      TabView(selection: .constant("alpha")) {
        SetBWrappedTab()
        Tab("Beta", value: "beta") { Text("beta body") }
      }
      .tabViewStyle(.literalTabs),
      context: .init(identity: testIdentity("SetBNavigation", "WrappedTab")),
      proposal: .init(width: 32, height: 6)
    )
    let frame = snapshot.rasterSurface.lines.joined(separator: "\n")
    let codes = snapshot.diagnostics.runtime.issues.map(\.code)
    #expect(frame.contains("Beta"), "\(frame)")
    #expect(frame.contains("beta body"), "\(frame)")
    do {
      #expect(
        frame.contains("Alpha")
          || codes.contains { $0.hasPrefix("tab.") || $0.hasPrefix("structure.") }, "\(codes)")
    }
  }

  // Tabs declared through a ForEach are discovered by position: each
  // iteration's Tab supplies its label and tag, and selection resolves.
  @Test func setB397ForEachDeclaredTabsAreDiscovered() throws {
    let h = try harness("ForEachTabs", width: 40, height: 8) { SetBForEachTabs() }
    defer { h.shutdown() }
    #expect(h.frame.contains("One") && h.frame.contains("Two"), "\(h.frame)")
    #expect(h.frame.contains("one body"), "\(h.frame)")
    _ = try h.clickText("Go Three")
    #expect(h.frame.contains("three body"), "\(h.frame)")
    #expect(!h.frame.contains("one body"), "\(h.frame)")
    let codes = h.runLoop.renderer.viewGraph.frameRuntimeIssues.map(\.code)
    #expect(!codes.contains { $0.hasPrefix("tab.") || $0.hasPrefix("structure.") }, "\(codes)")
  }

  // A plain ScrollView's offset inside a deselected tab is archived with the
  // tab's state and restored when the tab returns.
  @Test func setB398ScrollOffsetSurvivesTabDormancy() throws {
    let h = try harness("DormantScroll", width: 40, height: 10) { SetBDormantScroll() }
    defer { h.shutdown() }
    try #require(h.frame.contains("line 0"), "\(h.frame)")
    let point = try #require(h.point(forText: "line 1"))
    _ = try h.scrollPointer(at: point, deltaY: 3)
    try #require(h.frame.contains("line 3") && !h.frame.contains("line 0"), "\(h.frame)")
    _ = try h.clickText("Go Beta")
    try #require(h.frame.contains("beta body"), "\(h.frame)")
    _ = try h.clickText("Go Alpha")
    #expect(h.frame.contains("line 3"), "\(h.frame)")
    #expect(!h.frame.contains("line 0"), "\(h.frame)")
  }

  // Builder artifacts that resolve to nothing consume no stack spacing, and
  // a twelve-element TupleView contributes all twelve children.
  @Test func setB399EmptyBuilderArtifactsConsumeNoSpacing() throws {
    let lines = DefaultRenderer().render(
      SetBEmptyArtifacts(hidden: false),
      context: .init(identity: testIdentity("SetBNavigation", "Empties")),
      proposal: .init(width: 20, height: 6)
    ).rasterSurface.lines
    try #require(lines.count >= 3, "\(lines)")
    #expect(lines[0].contains("alpha"), "\(lines)")
    #expect(lines[1].allSatisfy { $0 == " " }, "\(lines)")
    #expect(lines[2].contains("omega"), "\(lines)")
    let twelve = DefaultRenderer().render(
      SetBTwelveChildren(),
      context: .init(identity: testIdentity("SetBNavigation", "Twelve")),
      proposal: .init(width: 10, height: 14)
    ).rasterSurface.lines
    #expect(twelve.filter { !$0.isEmpty }.count == 12, "\(twelve)")
    #expect((1...12).allSatisfy { n in twelve.contains { $0 == "c\(n)" } }, "\(twelve)")
  }

  // An `if #available` branch (buildLimitedAvailability, an erased AnyView)
  // keeps its @State across re-evaluations caused by a sibling's state.
  @Test func setB400AvailabilityBranchKeepsStateAcrossSiblingUpdates() throws {
    let h = try harness("Availability", width: 40, height: 8) { SetBAvailabilityRoot() }
    defer { h.shutdown() }
    try #require(h.frame.contains("avail Count 0"), "\(h.frame)")
    _ = try h.clickText("avail Increment")
    _ = try h.clickText("avail Increment")
    try #require(h.frame.contains("avail Count 2"), "\(h.frame)")
    _ = try h.clickText("Bump")
    #expect(h.frame.contains("other 1"), "\(h.frame)")
    #expect(h.frame.contains("avail Count 2"), "\(h.frame)")
    #expect(h.runLoop.renderer.viewGraph.debugTeardownCoherenceViolation() == nil)
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
private struct SetBMixedFormsStack: View {
  @State private var path: [Int] = []
  @State private var flag = false

  var body: some View {
    NavigationStack(path: $path) {
      VStack(alignment: .leading, spacing: 0) {
        Text("root")
        Button("Push") { path = [1] }
      }
      .navigationDestination(for: Int.self) { n in
        VStack(alignment: .leading, spacing: 0) {
          Text("typed \(n)")
          Button("Flag") { flag = true }
          Button("Pop") { path = [] }
        }
      }
      .navigationDestination(isPresented: $flag) {
        VStack {
          Text("flag dest").focusable()
          Button("Pop") { path = [] }
        }
      }
    }
  }
}

@MainActor
private struct SetBDeepPathStack: View {
  @State private var path = Array(1...34)

  var body: some View {
    NavigationStack(path: $path) {
      Text("deep root")
        .navigationDestination(for: Int.self) { n in
          Text("d \(n) of \(path.count)")
        }
    }
  }
}

private struct SetBOptionalTitle: View {
  let text: String
  let title: String?

  var body: some View {
    if let title {
      Text(text).navigationTitle(title)
    } else {
      Text(text)
    }
  }
}

@MainActor
private func setBTitledStack(titled: Bool) -> some View & ActionScope {
  NavigationStack(path: .constant([1])) {
    Text("root").navigationTitle("RootTitle")
      .navigationDestination(for: Int.self) { n in
        SetBOptionalTitle(text: "dest \(n)", title: titled ? "DestTitle" : nil)
      }
  }
}

@MainActor
private func setBToolbarItemStack() -> some View & ActionScope {
  NavigationStack(path: .constant([1])) {
    Text("root")
      .toolbarItem(.init(title: "RootItem") {})
      .navigationDestination(for: Int.self) { n in
        Text("dest \(n)").toolbarItem(.init(title: "DestItem") {})
      }
  }
}

@MainActor
private struct SetBWrappedTab: View {
  var body: some View {
    Tab("Alpha", value: "alpha") { Text("alpha body") }
  }
}

private struct SetBTabSpec: Sendable {
  let value: String
  let label: String
}

@MainActor
private struct SetBForEachTabs: View {
  @State private var selection = "one"
  private let specs = [
    SetBTabSpec(value: "one", label: "One"),
    SetBTabSpec(value: "two", label: "Two"),
    SetBTabSpec(value: "three", label: "Three"),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Go Three") { selection = "three" }
      TabView(selection: $selection) {
        ForEach(specs, id: \.value) { spec in
          Tab(spec.label, value: spec.value) { Text("\(spec.value) body") }
        }
      }
      .tabViewStyle(.literalTabs)
    }
  }
}

@MainActor
private struct SetBDormantScroll: View {
  @State private var selection = "alpha"

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Button("Go Alpha") { selection = "alpha" }
        Button("Go Beta") { selection = "beta" }
      }
      TabView(selection: $selection) {
        Tab("Alpha", value: "alpha") {
          ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
              ForEach(0..<20, id: \.self) { row in Text("line \(row)") }
            }
          }
          .scrollIndicators(.hidden)
          .frame(width: 20, height: 4)
        }
        Tab("Beta", value: "beta") { Text("beta body") }
      }
      .tabViewStyle(.literalTabs)
    }
  }
}

private struct SetBEmptyArtifacts: View {
  let hidden: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("alpha")
      EmptyView()
      if hidden {
        Text("hidden")
      }
      Group {}
      if hidden {
        Text("never")
      } else {
        EmptyView()
      }
      Text("omega")
    }
  }
}

private struct SetBTwelveChildren: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("c1")
      Text("c2")
      Text("c3")
      Text("c4")
      Text("c5")
      Text("c6")
      Text("c7")
      Text("c8")
      Text("c9")
      Text("c10")
      Text("c11")
      Text("c12")
    }
  }
}

@MainActor
private struct SetBAvailabilityRoot: View {
  @State private var other = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if #available(macOS 16, iOS 19, *) {
        SetBCounter(label: "avail")
      } else {
        Text("unavailable")
      }
      Text("other \(other)")
      Button("Bump") { other += 1 }
    }
  }
}
