// Adversarial set H, pass 1 (F6 platform edges): unchecked floating-point to
// integer conversions behind public drawing, geometry, scrolling and
// diagnostics APIs (setH051–setH068). A trap is observed through an exit
// test; every trap case has an in-process control that qualifies its fixture
// with an ordinary finite input, so a fixture error cannot pose as a trap.
import Foundation
import SwiftTUIPrimitives
import SwiftTUIProfiling
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@Suite("Adversarial set H: numeric edges", .serialized)
struct AdversarialSetHNumericEdgeTests {
  // The subpixel sampler converts raw / 0.5 to Int for its step count.
  @Test func setH051StrokeTrackHugeSegmentTraps() async {
    let control = SampledStrokeTrack(
      polylines: [[Point(x: 0, y: 0), Point(x: 8, y: 0)]], aspectRatio: 2)
    _ = control
    await setHKnown(
      "STUI-741: setH051: SampledStrokeTrack traps for a finite 1e300 segment; Int((raw / 0.5).rounded(.up)) is unchecked (SampledStrokeTrack.swift:63); a public custom Shape path with that point also traps the renderer (attribution probe); contract: finite path coordinates are drawable (Path.swift:73-80, 293); adjacent STUI-723"
    ) {
      await #expect(processExitsWith: .success) {
        _ = SampledStrokeTrack(
          polylines: [[Point(x: 0, y: 0), Point(x: 1e300, y: 0)]], aspectRatio: 2)
      }
    }
  }

  @Test func setH052StrokeTrackHugeEllipseTraps() async {
    _ = SampledStrokeTrack.ellipse(centerX: 4, centerY: 4, radiusX: 4, radiusY: 2, aspectRatio: 2)
    await setHKnown(
      "STUI-741: setH052: SampledStrokeTrack.ellipse traps for an Int.max / 2 radius; the arc step count Int(...rounded(.up)) is unchecked (SampledStrokeTrack.swift:128); contract: finite radii are drawable; adjacent STUI-723"
    ) {
      await #expect(processExitsWith: .success) {
        _ = SampledStrokeTrack.ellipse(
          centerX: 0, centerY: 0, radiusX: Int.max / 2, radiusY: 1, aspectRatio: 2)
      }
    }
  }

  // BrailleCanvas documents that out-of-range dots are clipped by setPixel.
  @Test func setH053BrailleStrokeEllipseOverflowTraps() async {
    var control = BrailleCanvas(width: 2, height: 2)
    control.strokeEllipse(centerX: 1, centerY: 1, radiusX: 40, radiusY: 40)
    await setHKnown(
      "STUI-753: setH053: BrailleCanvas.strokeEllipse traps for Int.max / 2 radii; 4 * (rx + ry) overflows (BrailleCanvas.swift:301); contract: out-of-range dots are clipped by setPixel (BrailleCanvas.swift:235-236); adjacent: none"
    ) {
      await #expect(processExitsWith: .success) {
        var canvas = BrailleCanvas(width: 2, height: 2)
        canvas.strokeEllipse(centerX: 0, centerY: 0, radiusX: Int.max / 2, radiusY: Int.max / 2)
      }
    }
  }

  // gridRadius clamps a huge Double radius to Int.max / 2; the grid's
  // stroke then computes (radiusX + radiusY) * 4.
  @Test func setH054CanvasDrawingHugeRadiusTraps() async {
    var control = setHCanvasContext()
    control.strokeEllipse(center: Point(x: 1, y: 1), radiusX: 30, radiusY: 30)
    await setHKnown(
      "STUI-753: setH054: CanvasContext.strokeEllipse(radiusX: 1e300, radiusY: 1e300) traps; gridRadius saturates to Int.max / 2 and CanvasGridBuffer.strokeEllipse computes (radiusX + radiusY) * 4 (CanvasDrawing.swift:416-455, CanvasGrid.swift:190); contract: public continuous drawing tolerates finite radii; adjacent: none"
    ) {
      await #expect(processExitsWith: .success) {
        var context = setHCanvasContext()
        context.strokeEllipse(center: .zero, radiusX: 1e300, radiusY: 1e300)
      }
    }
  }

  @Test func setH055PointContainingCellHugeAndNaNTrap() async {
    #expect(Point(x: 3.5, y: -1.5).containingCell == CellPoint(x: 3, y: -2))
    await setHKnown(
      "STUI-823: setH055: Point(x: 1e300).containingCell traps; Int(x.rounded(.down)) is unchecked (Point.swift:26-27); contract: public geometry query with no documented precondition; adjacent STUI-723"
    ) {
      await #expect(processExitsWith: .success) {
        _ = Point(x: 1e300, y: 0).containingCell
      }
    }
    await setHKnown(
      "STUI-823: setH055: Point(x: .nan).containingCell traps; Int(x.rounded(.down)) is unchecked (Point.swift:26-27); contract: public geometry query with no documented precondition; adjacent STUI-723"
    ) {
      await #expect(processExitsWith: .success) {
        _ = Point(x: .nan, y: 0).containingCell
      }
    }
    await setHKnown(
      "STUI-823: setH055: Point(x: -1e300).snapped(.toNearestOrEven) traps; Int(x.rounded(rule)) is unchecked (Point.swift:41-42); contract: public geometry query with no documented precondition; adjacent STUI-723"
    ) {
      await #expect(processExitsWith: .success) {
        _ = Point(x: -1e300, y: 0).snapped(.toNearestOrEven)
      }
    }
  }

  @Test func setH056PointContainingCellFloors() {
    #expect(Point(x: 2.9999999999999996, y: -0.5).containingCell == CellPoint(x: 2, y: -1))
    #expect(Point(x: -0.0, y: 0.5).containingCell == CellPoint(x: 0, y: 0))
  }

  // ScrollViewProxy.scrollTo(_:anchor:) has no finiteness precondition on
  // the anchor; the collection path multiplies free lines by anchor.y.
  @Test func setH057ListScrollToNaNAnchorTraps() async throws {
    try await MainActor.run {
      let harness = try StressRuntimeHarness(
        rootIdentity: testIdentity("SetHNumeric", "ListAnchorControl"),
        size: .init(width: 32, height: 10)
      ) {
        SetHAnchoredList(anchor: .bottom)
      }
      defer { harness.shutdown() }
      let frame = try harness.clickText("Jump")
      #expect(frame.contains("«9»"), "\(frame)")
    }
    await setHKnown(
      "STUI-768: setH057: ScrollViewProxy.scrollTo(_:anchor:) with UnitPoint(y: .nan) traps on a List; Int((free lines) * anchor.y) is unchecked (CollectionScrollState.swift:303); contract: SwiftUI ScrollViewProxy/UnitPoint have no finiteness precondition (GeometryTypes.swift:160); adjacent STUI-1170, STUI-1171"
    ) {
      await #expect(processExitsWith: .success) {
        try await MainActor.run {
          let harness = try StressRuntimeHarness(
            rootIdentity: testIdentity("SetHNumeric", "ListAnchorNaN"),
            size: .init(width: 32, height: 10)
          ) {
            SetHAnchoredList(anchor: UnitPoint(x: 0, y: .nan))
          }
          defer { harness.shutdown() }
          _ = try harness.clickText("Jump")
        }
      }
    }
  }

  @Test func setH058ScrollViewScrollToNaNAnchorTraps() async throws {
    try await MainActor.run {
      let harness = try StressRuntimeHarness(
        rootIdentity: testIdentity("SetHNumeric", "ScrollAnchorControl"),
        size: .init(width: 32, height: 10)
      ) {
        SetHAnchoredScrollView(anchor: .bottom)
      }
      defer { harness.shutdown() }
      let frame = try harness.clickText("Jump")
      #expect(frame.contains("row 9"), "\(frame)")
    }
    await setHKnown(
      "STUI-768: setH058: ScrollViewProxy.scrollTo(_:anchor:) with a NaN UnitPoint traps on a ScrollView; anchoredCoordinate converts (length - 1) * unit unchecked (LocalScrollPositionRegistry.swift:969-974, 1094-1100); contract: SwiftUI ScrollViewProxy/UnitPoint have no finiteness precondition; adjacent STUI-1170, STUI-1130"
    ) {
      await #expect(processExitsWith: .success) {
        try await MainActor.run {
          let harness = try StressRuntimeHarness(
            rootIdentity: testIdentity("SetHNumeric", "ScrollAnchorNaN"),
            size: .init(width: 32, height: 10)
          ) {
            SetHAnchoredScrollView(anchor: UnitPoint(x: .nan, y: .nan))
          }
          defer { harness.shutdown() }
          _ = try harness.clickText("Jump")
        }
      }
    }
  }

  @Test func setH059ProgressFractionTotality() {
    #expect(progressFraction(value: 0, total: 0) == 0)
    #expect(progressFraction(value: 1, total: 0) == 1)
    #expect(progressFraction(value: .nan, total: 1) == 0)
    #expect(progressFraction(value: .infinity, total: .infinity) == 0)
    #expect(progressFraction(value: -1, total: 10) == 0)
    #expect(progressFraction(value: 11, total: 10) == 1)
    #expect(meterSummaryText(value: .infinity, total: .infinity) == "0%")
  }

  @Test func setH060SliderMarkerAndTrackTotality() {
    #expect(sliderMarkerPosition(fraction: .nan, width: 10) == 0)
    #expect(sliderMarkerPosition(fraction: .infinity, width: 10) == 0)
    #expect(sliderMarkerPosition(fraction: -.infinity, width: 10) == 0)
    #expect(sliderMarkerPosition(fraction: 1, width: 1) == 0)
    #expect(metricTrackString(fraction: .infinity, barWidth: 10).filled.count == 10)
  }

  // MeshGradient requires only finite points; the row binning converts Float
  // triangle extents with Int(_).
  @Test func setH061MeshGradientHugeFinitePointTraps() async {
    _ = setHPreparedMesh(corner: SIMD2<Float>(1, 1))
    await setHKnown(
      "STUI-745: setH061: PreparedMeshGradient traps for a finite mesh point (1e30, 1e30), also through a public MeshGradient fill (attribution probe); row binning converts Float extents with Int(_) unchecked (PreparedMeshGradient.swift:336-343); contract: MeshGradient requires only finite points (GradientStyles.swift:275-277); adjacent: none"
    ) {
      await #expect(processExitsWith: .success) {
        _ = setHPreparedMesh(corner: SIMD2<Float>(1e30, 1e30))
      }
    }
  }

  // measurementCacheHitRate is a public Double?; the formatter computes
  // Int(rate * 1000). The framework's own derivation guards lookups > 0.
  @Test func setH062TSVCacheHitRateNaNTraps() async {
    var control = FrameDiagnosticRecord(frameNumber: 1, causeSummary: "setH062")
    control.measurementCacheHitRate = 0.5
    #expect(FrameDiagnosticsTSVFormatting.recordFields(for: control).contains("50.0%"))
    await setHKnown(
      "STUI-1228: setH062: FrameDiagnosticsTSVFormatting.recordFields traps for measurementCacheHitRate = .nan; Int(rate * 1000) is unchecked (FrameDiagnosticsTSVFormatting.swift:330-334); contract: the formatter is total over its public record field (FrameDiagnosticRecord.swift:184); adjacent: setB321-330 diagnostics sinks, no STUI"
    ) {
      await #expect(processExitsWith: .success) {
        var record = FrameDiagnosticRecord(frameNumber: 1, causeSummary: "setH062")
        record.measurementCacheHitRate = .nan
        _ = FrameDiagnosticsTSVFormatting.recordFields(for: record)
      }
    }
  }

  @Test func setH063SummarySinkInfiniteCPUPercentTraps() async {
    let reports = await MainActor.run {
      let finite = SummarySink()
      finite.emit(.cpu(setHCPUSample(percent: 150)))
      let notANumber = SummarySink()
      notANumber.emit(.cpu(setHCPUSample(percent: .nan)))
      return (finite.report(), notANumber.report())
    }
    #expect(reports.0.contains("cpu: peak 150%"), "\(reports.0)")
    #expect(!reports.1.lowercased().contains("nan"), "\(reports.1)")
    await setHKnown(
      "STUI-1228: setH063: SummarySink.report traps after an infinite estimatedCPUPercent sample; max keeps +inf and Int(cpuPeakPercent.rounded()) is unchecked (SummarySink.swift:52, 80); contract: profiling sinks are total over the public CPUSample (CPUSampler.swift:62-78); adjacent: none"
    ) {
      await #expect(processExitsWith: .success) {
        await MainActor.run {
          let sink = SummarySink()
          sink.emit(.cpu(setHCPUSample(percent: .infinity)))
          _ = sink.report()
        }
      }
    }
  }

  @Test func setH064MetricValueStringTotality() {
    #expect(metricValueString(.infinity) == "0")
    #expect(metricValueString(.nan) == "0")
    #expect(!metricValueString(1e300).isEmpty)
  }

  @Test func setH065PathArcHugeRadiusBuilds() {
    var path = Path()
    path.addArc(
      center: .zero, radius: 1e300, startAngle: .degrees(0), endAngle: .degrees(90),
      clockwise: false)
    #expect(!path.elements.isEmpty)
    let points = path.flattened(tolerance: 1).flatMap { $0 }
    #expect(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
  }

  @Test func setH066HalfSpanHugeRadiusIsTotal() {
    #expect(
      EllipseRasterization.halfSpan(radiusX: Int.max / 2, radiusY: Int.max / 2, offsetY: 0)
        == Int.max / 2)
  }

  @Test func setH067CanvasNaNCenterIsIgnored() {
    var context = setHCanvasContext()
    context.fillEllipse(center: Point(x: .nan, y: .nan), radiusX: 1, radiusY: 1)
    context.strokeEllipse(center: Point(x: .nan, y: .nan), radiusX: 1, radiusY: 1)
  }

  // Not executed: fillEllipse with radiusX 1e300 and radiusY 0 runs the
  // single-row branch over -(Int.max / 2)...(Int.max / 2) — an unbounded
  // loop no 10 s test can bound. Recorded from code reading in the brief.
  @Test(
    .disabled(
      "setH068: hang by code reading (BrailleCanvas.swift:254-258); not executable within the 10 s budget"
    ))
  func setH068FillEllipseHugeRadiusHangs() {
    var context = setHCanvasContext()
    context.fillEllipse(center: .zero, radiusX: 1e300, radiusY: 0)
  }
}

// MARK: - Fixtures

private func setHCanvasContext() -> CanvasContext {
  CanvasContext(
    canvas: CanvasGridBuffer(size: CellSize(width: 4, height: 2), grid: .braille2x4),
    foreground: .white,
    background: nil)
}

private func setHPreparedMesh(corner: SIMD2<Float>) -> PreparedMeshGradient {
  PreparedMeshGradient(
    input: MeshGradientRasterInput(
      width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], corner],
      colors: [.black, .red, .blue, .white],
      background: .clear, smoothsColors: false, colorSpace: .device),
    bounds: CellRect(origin: .zero, size: CellSize(width: 8, height: 4)))
}

private func setHCPUSample(percent: Double) -> CPUSample {
  CPUSample(
    timestampSeconds: 1, userCPUSeconds: 0, systemCPUSeconds: 0, totalCPUSeconds: 0,
    wallDeltaSeconds: 1, estimatedCPUPercent: percent, maxResidentBytes: 0)
}

@MainActor
private struct SetHAnchoredList: View {
  let anchor: UnitPoint

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        Button("Jump") { _ = proxy.scrollTo(9, anchor: anchor) }
        List(0..<30, id: \.self) { row in Text("«\(row)»") }
          .scrollIndicators(.hidden)
          .frame(height: 5)
      }
    }
  }
}

@MainActor
private struct SetHAnchoredScrollView: View {
  let anchor: UnitPoint

  var body: some View {
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: 0) {
        Button("Jump") { _ = proxy.scrollTo(9, anchor: anchor) }
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<30, id: \.self) { row in Text("row \(row)").id(row) }
          }
        }
        .scrollIndicators(.hidden)
        .frame(height: 5)
      }
    }
  }
}
