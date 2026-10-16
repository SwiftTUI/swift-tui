import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct CollectionFocusRecoveryTests {
  @Test("sibling lists with overlapping IDs recover only their own focused row")
  func siblingListsKeepIndependentFocusAndActions() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SiblingCollectionFocusRecovery"),
      size: CellSize(width: 54, height: 14)
    ) {
      SiblingRecoveryLists()
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("A«0»:0")
    for row in 1...7 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
      try requireRecoveryFocus("A«\(row)»:0", selection: "A selected=\(row)", in: harness)
    }
    let focusedIdentity = harness.runLoop.focusTracker.currentFocusIdentity
    let routes = harness.runLoop.localScrollPositionRegistry.routesWithCurrentOffsets(
      harness.runLoop.latestSemanticSnapshot.scrollRoutes)
    let firstRoute = try #require(
      routes.min { $0.viewportRect.origin.x < $1.viewportRect.origin.x })
    let secondRoute = try #require(
      routes.max { $0.viewportRect.origin.x < $1.viewportRect.origin.x })
    try #require(firstRoute.identity != secondRoute.identity)
    let firstOffset = firstRoute.contentOffset
    #expect(firstOffset.y > 0, "A has scrolled beyond its initial window")
    #expect(!harness.frame.contains("A«0»:0"))
    let secondAnchor = try #require(
      harness.runLoop.localScrollPositionRegistry.snapshot().first {
        $0.identity == secondRoute.identity
      }
    ).currentCollectionAnchor()

    _ = try harness.pressKey(KeyPress(.character("b"), modifiers: .ctrl))
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == focusedIdentity)
    try requireRecoveryFocus("A«7»:0", selection: "A selected=7", in: harness)
    #expect(harness.frame.contains("B«0»:2"), "B publishes its changed height:\n\(harness.frame)")
    let unchangedFirstRoute = try #require(
      harness.runLoop.localScrollPositionRegistry.routesWithCurrentOffsets(
        harness.runLoop.latestSemanticSnapshot.scrollRoutes
      ).first {
        $0.identity == firstRoute.identity
      })
    #expect(unchangedFirstRoute.contentOffset == firstOffset)

    _ = try harness.pressKey(KeyPress(.character("a"), modifiers: .ctrl))
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == focusedIdentity)
    try requireRecoveryFocus("A«7»:0", selection: "A selected=7", in: harness)
    #expect(
      harness.frame.contains("A«7»:2"), "the focused row fits completely:\n\(harness.frame)")
    #expect(harness.frame.contains("B«0»:0"))
    #expect(harness.frame.contains("B«0»:2"))
    #expect(harness.frame.contains("B selected=0"))
    let retainedSecondAnchor = try #require(
      harness.runLoop.localScrollPositionRegistry.snapshot().first {
        $0.identity == secondRoute.identity
      }
    ).currentCollectionAnchor()
    #expect(retainedSecondAnchor == secondAnchor)

    _ = try harness.pressKey(KeyPress(.return))
    #expect(harness.frame.contains("A activated=7 count=1"), "\(harness.frame)")
    #expect(harness.frame.contains("B activated=-1 count=0"), "\(harness.frame)")
    _ = try harness.pressKey(KeyPress(.arrowDown))
    try requireRecoveryFocus("A«8»:0", selection: "A selected=8", in: harness)
    #expect(harness.frame.contains("B selected=0"))
  }

  @Test("a scrolled collection keeps its target through viewport shrink and growth")
  func viewportChangesKeepFocusedRow() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("CollectionViewportFocusRecovery"),
      size: CellSize(width: 36, height: 12)
    ) {
      ResizingRecoveryList()
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("«0»:0")
    for _ in 1...7 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
    }
    try requireRecoveryFocus("«7»:0", selection: "selected=7", in: harness)
    #expect(!harness.frame.contains("«0»:0"))
    let focusedIdentity = harness.runLoop.focusTracker.currentFocusIdentity

    for (phase, height) in [4, 8].enumerated() {
      _ = try harness.pressKey(KeyPress(.character("v"), modifiers: .ctrl))
      // Inspect the input's committed result before navigation can repair its window.
      #expect(harness.runLoop.focusTracker.currentFocusIdentity == focusedIdentity)
      try requireRecoveryFocus("«7»:0", selection: "selected=7", in: harness)
      #expect(harness.frame.contains("«7»:1"), "\(harness.frame)")
      let route = try #require(harness.runLoop.latestSemanticSnapshot.scrollRoutes.first)
      #expect(route.viewportRect.size.height == height)
      _ = try harness.pressKey(KeyPress(.return))
      #expect(harness.frame.contains("activated=7 count=\(phase + 1)"), "\(harness.frame)")
      _ = try harness.pressKey(KeyPress(.arrowUp))
      try requireRecoveryFocus("«6»:0", selection: "selected=6", in: harness)
      _ = try harness.pressKey(KeyPress(.arrowDown))
      try requireRecoveryFocus("«7»:0", selection: "selected=7", in: harness)
    }
  }

  @Test("a focused row reveals its leading content when it grows beyond the viewport")
  func focusedRowBecomesOversizedAndFitsAgain() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("OversizedCollectionFocusRecovery"),
      size: CellSize(width: 36, height: 12)
    ) {
      OversizedRecoveryList()
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("«0»:0")
    for _ in 1...7 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
    }
    try requireRecoveryFocus("«7»:0", selection: "selected=7", in: harness)
    #expect(!harness.frame.contains("«0»:0"))
    let focusedIdentity = harness.runLoop.focusTracker.currentFocusIdentity

    _ = try harness.pressKey(KeyPress(.character("g"), modifiers: .ctrl))
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == focusedIdentity)
    try requireRecoveryFocus("«7»:0", selection: "selected=7", in: harness)
    let route = try #require(harness.runLoop.latestSemanticSnapshot.scrollRoutes.first)
    let lines = harness.frame.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    let leadingLine = try #require(lines.firstIndex { $0.contains("«7»:0") })
    #expect(leadingLine == route.viewportRect.origin.y, "\(harness.frame)")
    #expect(!harness.frame.contains("«7»:9"), "ten lines exceed the six-line viewport")
    _ = try harness.pressKey(KeyPress(.return))
    #expect(harness.frame.contains("activated=7 count=1"), "\(harness.frame)")
    _ = try harness.pressKey(KeyPress(.arrowDown))
    try requireRecoveryFocus("«8»:0", selection: "selected=8", in: harness)
    _ = try harness.pressKey(KeyPress(.arrowUp))
    try requireRecoveryFocus("«7»:0", selection: "selected=7", in: harness)

    _ = try harness.pressKey(KeyPress(.character("g"), modifiers: .ctrl))
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == focusedIdentity)
    try requireRecoveryFocus("«7»:0", selection: "selected=7", in: harness)
    #expect(!harness.frame.contains("«7»:1"), "the focused row fits again:\n\(harness.frame)")
    _ = try harness.pressKey(KeyPress(.return))
    #expect(harness.frame.contains("activated=7 count=2"), "\(harness.frame)")
    _ = try harness.pressKey(KeyPress(.arrowDown))
    try requireRecoveryFocus("«8»:0", selection: "selected=8", in: harness)
    _ = try harness.pressKey(KeyPress(.return))
    #expect(harness.frame.contains("activated=8 count=3"), "\(harness.frame)")
  }

  @Test("equal-total row height redistribution still reveals the focused target")
  func unchangedTotalHeightStillRecoversFocus() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("RedistributedCollectionFocusRecovery"),
      size: CellSize(width: 36, height: 12)
    ) {
      RedistributedRecoveryList()
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("«0»:0")
    for _ in 1...7 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
    }
    try requireRecoveryFocus("«7»:0", selection: "selected=7", in: harness)
    try #require(harness.frame.contains("«6»:0"), "the growing predecessor is measured")
    #expect(harness.frame.contains("«7»:2"), "\(harness.frame)")
    #expect(harness.frame.contains("total=17"))
    let focusedIdentity = harness.runLoop.focusTracker.currentFocusIdentity
    let viewport = try #require(
      harness.runLoop.latestSemanticSnapshot.scrollRoutes.first?.viewportRect)

    // Twelve rows retain seventeen authored cells: row 6 gains three, row 9 loses three.
    _ = try harness.pressKey(KeyPress(.character("r"), modifiers: .ctrl))
    #expect(harness.frame.contains("total=17"))
    #expect(harness.runLoop.latestSemanticSnapshot.scrollRoutes.first?.viewportRect == viewport)
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == focusedIdentity)
    try requireRecoveryFocus("«7»:0", selection: "selected=7", in: harness)
    #expect(harness.frame.contains("«7»:2"), "\(harness.frame)")
    _ = try harness.pressKey(KeyPress(.return))
    #expect(harness.frame.contains("activated=7 count=1"), "\(harness.frame)")
    _ = try harness.pressKey(KeyPress(.arrowUp))
    try requireRecoveryFocus("«6»:0", selection: "selected=6", in: harness)
    #expect(harness.frame.contains("«6»:3"), "the predecessor now needs four cells")
    _ = try harness.pressKey(KeyPress(.arrowDown))
    try requireRecoveryFocus("«7»:0", selection: "selected=7", in: harness)
    _ = try harness.pressKey(KeyPress(.arrowDown))
    try requireRecoveryFocus("«8»:0", selection: "selected=8", in: harness)
    _ = try harness.pressKey(KeyPress(.arrowDown))
    try requireRecoveryFocus("«9»:0", selection: "selected=9", in: harness)
    #expect(!harness.frame.contains("«9»:1"), "the compensating row now needs one cell")
    _ = try harness.pressKey(KeyPress(.return))
    #expect(harness.frame.contains("activated=9 count=2"), "\(harness.frame)")
  }

  @Test(
    "navigation after a focused ID leaves the data activates a painted surviving ID",
    arguments: [false, true]
  )
  func removedFocusedIDKeepsNavigationAndActivationConsistent(replacesRemovedRow: Bool) throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("RemovedCollectionFocusRecovery", "\(replacesRemovedRow)"),
      size: CellSize(width: 36, height: 12)
    ) {
      RemovingRecoveryList(replacesRemovedRow: replacesRemovedRow)
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("«110»:0")
    for _ in 1...7 {
      _ = try harness.pressKey(KeyPress(.arrowDown))
    }
    try requireRecoveryFocus("«880»:0", selection: "selected=880", in: harness)
    #expect(!harness.frame.contains("«110»:0"), "the removed target is initially scrolled")

    _ = try harness.pressKey(KeyPress(.character("f"), modifiers: .ctrl))
    #expect(!harness.frame.contains("«880»:"), "the removed ID is no longer painted")
    #expect(harness.frame.contains("rows=\(replacesRemovedRow ? 12 : 11) lines=3"))

    // The fallback is unspecified. One navigation input must restore a coherent live target.
    _ = try harness.pressKey(KeyPress(.arrowDown))
    let survivingIDs =
      [110, 220, 330, 440, 550, 660, 770, 990, 1100, 1210, 1320]
      + (replacesRemovedRow ? [2000] : [])
    let focusedIdentity = try #require(harness.runLoop.focusTracker.currentFocusIdentity)
    var paintedFocusedIDs: [Int] = []
    for id in survivingIDs where harness.frame.contains("«\(id)»:0") {
      let paintedIdentity = try harness.focusIdentity(forText: "«\(id)»:0")
      if paintedIdentity == focusedIdentity {
        paintedFocusedIDs.append(id)
      }
    }
    try #require(
      paintedFocusedIDs.count == 1,
      "exactly one painted surviving data ID owns focus:\n\(harness.frame)")
    let liveID = try #require(paintedFocusedIDs.first)
    #expect(liveID != 880)
    #expect(harness.frame.contains("selected=\(liveID)"), "\(harness.frame)")
    #expect(!harness.frame.contains("«880»:"))
    _ = try harness.pressKey(KeyPress(.return))
    #expect(harness.frame.contains("activated=\(liveID) count=1"), "\(harness.frame)")
    #expect(!harness.frame.contains("activated=880"))
    try requireRecoveryFocus("«\(liveID)»:0", selection: "selected=\(liveID)", in: harness)
  }
}

@MainActor
private func requireRecoveryFocus<Content: View>(
  _ label: String, selection: String, in harness: StressRuntimeHarness<Content>
) throws {
  try #require(harness.frame.contains(label), "the expected data row is painted:\n\(harness.frame)")
  let identity = try harness.focusIdentity(forText: label)
  #expect(harness.runLoop.focusTracker.currentFocusIdentity == identity, "\(harness.frame)")
  #expect(harness.frame.contains(selection), "\(harness.frame)")
}

@MainActor
private struct SiblingRecoveryLists: View {
  @State private var firstIsTall = false
  @State private var secondIsTall = false
  @State private var firstSelection: Int? = 0
  @State private var secondSelection: Int? = 0
  @State private var firstActivated = -1
  @State private var secondActivated = -1
  @State private var firstCount = 0
  @State private var secondCount = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 2) {
        List(
          0..<12, id: \.self, selection: $firstSelection,
          onActivate: { row in
            firstActivated = row
            firstCount += 1
          }
        ) { row in
          RecoveryRow(prefix: "A", row: row, lines: firstIsTall ? 3 : 1)
        }
        .listStyle(RecoveryListStyle())
        .scrollIndicators(.hidden)
        .frame(width: 24, height: 6)
        List(
          0..<12, id: \.self, selection: $secondSelection,
          onActivate: { row in
            secondActivated = row
            secondCount += 1
          }
        ) { row in
          RecoveryRow(prefix: "B", row: row, lines: secondIsTall ? 3 : 1)
        }
        .listStyle(RecoveryListStyle())
        .scrollIndicators(.hidden)
        .frame(width: 24, height: 6)
      }
      Text("A selected=\(firstSelection ?? -1)")
      Text("B selected=\(secondSelection ?? -1)")
      Text("A activated=\(firstActivated) count=\(firstCount)")
      Text("B activated=\(secondActivated) count=\(secondCount)")
    }
    .onKeyPress(.character("a"), modifiers: .ctrl) { _ in
      firstIsTall.toggle()
      return .handled
    }
    .onKeyPress(.character("b"), modifiers: .ctrl) { _ in
      secondIsTall.toggle()
      return .handled
    }
  }
}

@MainActor
private struct ResizingRecoveryList: View {
  @State private var isSmall = false
  @State private var selected: Int? = 0
  @State private var activated = -1
  @State private var activationCount = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      List(
        0..<12, id: \.self, selection: $selected,
        onActivate: { row in
          activated = row
          activationCount += 1
        }
      ) { row in
        RecoveryRow(prefix: "", row: row, lines: 2)
      }
      .listStyle(RecoveryListStyle())
      .scrollIndicators(.hidden)
      .frame(height: isSmall ? 4 : 8)
      Text("selected=\(selected ?? -1)")
      Text("activated=\(activated) count=\(activationCount)")
    }
    .onKeyPress(.character("v"), modifiers: .ctrl) { _ in
      isSmall.toggle()
      return .handled
    }
  }
}

@MainActor
private struct OversizedRecoveryList: View {
  @State private var isOversized = false
  @State private var selected: Int? = 0
  @State private var activated = -1
  @State private var activationCount = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      List(
        0..<12, id: \.self, selection: $selected,
        onActivate: { row in
          activated = row
          activationCount += 1
        }
      ) { row in
        RecoveryRow(prefix: "", row: row, lines: row == 7 && isOversized ? 10 : 1)
      }
      .listStyle(RecoveryListStyle())
      .scrollIndicators(.hidden)
      .frame(height: 6)
      Text("selected=\(selected ?? -1)")
      Text("activated=\(activated) count=\(activationCount)")
    }
    .onKeyPress(.character("g"), modifiers: .ctrl) { _ in
      isOversized.toggle()
      return .handled
    }
  }
}

@MainActor
private struct RedistributedRecoveryList: View {
  @State private var isRedistributed = false
  @State private var selected: Int? = 0
  @State private var activated = -1
  @State private var activationCount = 0

  private var heights: [Int] {
    if isRedistributed {
      [1, 1, 1, 1, 1, 1, 4, 3, 1, 1, 1, 1]
    } else {
      [1, 1, 1, 1, 1, 1, 1, 3, 1, 4, 1, 1]
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      List(
        0..<12, id: \.self, selection: $selected,
        onActivate: { row in
          activated = row
          activationCount += 1
        }
      ) { row in
        RecoveryRow(prefix: "", row: row, lines: heights[row])
      }
      .listStyle(RecoveryListStyle())
      .scrollIndicators(.hidden)
      .frame(height: 8)
      Text("selected=\(selected ?? -1)")
      Text("activated=\(activated) count=\(activationCount)")
      Text("total=\(heights.reduce(0, +))")
    }
    .onKeyPress(.character("r"), modifiers: .ctrl) { _ in
      isRedistributed.toggle()
      return .handled
    }
  }
}

@MainActor
private struct RecoveryRow: View {
  let prefix: String
  let row: Int
  let lines: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(0..<lines, id: \.self) { line in
        Text("\(prefix)«\(row)»:\(line)")
      }
    }
  }
}

private struct RecoveryListStyle: ListStyle {
  @MainActor
  func resolvePresentation(for configuration: ListStyleConfiguration) -> ListStylePresentation {
    ListStylePresentation(
      contentInsets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
      showsRowSeparators: false,
      showsSectionSeparators: false
    )
  }
}

@MainActor
private struct RemovingRecoveryList: View {
  let replacesRemovedRow: Bool
  @State private var rows = [110, 220, 330, 440, 550, 660, 770, 880, 990, 1100, 1210, 1320]
  @State private var hasChanged = false
  @State private var selected: Int? = 110
  @State private var activated = -1
  @State private var activationCount = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      List(
        rows, id: \.self, selection: $selected,
        onActivate: { row in
          activated = row
          activationCount += 1
        }
      ) { row in
        RecoveryRow(prefix: "", row: row, lines: hasChanged ? 3 : 1)
      }
      .listStyle(RecoveryListStyle())
      .scrollIndicators(.hidden)
      .frame(height: 6)
      Text("selected=\(selected ?? -1)")
      Text("activated=\(activated) count=\(activationCount)")
      Text("rows=\(rows.count) lines=\(hasChanged ? 3 : 1)")
    }
    .onKeyPress(.character("f"), modifiers: .ctrl) { _ in
      if replacesRemovedRow {
        rows = rows.map { $0 == 880 ? 2000 : $0 }
      } else {
        rows = rows.filter { $0 != 880 }
      }
      hasChanged = true
      return .handled
    }
  }
}
