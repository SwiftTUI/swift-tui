// Adversarial set B, pass 2: environment and preference propagation
// (191–200).
//
// Environment values flow down and preferences fold up, each with SwiftUI's
// replacement rule: the write closest to the view wins on the way down, and
// a `preference` write on a view replaces whatever its subtree folded. These
// probes cover a container writing over its subtree's fold, the order of
// chained writes and transforms, change observation on unchanged values,
// disabled and transparent controls, and the sizing rules of the
// geometry-reading containers.
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

private enum SetBListKey: PreferenceKey {
  static let defaultValue: [String] = []
  static func reduce(value: inout [String], nextValue: () -> [String]) {
    value.append(contentsOf: nextValue())
  }
}

private enum SetBIntKey: PreferenceKey {
  static let defaultValue = 0
  static func reduce(value: inout Int, nextValue: () -> Int) {
    value += nextValue()
  }
}

private struct SetBProbeKey: EnvironmentKey {
  static let defaultValue = 1
}

extension EnvironmentValues {
  fileprivate var setBProbe: Int {
    get { self[SetBProbeKey.self] }
    set { self[SetBProbeKey.self] = newValue }
  }
}

@MainActor
@Suite("Adversarial set B: environment and preferences", .serialized)
struct AdversarialSetBEnvironmentTests {
  private func fold<V: View>(_ view: V, _ name: String) -> [String] {
    Resolver().resolve(view, in: .init(identity: testIdentity("SetBEnvironment", name)))
      .preferenceValues[SetBListKey.self]
  }

  private func render<V: View>(_ view: V, _ name: String, width: Int? = 30, height: Int? = 6)
    -> RenderSnapshot
  {
    DefaultRenderer().render(
      view, context: .init(identity: testIdentity("SetBEnvironment", name)),
      proposal: .init(width: width, height: height))
  }

  // A `preference` write on a container replaces the value its subtree
  // folded; it is not reduced into it.
  @Test func setB191ContainerPreferenceWriteReplacesTheSubtreeFold() {
    let container = fold(
      VStack {
        Text("a").preference(key: SetBListKey.self, value: ["inner"])
      }
      .preference(key: SetBListKey.self, value: ["outer"]), "container")
    let chained = fold(
      Text("a").preference(key: SetBListKey.self, value: ["first"])
        .preference(key: SetBListKey.self, value: ["second"]), "chained")
    withKnownIssue("a preference write is reduced into the subtree fold instead of replacing it") {
      #expect(container == ["outer"], "\(container)")
      #expect(chained == ["second"], "\(chained)")
    }
    // Siblings still fold in order beneath an untouched parent.
    let siblings = fold(
      VStack {
        Text("a").preference(key: SetBListKey.self, value: ["a"])
        Text("b").preference(key: SetBListKey.self, value: ["b"])
      }, "siblings")
    #expect(siblings == ["a", "b"], "\(siblings)")
  }

  // The environment write closest to the view wins over an outer write.
  @Test func setB192InnermostEnvironmentWriteWins() {
    let snapshot = render(
      EnvironmentReader(\.setBProbe) { Text("v=\($0)") }
        .environment(\.setBProbe, 1)
        .environment(\.setBProbe, 2), "innermost")
    #expect(snapshot.rasterSurface.lines.first == "v=1", "\(snapshot.rasterSurface.lines)")
    let outerOnly = render(
      VStack { EnvironmentReader(\.setBProbe) { Text("v=\($0)") } }.environment(\.setBProbe, 7),
      "outerOnly")
    #expect(outerOnly.rasterSurface.lines.first == "v=7", "\(outerOnly.rasterSurface.lines)")
  }

  // `allowsHitTesting(false)` removes pointer interaction only: the control
  // keeps focus and keyboard activation.
  @Test func setB193AllowsHitTestingFalseKeepsKeyboardActivation() throws {
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBEnvironment", "hitTesting"), size: .init(width: 30, height: 5)
    ) {
      SetBHitTestingFixture()
    }
    defer { h.shutdown() }
    _ = try h.focusText("Go")
    _ = try h.pressKey(KeyPress(.return))
    #expect(h.frame.contains("n=1"), "\(h.frame)")
    _ = try h.clickText("Go")
    #expect(h.frame.contains("n=1"), "a click on a non-hit-testable control is inert: \(h.frame)")
    _ = try h.pressKey(KeyPress(.space))
    #expect(h.frame.contains("n=2"), "\(h.frame)")
  }

  // `ViewThatFits` judges only the constrained axes and falls back to the
  // last candidate when none fits.
  @Test func setB194ViewThatFitsJudgesOnlyTheConstrainedAxes() {
    let horizontal = render(
      ViewThatFits(in: .horizontal) {
        Text("abc").frame(width: 3, height: 5)
        Text("z")
      }, "horizontalOnly", width: 3, height: 1)
    #expect(horizontal.rasterSurface.lines.contains("abc"), "\(horizontal.rasterSurface.lines)")
    #expect(!horizontal.rasterSurface.lines.contains("z"), "\(horizontal.rasterSurface.lines)")
    let none = render(
      ViewThatFits {
        Text("AAAAAAAA")
        Text("BBBBBB")
      }, "noneFits", width: 3, height: 1)
    #expect(none.rasterSurface.lines.first?.contains("B") == true, "\(none.rasterSurface.lines)")
    #expect(none.rasterSurface.lines.first?.contains("A") != true, "\(none.rasterSurface.lines)")
    let both = render(
      ViewThatFits {
        Text("wide text here")
        Text("short")
      }, "secondFits", width: 6, height: 1)
    #expect(
      both.rasterSurface.lines.first?.hasPrefix("short") == true, "\(both.rasterSurface.lines)")
  }

  // A `GeometryReader` fills a finite proposal and takes ten cells on an
  // unspecified axis.
  @Test func setB195GeometryReaderFillsFiniteAxesAndDefaultsUnspecifiedOnes() {
    let both = render(
      GeometryReader { proxy in Text("\(proxy.size.width)x\(proxy.size.height)") }, "both",
      width: 12, height: 4)
    #expect(both.rasterSurface.lines.first == "12x4", "\(both.rasterSurface.lines)")
    let heightOnly = render(
      GeometryReader { proxy in Text("\(proxy.size.width)x\(proxy.size.height)") }, "heightOnly",
      width: nil, height: 4)
    #expect(heightOnly.rasterSurface.lines.first == "10x4", "\(heightOnly.rasterSurface.lines)")
    let neither = render(
      GeometryReader { proxy in Text("\(proxy.size.width)x\(proxy.size.height)") }, "neither",
      width: nil, height: nil)
    #expect(neither.rasterSurface.lines.first == "10x10", "\(neither.rasterSurface.lines)")
  }

  // `onPreferenceChange` runs once per distinct value: a re-render that
  // leaves the preference unchanged does not call it again.
  @Test func setB196PreferenceChangeObserverRunsOncePerDistinctValue() throws {
    let probe = SetBEventProbe()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBEnvironment", "prefChange"), size: .init(width: 30, height: 6)
    ) {
      SetBPreferenceChangeFixture(probe: probe)
    }
    defer { h.shutdown() }
    let initial = probe.events
    #expect(initial.last == "pref 1", "the first non-default value is delivered: \(initial)")
    _ = try h.clickText("Bump pref")
    #expect(probe.events.last == "pref 2", "\(probe.events)")
    let beforeOther = probe.events.count
    _ = try h.clickText("Bump other")
    _ = try h.clickText("Bump other")
    try #require(h.frame.contains("other 2"), "\(h.frame)")
    #expect(probe.events.count == beforeOther, "\(probe.events)")
    #expect(
      Set(probe.events).count == probe.events.count, "no value is reported twice: \(probe.events)")
  }

  // A `transformPreference` on a container sees the complete sibling fold
  // and its result is what the container publishes.
  @Test func setB197TransformPreferenceSeesTheWholeSiblingFold() {
    let transformed = fold(
      VStack {
        Text("a").preference(key: SetBListKey.self, value: ["a"])
        Text("b").preference(key: SetBListKey.self, value: ["b"])
      }
      .transformPreference(SetBListKey.self) { $0.append("t") }, "transform")
    #expect(transformed == ["a", "b", "t"], "\(transformed)")
    let doubled = fold(
      Text("a").preference(key: SetBListKey.self, value: ["a"])
        .transformPreference(SetBListKey.self) { $0.append("one") }
        .transformPreference(SetBListKey.self) { $0.append("two") }, "doubleTransform")
    #expect(doubled == ["a", "one", "two"], "\(doubled)")
    let empty = fold(
      Text("a").transformPreference(SetBListKey.self) { $0.append("only") }, "transformOnly")
    #expect(empty == ["only"], "\(empty)")
  }

  // Disabling a List disables its rows: the row selectors and items publish
  // `isEnabled == false` and the list has no focusable row.
  @Test func setB198DisabledListPublishesDisabledRows() {
    let probe = SetBOptionalBox<Int>(1)
    let snapshot = render(
      List(selection: probe.binding()) {
        Text("A").tag(1)
        Text("B").tag(2)
      }
      .disabled(true), "disabledList", width: 30, height: 6)
    let nodes = snapshot.semanticSnapshot.accessibilityNodes
    let selectors = nodes.filter { $0.label?.hasPrefix("Select row") == true }
    #expect(!selectors.isEmpty, "\(nodes.map(\.label))")
    #expect(selectors.allSatisfy { !$0.isEnabled }, "\(selectors.map { ($0.label, $0.isEnabled) })")
    let items = nodes.filter { $0.role == .custom("listitem") }
    #expect(items.allSatisfy { !$0.isEnabled }, "\(items.map { ($0.label, $0.isEnabled) })")
    #expect(
      snapshot.semanticSnapshot.focusRegions.isEmpty,
      "\(snapshot.semanticSnapshot.focusRegions.map(\.identity))")
  }

  // A control at opacity zero is invisible but present: it keeps its focus
  // region, its keyboard activation and its pointer hit region.
  @Test func setB199TransparentControlStaysFocusableAndHittable() throws {
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBEnvironment", "ghost"), size: .init(width: 30, height: 5)
    ) {
      SetBGhostButtonFixture()
    }
    defer { h.shutdown() }
    let region = try #require(
      h.runLoop.focusTracker.focusRegions.first {
        $0.identity == SetBGhostButtonFixture.ghostIdentity
      },
      "\(h.runLoop.focusTracker.focusRegions.map(\.identity))")
    _ = try h.focus(SetBGhostButtonFixture.ghostIdentity)
    _ = try h.pressKey(KeyPress(.return))
    #expect(h.frame.contains("n=1"), "\(h.frame)")
    let center = Point(
      CellPoint(x: region.rect.origin.x + region.rect.size.width / 2, y: region.rect.origin.y))
    _ = try h.click(center)
    #expect(h.frame.contains("n=2"), "\(h.frame)")
    #expect(!h.frame.contains("Ghost"), "the label is not painted: \(h.frame)")
  }

  // Chained `transformEnvironment` calls apply from the outside in, so the
  // transform nearest the view runs last on the value the outer one produced.
  @Test func setB200TransformEnvironmentAppliesFromTheOutsideIn() {
    let chained = render(
      EnvironmentReader(\.setBProbe) { Text("v=\($0)") }
        .transformEnvironment(\.setBProbe) { $0 += 1 }
        .transformEnvironment(\.setBProbe) { $0 *= 2 }, "chained")
    #expect(chained.rasterSurface.lines.first == "v=3", "\(chained.rasterSurface.lines)")
    let seeded = render(
      VStack {
        EnvironmentReader(\.setBProbe) { Text("v=\($0)") }
          .transformEnvironment(\.setBProbe) { $0 += 1 }
          .transformEnvironment(\.setBProbe) { $0 *= 2 }
      }
      .environment(\.setBProbe, 5), "seeded")
    #expect(seeded.rasterSurface.lines.first == "v=11", "\(seeded.rasterSurface.lines)")
    let reset = render(
      EnvironmentReader(\.setBProbe) { Text("v=\($0)") }
        .environment(\.setBProbe, 9)
        .transformEnvironment(\.setBProbe) { $0 += 1 }, "reset")
    #expect(reset.rasterSurface.lines.first == "v=9", "\(reset.rasterSurface.lines)")
  }
}

@MainActor
private final class SetBEventProbe {
  var events: [String] = []
}

@MainActor
private final class SetBOptionalBox<Value> {
  var value: Value?
  init(_ value: Value?) { self.value = value }
  func binding() -> Binding<Value?> {
    Binding(get: { self.value }, set: { self.value = $0 })
  }
}

private struct SetBHitTestingFixture: View {
  @State private var n = 0

  var body: some View {
    VStack(alignment: .leading) {
      VStack { Button("Go") { n += 1 } }.allowsHitTesting(false)
      Text("n=\(n)")
    }
  }
}

private struct SetBPreferenceChangeFixture: View {
  let probe: SetBEventProbe
  @State private var n = 1
  @State private var other = 0

  var body: some View {
    VStack(alignment: .leading) {
      Button("Bump pref") { n += 1 }
      Button("Bump other") { other += 1 }
      Text("other \(other)")
    }
    .preference(key: SetBIntKey.self, value: n)
    .onPreferenceChange(SetBIntKey.self) { probe.events.append("pref \($0)") }
  }
}

private struct SetBGhostButtonFixture: View {
  static let ghostIdentity = testIdentity("SetBEnvironment", "ghostButton")
  @State private var n = 0

  var body: some View {
    VStack(alignment: .leading) {
      Button("Ghost") { n += 1 }.opacity(0).id(Self.ghostIdentity)
      Text("n=\(n)")
    }
  }
}
