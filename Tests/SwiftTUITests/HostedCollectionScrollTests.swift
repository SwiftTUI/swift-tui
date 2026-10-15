import SwiftTUIRuntime
@_spi(Testing) import SwiftTUITestSupport
import SwiftTUIViews
import Testing

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct HostedCollectionScrollTests {
  @Test(
    "scene-hosted row growth preserves focus and selection in an unchanged viewport",
    arguments: [false, true]
  )
  func rowGrowthKeepsFocusedRow(multiple: Bool) async throws {
    let recorder = HostedCollectionFrameRecorder()
    let surface = HostedRasterSurface(
      surfaceSize: CellSize(width: 32, height: 12),
      appearance: .fallback,
      onFrame: { recorder.receive($0) }
    )
    let session = try HostedSceneSession(
      for: HostedRowGrowthListApp(multiple: multiple),
      sceneID: WindowIdentifier("row-growth-list"),
      surface: surface
    )
    let run = Task { try await session.start() }
    do {
      var previous = try await recorder.wait(description: "initial focus on row 0") {
        $0.focusesHostedRow(0)
      }
      for row in 1...7 {
        session.send(.key(KeyPress(.arrowDown)))
        previous = try await recorder.wait(
          after: previous.sequence, description: "downward focus on row \(row)"
        ) { $0.focusesHostedRow(row) }
      }
      if multiple {
        session.send(.key(KeyPress(.space)))
        previous = try await recorder.wait(
          after: previous.sequence, description: "check row 7 and retain offscreen row 0"
        ) { $0.containsHostedToken("Checked=0,7") && $0.focusesHostedRow(7) }
      }
      #expect(!previous.raster.lines.contains { $0.contains("Row 00") })
      let focusedIdentity = previous.focusedIdentity
      let viewport = try #require(previous.semantics.scrollRoutes.first?.viewportRect)
      for (step, padding) in [1, 0, 1, 0, 1, 0].enumerated() {
        let beforeResize = previous.sequence
        session.send(.key(KeyPress(.character("p"), modifiers: .ctrl)))
        previous = try await recorder.wait(
          after: previous.sequence, description: "row padding changes to \(padding)"
        ) { $0.containsHostedToken("Padding=\(padding)") }
        let firstResize = try recorder.firstFrame(
          after: beforeResize, containing: "Padding=\(padding)")
        #expect(firstResize.focusesHostedRow(7))
        #expect(firstResize.focusedIdentity == focusedIdentity)
        #expect(firstResize.containsHostedToken(multiple ? "Checked=0,7" : "Selected=7"))
        let raster = previous.raster.lines.joined(separator: "\n")
        let targetIsFocused = previous.focusesHostedRow(7)
        try #require(targetIsFocused, "row growth preserves focus:\n\(raster)")
        #expect(previous.focusedIdentity == focusedIdentity)
        #expect(previous.semantics.scrollRoutes.first?.viewportRect == viewport)
        #expect(previous.containsHostedToken(multiple ? "Checked=0,7" : "Selected=7"))
        let region = try #require(
          previous.semantics.focusRegions.first { $0.identity == focusedIdentity })
        #expect(region.rect.size.height == (padding == 0 ? 2 : 4))
        #expect(previous.raster.lines.contains { $0.contains("Detail 7:0") })

        session.send(.key(KeyPress(.arrowDown)))
        previous = try await recorder.wait(
          after: previous.sequence, description: "row 8 immediately after padding \(padding)"
        ) { $0.focusesHostedRow(8) }
        #expect(previous.containsHostedToken(multiple ? "Checked=0,7" : "Selected=8"))
        session.send(.key(KeyPress(.arrowUp)))
        previous = try await recorder.wait(
          after: previous.sequence, description: "row 7 after reversing at padding \(padding)"
        ) { $0.focusesHostedRow(7) }
        #expect(previous.focusedIdentity == focusedIdentity)
        #expect(previous.containsHostedToken(multiple ? "Checked=0,7" : "Selected=7"))

        session.send(.key(KeyPress(.return)))
        previous = try await recorder.wait(
          after: previous.sequence, description: "Return acts on row 7 after resize \(step)"
        ) {
          $0.containsHostedToken(multiple ? "Checked=0" : "Activated=7")
            && $0.containsHostedToken("Count=\(multiple ? 0 : step + 1)")
            && $0.focusesHostedRow(7)
        }
        if multiple {
          session.send(.key(KeyPress(.return)))
          previous = try await recorder.wait(
            after: previous.sequence, description: "restore row 7 membership after resize \(step)"
          ) { $0.containsHostedToken("Checked=0,7") && $0.focusesHostedRow(7) }
        }
      }
      #expect(previous.containsHostedToken(multiple ? "Checked=0,7" : "Selected=7"))
      #expect(try await session.stopAndWait() == .inputEnded)
      #expect(try await run.value == .inputEnded)
    } catch {
      session.stop()
      _ = await run.result
      throw error
    }
  }

  @Test("an authored focus request wins over simultaneous row growth")
  func authoredFocusRequestWinsOverGrowth() async throws {
    try await withFocusedPriorityList { session, recorder, initial in
      session.send(.key(KeyPress(.character("f"), modifiers: .ctrl)))
      let requested = try await recorder.wait(
        after: initial.sequence, description: "growth and authored focus request"
      ) { $0.containsHostedToken("Padding=1") }
      let firstResize = try recorder.firstFrame(after: initial.sequence, containing: "Padding=1")
      #expect(firstResize.focusesHostedText("External action"))
      #expect(firstResize.containsHostedToken("Selected=7"))
      #expect(firstResize.containsHostedToken("Activated=-"))
      try #require(requested.focusesHostedText("External action"))
      #expect(requested.containsHostedToken("Selected=7"))
      #expect(requested.containsHostedToken("Activated=-"))
      session.send(.key(KeyPress(.return)))
      let activated = try await recorder.wait(
        after: requested.sequence, description: "Return activates the requested sibling"
      ) { $0.containsHostedToken("Action=1") }
      #expect(activated.focusesHostedText("External action"))
      #expect(activated.containsHostedToken("Selected=7"))
      #expect(activated.containsHostedToken("Activated=-"))
    }
  }

  @Test("row geometry changes do not steal focus or input from a sibling editor")
  func externalEditorKeepsFocusDuringGeometryChanges() async throws {
    try await withFocusedPriorityList { session, recorder, initial in
      session.send(.key(KeyPress(.character("e"), modifiers: .ctrl)))
      var previous = try await recorder.wait(
        after: initial.sequence, description: "focus the sibling editor"
      ) { $0.focusedIdentity == HostedRowGrowthPriorityIDs.editor }
      let editorIdentity = try #require(previous.focusedIdentity)
      for (padding, character, text) in [(1, Character("A"), "A"), (0, Character("B"), "AB")] {
        let beforeResize = previous.sequence
        session.send(.key(KeyPress(.character("p"), modifiers: .ctrl)))
        previous = try await recorder.wait(
          after: previous.sequence, description: "padding \(padding) with sibling editor focused"
        ) { $0.containsHostedToken("Padding=\(padding)") }
        let firstResize = try recorder.firstFrame(
          after: beforeResize, containing: "Padding=\(padding)")
        #expect(firstResize.focusedIdentity == editorIdentity)
        #expect(previous.focusedIdentity == editorIdentity)
        session.send(.key(KeyPress(.character(character))))
        previous = try await recorder.wait(
          after: previous.sequence, description: "the sibling editor receives \(text)"
        ) { $0.containsHostedToken("Editor=\(text)") }
        #expect(previous.focusedIdentity == editorIdentity)
        #expect(previous.focusesHostedText(text))
        #expect(previous.containsHostedToken("Selected=7"))
        #expect(previous.containsHostedToken("Activated=-"))
      }
      session.send(.key(KeyPress(.return)))
      let submitted = try await recorder.wait(
        after: previous.sequence, description: "Return submits the sibling editor"
      ) { $0.containsHostedToken("Submit=1") }
      #expect(submitted.focusedIdentity == editorIdentity)
      #expect(submitted.containsHostedToken("Selected=7"))
      #expect(submitted.containsHostedToken("Activated=-"))
    }
  }

  @Test("an explicit focus clear during growth stays cleared after a public host refresh")
  func authoredFocusClearSurvivesHostRefresh() async throws {
    try await withFocusedPriorityList { session, recorder, initial in
      session.send(.key(KeyPress(.character("e"), modifiers: .ctrl)))
      let editor = try await recorder.wait(
        after: initial.sequence, description: "establish the focus relationship to clear"
      ) { $0.focusedIdentity == HostedRowGrowthPriorityIDs.editor }
      session.send(.key(KeyPress(.character("c"), modifiers: .ctrl)))
      let cleared = try await recorder.wait(
        after: editor.sequence, description: "growth and authored focus clear"
      ) { $0.containsHostedToken("Padding=1") }
      let firstResize = try recorder.firstFrame(after: editor.sequence, containing: "Padding=1")
      #expect(firstResize.focusedIdentity == nil)
      #expect(cleared.focusedIdentity == nil)
      #expect(cleared.containsHostedToken("Selected=7"))
      session.requestSurfaceRefresh()
      _ = try await recorder.wait(
        after: cleared.sequence, description: "public host refresh after the focus clear"
      ) { _ in true }
      let refreshed = try recorder.firstFrame(after: cleared.sequence, containing: "Padding=1")
      #expect(refreshed.focusedIdentity == nil)
      #expect(refreshed.containsHostedToken("Selected=7"))
      #expect(refreshed.containsHostedToken("Activated=-"))
    }
  }

  @Test("a simultaneous explicit scroll command wins over row growth recovery")
  func explicitScrollCommandWinsOverGrowth() async throws {
    try await withFocusedPriorityList { session, recorder, initial in
      session.send(.key(KeyPress(.character("s"), modifiers: .ctrl)))
      _ = try await recorder.wait(
        after: initial.sequence, description: "growth and explicit scroll to row 10"
      ) { $0.containsHostedToken("Padding=1") && $0.containsHostedToken("Scroll=true") }
      let scrolled = try recorder.firstFrame(after: initial.sequence, containing: "Padding=1")
      #expect(scrolled.containsHostedToken("Scroll=true"))
      let viewport = try #require(scrolled.semantics.scrollRoutes.first?.viewportRect)
      let titleLine = try #require(scrolled.raster.lines.firstIndex { $0.contains("Row 10") })
      #expect(titleLine == viewport.origin.y + 1)
      #expect(scrolled.raster.lines.contains { $0.contains("Detail 10:0") })
      #expect(!scrolled.raster.lines.contains { $0.contains("Row 07") })
      #expect(scrolled.containsHostedToken("Activated=-"))
      session.send(.key(KeyPress(.character("i"), modifiers: .ctrl)))
      let inert = try await recorder.wait(
        after: scrolled.sequence, description: "explicit scroll window survives another frame"
      ) { $0.containsHostedToken("Inert=1") }
      #expect(inert.raster.lines.firstIndex { $0.contains("Row 10") } == titleLine)
      #expect(!inert.raster.lines.contains { $0.contains("Row 07") })
    }
  }

  private func withFocusedPriorityList(
    _ journey:
      @MainActor (
        HostedSceneSession, HostedCollectionFrameRecorder, SemanticHostFrame
      ) async throws -> Void
  ) async throws {
    let recorder = HostedCollectionFrameRecorder()
    let surface = HostedRasterSurface(
      surfaceSize: CellSize(width: 40, height: 16), appearance: .fallback,
      onFrame: { recorder.receive($0) }
    )
    let session = try HostedSceneSession(
      for: HostedRowGrowthPriorityApp(),
      sceneID: WindowIdentifier("row-growth-priority"), surface: surface
    )
    let run = Task { try await session.start() }
    do {
      var previous = try await recorder.wait(description: "initial row 0 in the priority fixture") {
        $0.focusesHostedRow(0)
      }
      for row in 1...7 {
        session.send(.key(KeyPress(.arrowDown)))
        previous = try await recorder.wait(
          after: previous.sequence, description: "priority fixture focus on row \(row)"
        ) { $0.focusesHostedRow(row) }
      }
      #expect(previous.containsHostedToken("Selected=7"))
      try await journey(session, recorder, previous)
      #expect(try await session.stopAndWait() == .inputEnded)
      #expect(try await run.value == .inputEnded)
    } catch {
      session.stop()
      _ = await run.result
      throw error
    }
  }

  @Test("scene-hosted mixed-height list reveals every selected row when navigation reverses")
  func mixedHeightListKeepsReverseNavigationTarget() async throws {
    let recorder = HostedCollectionFrameRecorder()
    let surface = HostedRasterSurface(
      surfaceSize: CellSize(width: 32, height: 12),
      appearance: .fallback,
      onFrame: { recorder.receive($0) }
    )
    let session = try HostedSceneSession(
      for: HostedMixedHeightListApp(),
      sceneID: WindowIdentifier("mixed-height-list"),
      surface: surface
    )
    let run = Task { try await session.start() }
    do {
      var previous = try await recorder.wait(description: "initial focus on row 0") {
        $0.focusesHostedRow(0)
      }
      try requireWholeHostedRow(0, in: previous)
      for row in 1..<12 {
        session.send(.key(KeyPress(.arrowDown)))
        previous = try await recorder.wait(
          after: previous.sequence, description: "downward focus on row \(row)"
        ) { $0.focusesHostedRow(row) }
        try requireWholeHostedRow(row, in: previous)
      }

      session.send(.key(KeyPress(.return)))
      previous = try await recorder.wait(
        after: previous.sequence, description: "activation of row 11"
      ) { $0.containsHostedToken("Activated=11") && $0.containsHostedToken("Count=1") }
      try requireWholeHostedRow(11, in: previous)

      for row in (0..<11).reversed() {
        session.send(.key(KeyPress(.arrowUp)))
        previous = try await recorder.wait(
          after: previous.sequence, description: "reverse focus on row \(row)"
        ) { $0.focusesHostedRow(row) }
        try requireWholeHostedRow(row, in: previous)
      }

      session.send(.key(KeyPress(.return)))
      let activated = try await recorder.wait(
        after: previous.sequence, description: "activation of row 0 after reversal"
      ) { $0.containsHostedToken("Activated=0") && $0.containsHostedToken("Count=2") }
      try requireWholeHostedRow(0, in: activated)

      #expect(try await session.stopAndWait() == .inputEnded)
      #expect(try await run.value == .inputEnded)
    } catch {
      session.stop()
      _ = await run.result
      throw error
    }
  }
}

private struct HostedRowGrowthListApp {
  let multiple: Bool

  nonisolated init() {
    multiple = false
  }

  nonisolated init(multiple: Bool) {
    self.multiple = multiple
  }
}

extension HostedRowGrowthListApp: App {
  var body: some Scene {
    WindowGroup(id: WindowIdentifier("row-growth-list")) {
      HostedRowGrowthListView(multiple: multiple)
    }
    .exitOnKeys([])
  }
}

@MainActor
private struct HostedRowGrowthListView {
  let multiple: Bool
  @State private var selected: Int? = 0
  @State private var checked: Set<Int> = [0]
  @State private var padding = 0
  @State private var activated: Int?
  @State private var activationCount = 0

  private func rowContent(_ row: HostedMixedHeightRow) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(row.title)
      ForEach(0..<(row.id % 3), id: \.self) { line in Text("Detail \(row.id):\(line)") }
    }
    .padding(.vertical, padding)
  }
}

extension HostedRowGrowthListView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Group {
        if multiple {
          List(HostedMixedHeightRow.fixtures, selection: $checked) { row in rowContent(row) }
        } else {
          List(
            HostedMixedHeightRow.fixtures, selection: $selected,
            onActivate: { row in
              activated = row
              activationCount += 1
            }
          ) { row in rowContent(row) }
        }
      }
      .listStyle(HostedRowGrowthListStyle())
      .focusable(false)
      .frame(height: 8, alignment: .topLeading)
      Text("Selected=\(selected.map { String($0) } ?? "-")")
      Text("Checked=\(checked.sorted().map { String($0) }.joined(separator: ","))")
      Text("Activated=\(activated.map { String($0) } ?? "-") Count=\(activationCount)")
      Text("Padding=\(padding)")
    }
    .onKeyPress(.character("p"), modifiers: .ctrl) { _ in
      padding = 1 - padding
      return .handled
    }
  }
}

private struct HostedRowGrowthListStyle: ListStyle {
  func resolvePresentation(for configuration: ListStyleConfiguration) -> ListStylePresentation {
    ListStylePresentation(showsRowSeparators: false, showsSectionSeparators: false)
  }
}

private struct HostedRowGrowthPriorityApp {}

private enum HostedRowGrowthPriorityIDs {
  static let editor = Identity(components: ["HostedRowGrowthEditor"])
}

extension HostedRowGrowthPriorityApp: App {
  var body: some Scene {
    WindowGroup(id: WindowIdentifier("row-growth-priority")) { HostedRowGrowthPriorityView() }
      .exitOnKeys([])
  }
}

@MainActor
private struct HostedRowGrowthPriorityView {
  @State private var selected: Int? = 0
  @State private var padding = 0
  @State private var activated: Int?
  @State private var editor = ""
  @State private var actionCount = 0
  @State private var submitCount = 0
  @State private var inertCount = 0
  @State private var scrollAccepted = false
  @FocusState private var focus: Field?

  private enum Field: Hashable {
    case action
    case editor
  }
}

extension HostedRowGrowthPriorityView: View {
  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        List(
          HostedMixedHeightRow.fixtures, selection: $selected,
          onActivate: { activated = $0 }
        ) { row in
          VStack(alignment: .leading, spacing: 0) {
            Text(row.title)
            ForEach(0..<(row.id % 3), id: \.self) { line in Text("Detail \(row.id):\(line)") }
          }
          .padding(.vertical, padding)
        }
        .listStyle(HostedRowGrowthListStyle())
        .scrollIndicators(.hidden)
        .focusable(false)
        .frame(height: 8, alignment: .topLeading)
        Button("External action") { actionCount += 1 }
          .focused($focus, equals: .action)
        TextField("External editor", text: $editor)
          .id(HostedRowGrowthPriorityIDs.editor)
          .focused($focus, equals: .editor)
          .onSubmit { submitCount += 1 }
        Text("Selected=\(selected.map { String($0) } ?? "-") Padding=\(padding)")
        Text("Activated=\(activated.map { String($0) } ?? "-") Action=\(actionCount)")
        Text("Editor=\(editor) Submit=\(submitCount)")
        Text("Scroll=\(scrollAccepted) Inert=\(inertCount)")
      }
      .onKeyPress(.character("p"), modifiers: .ctrl) { _ in
        padding = 1 - padding
        return .handled
      }
      .onKeyPress(.character("f"), modifiers: .ctrl) { _ in
        padding = 1
        focus = .action
        return .handled
      }
      .onKeyPress(.character("e"), modifiers: .ctrl) { _ in
        focus = .editor
        return .handled
      }
      .onKeyPress(.character("c"), modifiers: .ctrl) { _ in
        padding = 1
        focus = nil
        return .handled
      }
      .onKeyPress(.character("s"), modifiers: .ctrl) { _ in
        padding = 1
        scrollAccepted = proxy.scrollTo(10, anchor: .top)
        return .handled
      }
      .onKeyPress(.character("i"), modifiers: .ctrl) { _ in
        inertCount += 1
        return .handled
      }
    }
  }
}

private struct HostedMixedHeightListApp {}

extension HostedMixedHeightListApp: App {
  var body: some Scene {
    WindowGroup(id: WindowIdentifier("mixed-height-list")) {
      HostedMixedHeightListView()
    }
    .exitOnKeys([])
  }
}

@MainActor
private struct HostedMixedHeightListView {
  @State private var selected: Int? = 0
  @State private var activated: Int?
  @State private var activationCount = 0
}

extension HostedMixedHeightListView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      List(
        HostedMixedHeightRow.fixtures,
        selection: $selected,
        onActivate: { row in
          activated = row
          activationCount += 1
        }
      ) { row in
        VStack(alignment: .leading, spacing: 0) {
          Text(row.title)
          ForEach(0..<(row.id % 3), id: \.self) { line in
            Text("Detail \(row.id):\(line)")
          }
        }
        .padding(.vertical, row.id % 2)
      }
      .listStyle(.automatic)
      .focusable(false)
      .frame(height: 8, alignment: .topLeading)
      Text("Selected=\(selected.map { String($0) } ?? "-")")
      Text("Checked=-")
      Text("Activated=\(activated.map { String($0) } ?? "-") Count=\(activationCount)")
    }
  }
}

private struct HostedMixedHeightRow {
  let id: Int
  var title: String { "Row \(id < 10 ? "0" : "")\(id)" }
  static let fixtures = (0..<12).map { HostedMixedHeightRow(id: $0) }
}

extension HostedMixedHeightRow: Identifiable {}
extension HostedMixedHeightRow: Sendable {}

extension SemanticHostFrame {
  fileprivate func containsHostedToken(_ token: String) -> Bool {
    raster.lines.contains { $0.split(separator: " ").contains(Substring(token)) }
  }

  fileprivate func focusesHostedRow(_ row: Int) -> Bool {
    let title = HostedMixedHeightRow(id: row).title
    guard let line = raster.lines.firstIndex(where: { $0.contains(title) }),
      let region = semantics.focusRegions.first(where: { $0.identity == focusedIdentity })
    else { return false }
    let titleIsInsideFocus = line >= region.rect.origin.y && line < region.rect.maxY
    let rowAcceptsActivation = region.focusInteractions == .activate
    return titleIsInsideFocus && rowAcceptsActivation
  }

  fileprivate func focusesHostedText(_ text: String) -> Bool {
    guard let line = raster.lines.firstIndex(where: { $0.contains(text) }),
      let region = semantics.focusRegions.first(where: { $0.identity == focusedIdentity })
    else { return false }
    return line >= region.rect.origin.y && line < region.rect.maxY
  }
}

private func requireWholeHostedRow(_ row: Int, in frame: SemanticHostFrame) throws {
  let raster = frame.raster.lines.joined(separator: "\n")
  try #require(frame.focusesHostedRow(row), "row \(row) remains focused:\n\(raster)")
  #expect(frame.containsHostedToken("Selected=\(row)"), "\(raster)")
  let title = HostedMixedHeightRow(id: row).title
  let titleLine = try #require(frame.raster.lines.firstIndex { $0.contains(title) })
  let region = try #require(
    frame.semantics.focusRegions.first { $0.identity == frame.focusedIdentity })

  // Authored heights, independent of the runtime's measured scroll metadata.
  // Automatic style consumes two cells of chrome and two overflow-indicator cells.
  // Taller targets need to retain focus and selection, but cannot fit whole.
  let expectedHeights = [1, 4, 3, 3, 2, 5, 1, 4, 3, 3, 2, 5]
  let expectedHeight = expectedHeights[row]
  let rowFitsViewport = expectedHeight <= 4
  guard rowFitsViewport else { return }
  let padding = row % 2
  #expect(region.rect.size.height == expectedHeight, "whole padded row \(row):\n\(raster)")
  #expect(titleLine == region.rect.origin.y + padding, "top padding of row \(row):\n\(raster)")
  #expect(region.rect.origin.y >= 0 && region.rect.maxY <= 8, "row fits list:\n\(raster)")
  for detail in 0..<(row % 3) {
    let line = titleLine + detail + 1
    try #require(frame.raster.lines.indices.contains(line))
    #expect(frame.raster.lines[line].contains("Detail \(row):\(detail)"), "\(raster)")
  }
}

@MainActor
private final class HostedCollectionFrameRecorder {
  private(set) var latest: SemanticHostFrame?
  private var history: [SemanticHostFrame] = []
  private let updates = MainActorConditionSignal()
  private let stages = ManualStageClock()

  func receive(_ frame: SemanticHostFrame) {
    latest = frame
    history.append(frame)
    if history.count > 64 { history.removeFirst(history.count - 64) }
    stages.advance()
    updates.notify()
  }

  func firstFrame(after sequence: UInt64, containing token: String) throws -> SemanticHostFrame {
    try #require(history.first { $0.sequence > sequence && $0.containsHostedToken(token) })
  }

  func wait(
    after sequence: UInt64? = nil,
    description: String,
    matching predicate: @escaping @MainActor @Sendable (SemanticHostFrame) -> Bool
  ) async throws -> SemanticHostFrame {
    do {
      try await updates.wait(
        until: {
          guard let frame = self.latest else { return false }
          if let sequence, frame.sequence <= sequence { return false }
          return predicate(frame)
        },
        for: description,
        within: ProgressBudget(stages: 32),
        on: stages
      )
    } catch let error as StageBudgetExceeded {
      let raster = latest?.raster.lines.joined(separator: "\n") ?? "No frame received"
      throw FrameDeadlineExceeded(expectation: error.description, lastRaster: raster)
    }
    return try #require(latest)
  }

  private struct FrameDeadlineExceeded: Error, CustomStringConvertible {
    let expectation: String
    let lastRaster: String

    var description: String {
      "Timed out waiting for \(expectation). Last raster:\n\(lastRaster)"
    }
  }
}
