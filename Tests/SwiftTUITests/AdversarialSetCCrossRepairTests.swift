import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// F1 pass 3 (STUI-1282), area 7: lifetimes that cross several repairs —
/// pointer callbacks (STUI-1128) under presentation and tabs, trimmed content
/// shapes (STUI-1244), tab dormancy with navigation, focus and collections
/// (STUI-1233), and centre rounding at non-stack sites (STUI-1212).
@MainActor
@Suite(.serialized)
struct AdversarialSetCCrossRepairTests {
  // MARK: Pointer callbacks across presentation and tabs

  @Test func setC287SheetHoverHandlerRetiredAtDismissal() throws {
    let log = SetCXLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC287"), size: .init(width: 40, height: 10)
    ) { SetCXHoverSheetRoot(log: log) }
    defer { h.shutdown() }
    let baseline = h.pointerHoverHandlerCount
    _ = try h.clickText("Open")
    let point = try #require(h.point(forText: "hover target"))
    _ = try h.movePointer(to: point)
    try #require(log.hover.contains("entered"), "\(log.hover)")
    _ = try h.clickText("Close")
    #expect(h.pointerHoverHandlerCount == baseline)
    let count = log.hover.count
    _ = try h.movePointer(to: point)
    _ = try h.movePointer(to: Point(x: point.x + 1, y: point.y))
    #expect(log.hover.count <= count + 1, "\(log.hover)")
    #expect(!log.hover.dropFirst(count).contains("entered"), "\(log.hover)")
  }

  @Test func setC288DestinationWheelHandlerRetiredAtPop() throws {
    let log = SetCXLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC288"), size: .init(width: 40, height: 10)
    ) { SetCXWheelNavigationRoot(log: log) }
    defer { h.shutdown() }
    let baseline = h.runLoop.localPointerHandlerRegistry.snapshotWheel().count
    _ = try h.clickText("Push")
    let point = try #require(h.point(forText: "dest wheel"))
    _ = try h.scrollPointer(at: point, deltaY: 1)
    try #require(log.destinationWheel == 1)
    _ = try h.clickText("Back")
    #expect(h.runLoop.localPointerHandlerRegistry.snapshotWheel().count == baseline)
    _ = try h.scrollPointer(at: point, deltaY: 1)
    #expect(log.destinationWheel == 1)
  }

  @Test func setC289TabHoverHandlerRetiredAtSwitch() throws {
    let log = SetCXLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC289"), size: .init(width: 40, height: 10)
    ) { SetCXTabsRoot(log: log) }
    defer { h.shutdown() }
    let point = try #require(h.point(forText: "hover A"))
    _ = try h.movePointer(to: point)
    try #require(log.hover.contains("entered"))
    log.selection = "b"
    _ = try h.renderAfterExternalMutation()
    #expect(h.pointerHoverHandlerCount == 0)
    let count = log.hover.count
    _ = try h.movePointer(to: Point(x: point.x + 1, y: point.y))
    #expect(!log.hover.dropFirst(count).contains("entered"), "\(log.hover)")
  }

  @Test func setC290TrimmedContentShapeUnderOffsetTaps() throws {
    let log = SetCXLog()
    let outline = Circle().trim(from: 0, to: 0.5)
      .path(in: Rect(origin: Point(x: 0, y: 0), size: Size(width: 10, height: 5)))
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC290"), size: .init(width: 20, height: 6)
    ) {
      Circle().trim(from: 0, to: 0.5).fill().frame(width: 10, height: 5)
        .contentShape(outline)
        .onTapGesture { log.taps += 1 }
        .offset(x: 3)
        .frame(width: 20, height: 6, alignment: .topLeading)
    }
    defer { h.shutdown() }
    let rows = h.frame.split(separator: "\n", omittingEmptySubsequences: false).map(Array.init)
    var target: Point?
    for (y, row) in rows.enumerated() {
      if let x = row.firstIndex(where: { $0 != " " }) {
        target = Point(x: Double(x) + 0.5, y: Double(y) + 0.5)
        break
      }
    }
    let point = try #require(target, "nothing painted: \(h.frame)")
    try #require(point.x >= 3, "offset did not move the fill: \(h.frame)")
    _ = try h.click(point)
    #expect(log.taps == 1, "click at \(point)\n\(h.frame)")
  }

  @Test func setC291SheetLazyEndReachesLastRow() throws {
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC291"), size: .init(width: 30, height: 12)
    ) { SetCXLazySheetRoot() }
    defer { h.shutdown() }
    _ = try h.clickText("Open")
    _ = try h.focusText("vrow 0")
    _ = try h.pressKey(.init(.end))
    #expect(h.frame.contains("vrow 119"), "\(h.frame)")
  }

  // MARK: Tab dormancy with navigation, focus and collections

  @Test func setC292TabArchivedDestinationKeepsState() throws {
    let log = SetCXLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC292"), size: .init(width: 40, height: 10)
    ) { SetCXTabsRoot(log: log, navigation: true) }
    defer { h.shutdown() }
    _ = try h.clickText("Push")
    try #require(h.frame.contains("dest 0"), "\(h.frame)")
    _ = try h.clickText("Increment")
    _ = try h.clickText("Increment")
    _ = try h.clickText("Increment")
    try #require(h.frame.contains("dest 3"), "\(h.frame)")
    // STUI-1307: before the repair each return re-minted the destination and
    // stranded its predecessor's restored records (2, 4, 6). The census is
    // read here and the sampled-frame trace is kept local to this scope
    // (setC006's pattern), so the gate's trace scan sees only unexpected ones.
    var stranded: [Int] = []
    try setCWithoutSoundnessTrace {
      for _ in 0..<3 {
        log.selection = "b"
        _ = try h.renderAfterExternalMutation()
        try #require(h.frame.contains("tab b"), "\(h.frame)")
        log.selection = "a"
        _ = try h.renderAfterExternalMutation()
        _ = try h.render()
        stranded.append(
          h.runLoop.renderer.viewGraph.debugTeardownCoherenceViolation()?.unreachableCount ?? 0)
      }
    }
    try #require(h.frame.contains("dest"), "the destination is presented again: \(h.frame)")
    #expect(h.frame.contains("dest 3"), "\(h.frame)")
    #expect(stranded.allSatisfy { $0 == 0 }, "stranded node counts per round trip \(stranded)")
  }

  @Test func setC293TabArchivedDestinationFocusRestored() throws {
    let log = SetCXLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC293"), size: .init(width: 40, height: 10)
    ) { SetCXTabsRoot(log: log, navigation: true) }
    defer { h.shutdown() }
    _ = try h.clickText("Push")
    _ = try h.focusText("draft")
    try #require(log.fieldFocused == true, "\(String(describing: log.fieldFocused))")
    try setCWithoutSoundnessTrace {
      log.selection = "b"
      _ = try h.renderAfterExternalMutation()
      log.selection = "a"
      _ = try h.renderAfterExternalMutation()
      _ = try h.render()
    }
    try #require(h.frame.contains("draft"), "\(h.frame)")
    setCKnown(setCSTUI1308) {
      #expect(log.fieldFocused == true, "\(String(describing: log.fieldFocused))")
    }
  }

  // Control for setC293 (minimization, not a corpus case): the same field
  // directly in tab A's content, without a navigation destination. It loses
  // focus as well (STUI-1308), independent of setC292's re-mint (STUI-1307).
  @Test func setC293ControlTabContentFocusRestored() throws {
    let log = SetCXLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC293-control"), size: .init(width: 40, height: 10)
    ) { SetCXTabsRoot(log: log, focusField: true) }
    defer { h.shutdown() }
    _ = try h.focusText("draft")
    try #require(log.fieldFocused == true)
    log.selection = "b"
    _ = try h.renderAfterExternalMutation()
    log.selection = "a"
    _ = try h.renderAfterExternalMutation()
    _ = try h.render()
    setCKnown(setCSTUI1308) {
      #expect(
        log.fieldFocused == true,
        "history \(log.focusHistory) focus \(String(describing: h.runLoop.focusTracker.currentFocusIdentity))"
      )
    }
  }

  @Test func setC294TabListWindowRestored() throws {
    let log = SetCXLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC294"), size: .init(width: 40, height: 10)
    ) { SetCXTabsRoot(log: log, list: true) }
    defer { h.shutdown() }
    let point = try #require(h.point(forText: "L000"))
    _ = try h.scrollPointer(at: point, deltaY: 20)
    let top = setCXTopListRow(h)
    try #require(top != nil && top != "L000", "\(h.frame)")
    log.selection = "b"
    _ = try h.renderAfterExternalMutation()
    log.selection = "a"
    _ = try h.renderAfterExternalMutation()
    #expect(setCXTopListRow(h) == top, "\(h.frame)")
  }

  @Test func setC295TabListWindowKeptAcrossDormantAppend() throws {
    let log = SetCXLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC295"), size: .init(width: 40, height: 10)
    ) { SetCXTabsRoot(log: log, list: true) }
    defer { h.shutdown() }
    let point = try #require(h.point(forText: "L000"))
    _ = try h.scrollPointer(at: point, deltaY: 20)
    let top = setCXTopListRow(h)
    log.selection = "b"
    _ = try h.renderAfterExternalMutation()
    log.listCount += 50
    log.selection = "a"
    _ = try h.renderAfterExternalMutation()
    #expect(setCXTopListRow(h) == top, "\(h.frame)")
  }

  @Test func setC296TabTaskIDRestartsWithRestoredID() throws {
    let log = SetCXLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC296"), size: .init(width: 40, height: 10)
    ) { SetCXTabsRoot(log: log, task: true) }
    defer { h.shutdown() }
    _ = try h.clickText("Token")
    _ = try h.clickText("Token")
    try #require(h.frame.contains("token 2"), "\(h.frame)")
    for _ in 0..<3 {
      log.selection = "b"
      _ = try h.renderAfterExternalMutation()
      log.selection = "a"
      _ = try h.renderAfterExternalMutation()
    }
    #expect(h.activeTaskCount == 1)
    #expect(h.frame.contains("token 2"), "\(h.frame)")
  }

  @Test func setC297TabListSelectionRestored() throws {
    let log = SetCXLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC297"), size: .init(width: 40, height: 10)
    ) { SetCXTabsRoot(log: log, selectableList: true) }
    defer { h.shutdown() }
    _ = try h.clickText("S3")
    try #require(h.frame.contains("selected S3"), "\(h.frame)")
    log.selection = "b"
    _ = try h.renderAfterExternalMutation()
    log.selection = "a"
    _ = try h.renderAfterExternalMutation()
    #expect(h.frame.contains("selected S3"), "\(h.frame)")
  }

  // MARK: Centre rounding outside stacks (FW-D's single rule)

  @Test func setC298CentredTableColumnPutsOddCellTrailing() {
    func column(of text: String) -> Int? {
      let lines = DefaultRenderer().render(
        Table(
          [SetCXRow(id: 1, text: text)],
          columns: [TableColumn("C", width: 5, alignment: .center)]
        ) { row in Text(row.text) }.tableHeaders(.hidden),
        context: .init(identity: testIdentity("setC298", text)),
        proposal: .init(width: 20, height: 4)
      ).rasterSurface.lines
      guard let line = lines.first(where: { $0.contains(text) }),
        let border = line.firstIndex(of: "│"), let start = line.range(of: text)?.lowerBound
      else { return nil }
      return line.distance(from: border, to: start)
    }
    let odd = column(of: "abcd")
    let even = column(of: "abc")
    let three = column(of: "ab")
    #expect(odd != nil && even != nil && three != nil)
    if let odd, let even, let three {
      // Leftovers 1, 2, 3: leading shares floor(leftover / 2).
      #expect(even == odd + 1, "abcd at \(odd), abc at \(even)")
      #expect(three == odd + 1, "abcd at \(odd), ab at \(three)")
    }
  }

  // Correction C0 (compile): the framework has no `multilineTextAlignment`;
  // the case measures a centring frame, the site FW-D's rule came from.
  @Test func setC299CentredFramePutsOddCellTrailing() {
    func start(of text: String, width: Int) -> Int? {
      let lines = DefaultRenderer().render(
        HStack(spacing: 0) {
          Text("|")
          Text(text).frame(width: width)
          Text("|")
        },
        context: .init(identity: testIdentity("setC299", "\(text)-\(width)")),
        proposal: .init(width: 20, height: 2)
      ).rasterSurface.lines
      guard let line = lines.first(where: { $0.contains(text) }),
        let bar = line.firstIndex(of: "|"), let found = line.range(of: text)
      else { return nil }
      return line.distance(from: bar, to: found.lowerBound) - 1
    }
    // Leftover 3 in a frame of 6 puts one cell before "abc" and two after.
    #expect(start(of: "abc", width: 6) == 1)
    // Leftover 1 puts no cell before "abcde".
    #expect(start(of: "abcde", width: 6) == 0)
  }

  @Test func setC300TabSwitchRemovesTabSheet() throws {
    let log = SetCXLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC300"), size: .init(width: 40, height: 10)
    ) { SetCXTabsRoot(log: log, sheet: true) }
    defer { h.shutdown() }
    let baseline = h.activeTaskCount
    _ = try h.clickText("Sheet")
    try #require(h.frame.contains("tab sheet"), "\(h.frame)")
    try #require(h.activeTaskCount == baseline + 1)
    log.selection = "b"
    _ = try h.renderAfterExternalMutation()
    #expect(!h.frame.contains("tab sheet"), "\(h.frame)")
    #expect(h.activeTaskCount == baseline)
  }
}

// MARK: - Fixtures

/// Runs `body` with the soundness trace off and restores the teardown
/// counters, so a census violation the test asserts itself does not reach the
/// gate's final trace scan (the setC006 / setB201 pattern).
@MainActor
private func setCWithoutSoundnessTrace<T>(_ body: () throws -> T) rethrows -> T {
  let savedTrace = SoundnessProbeConfiguration.isTraceEnabled
  let savedViolations = SoundnessProbeConfiguration.teardownCoherenceViolationCount
  let savedLeaks = SoundnessProbeConfiguration.teardownCoherenceLeakCount
  let savedUnreachable = SoundnessProbeConfiguration.lastTeardownLeakUnreachableCount
  SoundnessProbeConfiguration.isTraceEnabled = false
  defer {
    SoundnessProbeConfiguration.isTraceEnabled = savedTrace
    SoundnessProbeConfiguration.teardownCoherenceViolationCount = savedViolations
    SoundnessProbeConfiguration.teardownCoherenceLeakCount = savedLeaks
    SoundnessProbeConfiguration.lastTeardownLeakUnreachableCount = savedUnreachable
  }
  return try body()
}

@MainActor
private final class SetCXLog {
  var hover: [String] = []
  var destinationWheel = 0
  var taps = 0
  var selection = "a"
  var fieldFocused: Bool?
  var focusHistory: [Bool] = []
  var listCount = 100

  var selectionBinding: Binding<String> {
    Binding(get: { self.selection }, set: { self.selection = $0 })
  }
}

private struct SetCXRow: Identifiable, Sendable {
  var id: Int
  var text: String
}

@MainActor
private func setCXTopListRow<V: View>(_ h: StressRuntimeHarness<V>) -> String? {
  h.frame.split(separator: "\n").compactMap { line in
    line.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
      .first { $0.hasPrefix("L") && $0.count == 4 }
  }.first
}

private func setCXHoverName(_ phase: HoverPhase) -> String {
  switch phase {
  case .entered: "entered"
  case .moved: "moved"
  case .exited: "exited"
  }
}

private struct SetCXHoverSheetRoot: View {
  let log: SetCXLog
  @State private var shown = false

  var body: some View {
    Button("Open") { shown = true }
      .sheet(isPresented: $shown) {
        VStack(alignment: .leading, spacing: 0) {
          Text("hover target").onPointerHover { log.hover.append(setCXHoverName($0)) }
          Button("Close") { shown = false }
        }
      }
  }
}

private struct SetCXWheelNavigationRoot: View {
  let log: SetCXLog
  @State private var pushed = false

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 0) {
        Text("root wheel").onScrollWheel { _ in .handled }
        Button("Push") { pushed = true }
      }
      .navigationDestination(isPresented: $pushed) {
        VStack(alignment: .leading, spacing: 0) {
          Text("dest wheel").onScrollWheel { _ in
            log.destinationWheel += 1
            return .handled
          }
          Button("Back") { pushed = false }
        }
      }
    }
  }
}

private struct SetCXLazySheetRoot: View {
  @State private var shown = false

  var body: some View {
    Button("Open") { shown = true }
      .sheet(isPresented: $shown) {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<120, id: \.self) { i in Text("vrow \(i)").frame(height: i < 40 ? 1 : 3) }
          }
        }.scrollIndicators(.hidden).frame(height: 8)
      }
  }
}

private struct SetCXTabsRoot: View {
  let log: SetCXLog
  var navigation = false
  var list = false
  var task = false
  var selectableList = false
  var sheet = false
  var focusField = false

  var body: some View {
    TabView(selection: log.selectionBinding) {
      Tab("A", value: "a") {
        SetCXTabAContent(
          log: log, navigation: navigation, list: list, task: task,
          selectableList: selectableList, sheet: sheet, focusField: focusField)
      }
      Tab("B", value: "b") { Text("tab b") }
    }
    .tabViewStyle(.literalTabs)
  }
}

private struct SetCXTabAContent: View {
  let log: SetCXLog
  let navigation: Bool
  let list: Bool
  let task: Bool
  let selectableList: Bool
  let sheet: Bool
  let focusField: Bool
  @State private var pushed = false
  @State private var token = 0
  @State private var selected: String?
  @State private var sheetShown = false

  var body: some View {
    if navigation {
      NavigationStack {
        Button("Push") { pushed = true }
          .navigationDestination(isPresented: $pushed) { SetCXDestination(log: log) }
      }
    } else if list {
      List(Array(0..<log.listCount), id: \.self) { i in
        Text(i < 10 ? "L00\(i)" : i < 100 ? "L0\(i)" : "L\(i)")
      }
    } else if task {
      VStack(alignment: .leading, spacing: 0) {
        Text("token \(token)").task(id: token) { await suspendUntilCancelled() }
        Button("Token") { token += 1 }
      }
    } else if selectableList {
      VStack(alignment: .leading, spacing: 0) {
        Text("selected \(selected ?? "none")")
        List(["S1", "S2", "S3", "S4"], id: \.self, selection: $selected) { s in Text(s) }
      }
    } else if sheet {
      Button("Sheet") { sheetShown = true }
        .sheet(isPresented: $sheetShown) {
          Text("tab sheet").task { await suspendUntilCancelled() }
        }
    } else if focusField {
      SetCXDestination(log: log)
    } else {
      Text("hover A").onPointerHover { log.hover.append(setCXHoverName($0)) }
    }
  }
}

private struct SetCXDestination: View {
  let log: SetCXLog
  @State private var count = 0
  @State private var draft = "draft"
  @FocusState private var focused: Bool

  var body: some View {
    log.fieldFocused = focused
    log.focusHistory.append(focused)
    return VStack(alignment: .leading, spacing: 0) {
      Text("dest \(count)")
      Button("Increment") { count += 1 }
      TextField("field", text: $draft).focused($focused)
    }
  }
}

private let setCSTUI1308 = Comment(
  rawValue:
    "STUI-1308 (NEW-13): returning to a tab does not restore keyboard focus to the field "
    + "whose @FocusState was true at departure; runtime focus moves to the tab "
    + "container at departure and the restored FocusState reads false "
    + "(FocusState.swift:433-441 runtime store); contract: "
    + "Dormant-Tab-State.md:43, 107-109")
