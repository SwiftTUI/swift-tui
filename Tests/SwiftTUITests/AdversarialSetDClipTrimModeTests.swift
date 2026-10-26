import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Campaign two, F2 pass 2 (STUI-1283), setD151–setD160: clip masks (animated
// since STUI-1218) and trimmed shapes under frame elision, transaction
// scoping, reduced motion, wide glyphs and hit testing. Brief 06. The mask
// fixture follows PathAnimationIntegrationTests.swift:326-433.

/// A rectangle covering `fraction` of the width; every fraction has the same
/// element topology (four lines and a close), so it interpolates, and
/// fraction 0 is a collapsed but well-formed path.
private struct SetDMaskShape: Shape {
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

/// A zero-width rectangle whose height follows `height`: every value is an
/// empty mask with the same topology, so a change animates between two empty
/// masks.
private struct SetDZeroWidthMaskShape: Shape {
  var height: Double
  func path(in rect: Rect) -> Path {
    var path = Path()
    let bottom = rect.origin.y + rect.size.height * height
    path.move(to: Point(x: rect.origin.x, y: rect.origin.y))
    path.addLine(to: Point(x: rect.origin.x, y: rect.origin.y))
    path.addLine(to: Point(x: rect.origin.x, y: bottom))
    path.addLine(to: Point(x: rect.origin.x, y: bottom))
    path.closeSubpath()
    return path
  }
}

@MainActor
private final class SetDMaskLog {
  var fraction: Binding<Double>?
}

@MainActor
private final class SetDMaskClock { var now = MonotonicInstant.now() }

private enum SetDMaskMode: Sendable {
  case bare
  case innerTransactionDisabled
  case innerValueAnimation
  case reducedMotion
  case wide
  case trimmed
  case emptyToEmpty
  case staticEmptyMaskOpacity
  case innerTransactionDisabledWithInnerOpacity
  case insideTransactionDisabled
  case scopedBodyDisabled
  case scopedBodyAnimated
}

private struct SetDMaskRoot: View {
  @State private var fraction: Double
  let mode: SetDMaskMode
  let log: SetDMaskLog

  init(start: Double, mode: SetDMaskMode, log: SetDMaskLog) {
    _fraction = State(initialValue: start)
    self.mode = mode
    self.log = log
  }

  var body: some View {
    let _ = capture()
    switch mode {
    case .bare:
      rows("#").clipShape(SetDMaskShape(fraction: fraction))
    case .innerTransactionDisabled:
      rows("#").transaction { $0.disablesAnimations = true }
        .clipShape(SetDMaskShape(fraction: fraction))
    case .innerValueAnimation:
      rows("#").animation(.linear(duration: .seconds(1)), value: fraction)
        .clipShape(SetDMaskShape(fraction: fraction))
    case .reducedMotion:
      rows("#").clipShape(SetDMaskShape(fraction: fraction))
        .environment(\.accessibilityReduceMotion, true)
    case .wide:
      VStack(alignment: .leading, spacing: 0) {
        ForEach(0..<4, id: \.self) { _ in Text("日本語日本語日本語日本") }
      }
      .clipShape(SetDMaskShape(fraction: fraction))
    case .trimmed:
      rows("#").clipShape(SetDMaskShape(fraction: fraction).trim(from: 0, to: 0.75))
    case .emptyToEmpty:
      rows("#").clipShape(SetDZeroWidthMaskShape(height: fraction))
    case .staticEmptyMaskOpacity:
      rows("#").opacity(fraction).clipShape(SetDMaskShape(fraction: 0))
    case .innerTransactionDisabledWithInnerOpacity:
      rows("#").opacity(fraction).transaction { $0.disablesAnimations = true }
        .clipShape(SetDMaskShape(fraction: fraction))
    case .insideTransactionDisabled:
      rows("#").clipShape(SetDMaskShape(fraction: fraction))
        .transaction { $0.disablesAnimations = true }
    case .scopedBodyDisabled:
      rows("#").transaction({ $0.disablesAnimations = true }) { content in
        content.clipShape(SetDMaskShape(fraction: fraction))
      }
    case .scopedBodyAnimated:
      rows("#").animation(.linear(duration: .seconds(1))) { content in
        content.clipShape(SetDMaskShape(fraction: fraction))
      }
    }
  }

  private func rows(_ glyph: String) -> some View {
    VStack(spacing: 0) {
      ForEach(0..<4, id: \.self) { _ in Text(String(repeating: glyph, count: 20)) }
    }
  }

  private func capture() { log.fraction = $fraction }
}

@MainActor
private enum SetDMask {
  static func lastPaintedX(_ raster: RasterSurface?) -> Int {
    guard let row = raster?.cells.first else { return -1 }
    return row.lastIndex { !$0.isContinuation && $0.character != " " } ?? -1
  }

  /// The last painted column of a static mask at `fraction`.
  static func staticExtent(_ fraction: Double, trimmed: Bool = false) -> Int {
    let rows = VStack(spacing: 0) {
      ForEach(0..<4, id: \.self) { _ in Text(String(repeating: "#", count: 20)) }
    }
    let surface =
      trimmed
      ? DefaultRenderer().render(
        rows.clipShape(SetDMaskShape(fraction: fraction).trim(from: 0, to: 0.75)),
        proposal: .init(width: 20, height: 4)
      ).rasterSurface
      : DefaultRenderer().render(
        rows.clipShape(SetDMaskShape(fraction: fraction)), proposal: .init(width: 20, height: 4)
      ).rasterSurface
    return lastPaintedX(surface)
  }

  /// A live async run loop (the production frame driver, which elides
  /// off-screen deadline frames) over `SetDMaskRoot`.
  static func loop(
    _ name: String, start: Double, mode: SetDMaskMode, log: SetDMaskLog
  ) -> (SwiftTUIRuntime.RunLoop<Int, SetDMaskRoot>, SetDResizableSurface, FrameScheduler, Identity)
  {
    let root = testIdentity("setD", name)
    let surface = SetDResizableSurface()
    surface.surfaceSize = .init(width: 20, height: 4)
    let scheduler = FrameScheduler()
    let focus = FocusTracker(invalidationIdentities: [root])
    let loop = SwiftTUIRuntime.RunLoop(
      rootIdentity: root, presentationSurface: surface,
      terminalInputReader: SetDFiniteInput([]), signalReader: nil, scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: focus,
      viewBuilder: { _, _ in SetDMaskRoot(start: start, mode: mode, log: log) })
    focus.invalidator = scheduler
    return (loop, surface, scheduler, root)
  }

  /// Animates the mask from `start` to 1 over one second on an injected clock
  /// and returns the raster at `sampleAt` and after completion, the elided
  /// frame count, and the property slots animating after the write.
  /// `rootFrames` adds a root invalidation to every frame, so no frame is
  /// deadline-only.
  static func reveal(
    _ name: String, start: Double, mode: SetDMaskMode = .bare,
    sampleAt sample: Duration, rootFrames: Bool = false,
    write: (Binding<Double>) -> Void = { binding in
      withAnimation(.linear(duration: .seconds(1))) { binding.wrappedValue = 1 }
    }
  ) async throws -> (
    mid: RasterSurface?, end: RasterSurface?, elided: Int, slots: Set<AnimatableSlot>
  ) {
    let log = SetDMaskLog()
    let (loop, surface, scheduler, root) = Self.loop(name, start: start, mode: mode, log: log)
    let clock = SetDMaskClock()
    loop.frameClock = { clock.now }
    loop.renderMode = .asyncNoCancel
    defer { loop.lifecycleCoordinator.shutdown() }
    return try await withAnimationSinks(loop.renderer.internalAnimationController) {
      var rendered = 0
      scheduler.requestInvalidation(of: [root])
      try loop.renderPendingFrames(renderedFrames: &rendered)
      loop.renderer.enableSelectiveEvaluation()
      let binding = try #require(log.fraction)
      let started = clock.now
      write(binding)
      _ = try await loop.renderPendingFramesAsync(renderedFrames: &rendered, eventPump: nil)
      let slots = Set(
        loop.renderer.internalAnimationController.debugStateSnapshot().activeAnimationKeys
          .compactMap { key -> AnimatableSlot? in
            guard case .property(let slot) = key.scope else { return nil }
            return slot
          })
      @MainActor func advance(to target: MonotonicInstant) async throws {
        var turns = 0
        while let wake = scheduler.nextWakeInstant(after: clock.now), wake < target, turns < 256 {
          clock.now = wake
          if rootFrames { scheduler.requestInvalidation(of: [root]) }
          _ = try await loop.renderPendingFramesAsync(renderedFrames: &rendered, eventPump: nil)
          turns += 1
        }
        clock.now = target
        scheduler.requestDeadline(clock.now)
        if rootFrames { scheduler.requestInvalidation(of: [root]) }
        _ = try await loop.renderPendingFramesAsync(renderedFrames: &rendered, eventPump: nil)
      }
      try await advance(to: started.advanced(by: sample))
      let mid = surface.raster
      try await advance(to: started.advanced(by: .milliseconds(1_100)))
      return (mid, surface.raster, loop.renderer.elidedFrameCount, slots)
    }
  }
}

@MainActor
private final class SetDTapCount {
  var count = 0
}

@MainActor
@Suite(
  "Campaign F2 pass 2: clip masks and trims under elision, scoping and hit testing", .serialized)
struct AdversarialSetDClipTrimModeTests {
  @Test("setD151: a reveal from an empty clip mask paints midway through its animation")
  func setD151EmptyMaskRevealPaintsMidway() async throws {
    let expected = SetDMask.staticExtent(0.5)
    try #require(expected > 4 && expected < 19, "static midway extent \(expected)")
    let result = try await SetDMask.reveal("151", start: 0, sampleAt: .milliseconds(500))
    // STUI-1318: a mask animating toward area is an elision barrier.
    #expect(
      SetDMask.lastPaintedX(result.mid) == expected,
      "mid \(SetDMask.lastPaintedX(result.mid)) of \(expected); elided \(result.elided)")
  }

  @Test("setD152: a reveal from an empty clip mask paints fully after it completes")
  func setD152EmptyMaskRevealPaintsAtEnd() async throws {
    let result = try await SetDMask.reveal("152", start: 0, sampleAt: .milliseconds(500))
    // STUI-1318: the barrier holds through the completion frame.
    #expect(
      SetDMask.lastPaintedX(result.end) == 19,
      "end \(SetDMask.lastPaintedX(result.end)); elided \(result.elided)")
  }

  @Test("setD153: the same reveal with root-invalidated frames paints midway")
  func setD153EmptyMaskRevealWithRootFrames() async throws {
    let expected = SetDMask.staticExtent(0.5)
    let result = try await SetDMask.reveal(
      "153", start: 0, sampleAt: .milliseconds(500), rootFrames: true)
    #expect(SetDMask.lastPaintedX(result.mid) == expected, "\(SetDMask.lastPaintedX(result.mid))")
  }

  @Test("setD154: a mask outside a disabling .transaction still morphs")
  func setD154MaskOutsideDisablingTransactionMorphs() async throws {
    let expected = SetDMask.staticExtent(0.625)
    let result = try await SetDMask.reveal(
      "154", start: 0.25, mode: .innerTransactionDisabled, sampleAt: .milliseconds(500))
    // STUI-1319: the mask animates in the scope where clipShape is applied.
    #expect(
      SetDMask.lastPaintedX(result.mid) == expected,
      "mid \(SetDMask.lastPaintedX(result.mid)) of \(expected)")
  }

  @Test("setD155: a mask outside an inner .animation(value:) snaps on a plain write")
  func setD155MaskOutsideInnerValueAnimationSnaps() async throws {
    let result = try await SetDMask.reveal(
      "155", start: 0.25, mode: .innerValueAnimation, sampleAt: .milliseconds(500),
      write: { $0.wrappedValue = 1 })
    #expect(SetDMask.lastPaintedX(result.mid) == 19, "mid \(SetDMask.lastPaintedX(result.mid))")
  }

  @Test("setD156: reduce motion snaps an animated mask change")
  func setD156ReducedMotionSnapsMask() async throws {
    let result = try await SetDMask.reveal(
      "156", start: 0.25, mode: .reducedMotion, sampleAt: .milliseconds(500))
    #expect(SetDMask.lastPaintedX(result.mid) == 19, "mid \(SetDMask.lastPaintedX(result.mid))")
  }

  @Test("setD157: a disablesAnimations write snaps the mask")
  func setD157DisablesAnimationsWriteSnapsMask() async throws {
    let result = try await SetDMask.reveal(
      "157", start: 0.25, sampleAt: .milliseconds(500),
      write: { binding in
        withAnimation(.linear(duration: .seconds(1))) {
          withTransaction(\.disablesAnimations, true) { binding.wrappedValue = 1 }
        }
      })
    #expect(SetDMask.lastPaintedX(result.mid) == 19, "mid \(SetDMask.lastPaintedX(result.mid))")
  }

  @Test("setD158: a morphing mask paints a wide glyph only when its whole span is covered")
  func setD158MorphingMaskKeepsWideGlyphsWhole() async throws {
    let covered = SetDMask.staticExtent(0.625) + 1
    let result = try await SetDMask.reveal(
      "158", start: 0.25, mode: .wide, sampleAt: .milliseconds(500))
    let row = try #require(result.mid?.cells.first)
    var painted = 0
    for (x, cell) in row.enumerated() where !cell.isContinuation && cell.character != " " {
      painted += 1
      #expect(x + max(1, cell.spanWidth) <= covered, "glyph at \(x) past the mask end \(covered)")
    }
    #expect(painted > 0, "some glyphs are painted mid-morph")
    for (x, cell) in row.enumerated() where cell.isContinuation {
      #expect(x > 0 && row[x - 1].character != " ", "continuation at \(x) without its lead")
    }
  }

  @Test("setD159: clipping a button leaves its clipped-away cells hit-testable")
  func setD159ClipLeavesHitTesting() throws {
    let taps = SetDTapCount()
    let h = try SetDLiveHarness("159", size: .init(width: 20, height: 1)) {
      Button("ABCDEFGHIJ") { taps.count += 1 }
        .clipShape(SetDMaskShape(fraction: 0.3))
    }
    defer { h.shutdown() }
    let region = try #require(h.runLoop.latestSemanticSnapshot.interactionRegions.first)
    let far = CellPoint(
      x: region.rect.origin.x + region.rect.size.width - 2, y: region.rect.origin.y)
    try #require(h.raster?.cells[far.y][far.x].character == " ", "the far cell is clipped away")
    try h.click(far)
    #expect(taps.count == 1)
  }

  @Test("setD160: a trimmed contentShape follows its painted cells after scrolling")
  func setD160TrimmedContentShapeAfterScrolling() throws {
    let painted = try #require(SetDCentreless.paintedCell(painted: true))
    let unpainted = try #require(SetDCentreless.paintedCell(painted: false))
    let shape = Circle().trim(from: 0, to: 0.5).path(
      in: Rect(origin: .zero, size: .init(width: 10, height: 5)))
    let taps = SetDTapCount()
    let offset = SetDOffsetBox()
    let h = try SetDLiveHarness("160", size: .init(width: 20, height: 8)) {
      ScrollView(.vertical, position: offset.binding) {
        VStack(alignment: .leading, spacing: 0) {
          Text("pad0")
          Text("pad1")
          Text("pad2")
          Button {
            taps.count += 1
          } label: {
            Text("").frame(width: 10, height: 5)
          }
          .buttonStyle(.plain)
          .contentShape(shape)
          ForEach(0..<10, id: \.self) { Text("tail\($0)") }
        }
      }
      .scrollIndicators(.hidden)
    }
    defer { h.shutdown() }
    offset.value = .init(x: 0, y: 2)
    try h.renderRoot()
    try #require(h.lines.first?.hasPrefix("pad2") == true, "\(h.frame)")
    try h.click(CellPoint(x: unpainted.x, y: unpainted.y + 1))
    #expect(taps.count == 0, "an unpainted cell inside the frame does not activate")
    try h.click(CellPoint(x: painted.x, y: painted.y + 1))
    #expect(taps.count == 1, "a painted cell activates")
  }

  // Wave 4 (STUI-1318, STUI-1319): neighbours of the repaired mask cases.

  @Test("w4fk01: a trimmed reveal from an empty clip mask paints midway and at the end")
  func w4fk01TrimmedEmptyMaskRevealPaints() async throws {
    let midway = SetDMask.staticExtent(0.5, trimmed: true)
    let final = SetDMask.staticExtent(1, trimmed: true)
    try #require(midway >= 0 && midway < final, "static trimmed extents \(midway), \(final)")
    let result = try await SetDMask.reveal(
      "w4fk01", start: 0, mode: .trimmed, sampleAt: .milliseconds(500))
    #expect(
      SetDMask.lastPaintedX(result.mid) == midway,
      "mid \(SetDMask.lastPaintedX(result.mid)) of \(midway); elided \(result.elided)")
    #expect(SetDMask.lastPaintedX(result.end) == final, "end \(SetDMask.lastPaintedX(result.end))")
  }

  @Test("w4fk02: an animation between two empty clip masks still elides its deadline frames")
  func w4fk02EmptyToEmptyMaskStillElides() async throws {
    let result = try await SetDMask.reveal(
      "w4fk02", start: 0.25, mode: .emptyToEmpty, sampleAt: .milliseconds(500))
    #expect(result.slots.contains(.clipShapePaths), "the empty mask animates: \(result.slots)")
    #expect(SetDMask.lastPaintedX(result.mid) == -1)
    #expect(SetDMask.lastPaintedX(result.end) == -1)
    #expect(result.elided > 0, "an animation that ends in an empty mask reveals nothing")
  }

  @Test("w4fk03: a paint-only animation under a static empty clip mask still elides")
  func w4fk03StaticEmptyMaskKeepsElision() async throws {
    let result = try await SetDMask.reveal(
      "w4fk03", start: 0.25, mode: .staticEmptyMaskOpacity, sampleAt: .milliseconds(500))
    #expect(result.slots.contains(.opacity), "\(result.slots)")
    #expect(!result.slots.contains(.clipShapePaths), "\(result.slots)")
    #expect(SetDMask.lastPaintedX(result.mid) == -1)
    #expect(SetDMask.lastPaintedX(result.end) == -1)
    #expect(result.elided > 0, "content hidden by a static empty mask stays elidable")
  }

  @Test("w4fk04: a mask outside a disabling .transaction morphs; the content inside snaps")
  func w4fk04OuterMaskMorphsInnerOpacitySnaps() async throws {
    let expected = SetDMask.staticExtent(0.625)
    let result = try await SetDMask.reveal(
      "w4fk04", start: 0.25, mode: .innerTransactionDisabledWithInnerOpacity,
      sampleAt: .milliseconds(500))
    #expect(result.slots.contains(.clipShapePaths), "\(result.slots)")
    #expect(!result.slots.contains(.opacity), "the content keeps the inner transaction")
    #expect(
      SetDMask.lastPaintedX(result.mid) == expected,
      "mid \(SetDMask.lastPaintedX(result.mid)) of \(expected)")
    #expect(SetDMask.lastPaintedX(result.end) == 19)
  }

  @Test("w4fk05: a mask inside a disabling .transaction snaps")
  func w4fk05MaskInsideDisablingTransactionSnaps() async throws {
    let result = try await SetDMask.reveal(
      "w4fk05", start: 0.25, mode: .insideTransactionDisabled, sampleAt: .milliseconds(500))
    #expect(!result.slots.contains(.clipShapePaths), "\(result.slots)")
    #expect(SetDMask.lastPaintedX(result.mid) == 19, "mid \(SetDMask.lastPaintedX(result.mid))")
  }

  @Test("w4fk06: a mask in a disabling scoped transaction body snaps")
  func w4fk06MaskInScopedDisablingBodySnaps() async throws {
    let result = try await SetDMask.reveal(
      "w4fk06", start: 0.25, mode: .scopedBodyDisabled, sampleAt: .milliseconds(500))
    #expect(!result.slots.contains(.clipShapePaths), "\(result.slots)")
    #expect(SetDMask.lastPaintedX(result.mid) == 19, "mid \(SetDMask.lastPaintedX(result.mid))")
  }

  @Test("w4fk07: a mask in an animating scoped body morphs on a plain write")
  func w4fk07MaskInScopedAnimatingBodyMorphs() async throws {
    let expected = SetDMask.staticExtent(0.625)
    let result = try await SetDMask.reveal(
      "w4fk07", start: 0.25, mode: .scopedBodyAnimated, sampleAt: .milliseconds(500),
      write: { $0.wrappedValue = 1 })
    #expect(
      SetDMask.lastPaintedX(result.mid) == expected,
      "mid \(SetDMask.lastPaintedX(result.mid)) of \(expected)")
    #expect(SetDMask.lastPaintedX(result.end) == 19)
  }
}

@MainActor
private enum SetDCentreless {
  /// A cell of a 10×5 frame that the trimmed fill paints (or leaves blank).
  static func paintedCell(painted: Bool) -> CellPoint? {
    let raster = DefaultRenderer().render(
      Circle().trim(from: 0, to: 0.5).fill(Color.white).frame(width: 10, height: 5),
      proposal: .init(width: 10, height: 5)
    ).rasterSurface
    for (y, row) in raster.cells.enumerated() {
      for (x, cell) in row.enumerated()
      where (cell.character != " " || cell.style?.backgroundColor != nil) == painted {
        if !painted, y == 0 || x == 0 { continue }
        return CellPoint(x: x, y: y)
      }
    }
    return nil
  }
}
