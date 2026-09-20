/// A dash pattern measured along a stroke track.
///
/// Lengths and the phase are in track units: one unit is the width of a cell.
/// The pattern follows Core Graphics. The runs alternate on and off, an odd
/// count repeats to make an even one, and `phase` is how far into the pattern
/// the track starts.
package struct StrokeDashPattern: Equatable, Sendable {
  private let runs: [Double]
  private let period: Double
  private let phase: Double

  /// Returns `nil` when the stroke is solid: an empty pattern, a pattern with
  /// a negative or non-finite length, or one whose lengths sum to zero.
  package init?(dash: [Double], phase: Double) {
    guard !dash.isEmpty, dash.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
      return nil
    }
    let runs = dash.count.isMultiple(of: 2) ? dash : dash + dash
    let period = runs.reduce(0, +)
    guard period > 0 else {
      return nil
    }
    self.runs = runs
    self.period = period
    self.phase = phase.isFinite ? phase : 0
  }

  package func isOn(at position: Double) -> Bool {
    var offset = (position + phase).truncatingRemainder(dividingBy: period)
    if offset < 0 {
      offset += period
    }
    for (index, run) in runs.enumerated() {
      if offset < run {
        return index.isMultiple(of: 2)
      }
      offset -= run
    }
    return true
  }
}

/// The ordered cells along the outline of a rectangle, which is what a border
/// or a rectangle stroke draws.
///
/// The ring is walked clockwise from the top-leading corner: top left to
/// right, right top to bottom, bottom right to left, left bottom to top. Each
/// cell has two arms, one toward each neighbor on the track.
///
/// Each cell occupies an interval of track length. A cell on a horizontal run
/// is 1 unit long and a cell on a vertical run is `verticalCellLength` units
/// long, so a dash is the same physical length on every edge. A corner cell
/// belongs to the run it starts. The first half of a cell's interval is its
/// incoming arm and the second half is its outgoing arm.
///
/// A rectangle one row high or one column wide is an open track: a line.
package struct RectangleStrokeTrack: Equatable, Sendable {
  package struct Arm: Equatable, Sendable {
    package var direction: LineDirection
    /// The edge of the rectangle this arm runs along.
    package var side: BorderSide
  }

  package struct Cell: Equatable, Sendable {
    /// Column and row, relative to the rectangle's origin.
    package var x: Int
    package var y: Int
    package var incoming: Arm
    package var outgoing: Arm
    package var start: Double
    package var length: Double
    package var isCorner: Bool

    package var incomingMidpoint: Double { start + length * 0.25 }
    package var outgoingMidpoint: Double { start + length * 0.75 }
    package var midpoint: Double { start + length * 0.5 }
  }

  /// Which arms of a cell a stroke draws, after the mask.
  package struct ResolvedCell: Equatable, Sendable {
    package var north = false
    package var east = false
    package var south = false
    package var west = false

    package var isOn: Bool {
      north || east || south || west
    }

    package subscript(direction: LineDirection) -> Bool {
      get {
        switch direction {
        case .north: north
        case .east: east
        case .south: south
        case .west: west
        }
      }
      set {
        switch direction {
        case .north: north = newValue
        case .east: east = newValue
        case .south: south = newValue
        case .west: west = newValue
        }
      }
    }
  }

  package let width: Int
  package let height: Int
  package let verticalCellLength: Double

  package init(width: Int, height: Int, aspectRatio: Double) {
    self.width = max(0, width)
    self.height = max(0, height)
    verticalCellLength = Self.snappedAspectRatio(aspectRatio)
  }

  /// The cell aspect ratio a track measures with: the reported ratio snapped to
  /// the nearest 0.5.
  ///
  /// A reported ratio such as 2.1 makes vertical dash boundaries drift against
  /// the half-cell grid, so vertical dashes come out in uneven lengths. The
  /// snap keeps the pattern periodic. It applies to track length only.
  package static func snappedAspectRatio(_ aspectRatio: Double) -> Double {
    guard aspectRatio.isFinite, aspectRatio > 0 else {
      return CellPixelMetrics.estimated.aspectRatio
    }
    return max(0.5, (aspectRatio * 2).rounded() / 2)
  }

  private var isRing: Bool {
    width >= 2 && height >= 2
  }

  package var length: Double {
    if isRing {
      return 2 * Double(width - 1) + 2 * verticalCellLength * Double(height - 1)
    }
    if height == 1 {
      return Double(width)
    }
    return verticalCellLength * Double(height)
  }

  package func forEachCell(_ body: (Cell) -> Void) {
    guard width > 0, height > 0 else {
      return
    }
    guard isRing else {
      forEachLineCell(body)
      return
    }
    let vertical = verticalCellLength
    let top = Arm(direction: .east, side: .top)
    let right = Arm(direction: .south, side: .right)
    let bottom = Arm(direction: .west, side: .bottom)
    let left = Arm(direction: .north, side: .left)

    for x in 0..<(width - 1) {
      body(
        Cell(
          x: x, y: 0,
          incoming: x == 0
            ? Arm(direction: .south, side: .left) : Arm(direction: .west, side: .top),
          outgoing: top,
          start: Double(x), length: 1, isCorner: x == 0))
    }
    let rightStart = Double(width - 1)
    for y in 0..<(height - 1) {
      body(
        Cell(
          x: width - 1, y: y,
          incoming: y == 0
            ? Arm(direction: .west, side: .top) : Arm(direction: .north, side: .right),
          outgoing: right,
          start: rightStart + vertical * Double(y), length: vertical, isCorner: y == 0))
    }
    let bottomStart = rightStart + vertical * Double(height - 1)
    for step in 0..<(width - 1) {
      body(
        Cell(
          x: width - 1 - step, y: height - 1,
          incoming: step == 0
            ? Arm(direction: .north, side: .right) : Arm(direction: .east, side: .bottom),
          outgoing: bottom,
          start: bottomStart + Double(step), length: 1, isCorner: step == 0))
    }
    let leftStart = bottomStart + Double(width - 1)
    for step in 0..<(height - 1) {
      body(
        Cell(
          x: 0, y: height - 1 - step,
          incoming: step == 0
            ? Arm(direction: .east, side: .bottom) : Arm(direction: .south, side: .left),
          outgoing: left,
          start: leftStart + vertical * Double(step), length: vertical, isCorner: step == 0))
    }
  }

  private func forEachLineCell(_ body: (Cell) -> Void) {
    if height == 1 {
      for x in 0..<width {
        body(
          Cell(
            x: x, y: 0,
            incoming: Arm(direction: .west, side: .top),
            outgoing: Arm(direction: .east, side: .top),
            start: Double(x), length: 1, isCorner: false))
      }
      return
    }
    for y in 0..<height {
      body(
        Cell(
          x: 0, y: y,
          incoming: Arm(direction: .north, side: .left),
          outgoing: Arm(direction: .south, side: .left),
          start: verticalCellLength * Double(y), length: verticalCellLength, isCorner: false))
    }
  }

  /// The track position of the middle of the trailing edge.
  ///
  /// SwiftUI starts a `Rectangle` path at its top-leading corner, which is
  /// where this track starts. It starts a `RoundedRectangle` path at the middle
  /// of the trailing edge, so that is where a rounded rectangle measures its
  /// dash from. Both run clockwise. Measured with a native probe on 2026-09-19.
  package var trailingEdgeMidpoint: Double {
    guard isRing else {
      return 0
    }
    return Double(width - 1) + verticalCellLength * Double(height - 1) / 2
  }

  /// Applies the mask to one cell.
  ///
  /// `sides` and `dash` are both tests on position along the track. An arm is
  /// drawn when its edge is selected and the dash is on where the arm sits.
  ///
  /// - Parameters:
  ///   - dashOrigin: The track position the dash pattern is measured from.
  ///   - samplesEachArm: Samples the dash at each arm's midpoint, which gives
  ///     half-cell resolution. A pen without half-line glyphs passes `false`
  ///     and the dash is sampled once, at the middle of the cell.
  package func resolve(
    _ cell: Cell,
    sides: Edge.Set,
    dash: StrokeDashPattern?,
    dashOrigin: Double = 0,
    samplesEachArm: Bool
  ) -> ResolvedCell {
    let incomingSelected = includes(cell.incoming.side, in: sides)
    let outgoingSelected = includes(cell.outgoing.side, in: sides)
    let incomingSample = (samplesEachArm ? cell.incomingMidpoint : cell.midpoint) - dashOrigin
    let outgoingSample = (samplesEachArm ? cell.outgoingMidpoint : cell.midpoint) - dashOrigin
    let incomingOn = incomingSelected && (dash?.isOn(at: incomingSample) ?? true)
    let outgoingOn = outgoingSelected && (dash?.isOn(at: outgoingSample) ?? true)

    var resolved = ResolvedCell()
    resolved[cell.incoming.direction] = incomingOn
    resolved[cell.outgoing.direction] = outgoingOn

    // Where `sides` leaves out one edge of a corner, the remaining edge ends in
    // that cell. It is drawn to the cell's far edge, so a lone top border
    // reaches both ends of the frame.
    if cell.isCorner {
      if !incomingSelected, outgoingOn {
        resolved[cell.outgoing.direction.opposite] = true
      }
      if !outgoingSelected, incomingOn {
        resolved[cell.incoming.direction.opposite] = true
      }
    }
    return resolved
  }

  /// A line has one row or one column, so its two long edges are the same
  /// cells. Either edge selects it.
  private func includes(_ side: BorderSide, in sides: Edge.Set) -> Bool {
    if !isRing {
      return height == 1
        ? sides.contains(.top) || sides.contains(.bottom)
        : sides.contains(.leading) || sides.contains(.trailing)
    }
    switch side {
    case .top: return sides.contains(.top)
    case .right: return sides.contains(.trailing)
    case .bottom: return sides.contains(.bottom)
    case .left: return sides.contains(.leading)
    }
  }
}

/// How a stroke turns the arms of a track cell into a glyph.
///
/// A line pen picks its glyph from the arms, so a corner, a half-line and a
/// junction are one lookup. An edge pen draws ink against a side of the cell,
/// as the half-block palettes do, so it picks its glyph from the side or
/// corner the cell is on.
package enum StrokePen: Equatable, Sendable {
  case line(horizontal: LineWeight, vertical: LineWeight, roundsCorners: Bool)
  case edge(EdgeGlyphs)

  package struct EdgeGlyphs: Equatable, Sendable {
    package var top: Character
    package var bottom: Character
    package var left: Character
    package var right: Character
    package var topLeading: Character
    package var topTrailing: Character
    package var bottomLeading: Character
    package var bottomTrailing: Character
  }

  /// - Parameter roundsCorners: Whether the geometry or the join asks for
  ///   rounded corners. A `BorderSet` whose corner glyph is an arc asks too.
  package init(borderSet: BorderSet, roundsCorners: Bool) {
    if let horizontal = borderSet.top.first.flatMap(LineArms.init(glyph:)),
      let vertical = borderSet.left.first.flatMap(LineArms.init(glyph:)),
      horizontal.east != .none, horizontal.east == horizontal.west,
      horizontal.north == .none, horizontal.south == .none,
      vertical.north != .none, vertical.north == vertical.south,
      vertical.east == .none, vertical.west == .none
    {
      self = .line(
        horizontal: horizontal.east,
        vertical: vertical.north,
        roundsCorners: roundsCorners || borderSet.topLeading.first == "╭"
      )
      return
    }
    self = .edge(
      EdgeGlyphs(
        top: borderSet.top.first ?? " ",
        bottom: borderSet.bottom.first ?? " ",
        left: borderSet.left.first ?? " ",
        right: borderSet.right.first ?? " ",
        topLeading: borderSet.topLeading.first ?? " ",
        topTrailing: borderSet.topTrailing.first ?? " ",
        bottomLeading: borderSet.bottomLeading.first ?? " ",
        bottomTrailing: borderSet.bottomTrailing.first ?? " "
      ))
  }

  /// Whether the pen can draw half a cell. Unicode has half-lines for the
  /// light and heavy weights only.
  package var samplesEachArm: Bool {
    switch self {
    case .line(let horizontal, let vertical, _):
      horizontal != .double && vertical != .double
    case .edge:
      false
    }
  }

  /// The glyph for a resolved cell, or `nil` when the cell is not drawn.
  package func glyph(
    for cell: RectangleStrokeTrack.Cell,
    resolved: RectangleStrokeTrack.ResolvedCell
  ) -> Character? {
    guard resolved.isOn else {
      return nil
    }
    switch self {
    case .line(let horizontal, let vertical, let roundsCorners):
      let arms = LineArms(
        north: resolved.north ? vertical : .none,
        east: resolved.east ? horizontal : .none,
        south: resolved.south ? vertical : .none,
        west: resolved.west ? horizontal : .none
      )
      return arms.glyph(roundedCorner: roundsCorners && cell.isCorner)
        ?? arms.reweighted(to: horizontal).glyph()
    case .edge(let glyphs):
      return glyphs.glyph(for: cell, resolved: resolved)
    }
  }
}

extension StrokePen.EdgeGlyphs {
  fileprivate func glyph(
    for cell: RectangleStrokeTrack.Cell,
    resolved: RectangleStrokeTrack.ResolvedCell
  ) -> Character {
    // A corner glyph needs both of its edges. With one edge left out by
    // `sides`, the cell is the end of the remaining edge.
    let turnsCorner = resolved[cell.incoming.direction] && resolved[cell.outgoing.direction]
    if cell.isCorner, turnsCorner {
      switch (cell.incoming.side, cell.outgoing.side) {
      case (.left, .top): return topLeading
      case (.top, .right): return topTrailing
      case (.right, .bottom): return bottomTrailing
      default: return bottomLeading
      }
    }
    let side = resolved[cell.outgoing.direction] ? cell.outgoing.side : cell.incoming.side
    switch side {
    case .top: return top
    case .right: return right
    case .bottom: return bottom
    case .left: return left
    }
  }
}
