import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

/// Campaign two F5 pass 2 (setG101–setG150). Every property draws
/// `PropertyDefaults.iterations` values (100 on the hot path, 1,000 under
/// `SWIFTTUI_STRESS_FULL=1`) from seed `0xF5000000 + id` and shrinks at most 64
/// steps. A reproduced finding runs inside its exact known-issue guard unless
/// `SWIFTTUI_F5_UNMARKED=1` asks for the raw expectation.
let setGUnmarked = ProcessInfo.processInfo.environment["SWIFTTUI_F5_UNMARKED"] == "1"

@MainActor
func setGProperty<Value: Sendable>(
  _ id: Int, _ generator: Gen<Value>, _ body: @MainActor (Value) throws -> String?
) {
  let result = checkProperty(generator, seed: 0xF500_0000 + UInt64(id), maxShrinkSteps: 64, body)
  if let issue = setGKnownIssues[id], !setGUnmarked {
    withKnownIssue(Comment(rawValue: issue)) {
      #expect(result.isPassing, "setG\(id): \(result)")
    }
  } else {
    #expect(result.isPassing, "setG\(id): \(result)")
  }
}

/// Reproduced pass-2 findings, keyed by scenario number.
let setGKnownIssues: [Int: String] = [
  102:
    "STUI-1249 (duplicate): a segment with both endpoints beyond the clip square is clipped off its own line (residual 2^23 at 2^73 endpoints); the crossing interpolates from an endpoint far from the boundary; contract: SaturatingConversion.swift:57-61; adjacent STUI-1245",
  105:
    "NEW-5: the half-scale clip of a horizontal far segment turns its odd subnormal y into its even neighbour (5e-324 becomes 0); halving rounds to even before doubling back; contract: SaturatingConversion.swift:63-67; adjacent STUI-1245",
  107:
    "STUI-1249 (duplicate): a Canvas line through the canvas drawn from endpoints beyond 2^60 cells lights no sample; the clipped endpoints leave the line; contract: CanvasDrawing.swift:188-191, :455-457; adjacent STUI-1245",
  110:
    "NEW-3: BrailleCanvas.fillCircle lights column cx - r on rows near the centre once r >= 2^26 (span r, exact floor(sqrt(r^2 - dy^2)) is r - 1); the Double square root rounds up to r; contract: BrailleCanvas.swift:197-200; adjacent STUI-753",
  111:
    "NEW-4: Path.contains flips for a polygon and query scaled by 2^k beyond about 2^512 (a point outside a triangle hit at 2^949); (py - y1)(x2 - x1) overflows to infinity in rayCrossingDirection; contract: Path.swift:185-189, plan F5 affine containment; adjacent STUI-1268, STUI-1119",
  130:
    "NEW-6: visibleRowCount counts the row above a separator line that starts the published window (window 1..<3 over rows 0..<1 and 2..<3 counts 2); the exact branch takes row(atOrBeforeLine:) of the first line; contract: CollectionScrollState.swift:116-125, :76-78; adjacent STUI-1239, STUI-1262",
  136:
    "NEW-7: the Windows arm enables hyperlinks and synchronized output from an inherited WT_SESSION although TERM_PROGRAM names another emulator (mintty, TERM empty); isWindowsTerminal ignores TERM_PROGRAM; contract: Environment-Variables.md:43-45; adjacent STUI-1225, STUI-1247",
  142:
    "NEW-8: Point.fractionInCell is 1.0 for x in (-2^-53, 0) (x = -5.55e-17); x - floor(x) rounds to 1; contract: Point.swift:21-35; adjacent STUI-823",
]

/// `count` independent draws in `range`; properties derive their inputs from
/// them so every input shrinks towards the smallest draw.
func setGDraws(_ count: Int, _ range: ClosedRange<Int> = 0...1_000_000) -> Gen<[Int]> {
  Gen<[Int]>.array(of: .int(in: range), count: count...count)
}

func setGPow2(_ exponent: Int) -> Double {
  Double(sign: .plus, exponent: exponent, significand: 1)
}

/// The classic all-octant Bresenham walk: the unclipped reference every
/// clipped primitive is measured against.
func setGBresenham(from start: (x: Int, y: Int), to end: (x: Int, y: Int)) -> [[Int]] {
  var x = start.x
  var y = start.y
  let dx = abs(end.x - start.x)
  let dy = -abs(end.y - start.y)
  let stepX = start.x < end.x ? 1 : -1
  let stepY = start.y < end.y ? 1 : -1
  var error = dx + dy
  var samples: [[Int]] = []
  while true {
    samples.append([x, y])
    if x == end.x, y == end.y { break }
    let doubled = 2 * error
    if doubled >= dy {
      if x == end.x { break }
      error += dy
      x += stepX
    }
    if doubled <= dx {
      if y == end.y { break }
      error += dx
      y += stepY
    }
  }
  return samples
}
