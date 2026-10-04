import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct CompositeAccessibilityTests {
  @Test(
    "logical tabs preserve selection, retained state, relationships and target lifetimes",
    arguments: [0, 1, 2, 3])
  func tabs(style: Int) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("AccessibleTabs"),
      size: .init(width: 40, height: 16)
    ) { AccessibleTabsFixture(style: style) }
    defer { harness.shutdown() }
    var frames = 0
    func nodes() -> [AccessibilityNode] {
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes
    }
    func node(_ label: String) throws -> AccessibilityNode {
      try #require(
        nodes().first { $0.label == label },
        "Missing: \(label); labels: \(nodes().compactMap(\.label))")
    }
    func send(_ label: String) throws {
      let target = try #require(node(label).actionTarget)
      #expect(
        harness.runLoop.handleAccessibilityAction(.init(target: target, action: .activate))
          == .accepted)
      try harness.runLoop.renderPendingFrames(renderedFrames: &frames)
    }
    let tabs = nodes().filter { $0.role == .tab }
    #expect(tabs.map(\.label) == ["Home", "Settings", "Activity"])
    #expect(tabs.map { $0.properties?.selected } == [true, false, false])
    #expect(nodes().filter { $0.label == "Home" }.count == 1)
    let panel = try #require(nodes().first { $0.role == .tabPanel })
    #expect(tabs.allSatisfy { $0.properties?.controls == [panel.identity] })
    #expect(panel.properties?.labelledBy == [tabs[0].identity])
    var ancestor = try node("Increment local").parentIdentity
    var ancestors: Set<Identity> = []
    while let identity = ancestor, ancestors.insert(identity).inserted {
      ancestor = nodes().first { $0.identity == identity }?.parentIdentity
    }
    #expect(ancestors.contains(panel.identity))
    try send("Increment local")
    #expect(try node("Local 1").role == .group)
    try send("Settings")
    #expect(try node("Writes 1").role == .group)
    #expect(try node("Selection settings").role == .group)
    #expect(!nodes().contains { $0.label == "Local 1" })
    #expect(try node("Settings").properties?.selected == true)
    let retired = try #require(node("Settings").actionTarget)
    try send("Settings")
    #expect(try node("Writes 1").role == .group)
    try send("Home")
    #expect(try node("Local 1").role == .group)
    try send("Remove settings")
    #expect(!nodes().contains { $0.role == .tab && $0.label == "Settings" })
    #expect(
      harness.runLoop.handleAccessibilityAction(.init(target: retired, action: .activate))
        == .staleTarget)
    try send("Restore settings")
    #expect(try node("Settings").actionTarget != retired)
    try send("Disable tabs")
    let target = try #require(node("Activity").actionTarget)
    #expect(
      harness.runLoop.handleAccessibilityAction(.init(target: target, action: .activate))
        == .disabled)
  }
  @Test("changing built-in tab layout preserves selected and dormant authored state")
  func tabStyleChanges() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("AccessibleTabStyleChange"),
      size: .init(width: 40, height: 20)
    ) { ChangingAccessibleTabStyleFixture() }
    defer { harness.shutdown() }
    var frames = 0
    func node(_ label: String) throws -> AccessibilityNode {
      try #require(
        harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
          $0.label == label
        },
        "Missing \(label); labels \(harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.compactMap(\.label))"
      )
    }
    func send(_ label: String) throws {
      let target = try #require(node(label).actionTarget)
      let result = harness.runLoop.handleAccessibilityAction(
        .init(target: target, action: .activate))
      #expect(result == .accepted, "Action \(label) on \(target): \(result)")
      try harness.runLoop.renderPendingFrames(renderedFrames: &frames)
    }
    for count in 1...8 {
      try send("Increment local")
      #expect(try node("Local \(count)").role == .group)
      try send("Settings")
      try send("Home")
      #expect(try node("Local \(count)").role == .group)
      try send("Next style")
      #expect(try node("Local \(count)").role == .group)
    }
  }
  @Test(
    "menu and disclosure triggers expose expanded content without nested buttons",
    arguments: [0, 1, 2, 3])
  func expansion(style: Int) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("AccessibleExpansion"),
      size: .init(width: 60, height: 24)
    ) { AccessibleExpansionFixture(style: style) }
    defer { harness.shutdown() }
    var frames = 0
    func nodes() -> [AccessibilityNode] {
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes
    }
    func node(_ label: String) throws -> AccessibilityNode {
      try #require(
        nodes().first { $0.label == label },
        "Missing: \(label); labels: \(nodes().compactMap(\.label))")
    }
    func send(_ label: String, action: AccessibilityAction = .activate) throws {
      let target = try #require(node(label).actionTarget)
      #expect(
        harness.runLoop.handleAccessibilityAction(.init(target: target, action: action))
          == .accepted)
      try harness.runLoop.renderPendingFrames(renderedFrames: &frames)
    }
    let closed = try node("Commands")
    #expect(closed.role == .button)
    #expect(closed.properties?.expanded == false)
    #expect(closed.properties?.popup == .menu)
    #expect(!nodes().contains { $0.label == "Count command" })
    try send("Commands")
    let open = try node("Commands")
    #expect(open.properties?.expanded == true)
    let menu = try #require(nodes().first { $0.role == .menu })
    #expect(open.properties?.controls == [menu.identity])
    #expect(menu.properties?.labelledBy == [open.identity])
    #expect(try node("Count command").role == .menuItem)
    try send("Count command")
    #expect(try node("Writes 1").role == .group)
    try send("Commands")
    #expect(!nodes().contains { $0.label == "Count command" })
    #expect(try node("Details").properties?.expanded == false)
    try send("Details", action: .setValue(.boolean(true)))
    #expect(try node("Details").properties?.expanded == true)
    let details = try node("Details")
    let detailContent = try #require(
      nodes().first { $0.properties?.labelledBy == [details.identity] })
    #expect(try node("Details").properties?.controls == [detailContent.identity])
    #expect(try node("Nested action").parentIdentity != node("Details").identity)
    try send("Nested action")
    #expect(try node("Writes 2").role == .group)
    try send("Details", action: .setValue(.boolean(true)))
    #expect(try node("Expansion writes 1").role == .group)
    try send("Details")
    #expect(!nodes().contains { $0.label == "Nested action" })
  }

}

private struct AccessibleTabsFixture: View {
  let style: Int
  @State private var selection = "home"
  @State private var writes = 0
  @State private var settings = true
  @State private var disabled = false
  private var selectionBinding: Binding<String> {
    Binding(
      get: { selection },
      set: {
        selection = $0
        writes += 1
      })
  }
  var body: some View {
    VStack {
      Text("Writes \(writes)")
      Text("Selection \(selection)")
      TabView(selection: selectionBinding) {
        Tab("Home", value: "home") { LocalTabCounter() }
        if settings { Tab("Settings", value: "settings") { Text("Settings content") } }
        Tab("Activity", value: "activity") { Text("Activity content") }
      }.tabViewStyle([AnyTabViewStyle.automatic, .underline, .powerline, .literalTabs][style])
        .disabled(disabled).frame(width: 22, height: 6)
      Button(settings ? "Remove settings" : "Restore settings") { settings.toggle() }
      Button("Disable tabs") { disabled = true }
    }
  }
}
private struct LocalTabCounter: View {
  @State private var value = 0
  var body: some View {
    VStack {
      Text("Local \(value)")
      Button("Increment local") { value += 1 }
    }
  }
}

private struct AccessibleExpansionFixture: View {
  let style: Int
  @State private var writes = 0
  @State private var expanded = false
  @State private var expansionWrites = 0
  private var expansion: Binding<Bool> {
    Binding(
      get: { expanded },
      set: {
        expanded = $0
        expansionWrites += 1
      })
  }
  var body: some View {
    VStack {
      Text("Writes \(writes)")
      Text("Expansion writes \(expansionWrites)")
      Menu("Commands") { Button("Count command") { writes += 1 } }
        .menuStyle([AnyMenuStyle.automatic, .button, .borderlessButton, .inline][style])
      DisclosureGroup("Details", isExpanded: expansion) {
        Text("Disclosed content")
        Button("Nested action") { writes += 1 }
      }.disclosureGroupStyle(style % 2 == 0 ? AnyDisclosureGroupStyle.automatic : .compact)
    }
  }
}

extension CompositeAccessibilityTests {
  @Test("named modal surfaces expose dismissal, contain reading, and restore the invoker")
  func presentations() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("AccessiblePresentations"),
      size: .init(width: 60, height: 24)
    ) { AccessiblePresentationFixture() }
    defer { harness.shutdown() }
    var frames = 0
    func nodes() -> [AccessibilityNode] {
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes
    }
    func node(_ label: String) throws -> AccessibilityNode {
      try #require(
        nodes().first { $0.label == label },
        "Missing: \(label); labels: \(nodes().compactMap(\.label))")
    }
    func send(_ target: AccessibilityNode, _ action: AccessibilityAction) throws {
      #expect(
        harness.runLoop.handleAccessibilityAction(
          .init(target: try #require(target.actionTarget), action: action)) == .accepted)
      try harness.runLoop.renderPendingFrames(renderedFrames: &frames)
    }
    let invoker = try node("Open review")
    try send(invoker, .focus)
    try send(invoker, .activate)
    let review = try #require(nodes().first { $0.role == .sheet })
    #expect(review.label == "Review")
    #expect(review.properties?.modal == true)
    #expect(review.control?.customActions == ["Dismiss"])
    #expect(try node("Review instructions").role == .group)
    #expect(!nodes().contains { $0.label == "Open review" })
    try send(node("Open confirmation"), .focus)
    try send(node("Open confirmation"), .activate)
    let confirmation = try #require(nodes().first { $0.role == .sheet })
    #expect(confirmation.label == "Confirm")
    #expect(!nodes().contains { $0.label == "Review instructions" })
    try send(confirmation, .custom("Dismiss"))
    #expect(try node("Review instructions").role == .group)
    try send(node("Close Review"), .focus)
    try send(node("Close Review"), .activate)
    #expect(nodes().contains { $0.label == "Open review" })
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == invoker.actionIdentity)
  }
}

private struct AccessiblePresentationFixture: View {
  @State private var review = false
  @State private var confirm = false
  var body: some View {
    VStack {
      Button("Unrelated first button") {}
      Button("Open review") { review = true }
    }.sheet("Review", isPresented: $review) {
      VStack {
        Text("Review instructions")
        Button("Open confirmation") { confirm = true }
      }.sheet("Confirm", isPresented: $confirm) { Text("Confirm instructions") }
    }
  }
}

extension CompositeAccessibilityTests {
  @Test("navigation supplies a named Back operation and excludes inactive destinations")
  func navigation() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("AccessibleNavigation"),
      size: .init(width: 60, height: 20)
    ) { AccessibleNavigationFixture() }
    defer { harness.shutdown() }
    var frames = 0
    func nodes() -> [AccessibilityNode] {
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes
    }
    func send(_ node: AccessibilityNode, _ action: AccessibilityAction) throws {
      #expect(
        harness.runLoop.handleAccessibilityAction(
          .init(target: try #require(node.actionTarget), action: action)) == .accepted)
      try harness.runLoop.renderPendingFrames(renderedFrames: &frames)
    }
    let open = try #require(nodes().first { $0.label == "Open detail" })
    try send(open, .focus)
    try send(open, .activate)
    #expect(!nodes().contains { $0.label == "Open detail" })
    #expect(nodes().contains { $0.label == "Detail content" })
    let detail = try #require(nodes().first { $0.role == .region && $0.label == "Detail" })
    #expect(detail.control?.customActions == ["Back"])
    try send(detail, .custom("Back"))
    #expect(nodes().contains { $0.label == "Open detail" })
    #expect(!nodes().contains { $0.label == "Detail content" })
    #expect(!nodes().contains { $0.control?.customActions.contains("Back") == true })
  }
}
private struct AccessibleNavigationFixture: View {
  @State private var path: [Int] = []
  var body: some View {
    NavigationStack(path: $path) {
      Button("Open detail") { path.append(1) }
        .navigationTitle("Home")
        .navigationDestination(for: Int.self) { _ in
          Text("Detail content").navigationTitle("Detail")
        }
    }
  }
}

extension CompositeAccessibilityTests {
  @Test(
    "built-in presentations provide dismissal and correct modal or nonmodal reading",
    arguments: Array(0..<11))
  func presentationVariants(variant: Int) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PresentationVariant"),
      size: .init(width: 70, height: 28)
    ) { AccessiblePresentationVariant(variant: variant) }
    defer { harness.shutdown() }
    var frames = 0
    func nodes() -> [AccessibilityNode] {
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes
    }
    let open = try #require(nodes().first { $0.label == "Open presentation" })
    #expect(
      harness.runLoop.handleAccessibilityAction(
        .init(target: try #require(open.actionTarget), action: .activate)) == .accepted)
    try harness.runLoop.renderPendingFrames(renderedFrames: &frames)
    let surface = try #require(
      nodes().first { $0.control?.customActions.contains("Dismiss") == true })
    if variant < 6 {
      #expect(surface.properties?.modal == true)
      #expect(!nodes().contains { $0.label == "Open presentation" })
    } else {
      #expect(surface.properties?.modal != true)
      #expect(nodes().contains { $0.label == "Open presentation" })
    }
    if variant >= 7 {
      #expect(surface.role == .status)
      #expect(surface.label == "Saved changes")
      #expect(surface.liveRegion == .polite)
    }
    #expect(
      harness.runLoop.handleAccessibilityAction(
        .init(target: try #require(surface.actionTarget), action: .custom("Dismiss"))) == .accepted)
    try harness.runLoop.renderPendingFrames(renderedFrames: &frames)
    #expect(!nodes().contains { $0.control?.customActions.contains("Dismiss") == true })
    #expect(nodes().contains { $0.label == "Dismissals 1" })
  }
}
private struct AccessiblePresentationVariant: View {
  let variant: Int
  @State private var presented = false
  @State private var dismissals = 0
  private var opener: some View {
    VStack {
      Text("Dismissals \(dismissals)")
      Button("Open presentation") { presented = true }
    }
  }
  var body: some View {
    switch variant {
    case 0:
      opener.sheet("Purpose", isPresented: $presented, onDismiss: { dismissals += 1 }) {
        Text("Full content")
      }
    case 1:
      opener.sheet("Purpose", isPresented: $presented, onDismiss: { dismissals += 1 }) {
        Text("Full content")
      }.sheetStyle(.dropdown)
    case 2:
      opener.alert("Purpose", isPresented: $presented, onDismiss: { dismissals += 1 })
    case 3:
      opener.confirmationDialog("Purpose", isPresented: $presented, onDismiss: { dismissals += 1 })
    case 4:
      opener.fullScreenCover(isPresented: $presented, onDismiss: { dismissals += 1 }) {
        Text("Full content")
      }
    case 5:
      opener.popover(isPresented: $presented, onDismiss: { dismissals += 1 }) {
        Text("Full content")
      }
    case 6:
      opener.popoverTip(
        AccessibleReadingTip(), isPresented: $presented, onDismiss: { dismissals += 1 })
    default:
      opener.toast(
        "Saved changes", isPresented: $presented,
        style: [AnyToastStyle.info, .success, .warning, .danger][variant - 7], duration: nil,
        onDismiss: { dismissals += 1 })
    }
  }
}
private struct AccessibleReadingTip: PopoverTip {
  let id = "reading-tip"
  var title: Text { Text("Helpful information") }
  var message: Text? { Text("Read without losing context") }
}

extension CompositeAccessibilityTests {
  @Test("authored expansion grouping and role overrides survive primitive extraction")
  func authoredOverrides() {
    let artifacts = DefaultRenderer().render(
      DisclosureGroup("Details", isExpanded: .constant(true)) {
        Text("Hidden content")
        Button("Hidden operation") {}
      }.accessibilityElement(children: .ignore).accessibilityRole(.custom("switch")),
      context: .init(identity: testIdentity("IgnoredDisclosure")),
      proposal: .init(width: 30, height: 8))
    let nodes = artifacts.semanticSnapshot.accessibilityNodes
    #expect(nodes.contains { $0.label == "Details" && $0.role == .custom("switch") })
    #expect(!nodes.contains { $0.label == "Hidden content" || $0.label == "Hidden operation" })
    #expect(nodes.first { $0.label == "Details" }?.properties?.controls == [])
  }
}

private struct ChangingAccessibleTabStyleFixture: View {
  @State private var style = 0
  var body: some View {
    VStack {
      Button("Next style") { style = (style + 1) % 4 }
      AccessibleTabsFixture(style: style)
    }
  }
}
