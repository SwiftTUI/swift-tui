import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Campaign two, lineage F2 pass 2 (STUI-1283): shared fixtures for the
// setD101–setD200 interaction corpus. Briefs, hypotheses and corrections live
// in the coordination root under
// docs/reports/evidence/2026-10-26-campaign-two-f2-pass-2/.

/// A live run loop over a resizable recording surface. Unlike
/// `StressRuntimeHarness` the proposal follows the surface, so a resize plus
/// `SIGWINCH` re-lays out at the new size (pass 1's resize fixture shape).
@MainActor
final class SetDLiveHarness<Content: View> {
  let surface: SetDResizableSurface
  let runLoop: SwiftTUIRuntime.RunLoop<Int, Content>
  let scheduler: FrameScheduler
  let rootIdentity: Identity
  private var rendered = 0
  private var didShutdown = false

  init(
    _ name: String,
    size: CellSize,
    profile: TerminalCapabilityProfile = .previewUnicode,
    @ViewBuilder content: @escaping () -> Content
  ) throws {
    let root = testIdentity("setD", name)
    let surface = SetDResizableSurface()
    surface.surfaceSize = size
    let scheduler = FrameScheduler()
    let focus = FocusTracker(invalidationIdentities: [root])
    let loop = SwiftTUIRuntime.RunLoop(
      rootIdentity: root, presentationSurface: surface,
      terminalInputReader: SetDFiniteInput([]), signalReader: nil, scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: focus, viewBuilder: { _, _ in content() })
    focus.invalidator = scheduler
    self.surface = surface
    self.runLoop = loop
    self.scheduler = scheduler
    self.rootIdentity = root
    scheduler.requestInvalidation(of: [root])
    try render()
    loop.renderer.enableSelectiveEvaluation()
  }

  func shutdown() {
    guard !didShutdown else { return }
    didShutdown = true
    runLoop.lifecycleCoordinator.shutdown()
  }

  func render() throws {
    try runLoop.renderPendingFrames(renderedFrames: &rendered)
  }

  /// One explicit root frame, for fixture models the graph cannot observe.
  func renderRoot() throws {
    scheduler.requestInvalidation(of: [rootIdentity])
    try render()
  }

  var raster: RasterSurface? { surface.raster }
  var lines: [String] { surface.raster?.lines ?? [] }
  var frame: String { lines.joined(separator: "\n") }

  /// Dispatches without rendering (several calls form one input batch).
  func dispatch(_ event: InputEvent) {
    #expect(runLoop.withRuntimeRegistrationScope { runLoop.handle(.input(event)) } == nil)
  }

  func dispatchKey(_ key: KeyEvent) {
    #expect(runLoop.withRuntimeRegistrationScope { runLoop.handleKeyPress(.init(key)) } == nil)
  }

  func key(_ key: KeyEvent) throws {
    dispatchKey(key)
    try render()
  }

  func keys(_ keys: [KeyEvent]) throws {
    for key in keys { dispatchKey(key) }
    try render()
  }

  func dispatchClick(_ cell: CellPoint) {
    let point = Point(cell)
    dispatch(.mouse(.init(kind: .down(.primary), location: point)))
    dispatch(.mouse(.init(kind: .up(.primary), location: point)))
  }

  func click(_ cell: CellPoint) throws {
    let point = Point(cell)
    dispatch(.mouse(.init(kind: .down(.primary), location: point)))
    try render()
    dispatch(.mouse(.init(kind: .up(.primary), location: point)))
    try render()
  }

  func clickText(_ text: String) throws {
    let cell = try #require(cell(of: text), "no \(text) in\n\(frame)")
    try click(cell)
  }

  func wheel(at cell: CellPoint, deltaY: Int) throws {
    dispatch(.mouse(.init(kind: .scrolled(deltaX: 0, deltaY: deltaY), location: Point(cell))))
    try render()
  }

  func resize(_ size: CellSize) throws {
    surface.surfaceSize = size
    #expect(runLoop.withRuntimeRegistrationScope { runLoop.handle(.signal("SIGWINCH")) } == nil)
    try render()
    #expect(surface.raster?.size == size)
  }

  func focus(_ identity: Identity) throws {
    let changed = runLoop.focusTracker.setFocus(to: identity)
    #expect(changed || runLoop.focusTracker.currentFocusIdentity == identity)
    try render()
  }

  /// Focuses the smallest focus region containing `text`.
  func focusText(_ text: String) throws {
    let cell = try #require(cell(of: text), "no \(text) in\n\(frame)")
    let region = try #require(
      runLoop.focusTracker.focusRegions.last { $0.rect.contains(cell) },
      "no focus region at \(cell)")
    try focus(region.identity)
  }

  /// The cell of `text`'s first character, by raster cell column.
  func cell(of text: String) -> CellPoint? {
    guard let raster = surface.raster else { return nil }
    return setDCell(of: text, in: raster)
  }

  /// Whole-word tokens `<prefix><digits>` in frame order.
  func tokens(prefix: String) -> [String] {
    setDTokens(prefix: prefix, in: lines)
  }

  func accessibilityNode(label: String) -> AccessibilityNode? {
    runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first { $0.label == label }
  }

  func activate(label: String) throws -> AccessibilityActionResult? {
    guard let target = accessibilityNode(label: label)?.actionTarget else { return nil }
    let result = runLoop.withRuntimeRegistrationScope {
      runLoop.handleAccessibilityAction(.init(target: target, action: .activate))
    }
    try render()
    return result
  }

  var actionRegistrationCount: Int {
    runLoop.localActionRegistry.snapshot().count
  }
}

/// The cell of `text`'s first character in `raster`, counting wide glyphs as
/// their span (continuation cells carry no character of their own).
func setDCell(of text: String, in raster: RasterSurface) -> CellPoint? {
  for (y, row) in raster.cells.enumerated() {
    var line = ""
    var columns: [Int] = []
    for (x, cell) in row.enumerated() where !cell.isContinuation {
      line.append(cell.character)
      columns.append(x)
    }
    guard let range = line.range(of: text) else { continue }
    let index = line.distance(from: line.startIndex, to: range.lowerBound)
    return CellPoint(x: columns[index], y: y)
  }
  return nil
}

func setDTokens(prefix: String, in lines: [String]) -> [String] {
  var result: [String] = []
  for line in lines {
    for token in line.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
      guard token.hasPrefix(prefix) else { continue }
      let rest = token.dropFirst(prefix.count)
      guard !rest.isEmpty, rest.allSatisfy(\.isNumber) else { continue }
      result.append(String(token))
    }
  }
  return result
}

func setDPadded(_ value: Int, _ prefix: String, digits: Int = 3) -> String {
  let text = String(value)
  return prefix + String(repeating: "0", count: max(0, digits - text.count)) + text
}

struct SetDRow: Identifiable, Hashable, Sendable {
  var id: String
}

func setDRows(_ count: Int, prefix: String = "r", digits: Int = 3) -> [SetDRow] {
  (0..<count).map { SetDRow(id: setDPadded($0, prefix, digits: digits)) }
}

@MainActor
final class SetDSelection<Value: Hashable> {
  var value: Value
  var writes = 0
  init(_ value: Value) { self.value = value }
  var binding: Binding<Value> {
    .init(
      get: { self.value },
      set: {
        self.value = $0
        self.writes += 1
      })
  }
}

@MainActor
final class SetDOffsetBox {
  var value = ScrollCellOffset.zero
  var binding: Binding<ScrollCellOffset> {
    .init(get: { self.value }, set: { self.value = $0 })
  }
}

@MainActor
final class SetDIssueLog {
  var issues: [RuntimeIssue] = []
  func count(_ code: String) -> Int { issues.filter { $0.code == code }.count }
}
