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
  119:
    "NEW-1: AlignmentLine(guides: []).merged(with:) reports leading 0 for runs whose guides are all negative (and trailing 0 when every guide passes its child); the windowed lazy seed is a zero line, not the line of no children; contract: LayoutEngine+Alignment.swift:35-36; adjacent STUI-1242",
  120:
    "NEW-1: a scroll-hosted LazyVStack whose rows all carry negative leading guides draws every row one column right of the eager VStack; the windowed cross line starts from a zero line; contract: Divergences-And-Gaps.md:398-404; adjacent STUI-1242",
  122:
    "NEW-2: an alignment line whose widest-remainder child is a half-cell child moved toward leading spans one cell past its children (guides (6,int,6) and (5,half,7): extent 8, union 7); trailing is measured from the unmoved guide; contract: Authoring-Views.md:89-91; adjacent STUI-1242",
  123:
    "NEW-2: a VStack of Text(\"aaa\") and Text(\"bbbbbbbb\").alignmentGuide(.center) { _ in 7 } is 9 columns wide for 8 columns of children, so its HStack sibling draws one column late; trailing is measured from the unmoved guide; contract: Authoring-Views.md:89-91; adjacent STUI-1242",
  130:
    "NEW-6: visibleRowCount counts the row above a separator line that starts the published window (window 1..<3 over rows 0..<1 and 2..<3 counts 2); the exact branch takes row(atOrBeforeLine:) of the first line; contract: CollectionScrollState.swift:116-125, :76-78; adjacent STUI-1239, STUI-1262",
  136:
    "NEW-7: the Windows arm enables hyperlinks and synchronized output from an inherited WT_SESSION although TERM_PROGRAM names another emulator (mintty, TERM empty); isWindowsTerminal ignores TERM_PROGRAM; contract: Environment-Variables.md:43-45; adjacent STUI-1225, STUI-1247",
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
