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
      for padding in [1, 0] {
        session.send(.key(KeyPress(.character("p"), modifiers: .ctrl)))
        previous = try await recorder.wait(
          after: previous.sequence, description: "row padding changes to \(padding)"
        ) { $0.containsHostedToken("Padding=\(padding)") }
        let raster = previous.raster.lines.joined(separator: "\n")
        let targetIsFocused = previous.focusesHostedRow(7)
        try #require(targetIsFocused, "row growth preserves focus:\n\(raster)")
        #expect(previous.focusedIdentity == focusedIdentity)
        #expect(previous.semantics.scrollRoutes.first?.viewportRect == viewport)
        #expect(previous.containsHostedToken(multiple ? "Checked=0,7" : "Selected=7"))
        let region = try #require(
          previous.semantics.focusRegions.first { $0.identity == focusedIdentity })
        #expect(region.rect.size.height == (padding == 0 ? 2 : 4))
      }
      session.send(.key(KeyPress(.return)))
      previous = try await recorder.wait(
        after: previous.sequence, description: "Return acts on the retained row 7"
      ) {
        $0.containsHostedToken(multiple ? "Checked=0" : "Activated=7")
          && $0.focusesHostedRow(7)
      }
      #expect(previous.containsHostedToken(multiple ? "Count=0" : "Count=1"))
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
  private let updates = MainActorConditionSignal()
  private let stages = ManualStageClock()

  func receive(_ frame: SemanticHostFrame) {
    latest = frame
    stages.advance()
    updates.notify()
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
