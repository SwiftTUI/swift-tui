import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

/// Opt-in release measurement for the radial support walk (STUI-618 §4C).
///
/// Not a gate: it prints timings and asserts only that the two walks agree.
/// Run it in release with testing enabled:
///
///     SWIFTTUI_RADIAL_RASTER_BENCH=1 swiftly run swift test -c release \
///       -Xswiftc -enable-testing --filter RadialGradientRasterBenchmarkTests
///
/// The scene is the counter demo's overload shape: a 180 × 60 surface and
/// fifty overlapping screen-blended ripples (three stops: clear, colour,
/// clear) at radii spread from just-born to just-completed.
@Suite("Radial gradient raster benchmark")
struct RadialGradientRasterBenchmarkTests {
  @Test(
    "fifty overlapping ripples: reference walk vs support walk",
    .enabled(if: ProcessInfo.processInfo.environment["SWIFTTUI_RADIAL_RASTER_BENCH"] == "1")
  )
  func fiftyRipples() {
    let surface = CellSize(width: 180, height: 60)
    let node = Self.rippleScene(surface: surface, layers: 50)
    let iterations = 12

    func time(_ body: () -> RasterSurface) -> (
      median: Duration, best: Duration, surface: RasterSurface
    ) {
      let clock = ContinuousClock()
      var samples: [Duration] = []
      var last = body()
      for _ in 0..<iterations {
        let start = clock.now
        last = body()
        samples.append(start.duration(to: clock.now))
      }
      samples.sort()
      return (samples[samples.count / 2], samples[0], last)
    }

    let reference = time {
      Rasterizer.$forceReferenceRadialWalk.withValue(true) {
        Rasterizer().rasterize(node, minimumSize: surface)
      }
    }
    let optimized = time {
      Rasterizer().rasterize(node, minimumSize: surface)
    }
    #expect(reference.surface == optimized.surface)

    let probe = RasterWorkProbe()
    _ = Rasterizer.$workProbe.withValue(probe) {
      Rasterizer().rasterize(node, minimumSize: surface)
    }
    let work = probe.snapshot()
    let referenceProbe = RasterWorkProbe()
    _ = Rasterizer.$workProbe.withValue(referenceProbe) {
      Rasterizer.$forceReferenceRadialWalk.withValue(true) {
        Rasterizer().rasterize(node, minimumSize: surface)
      }
    }
    let referenceWork = referenceProbe.snapshot()

    // Per-call cost of the screen blend a write pays when it lands on an
    // already painted cell, to size the remaining per-write compositing.
    let overlay = ResolvedTextStyle(backgroundColor: Color.cyan.opacity(0.6))
    let underlay = ResolvedTextStyle(backgroundColor: Color(red: 0.1, green: 0.2, blue: 0.3))
    let blendClock = ContinuousClock()
    let blendCalls = 200_000
    let blendStart = blendClock.now
    var sink = 0.0
    for _ in 0..<blendCalls {
      sink += overlay.composited(over: underlay, blendMode: .screen).backgroundColor?.red ?? 0
    }
    let blendDuration = blendStart.duration(to: blendClock.now)
    #expect(sink > 0)

    // Where the blend's time goes: the two inbound profile conversions, the
    // outbound conversion with perceptual gamut compression, and the same
    // outbound conversion with plain clipping as a cost reference. Stage
    // timings, not a proposal: an outbound hoist would need an equivalence
    // proof at raster precision first.
    func stage(_ label: String, _ body: () -> Double) -> String {
      let start = blendClock.now
      var acc = 0.0
      for _ in 0..<blendCalls {
        acc += body()
      }
      let duration = start.duration(to: blendClock.now)
      sink += acc
      return "\(label)=\(Self.ms(duration / blendCalls * 1_000_000)) ns"
    }
    let overlayColor = Color.cyan.opacity(0.6)
    let underlayColor = Color(red: 0.1, green: 0.2, blue: 0.3)
    let linear = overlayColor.converted(to: .linearSRGB, gamutMapping: .preserve)
    let stages = [
      stage("inbound-preserve") {
        overlayColor.converted(to: .linearSRGB, gamutMapping: .preserve).red
      },
      stage("outbound-compressPerceptual") {
        linear.converted(to: .sRGB, gamutMapping: .compressPerceptual).red
      },
      stage("outbound-clip") {
        linear.converted(to: .sRGB, gamutMapping: .clip).red
      },
      stage("color-composited-screen") {
        overlayColor.composited(over: underlayColor, mode: .screen).red
      },
    ]

    print(
      """
      [radial-raster-bench] surface=\(surface.width)x\(surface.height) layers=50 iterations=\(iterations)
      [radial-raster-bench] reference: median=\(Self.ms(reference.median)) ms best=\(Self.ms(reference.best)) ms \
      samples=\(referenceWork.radialSamples) visited=\(referenceWork.visitedCells) blendedWrites=\(referenceWork.blendedWrites)
      [radial-raster-bench] optimized: median=\(Self.ms(optimized.median)) ms best=\(Self.ms(optimized.best)) ms \
      samples=\(work.radialSamples) visited=\(work.visitedCells) blendedWrites=\(work.blendedWrites) \
      spanRows=\(work.spanRows) skippedRows=\(work.skippedRows) culled=\(work.culledLayers)
      [radial-raster-bench] screen blend: \(Self.ms(blendDuration / blendCalls * 1_000_000)) ns/call; \
      \(work.blendedWrites) blended writes ≈ \(Self.ms(blendDuration / blendCalls * work.blendedWrites)) ms per frame if every write composites
      [radial-raster-bench] blend stages: \(stages.joined(separator: " "))
      """
    )
  }

  /// Milliseconds with three decimals, without `String(format:)` (which
  /// strict memory safety flags as unsafe).
  private static func ms(_ duration: Duration) -> String {
    let (seconds, attoseconds) = duration.components
    let microseconds = seconds * 1_000_000 + attoseconds / 1_000_000_000_000
    let whole = microseconds / 1_000
    let fraction = Int(microseconds % 1_000)
    let padded = String(fraction)
    return "\(whole)." + String(repeating: "0", count: 3 - padded.count) + padded
  }

  static func rippleScene(surface: CellSize, layers: Int) -> DrawNode {
    let bounds = CellRect(origin: .zero, size: surface)
    let maxRadius = Double(max(surface.width, surface.height)) * 0.6
    let children = (0..<layers).map { index -> DrawNode in
      let progress = Double(index) / Double(max(1, layers - 1))
      let endRadius = 2 + maxRadius * progress
      let gradient = RadialGradient(
        gradient: Gradient(stops: [
          .init(color: .clear, location: 0),
          .init(
            color: Color(red: 0.35, green: 0.8, blue: 1.0, alpha: 0.9 * (1 - progress)),
            location: 0.55),
          .init(color: .clear, location: 1),
        ]),
        center: .center,
        startRadius: endRadius * 0.6,
        endRadius: endRadius
      )
      return DrawNode(
        identity: testIdentity("ripple-bench", "layer-\(index)"),
        bounds: bounds,
        drawEffects: DrawEffects([.blendMode(.screen)]),
        commands: [
          .fill(
            bounds: bounds, geometry: .rectangle, insetAmount: 0, style: .radialGradient(gradient),
            mode: .full)
        ]
      )
    }
    return DrawNode(identity: testIdentity("ripple-bench"), bounds: bounds, children: children)
  }
}
