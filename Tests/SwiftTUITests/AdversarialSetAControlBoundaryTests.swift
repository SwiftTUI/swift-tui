import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Numeric, collection, and live control boundaries left open by earlier Set A passes.
@MainActor
@Suite(.serialized)
struct AdversarialSetAControlBoundaryTests {
  @Test func setA376TinySliderRangeStillFillsItsTrack() {
    // Hypothesis: an absolute epsilon in fraction calculation shrinks valid tiny ranges.
    withKnownIssue("STUI-973: An absolute span epsilon distorts valid tiny slider ranges") {
      #expect(sliderFraction(value: 5e-14, bounds: 0.0...1e-13) == 0.5)
      #expect(sliderFraction(value: 1e-13, bounds: 0.0...1e-13) == 1)
    }
  }

  @Test func setA377SmallControlValuesRemainDistinguishableFromZero() {
    // Hypothesis: fixed six-place display formatting erases a supported fractional step.
    let rendered = formattedControlValue(1e-7, bounds: 0.0...1e-5, step: 1e-7)
    withKnownIssue("STUI-974: Six-place display conversion erases supported small values") {
      #expect(Double(rendered) == 1e-7)
    }
  }

  @Test func setA378SliderPointerMappingIsTranslationInvariant() {
    // Hypothesis: removing track caps before normalization forgets the translated origin.
    let origin = CellRect(origin: .zero, size: .init(width: 13, height: 1))
    let shifted = CellRect(origin: .init(x: -37, y: 8), size: origin.size)
    let first: Double = sliderValue(at: 4.25, in: origin, bounds: -2.0...3.0, step: 0.25)
    let second: Double = sliderValue(at: -32.75, in: shifted, bounds: -2.0...3.0, step: 0.25)
    #expect(first == second)
    #expect(first == -0.5)
  }

  @Test func setA379CollapsedSliderHasOneReachableValue() {
    // Hypothesis: zero-span bounds produce a nonfinite fraction or an out-of-range pointer value.
    let rect = CellRect(origin: .init(x: 10, y: 0), size: .init(width: 1, height: 1))
    let value: Double = sliderValue(at: 500, in: rect, bounds: 7.25...7.25, step: 0.1)
    #expect(value == 7.25)
    #expect(sliderFraction(value: value, bounds: 7.25...7.25) == 0)
  }

  @Test func setA380LargeIntegerSliderPreservesAdjacentPositions() {
    // Hypothesis: conversion before subtraction loses adjacent Int values above Double's exact range.
    let lower = 9_007_199_254_740_992
    withKnownIssue("STUI-975: Converting Int operands before subtraction loses adjacent positions")
    {
      #expect(sliderFraction(value: lower + 1, bounds: lower...(lower + 4)) == 0.25)
    }
  }

  @Test func setA381ContinuousSliderQuantumFitsItsScale() {
    // Hypothesis: repeated decimal division picks a quantum larger than one percent at a power boundary.
    let steps = continuousSliderSteps(for: -0.015...0.015)
    #expect(steps.track > 0 && steps.track <= 0.0003)
    #expect(steps.track * 10 > 0.0003)
    #expect(steps.adjustment == steps.track * 10)
  }

  @Test func setA382SaturatedControlAvoidsBindingSideEffects() {
    // Hypothesis: a clamped no-op still calls a binding setter with externally visible effects.
    let box = ControlBoundaryBox(10)
    let changed = updateBoundControlValue(box.binding, delta: 3, step: 4, bounds: 0...10)
    #expect(!changed)
    #expect(box.writes == 0)
    #expect(box.value == 10)
  }

  @Test func setA383DiagonalWheelKeepsSelectionAndValueAxisPoliciesSeparate() {
    // Hypothesis: shared wheel normalization accidentally gives pickers the slider's axis precedence.
    #expect(pointerSelectionDelta(deltaX: 2, deltaY: -3) == -3)
    #expect(pointerValueDelta(deltaX: 2, deltaY: -3) == 2)
    #expect(pointerSelectionDelta(deltaX: 0, deltaY: 0) == nil)
    #expect(pointerValueDelta(deltaX: 0, deltaY: 0) == nil)
  }

  @Test func setA384SparseMeasuredRowsDoNotAbsorbSeparators() {
    // Hypothesis: sparse height corrections count the separator twice after consecutive measured rows.
    let geometry = CollectionScrollGeometry(
      rowCount: 6, rowSpan: 2, rowHeights: [1: 4, 2: 2, 5: 3])
    #expect(
      (0..<6).map { geometry.lineRange(forRow: $0) } == [
        0..<1, 2..<6, 7..<9, 10..<11, 12..<13, 14..<17,
      ])
    #expect(geometry.displayLineCount == 17)
  }

  @Test func setA385SectionChromeRoundsRevealInOppositeDirections() {
    // Hypothesis: a footer/header gap makes forward reveal and backward anchoring pick the same row.
    let geometry = CollectionScrollGeometry(
      rowRanges: [2..<4, 8..<11, 15..<16], displayLineCount: 19)
    #expect(geometry.row(atOrAfterLine: 6) == 1)
    #expect(geometry.row(atOrBeforeLine: 6) == 0)
    #expect(geometry.row(atOrBeforeLine: 18) == 2)
  }

  @Test func setA386PositionedAnchorClampsAgainstTheWholeViewport() {
    // Hypothesis: a sub-row anchor clamps to the last row start and leaves blank lines below it.
    let geometry = CollectionScrollGeometry(rowCount: 3, rowSpan: 1, rowHeights: [2: 8])
    #expect(geometry.positionedOffset(for: .position(row: 2, lineOffset: 5), capacity: 4) == 6)
    #expect(geometry.positionedOffset(for: .position(row: 1, lineOffset: -8), capacity: 4) == 0)
  }

  @Test func setA387EmptyCollectionIgnoresStaleHeightMeasurements() {
    // Hypothesis: retained measurements from removed rows invent a nonempty scroll extent.
    let geometry = CollectionScrollGeometry(rowCount: 0, rowSpan: 3, rowHeights: [0: 9, 8: 4])
    #expect(geometry.displayLineCount == 0)
    #expect(geometry.lineRange(forRow: 8).isEmpty)
    #expect(geometry.positionedOffset(for: .position(row: 8, lineOffset: 3), capacity: 5) == 0)
  }

  @Test func setA388OversizedViewportAnchorsBeforeLeadingSectionChrome() {
    // Hypothesis: leading chrome plus a viewport larger than the collection produces a trailing anchor.
    let geometry = CollectionScrollGeometry(rowRanges: [3..<6, 9..<10], displayLineCount: 12)
    #expect(geometry.maxAnchorRow(viewportLineCount: 30) == 0)
    #expect(geometry.positionedOffset(for: .position(row: 1, lineOffset: 0), capacity: 30) == 0)
  }

  @Test func setA389PickerNavigationSkipsDisabledOptions() throws {
    // Hypothesis: navigation counts disabled options as reachable values after the selected tag.
    let box = ControlBoundaryBox(1)
    let h = try harness(389) {
      Picker("Route", selection: box.binding) {
        Text("One").tag(1)
        Text("Two").tag(2).disabled(true)
        Text("Three").tag(3)
      }.pickerStyle(.segmented)
    }
    defer { h.shutdown() }
    try h.focusText("One")
    try h.pressKey(.init(.arrowRight))
    #expect(box.value == 3)
    #expect(box.writes == 1)
  }

  @Test func setA390PickerCanSelectAnExplicitNilTag() throws {
    // Hypothesis: optional tag extraction confuses a valid nil selection with a failed cast.
    let box = ControlBoundaryBox<Int?>(7)
    let h = try harness(390) {
      Picker("Optional", selection: box.binding) {
        Text("None").tag(Int?.none)
        Text("Seven").tag(Int?.some(7))
      }.pickerStyle(.segmented)
    }
    defer { h.shutdown() }
    try h.clickText("None")
    #expect(box.value == nil)
    #expect(box.writes == 1)
  }

  @Test func setA391PickerEscapeDoesNotRewriteSelection() throws {
    // Hypothesis: dismissing an expanded menu commits a highlighted item or writes an unchanged binding.
    let box = ControlBoundaryBox(2)
    let h = try harness(391) {
      Picker("Menu", selection: box.binding) {
        Text("Alpha").tag(1)
        Text("Beta").tag(2)
      }.pickerStyle(.menu)
    }
    defer { h.shutdown() }
    try h.clickText("Beta")
    try #require(h.frame.contains("Alpha"), "Opening the menu must expose its unselected option")
    try h.pressKey(.init(.escape))
    #expect(!h.frame.contains("Alpha"))
    #expect(box.value == 2)
    #expect(box.writes == 0)
    #expect(
      h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.contains { $0.label == "Menu" })
  }

  @Test func setA392DisabledPickerCannotActivateItsOptionRoutes() throws {
    // Hypothesis: parent disabling removes the picker action but leaves per-option pointer handlers live.
    let box = ControlBoundaryBox(1)
    let h = try harness(392) {
      Picker("Locked", selection: box.binding) {
        Text("First").tag(1)
        Text("Second").tag(2)
      }.pickerStyle(.segmented).disabled(true)
    }
    defer { h.shutdown() }
    try h.clickText("Second")
    #expect(box.value == 1)
    #expect(box.writes == 0)
  }

  @Test func setA393PickerHashCollisionsDoNotAliasSelection() throws {
    // Hypothesis: erased tag routing uses a hash instead of equality and conflates distinct options.
    let box = ControlBoundaryBox(CollidingControlTag(value: 1))
    let h = try harness(393) {
      Picker("Collisions", selection: box.binding) {
        Text("North").tag(CollidingControlTag(value: 1))
        Text("South").tag(CollidingControlTag(value: 2))
      }.pickerStyle(.segmented)
    }
    defer { h.shutdown() }
    try h.clickText("South")
    #expect(box.value.value == 2)
    #expect(box.writes == 1)
  }

  @Test func setA394StepperReleaseDoesNotApplyTheOppositeHalf() throws {
    // Hypothesis: release over the opposite half replays an adjustment after the down handler already committed.
    let box = ControlBoundaryBox(5)
    let h = try harness(394) { Stepper("Count", value: box.binding, in: 0...10) }
    defer { h.shutdown() }
    let region = try #require(h.runLoop.focusTracker.focusRegions.first)
    let left = Point(x: Double(region.rect.origin.x) + 0.5, y: Double(region.rect.origin.y) + 0.5)
    let right = Point(x: Double(region.rect.maxX) - 0.5, y: left.y)
    try h.sendMouse(.down(.primary), at: right)
    try h.sendMouse(.up(.primary), at: left)
    #expect(box.value == 6)
    #expect(box.writes == 1)
  }

  @Test func setA395SliderCapturedDragReachesBoundsOutsideTrack() throws {
    // Hypothesis: slider pointer capture stops updating when a drag leaves its hit rectangle.
    let box = ControlBoundaryBox(5)
    let h = try harness(395) { Slider("Level", value: box.binding, in: 0...10, step: 1) }
    defer { h.shutdown() }
    let region = try #require(h.runLoop.focusTracker.focusRegions.first)
    let center = try #require(h.point(forText: "●"))
    try h.drag(from: center, to: Point(x: Double(region.rect.maxX + 10), y: center.y))
    #expect(box.value == 10)
  }

  @Test func setA396AuthoredModifiedArrowPreemptsNumericControl() throws {
    // Hypothesis: built-in value adjustment runs before an authored modified-arrow interceptor.
    let box = ControlBoundaryBox(5)
    let calls = ControlBoundaryBox(0)
    let h = try harness(396) {
      Stepper("Shortcut", value: box.binding, in: 0...10)
        .onKeyPress(.arrowRight, modifiers: .ctrl) { _ in
          calls.value += 1
          return .handled
        }
    }
    defer { h.shutdown() }
    try h.focusText("Shortcut")
    try h.pressKey(.init(.arrowRight, modifiers: .ctrl))
    #expect(box.value == 5)
    #expect(calls.value == 1)
  }

  @Test func setA397ProgressPublicValueMutationRefreshesItsSummary() throws {
    // Hypothesis: the default current-value label captures initializer arguments instead of current public fields.
    var progress = ProgressView("Transfer", value: 1, total: 10)
    progress.value = 8
    let h = try harness(397) { progress }
    defer { h.shutdown() }
    let frame = try h.render()
    withKnownIssue("STUI-976: Default progress summary retains initializer values") {
      #expect(frame.contains("8/10"))
    }
    let node = try #require(
      h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first { $0.label == "Transfer" })
    #expect(node.control?.value == .number(0.8))
  }

  @Test func setA398ProgressCustomSummaryDoesNotBecomeASecondControl() throws {
    // Hypothesis: a composite current-value slot is exposed as a duplicate progress control or loses its value text.
    let h = try harness(398) {
      ProgressView(value: 0.25) {
        Text("Task")
      } currentValueLabel: {
        HStack {
          Text("One")
          Text("quarter")
        }
      }
    }
    defer { h.shutdown() }
    let nodes = h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes
    let progress = nodes.filter { $0.role == .progressBar }
    #expect(progress.count == 1)
    #expect(progress.first?.control?.value == .number(0.25))
    #expect(progress.first?.properties?.valueDescription == "One quarter")
    #expect((try h.render()).contains("quarter"))
  }

  @Test func setA399ReduceMotionRetiresIndeterminateProgressTask() throws {
    // Hypothesis: a live environment change freezes paint but leaves the primitive's periodic task running.
    let reduced = ControlBoundaryBox(false)
    let h = try harness(399) {
      ProgressView("Waiting").environment(\.accessibilityReduceMotion, reduced.value)
    }
    defer { h.shutdown() }
    #expect(h.activeTaskDescriptorCount == 1)
    reduced.value = true
    try h.renderAfterExternalMutation()
    #expect(h.activeTaskDescriptorCount == 0)
    #expect(h.activeTaskCount == 0)
  }

  @Test func setA400RejectedToggleWriteDoesNotInventLocalSelection() throws {
    // Hypothesis: an optimistic toggle state overrides a binding setter that deliberately rejects the edit.
    let box = ControlBoundaryBox(false)
    let binding = Binding(get: { box.value }, set: { _ in box.writes += 1 })
    let h = try harness(400) { Toggle("Guarded", isOn: binding) }
    defer { h.shutdown() }
    try h.clickText("Guarded")
    try h.renderAfterExternalMutation()
    let node = try #require(
      h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first { $0.label == "Guarded" })
    #expect(box.writes == 1)
    #expect(box.value == false)
    #expect(node.control?.value == .boolean(false))
  }

  private func harness<V: View>(_ number: Int, @ViewBuilder content: @escaping () -> V) throws
    -> StressRuntimeHarness<V>
  {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetAControl\(number)"), size: .init(width: 70, height: 16),
      content: content)
  }
}

@MainActor
private final class ControlBoundaryBox<Value> {
  var value: Value
  var writes = 0
  init(_ value: Value) { self.value = value }
  var binding: Binding<Value> {
    Binding(
      get: { self.value },
      set: {
        self.value = $0
        self.writes += 1
      })
  }
}

private struct CollidingControlTag: Hashable {
  let value: Int
  func hash(into hasher: inout Hasher) { hasher.combine(0) }
}
