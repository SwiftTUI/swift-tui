import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// The content boundary of a custom transition (STUI-1574, STUI-1575).
///
/// The body of a transition puts a boundary around the view it is for, and
/// a transition on content that emits several views is on each of them.
/// These tests state what follows: a view under a custom transition is laid
/// out as the same view is without one, whatever it declares to its
/// container, and content that emits several views is inserted and removed
/// one view at a time. They cover the cases the review of the transition
/// stages named as the same mechanism and did not run
/// (`TransitionStagesReviewTests` holds the ones it ran).
@MainActor
@Suite("Transition content boundary", .serialized)
struct TransitionContentBoundaryTests {
  private static let upper = "ABCDEFGHIJKLMNOPQRST"
  private static let lower = "abcdefghijklmnopqrst"
  private static let digits = "01234567890123456789"
  private static let linear = Animation.linear(duration: .milliseconds(800))

  // MARK: - The layout role of one view

  @Test(
    "a divider keeps its axis under a custom transition",
    arguments: ["hStack", "vStack"])
  func dividerKeepsItsAxis(container: String) {
    @ViewBuilder func stack<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
      if container == "hStack" {
        HStack(spacing: 0) { content() }
      } else {
        VStack(spacing: 0) { content() }
      }
    }
    let plain = stagesReviewRows(
      "divider-plain-\(container)",
      stack {
        Text("A")
        Divider()
        Text("B")
      })
    let custom = stagesReviewRows(
      "divider-custom-\(container)",
      stack {
        Text("A")
        Divider().transition(BoundaryDim())
        Text("B")
      })
    #expect(custom == plain, "\(custom)")
  }

  @Test("a spacer expands along a vertical stack under a custom transition")
  func spacerExpandsInAVerticalStack() {
    let plain = stagesReviewRows(
      "v-spacer-plain",
      VStack(spacing: 0) {
        Text("T")
        Spacer()
        Text("B")
      })
    let custom = stagesReviewRows(
      "v-spacer-custom",
      VStack(spacing: 0) {
        Text("T")
        Spacer().transition(BoundaryDim())
        Text("B")
      })
    #expect(plain.last?.contains("B") == true, "\(plain)")
    #expect(custom == plain, "\(custom)")
  }

  @Test("a spacer with a wrapper of the body around it still expands")
  func spacerExpandsBehindABodyWrapper() {
    let plain = stagesReviewRows(
      "wrapped-spacer-plain",
      HStack(spacing: 0) {
        Text("L")
        Spacer().padding(.horizontal, 1)
        Text("R")
      })
    let custom = stagesReviewRows(
      "wrapped-spacer-custom",
      HStack(spacing: 0) {
        Text("L")
        Spacer().transition(BoundaryInset())
        Text("R")
      })
    #expect(custom == plain, "\(custom)")
  }

  @Test("a spacer with a fixed size stays rigid under a custom transition")
  func fixedSpacerStaysRigid() {
    let plain = stagesReviewRows(
      "fixed-spacer-plain",
      HStack(spacing: 0) {
        Text("a")
        Spacer().fixedSize()
        Text("b")
      })
    let custom = stagesReviewRows(
      "fixed-spacer-custom",
      HStack(spacing: 0) {
        Text("a")
        Spacer().fixedSize().transition(BoundaryDim())
        Text("b")
      })
    #expect(custom == plain, "\(custom)")
  }

  @Test("a fixed size is honoured under a custom transition")
  func fixedSizePassesThrough() {
    let long = String(repeating: "w", count: 24)
    let plain = stagesReviewRows(
      "fixed-plain",
      HStack(spacing: 0) {
        Text(long)
        Text("fixed-size").fixedSize()
      })
    let custom = stagesReviewRows(
      "fixed-custom",
      HStack(spacing: 0) {
        Text(long)
        Text("fixed-size").fixedSize().transition(BoundaryDim())
      })
    #expect(custom == plain, "\(custom)")
  }

  @Test("an alignment guide is honoured under a custom transition")
  func alignmentGuidePassesThrough() {
    let plain = stagesReviewRows(
      "guide-plain",
      VStack(alignment: .leading, spacing: 0) {
        Text("AAAAAA")
        Text("B").alignmentGuide(.leading) { _ in -3 }
      })
    let custom = stagesReviewRows(
      "guide-custom",
      VStack(alignment: .leading, spacing: 0) {
        Text("AAAAAA")
        Text("B").alignmentGuide(.leading) { _ in -3 }.transition(BoundaryDim())
      })
    #expect(plain[1].hasPrefix("   B"), "\(plain)")
    #expect(custom == plain, "\(custom)")
  }

  @Test("a text baseline is the view's own under a custom transition")
  func textBaselinePassesThrough() {
    let plain = stagesReviewRows(
      "baseline-plain",
      HStack(alignment: .lastTextBaseline, spacing: 1) {
        Text("one\ntwo\nthree")
        Text("x").padding(.bottom, 1)
      })
    let custom = stagesReviewRows(
      "baseline-custom",
      HStack(alignment: .lastTextBaseline, spacing: 1) {
        Text("one\ntwo\nthree")
        Text("x").padding(.bottom, 1).transition(BoundaryDim())
      })
    #expect(custom == plain, "\(custom)")
  }

  @Test("a spacing preference is honoured under a custom transition")
  func spacingPassesThrough() {
    let plain = stagesReviewRows(
      "spacing-plain",
      HStack {
        Text("L")
        Text("M").layoutMetadata(.init(spacing: .init(horizontal: 4)))
        Text("R")
      })
    let custom = stagesReviewRows(
      "spacing-custom",
      HStack {
        Text("L")
        Text("M").layoutMetadata(.init(spacing: .init(horizontal: 4)))
          .transition(BoundaryDim())
        Text("R")
      })
    #expect(plain[0].hasPrefix("L    M    R"), "\(plain)")
    #expect(custom == plain, "\(custom)")
  }

  @Test("a minimum size is honoured under a custom transition")
  func minimumSizePassesThrough() {
    let long = String(repeating: "w", count: 40)
    let plain = stagesReviewRows(
      "minimum-plain",
      HStack(spacing: 0) {
        Text(long)
        Text("minimum").layoutMetadata(.init(minimumWidth: 7))
      })
    let custom = stagesReviewRows(
      "minimum-custom",
      HStack(spacing: 0) {
        Text(long)
        Text("minimum").layoutMetadata(.init(minimumWidth: 7)).transition(BoundaryDim())
      })
    #expect(custom == plain, "\(custom)")
  }

  @Test("a custom layout reads a layout value and a priority through a custom transition")
  func customLayoutReadsThroughTheBoundary() {
    let plain = stagesReviewRows(
      "layout-value-plain",
      BoundaryGapLayout {
        Text("A").layoutValue(key: BoundaryGapKey.self, value: 3).layoutPriority(2)
        Text("B")
      })
    let custom = stagesReviewRows(
      "layout-value-custom",
      BoundaryGapLayout {
        Text("A").layoutValue(key: BoundaryGapKey.self, value: 3).layoutPriority(2)
          .transition(BoundaryDim())
        Text("B")
      })
    // The gap is the layout value plus the priority: five columns.
    #expect(plain[0].hasPrefix("A     B"), "\(plain)")
    #expect(custom == plain, "\(custom)")
  }

  @Test("a modifier of the body can set the layout priority of the content")
  func bodyLayoutPriorityWins() {
    let a = String(repeating: "a", count: 20)
    let b = String(repeating: "b", count: 20)
    let plain = stagesReviewRows(
      "body-priority-plain",
      HStack(spacing: 0) {
        Text(a)
        Text(b).layoutPriority(1)
      })
    let custom = stagesReviewRows(
      "body-priority-custom",
      HStack(spacing: 0) {
        Text(a)
        Text(b).transition(BoundaryPriority())
      })
    #expect(custom == plain, "\(custom)")
  }

  @Test("a view that changes what it declares by itself is laid out again")
  func layoutRoleFollowsTheViewsOwnState() throws {
    // The view under the transition owns the state that decides its layout
    // priority, so a change evaluates that view alone. The boundary is not
    // resolved again and still has to stand for the view as it is now.
    func probe(custom: Bool, named name: String) throws -> (
      probe: StagesReviewProbe<AnyView>, flag: BoundaryFlag
    ) {
      let flag = BoundaryFlag()
      let probe = try StagesReviewProbe(named: name) { _, _, _ in
        AnyView(
          HStack(spacing: 0) {
            Text(String(repeating: "a", count: 20))
            if custom {
              BoundarySelfPriority(flag: flag).transition(BoundaryDim())
            } else {
              BoundarySelfPriority(flag: flag)
            }
          })
      }
      return (probe, flag)
    }
    let plain = try probe(custom: false, named: "self-priority-plain")
    defer { plain.probe.shutdown() }
    let custom = try probe(custom: true, named: "self-priority-custom")
    defer { custom.probe.shutdown() }
    #expect(custom.probe.line(0) == plain.probe.line(0))
    let before = plain.probe.line(0)

    for (probe, flag) in [plain, custom] {
      let binding = try #require(flag.binding)
      binding.wrappedValue = true
      _ = try probe.harness.render()
    }
    #expect(plain.probe.line(0) != before, "the priority changes the row: \(before)")
    #expect(custom.probe.line(0) == plain.probe.line(0), "\(custom.probe.frame)")
  }

  @Test("one of several views that changes by itself is laid out and drawn again")
  func oneOfSeveralViewsFollowsItsOwnState() throws {
    // The same, with the view among several under one transition. The
    // transition is on each of them, and none is resolved again.
    func probe(custom: Bool, named name: String) throws -> (
      probe: StagesReviewProbe<AnyView>, flag: BoundaryFlag
    ) {
      let flag = BoundaryFlag()
      let probe = try StagesReviewProbe(named: name) { _, _, _ in
        let pair = Group {
          Text(String(repeating: "a", count: 20))
          BoundarySelfPriority(flag: flag)
        }
        return AnyView(
          HStack(spacing: 0) {
            if custom {
              pair.transition(BoundaryDim())
            } else {
              pair
            }
          })
      }
      return (probe, flag)
    }
    let plain = try probe(custom: false, named: "several-self-priority-plain")
    defer { plain.probe.shutdown() }
    let custom = try probe(custom: true, named: "several-self-priority-custom")
    defer { custom.probe.shutdown() }
    #expect(custom.probe.frame == plain.probe.frame)
    let before = plain.probe.frame

    for (probe, flag) in [plain, custom] {
      let binding = try #require(flag.binding)
      binding.wrappedValue = true
      _ = try probe.harness.render()
    }
    #expect(plain.probe.frame != before, "the priority changes the row: \(before)")
    #expect(custom.probe.frame == plain.probe.frame, "\(custom.probe.frame)")
  }

  // MARK: - Metadata a collection reads from its rows

  @Test("a tagged row of a list is selected under a custom transition")
  func listRowTagPassesThrough() {
    let plain = stagesReviewRows(
      "list-plain",
      List(selection: Binding<Int>.constant(2)) {
        Text("one").tag(1)
        Text("two").tag(2)
      })
    let custom = stagesReviewRows(
      "list-custom",
      List(selection: Binding<Int>.constant(2)) {
        Text("one").tag(1)
        Text("two").tag(2).transition(BoundaryDim())
      })
    #expect(custom == plain, "\(custom)")
  }

  @Test("a tagged option of a picker is an option under a custom transition")
  func pickerOptionTagPassesThrough() {
    let plain = stagesReviewRows(
      "picker-plain",
      Picker("Choice", selection: .constant(2)) {
        Text("First").tag(1)
        Text("Second").tag(2)
      }.pickerStyle(AnyPickerStyle.inline))
    let custom = stagesReviewRows(
      "picker-custom",
      Picker("Choice", selection: .constant(2)) {
        Text("First").tag(1)
        Text("Second").tag(2).transition(BoundaryDim())
      }.pickerStyle(AnyPickerStyle.inline))
    #expect(custom == plain, "\(custom)")
  }

  @Test("the content of a tab is laid out under a custom transition as without one")
  func tabContentPassesThrough() {
    let plain = stagesReviewRows(
      "tab-plain",
      TabView(selection: Binding.constant(1)) {
        Tab("First", value: 1) { Text("Content") }
        Tab("Second", value: 2) { Text("Other") }
      })
    let custom = stagesReviewRows(
      "tab-custom",
      TabView(selection: Binding.constant(1)) {
        Tab("First", value: 1) { Text("Content").transition(BoundaryDim()) }
        Tab("Second", value: 2) { Text("Other") }
      })
    #expect(custom == plain, "\(custom)")
  }

  // MARK: - Content that emits several views

  @Test("the views of the content keep their roles among their siblings")
  func severalViewsKeepTheirRoles() {
    let plain = stagesReviewRows(
      "several-roles-plain",
      HStack(spacing: 0) {
        Group {
          Text("L")
          Spacer()
          Text("R")
        }
      })
    let custom = stagesReviewRows(
      "several-roles-custom",
      HStack(spacing: 0) {
        Group {
          Text("L")
          Spacer()
          Text("R")
        }
        .transition(BoundaryDim())
      })
    #expect(plain[0].hasPrefix("L") && plain[0].contains("R"), "\(plain)")
    #expect(custom == plain, "\(custom)")
  }

  @Test("a combination of two custom transitions lays several views out as without one")
  func nestedBodiesKeepSeveralViews() {
    let plain = stagesReviewRows("nested-plain", Self.column { Self.pair })
    let custom = stagesReviewRows(
      "nested-custom",
      Self.column { Self.pair.transition(BoundaryDim().combined(with: BoundaryStill())) })
    let mixed = stagesReviewRows(
      "mixed-custom",
      Self.column {
        Self.pair.transition(AnyTransition(BoundaryDim()).combined(with: .opacity))
      })
    #expect(custom == plain, "\(custom)")
    #expect(mixed == plain, "\(mixed)")
  }

  @Test("a body that places content twice shows each view of the content twice")
  func contentPlacedTwiceKeepsSeveralViews() {
    // The body is evaluated for each view, so each view is doubled in place.
    let rows = stagesReviewRows(
      "twice-several",
      Self.column { Self.pair.transition(BoundaryTwice()) })
    #expect(
      Array(rows.prefix(5)).map(Self.trimmed)
        == ["FIRST-FIRST", "FIRST-FIRST", "SECOND", "SECOND", "BELOW"], "\(rows)")
  }

  @Test("geometry and draw modifiers are applied to each declared view")
  func aModifierAppliesToEachDeclaredView() {
    func rows(_ name: String, _ view: some View) -> [String] {
      Array(stagesReviewRows(name, Self.column { view }).prefix(3)).map(Self.trimmed)
    }
    #expect(
      rows("padding", Self.pair.padding(.horizontal, 1))
        == [" FIRST-FIRST", " SECOND", "BELOW"])
    #expect(
      rows("offset", Self.pair.offset(x: 2, y: 0))
        == ["  FIRST-FIRST", "  SECOND", "BELOW"])
    #expect(
      rows("frame", Self.pair.frame(width: 14, alignment: .trailing))
        == ["   FIRST-FIRST", "        SECOND", "BELOW"])
    #expect(
      rows("opacity", ForEach(["FIRST", "SECOND"], id: \.self) { Text($0) }.opacity(0))
        == ["", "", "BELOW"])
    #expect(rows("clip", Self.pair.clipShape(Rectangle().inset(by: 2))) == ["", "", "BELOW"])
    let twice = stagesReviewRows(
      "padded-twice",
      Self.column { Self.pair.padding(.horizontal, 1).transition(BoundaryTwice()) })
    #expect(
      Array(twice.prefix(5)).map(Self.trimmed)
        == [" FIRST-FIRST", " FIRST-FIRST", " SECOND", " SECOND", "BELOW"])
  }

  @Test("geometry wrappers pass through a child's layout priority")
  func geometryWrappersPassPriority() {
    let a = String(repeating: "a", count: 20)
    let b = String(repeating: "b", count: 20)
    func line(_ view: some View) -> String {
      stagesReviewRows(
        "wrapped-priority",
        HStack(spacing: 0) {
          Text(a)
          view
        })[0]
    }
    let plain = line(Text(b).layoutPriority(1))
    #expect(line(Text(b).layoutPriority(1).padding(0)) == plain)
    #expect(line(Text(b).layoutPriority(1).offset(x: 0, y: 0)) == plain)
    #expect(line(Text(b).layoutPriority(1).padding(0).layoutPriority(0)) == line(Text(b)))
  }

  @Test("a body that wraps content wraps each view of the content")
  func wrapperBodyWrapsEachView() {
    // The body is evaluated for each view, so its padding is around each
    // one, as if the transition were written on each.
    let each = stagesReviewRows(
      "wrapper-each",
      Self.column {
        Text("FIRST-FIRST").transition(BoundaryInset())
        Text("SECOND").transition(BoundaryInset())
      })
    let custom = stagesReviewRows(
      "wrapper-custom", Self.column { Self.pair.transition(BoundaryInset()) })
    #expect(custom == each, "\(custom)")
    #expect(Array(custom.prefix(3)) == [" FIRST-FIRST", " SECOND", "BELOW"], "\(custom)")
  }

  @Test(
    "each view of the content leaves through the body",
    arguments: ["group", "forEach", "view with two roots"])
  func eachViewIsRemovedThroughTheBody(shape: String) throws {
    let probe = try StagesReviewProbe(named: "several-removal-\(shape)") { step, _, _ in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 {
          Self.twoRows(shape).transition(BoundaryReveal())
        }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      #expect(probe.line(1) == Self.upper)
      #expect(probe.line(2) == Self.lower)
      try probe.set(1, animation: Self.linear)
      // One removal for each view, each with the clip path and the opacity
      // of the body.
      #expect(probe.removingCount == 2)
      #expect(probe.activeAnimationCount == 4)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.line(1) == String(Self.upper.prefix(10)), "\(probe.frame)")
      #expect(probe.line(2) == String(Self.lower.prefix(10)), "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(900)))
      #expect(probe.removingCount == 0)
      #expect(probe.activeAnimationCount == 0)
      #expect(probe.line(1) == "", "\(probe.frame)")
      #expect(probe.log.completions == ["done"])
    }
  }

  @Test(
    "each view of the content arrives through the body",
    arguments: ["group", "forEach", "view with two roots"])
  func eachViewIsInsertedThroughTheBody(shape: String) throws {
    let probe = try StagesReviewProbe(named: "several-insertion-\(shape)") { step, _, _ in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 1 {
          Self.twoRows(shape).transition(BoundaryReveal())
        }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.linear)
      #expect(probe.activeAnimationCount == 4)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.line(1) == String(Self.upper.prefix(10)), "\(probe.frame)")
      #expect(probe.line(2) == String(Self.lower.prefix(10)), "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(900)))
      #expect(probe.activeAnimationCount == 0)
      #expect(probe.line(1) == Self.upper)
      #expect(probe.line(2) == Self.lower)
    }
  }

  @Test("a removal behind a wrapper of the body draws every view of the content")
  func wrapperBodyRemovalDrawsEveryView() throws {
    let probe = try StagesReviewProbe(named: "wrapper-removal") { step, _, _ in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 {
          Self.pair.transition(BoundaryFadingInset())
        }
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      let atRest = [probe.line(1), probe.line(2)]
      #expect(atRest == [" FIRST-FIRST", " SECOND"], "\(probe.frame)")
      try probe.set(1, animation: Self.linear)
      // One removal for each view, each with the opacity of its own padded
      // view.
      #expect(probe.removingCount == 2)
      #expect(probe.activeAnimationCount == 2)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      // Both views are drawn, where they were.
      #expect([probe.line(1), probe.line(2)] == atRest, "\(probe.frame)")
      try probe.advance(to: start.advanced(by: .milliseconds(900)))
      #expect(probe.removingCount == 0)
      #expect(probe.line(1) == "", "\(probe.frame)")
    }
  }

  @Test("a row that joins a ForEach under one transition arrives alone")
  func rowInsertedIntoAForEachPlaysAlone() throws {
    let probe = try Self.rowsProbe(named: "row-insertion") { step in
      step == 0 ? [Self.upper, Self.lower] : [Self.upper, Self.lower, Self.digits]
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.linear)
      // The clip path and the opacity of the new row, and nothing else.
      #expect(probe.activeAnimationCount == 2)
      #expect(probe.removingCount == 0)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.line(1) == Self.upper)
      #expect(probe.line(2) == Self.lower)
      #expect(probe.line(3) == String(Self.digits.prefix(10)), "\(probe.frame)")
    }
  }

  @Test("the last row of a ForEach under one transition leaves alone")
  func lastRowRemovedFromAForEachPlaysAlone() throws {
    let probe = try Self.rowsProbe(named: "row-removal-last") { step in
      step == 0 ? [Self.upper, Self.lower, Self.digits] : [Self.upper, Self.lower]
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.linear)
      #expect(probe.removingCount == 1)
      #expect(probe.activeAnimationCount == 2)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.line(1) == Self.upper)
      #expect(probe.line(2) == Self.lower)
      #expect(probe.line(3) == String(Self.digits.prefix(10)), "\(probe.frame)")
    }
  }

  @Test("the first row of a ForEach under one transition leaves and the others stay")
  func firstRowRemovedFromAForEachPlaysAlone() throws {
    // Each row has the transition by itself, whatever its position: the
    // rows that stay are the views they were, so nothing is inserted and
    // only the row that left is removed.
    let probe = try Self.rowsProbe(named: "row-removal-first") { step in
      step == 0 ? [Self.upper, Self.lower, Self.digits] : [Self.lower, Self.digits]
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.linear)
      #expect(probe.removingCount == 1)
      #expect(probe.activeAnimationCount == 2)
      try probe.advance(to: start.advanced(by: .milliseconds(900)))
      #expect(probe.removingCount == 0)
      #expect(probe.activeAnimationCount == 0)
      #expect(probe.line(1) == Self.lower, "\(probe.frame)")
      #expect(probe.line(2) == Self.digits, "\(probe.frame)")
      #expect(probe.line(3) == "", "\(probe.frame)")
    }
  }

  @Test("rows under one transition keep their state and lifecycle when another row leaves")
  func rowsKeepStateAndLifecycle() throws {
    // Each row is mounted once and torn down once. A row that stays keeps
    // its node: its state survives and it does not appear again.
    let bindings = BoundaryRowBindings()
    let probe = try StagesReviewProbe(named: "row-lifecycle") { step, _, log in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        ForEach(step == 0 ? ["one", "two", "three"] : ["two", "three"], id: \.self) { name in
          BoundaryCountedRow(name: name, log: log, bindings: bindings)
        }
        .transition(BoundaryReveal())
      }
    }
    defer { probe.shutdown() }
    try probe.run { start in
      #expect(probe.log.completions.sorted() == ["appear:one", "appear:three", "appear:two"])
      let count = try #require(bindings.counts["two"])
      count.wrappedValue = 7
      _ = try probe.harness.render()
      #expect(probe.line(2) == "two 7", "\(probe.frame)")
      probe.log.completions = []

      try probe.set(1, animation: Self.linear)
      #expect(probe.removingCount == 1)
      try probe.advance(to: start.advanced(by: .milliseconds(900)))
      #expect(probe.removingCount == 0)
      #expect(probe.log.completions == ["disappear:one", "done"], "\(probe.log.completions)")
      #expect(probe.line(1) == "two 7", "\(probe.frame)")
      #expect(probe.line(2) == "three 0", "\(probe.frame)")
    }
  }

  @Test("a ForEach that grows from one row to two keeps the first row in place")
  func growingFromOneRowKeepsTheFirstRow() throws {
    let probe = try Self.rowsProbe(named: "row-one-to-two") { step in
      step == 0 ? [Self.upper] : [Self.upper, Self.lower]
    }
    defer { probe.shutdown() }
    try probe.run { start in
      try probe.set(1, animation: Self.linear)
      // Only the new row plays. The row that stayed is the view it was
      // when it was the only one.
      #expect(probe.removingCount == 0)
      #expect(probe.activeAnimationCount == 2)
      try probe.advance(to: start.advanced(by: .milliseconds(400)))
      #expect(probe.line(1) == Self.upper)
      #expect(probe.line(2) == String(Self.lower.prefix(10)), "\(probe.frame)")
    }
  }

  // MARK: - A transition inside a departing view (STUI-1576)

  @Test("a custom body inside a view with a built-in transition plans no removal of its own")
  func customBodyInsideABuiltInRemoval() throws {
    var removing: [Int] = []
    var shown: [String] = []
    for round in 0..<12 {
      let probe = try StagesReviewProbe(named: "custom-in-built-in-\(round)") { step, _, _ in
        VStack(alignment: .leading, spacing: 0) {
          Text("TITLE")
          if step == 0 {
            HStack(spacing: 0) { Text(Self.upper).transition(BoundaryReveal()) }
              .transition(.offset(x: 8, y: 0))
          }
        }
      }
      defer { probe.shutdown() }
      try probe.run { start in
        try probe.set(1, animation: Self.linear)
        removing.append(probe.removingCount)
        try probe.advance(to: start.advanced(by: .milliseconds(400)))
        shown.append(probe.line(1))
      }
    }
    // The stack left, with the text in it. The text plays nothing: the row
    // is the whole text, half way along the stack's eight columns.
    #expect(removing.allSatisfy { $0 == 1 }, "\(removing)")
    #expect(shown.allSatisfy { $0 == "    " + Self.upper }, "\(shown)")
  }

  @Test("a view inside a view that leaves with the identity transition plays nothing")
  func innerTransitionUnderAnIdentityRemovalPlaysNothing() throws {
    let probe = try StagesReviewProbe(named: "inner-under-identity") { step, _, _ in
      VStack(alignment: .leading, spacing: 0) {
        Text("TITLE")
        if step == 0 {
          HStack(spacing: 0) { Text(Self.upper).transition(.opacity) }
            .transition(.identity)
        }
      }
    }
    defer { probe.shutdown() }
    try probe.run { _ in
      try probe.set(1, animation: Self.linear)
      // The stack left, and its transition says it leaves at once. The text
      // goes with it: its own transition is for its own presence, which did
      // not change inside the stack.
      #expect(probe.removingCount == 0)
      #expect(probe.line(1) == "", "\(probe.frame)")
    }
  }

  @Test(
    "a view the body adds, with a transition of its own, plans no removal of its own",
    arguments: ["beside the content", "around the content"])
  func bodyAddedViewWithItsOwnTransition(place: String) throws {
    var removing: [Int] = []
    var animating: [Int] = []
    var shown: [String] = []
    for round in 0..<12 {
      let probe = try StagesReviewProbe(named: "added-view-\(round)") { step, _, _ in
        VStack(alignment: .leading, spacing: 0) {
          Text("TITLE")
          if step == 0 {
            // Nineteen letters and the badge: twenty columns, so half is ten.
            if place == "beside the content" {
              Text(String(Self.upper.prefix(19))).transition(BoundaryBadge())
            } else {
              Text(String(Self.upper.prefix(19))).transition(BoundaryFramedBadge())
            }
          }
        }
      }
      defer { probe.shutdown() }
      try probe.run { start in
        #expect(probe.line(1) == String(Self.upper.prefix(19)) + "!")
        try probe.set(1, animation: Self.linear)
        removing.append(probe.removingCount)
        animating.append(probe.activeAnimationCount)
        try probe.advance(to: start.advanced(by: .milliseconds(400)))
        shown.append(probe.line(1))
      }
    }
    // One removal, for the view the transition is on: its clip path
    // animates, and the badge inside it leaves with it.
    #expect(removing.allSatisfy { $0 == 1 }, "\(removing)")
    #expect(animating.allSatisfy { $0 == 1 }, "\(animating)")
    #expect(shown.allSatisfy { $0 == String(Self.upper.prefix(10)) }, "\(shown)")
  }

  // MARK: - Helpers

  private static var pair: some View {
    Group {
      Text("FIRST-FIRST")
      Text("SECOND")
    }
  }

  /// Two rows of twenty columns, emitted by one view in the given way.
  @ViewBuilder
  private static func twoRows(_ shape: String) -> some View {
    switch shape {
    case "group":
      Group {
        Text(upper)
        Text(lower)
      }
    case "forEach":
      ForEach([upper, lower], id: \.self) { Text($0) }
    default:
      BoundaryTwoRows(first: upper, second: lower)
    }
  }

  private static func column<Content: View>(
    @ViewBuilder _ content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      content()
      Text("BELOW")
    }
  }

  private static func trimmed(_ row: String) -> String {
    String(row.reversed().drop { $0 == " " }.reversed())
  }

  /// A column of rows from a `ForEach` under one custom transition, below a
  /// title, as a function of the probe's step.
  private static func rowsProbe(
    named name: String,
    rows: @escaping (Int) -> [String]
  ) throws -> StagesReviewProbe<AnyView> {
    try StagesReviewProbe(named: name) { step, _, _ in
      AnyView(
        VStack(alignment: .leading, spacing: 0) {
          Text("TITLE")
          ForEach(rows(step), id: \.self) { Text($0) }
            .transition(BoundaryReveal())
        })
    }
  }
}

// MARK: - Fixtures

/// An opacity from one to zero.
private struct BoundaryDim: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.opacity(phase.isIdentity ? 1 : 0)
  }
}

/// A body that changes nothing.
private struct BoundaryStill: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.opacity(1)
  }
}

/// A body that pads its content: one wrapper view around it.
private struct BoundaryInset: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.padding(.horizontal, 1)
  }
}

/// A body that pads its content and fades the padded view.
private struct BoundaryFadingInset: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.padding(.horizontal, 1).opacity(phase.isIdentity ? 1 : 0.2)
  }
}

/// A view whose body has two roots.
private struct BoundaryTwoRows: View {
  let first: String
  let second: String

  var body: some View {
    Text(first)
    Text(second)
  }
}

private enum BoundaryGapKey: LayoutValueKey {
  static let defaultValue = 0
}

/// A row that leaves, after each view, a gap of that view's layout value plus
/// its layout priority.
private struct BoundaryGapLayout: Layout {
  func makeCache(subviews _: LayoutSubviews) {}

  func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    let width = sizes.enumerated().reduce(0) { partial, entry in
      partial + entry.element.width + Self.gap(after: subviews[entry.offset])
    }
    return .init(width: width, height: sizes.map(\.height).max() ?? 0)
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    var x = bounds.origin.x
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      subview.place(
        at: .init(x: x, y: bounds.origin.y),
        anchor: .topLeading,
        proposal: .init(width: size.width, height: size.height)
      )
      x += size.width + Self.gap(after: subview)
    }
  }

  private static func gap(after subview: LayoutSubview) -> Int {
    subview[BoundaryGapKey.self] + Int(subview.layoutPriority)
  }
}

/// A body that gives its content a layout priority.
private struct BoundaryPriority: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.layoutPriority(1)
  }
}

/// A body that places its content twice.
private struct BoundaryTwice: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      content
      content
    }
  }
}

/// A rectangle covering `fraction` of the width. Every fraction has the same
/// element topology, so two of them interpolate.
private struct BoundaryRevealShape: Shape {
  var fraction: Double

  func path(in rect: Rect) -> Path {
    var path = Path()
    let right = rect.origin.x + rect.size.width * fraction
    let bottom = rect.origin.y + rect.size.height
    path.move(to: Point(x: rect.origin.x, y: rect.origin.y))
    path.addLine(to: Point(x: right, y: rect.origin.y))
    path.addLine(to: Point(x: right, y: bottom))
    path.addLine(to: Point(x: rect.origin.x, y: bottom))
    path.closeSubpath()
    return path
  }
}

/// A clip path that covers the whole view at identity and nothing outside
/// it, and an opacity.
private struct BoundaryReveal: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .clipShape(BoundaryRevealShape(fraction: phase.isIdentity ? 1 : 0))
      .opacity(phase.isIdentity ? 1 : 0.2)
  }
}

/// A body that adds a view with a transition of its own beside the content,
/// inside one stack that it reveals.
private struct BoundaryBadge: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    HStack(spacing: 0) {
      content
      Text("!").transition(BoundaryDim())
    }
    .clipShape(BoundaryRevealShape(fraction: phase.isIdentity ? 1 : 0))
  }
}

/// The same reveal, with the view the body adds around the content: a stack
/// with a transition of its own, the only child of the body's root. Only
/// single-child views lie between the two transitions.
private struct BoundaryFramedBadge: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 0) {
        content
        Text("!")
      }
      .transition(BoundaryDim())
    }
    .clipShape(BoundaryRevealShape(fraction: phase.isIdentity ? 1 : 0))
  }
}

@MainActor
private final class BoundaryRowBindings {
  var counts: [String: Binding<Int>] = [:]
}

/// A row with state of its own that records when it appears and disappears.
private struct BoundaryCountedRow: View {
  let name: String
  let log: StagesReviewLog
  let bindings: BoundaryRowBindings
  @State private var count = 0

  var body: some View {
    let _ = capture()
    Text("\(name) \(count)")
      .onAppear { log.completions.append("appear:\(name)") }
      .onDisappear { log.completions.append("disappear:\(name)") }
  }

  private func capture() {
    bindings.counts[name] = $count
  }
}

@MainActor
private final class BoundaryFlag {
  var binding: Binding<Bool>?
}

/// A text whose own state changes only its parent-visible priority (STUI-1579).
private struct BoundarySelfPriority: View {
  @State private var isWide = false
  let flag: BoundaryFlag

  var body: some View {
    let _ = capture()
    Text(String(repeating: "b", count: 20)).layoutPriority(isWide ? 1 : 0)
  }

  private func capture() {
    flag.binding = $isWide
  }
}
