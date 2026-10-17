@_spi(Testing) import SwiftTUITestSupport
// Adversarial set B, pass 3: accessibility structure and assistive focus
// (251–260).
//
// The DocC accessibility guide fixes the authoring contract: combined groups
// join labels and values and promote descendant operations, traits describe
// meaning with a documented precedence, sort priorities order siblings, and
// explicitly annotated children keep their own semantics inside a named
// container. These probes combine a built-in control, publish numeric values
// without descriptions, stack traits, remove absent traits, use infinite
// priorities, hint a text inside a named container, name an action on static
// text, write an unmatched assistive focus value, and read the linear
// renderer and hidden nodes back.
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: accessibility structure", .serialized)
struct AdversarialSetBAccessibilityStructureTests {
  private func nodes<V: View>(_ view: V, _ name: String) -> [AccessibilityNode] {
    DefaultRenderer().render(
      view, context: .init(identity: testIdentity("SetBA11y", name)),
      proposal: .init(width: 60, height: 20)
    ).semanticSnapshot.accessibilityNodes
  }

  // A combined group joins its children's labels and promotes a stepper's
  // operations to named actions instead of keeping the stepper as a child.
  @Test func setB251CombinedGroupAbsorbsAStepperAndPromotesItsOperations() throws {
    let published = nodes(
      HStack {
        Text("Volume")
        Stepper("Level", value: .constant(3), in: 0...10)
      }
      .accessibilityElement(children: .combine), "combineStepper")
    let group = try #require(
      published.first { $0.label?.contains("Volume") == true }, "\(published.map(\.label))")
    let stepper = published.first { $0.role == .stepper }
    withKnownIssue(
      "children with a setValue action are retained instead of combined, so the stepper stays separate (adjacent to STUI-968)"
    ) {
      #expect(group.label == "Volume, Level", "\(String(describing: group.label))")
      #expect(
        group.control?.customActions.contains("Increase Level") == true,
        "\(String(describing: group.control))")
      #expect(stepper == nil, "a retained stepper \(String(describing: stepper?.label))")
    }
  }

  // A combined group carries a child's numeric value even when the child
  // published no description.
  @Test func setB252CombinedGroupCarriesNumericValues() throws {
    let published = nodes(
      VStack {
        Text("Count")
        Text("x").accessibilityLabel("Items").accessibilityValue(3, in: 0...10)
      }
      .accessibilityElement(children: .combine), "combineValue")
    let group = try #require(
      published.first { $0.label?.contains("Count") == true }, "\(published.map(\.label))")
    withKnownIssue(
      "combine collects valueDescription only; a bare numeric control value is dropped"
    ) {
      #expect(
        group.control?.value == .number(3) || group.properties?.valueDescription == "3", "\(group)")
    }
    let described = nodes(
      VStack {
        Text("Count")
        Text("x").accessibilityLabel("Items").accessibilityValue("three")
      }
      .accessibilityElement(children: .combine), "combineDescribed")
    #expect(
      described.first { $0.label?.contains("Count") == true }?.properties?.valueDescription
        == "three")
  }

  // Traits never demote an explicit heading level, and the documented
  // precedence holds across chained calls: a heading outranks a button.
  @Test func setB253TraitsKeepExplicitHeadingLevelsAndPrecedence() throws {
    let levelled = nodes(
      Text("T").accessibilityRole(.heading(level: 3)).accessibilityAddTraits(.isHeader), "levelled")
    let chained = nodes(
      Text("T").accessibilityAddTraits(.isHeader).accessibilityAddTraits(.isButton), "chained")
    let levelledNode = try #require(levelled.first { $0.label == "T" }, "\(levelled.map(\.label))")
    let chainedNode = try #require(chained.first { $0.label == "T" }, "\(chained.map(\.label))")
    withKnownIssue(
      "isHeader writes heading level 1 unconditionally and the outer trait call wins outright"
    ) {
      #expect(levelledNode.role == .heading(level: 3), "\(levelledNode.role)")
      if case .heading = chainedNode.role {
      } else {
        Issue.record("the heading trait lost to a later button trait: \(chainedNode.role)")
      }
    }
    let single = nodes(Text("T").accessibilityAddTraits(.isHeader), "single")
    #expect(single.first { $0.label == "T" }?.role == .heading(level: 1))
  }

  // Removing a trait the node never had is a no-op: it does not publish an
  // explicit "not selected" state.
  @Test func setB254RemovingAnAbsentTraitPublishesNothing() throws {
    let published = nodes(Text("Plain").accessibilityRemoveTraits(.isSelected), "removeAbsent")
    let node = published.first { $0.label == "Plain" }
    withKnownIssue("removeTraits(.isSelected) writes selected = false even when it was never set") {
      #expect(node?.properties?.selected == nil, "\(String(describing: node?.properties))")
    }
    let toggled = nodes(
      Text("Plain").accessibilityAddTraits(.isSelected).accessibilityRemoveTraits(.isSelected),
      "addRemove")
    #expect(toggled.first { $0.label == "Plain" }?.properties?.selected == false)
  }

  // Sort priorities order siblings with larger first; infinite priorities
  // sort at the ends instead of being ignored.
  @Test func setB255InfiniteSortPrioritiesSortAtTheEnds() {
    let published = nodes(
      VStack {
        Text("A")
        Text("B").accessibilitySortPriority(.infinity)
        Text("C").accessibilitySortPriority(1)
        Text("D").accessibilitySortPriority(-.infinity)
      }, "sort")
    let labels = published.compactMap(\.label).filter { ["A", "B", "C", "D"].contains($0) }
    withKnownIssue("non-finite priorities are dropped by the modifier and sort as zero") {
      #expect(labels == ["B", "C", "A", "D"], "\(labels)")
    }
    let finite = nodes(
      VStack {
        Text("A")
        Text("C").accessibilitySortPriority(1)
      }, "sortFinite")
    #expect(finite.compactMap(\.label).filter { ["A", "C"].contains($0) } == ["C", "A"])
  }

  // A hinted text inside an explicitly named container keeps both its text
  // and its hint.
  @Test func setB256HintedTextInsideANamedContainerKeepsItsText() throws {
    let published = nodes(
      VStack {
        Text("Price")
        Text("42").accessibilityHint("Dollars")
      }
      .accessibilityLabel("Card"), "namedContainer")
    let hinted = try #require(
      published.first { $0.hint == "Dollars" }, "\(published.map { ($0.label, $0.hint) })")
    withKnownIssue("a named ancestor suppresses the child's inferred text while its hint survives")
    {
      #expect(hinted.label == "42", "\(String(describing: hinted.label))")
    }
    let contained = nodes(
      VStack {
        Text("Price")
        Text("42").accessibilityHint("Dollars")
      }
      .accessibilityLabel("Card").accessibilityElement(children: .contain), "containedContainer")
    #expect(
      contained.first { $0.hint == "Dollars" }?.label == "42",
      "\(contained.map { ($0.label, $0.hint) })")
  }

  // A named action on static text adds an assistive action: it does not turn
  // the text into a button or a keyboard stop.
  @Test func setB257NamedActionOnStaticTextIsNotAButton() throws {
    let snapshot = DefaultRenderer().render(
      VStack {
        Text("Row").accessibilityAction(named: "Archive") {}
        Button("Real") {}
      }, context: .init(identity: testIdentity("SetBA11y", "namedAction")),
      proposal: .init(width: 40, height: 6))
    let row = try #require(snapshot.semanticSnapshot.accessibilityNodes.first { $0.label == "Row" })
    #expect(row.control?.customActions == ["Archive"], "\(String(describing: row.control))")
    withKnownIssue("a named action marks the text focusable and gives it the button role") {
      #expect(
        snapshot.semanticSnapshot.focusRegions.count == 1,
        "\(snapshot.semanticSnapshot.focusRegions.map(\.identity))")
      #expect(row.role != .button, "\(row.role)")
    }
  }

  // Writing an assistive focus value that no view claims leaves the current
  // assistive focus where it was.
  @Test func setB258UnmatchedAssistiveFocusWriteKeepsCurrentFocus() throws {
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBA11y", "Unmatched"), size: .init(width: 40, height: 8)
    ) {
      SetBAssistiveFocusFixture()
    }
    defer { h.shutdown() }
    _ = try h.clickText("Focus A")
    _ = try h.render()
    let focusedA = h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
      $0.label == "A"
    }
    try #require(
      focusedA?.isAccessibilityFocused == true,
      "\(h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.map { ($0.label, $0.isAccessibilityFocused) })"
    )
    _ = try h.clickText("Ghost")
    _ = try h.render()
    let afterGhost = h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
      $0.label == "A"
    }
    withKnownIssue(
      "an unmatched AccessibilityFocusState write resolves to nil and clears the assistive focus"
    ) {
      #expect(
        afterGhost?.isAccessibilityFocused == true,
        "\(h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.map { ($0.label, $0.isAccessibilityFocused) })"
      )
    }
  }

  // The linear assistive renderer prints values as its documentation says.
  @Test func setB259LinearRendererPrintsValues() {
    let snapshot = DefaultRenderer().render(
      VStack {
        Toggle("Wifi", isOn: .constant(true))
        Text("Rating").accessibilityValue("3 of 5")
      }, context: .init(identity: testIdentity("SetBA11y", "linear")),
      proposal: .init(width: 40, height: 6)
    ).semanticSnapshot
    let output = renderLinearAccessibilityOutput(snapshot)
    #expect(output.contains("Wifi") && output.contains("Rating"), "\(output)")
    withKnownIssue("the linear line format carries role, label and hint only") {
      #expect(output.contains("3 of 5"), "\(output)")
      #expect(output.lowercased().contains("on"), "\(output)")
    }
  }

  // Hiding a focused control from assistive technology keeps its keyboard
  // stop, removes its node, stales its target and clears its focus binding.
  @Test func setB260HiddenControlKeepsKeyboardFocusAndClearsAssistiveState() throws {
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBA11y", "Hidden"), size: .init(width: 40, height: 8)
    ) {
      SetBHideableFixture()
    }
    defer { h.shutdown() }
    let node = try #require(
      h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first { $0.label == "Hide me" })
    let target = try #require(node.actionTarget)
    #expect(
      h.runLoop.handleAccessibilityAction(.init(target: target, action: .accessibilityFocus))
        == .accepted)
    _ = try h.render()
    #expect(h.frame.contains("bound true"), "\(h.frame)")
    _ = try h.clickText("Conceal")
    _ = try h.render()
    #expect(
      h.runLoop.focusTracker.focusRegions.count == 2,
      "\(h.runLoop.focusTracker.focusRegions.map(\.identity))")
    #expect(
      !h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.contains {
        $0.label == "Hide me"
      })
    #expect(
      h.runLoop.handleAccessibilityAction(.init(target: target, action: .accessibilityFocus))
        == .staleTarget)
    #expect(h.frame.contains("bound false"), "\(h.frame)")
  }
}

@MainActor
private struct SetBAssistiveFocusFixture: View {
  @AccessibilityFocusState private var review: String?

  var body: some View {
    VStack(alignment: .leading) {
      Text("A").accessibilityFocused($review, equals: "a")
      Text("B").accessibilityFocused($review, equals: "b")
      Button("Focus A") { review = "a" }
      Button("Ghost") { review = "zzz" }
      Text("review \(review ?? "nil")")
    }
  }
}

@MainActor
private struct SetBHideableFixture: View {
  @AccessibilityFocusState private var bound: Bool
  @State private var hidden = false

  var body: some View {
    VStack(alignment: .leading) {
      Button("Hide me") {}.accessibilityHidden(hidden).accessibilityFocused($bound)
      Button("Conceal") { hidden = true }
      Text("bound \(bound)")
    }
  }
}
