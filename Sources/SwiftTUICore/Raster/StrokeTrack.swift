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

/// The test a stroke applies to each position along its track.
///
/// A trim and a dash are both tests on position. Both are measured from the
/// start of the path, which SwiftUI puts at the top-leading corner of a
/// `Rectangle` and at the middle of the trailing edge of a rounded shape. The
/// dash is measured from the start of the trimmed part, as in SwiftUI.
package struct StrokeMask: Equatable, Sendable {
  package var dash: StrokeDashPattern?
  package var trim: StrokeTrim?
  /// The track position the dash pattern is measured from.
  package var origin: Double
  /// The track position of the start of the path, which the trim is measured
  /// from.
  ///
  /// On a rectangle the two differ by half a cell. The dash is measured from
  /// the leading edge of the corner cell, so that whole-number dashes land on
  /// whole cells. The path starts at the corner's vertex, in the middle of that
  /// cell, between its two arms. Measuring the trim from the vertex keeps the
  /// arm that points down the leading edge out of a trim that starts along the
  /// top.
  package var trimOrigin: Double

  package init(
    dash: StrokeDashPattern? = nil,
    trim: StrokeTrim? = nil,
    origin: Double = 0,
    trimOrigin: Double? = nil
  ) {
    self.dash = dash
    self.trim = trim
    self.origin = origin
    self.trimOrigin = trimOrigin ?? origin
  }

  package init(_ style: StrokeStyle, origin: Double = 0, trimOrigin: Double? = nil) {
    self.init(
      dash: StrokeDashPattern(dash: style.effectiveDash, phase: style.dashPhase),
      trim: style.trim,
      origin: origin,
      trimOrigin: trimOrigin
    )
  }

  /// Whether every position is on, so the stroke can skip the test.
  package var isSolid: Bool {
    dash == nil && trim == nil
  }

  package func isOn(at position: Double, trackLength: Double) -> Bool {
    guard trackLength > 0 else {
      return dash?.isOn(at: position) ?? true
    }
    // Positions wrap round a closed track, so the seam of a pattern that does
    // not divide the length falls at the start of the path.
    func wrapped(_ value: Double) -> Double {
      let remainder = value.truncatingRemainder(dividingBy: trackLength)
      return remainder < 0 ? remainder + trackLength : remainder
    }
    guard let trim else {
      return dash?.isOn(at: wrapped(position - origin)) ?? true
    }
    let fromStart = wrapped(position - trimOrigin)
    let start = trim.from * trackLength
    guard !trim.isEmpty, fromStart >= start, fromStart < trim.to * trackLength else {
      return false
    }
    // The dash is measured from the start of the trimmed part, as in SwiftUI.
    // With nothing trimmed from the start it falls where the untrimmed dash
    // does.
    return dash?.isOn(at: fromStart - start + (trimOrigin - origin)) ?? true
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
    /// Whether an arm points off the end of an open track. Such an arm is a
    /// cap: it draws the end cell to its edge, so a lone `Divider` is `─` to
    /// both ends. It is soft, which means it gives way when another stroke
    /// shares the cell.
    package var incomingIsCap = false
    package var outgoingIsCap = false

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
    /// The drawn arms that are caps, one bit for each ``LineDirection``.
    private var softMask: UInt8 = 0

    package var isOn: Bool {
      north || east || south || west
    }

    package func isSoft(_ direction: LineDirection) -> Bool {
      softMask & (1 << UInt8(direction.rawValue)) != 0
    }

    package mutating func markSoft(_ direction: LineDirection) {
      softMask |= 1 << UInt8(direction.rawValue)
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

  /// Whether a track one cell thick runs along a row. It means nothing for a
  /// ring.
  private let isHorizontalLine: Bool

  /// - Parameter lineAxis: Which way a rule runs. It matters for one cell
  ///   only: a 1 x 1 rectangle is one row high and one column wide at once, so
  ///   its size cannot say whether it is a horizontal rule or a vertical one.
  ///   Without an axis it is horizontal.
  package init(width: Int, height: Int, aspectRatio: Double, lineAxis: Axis? = nil) {
    self.width = max(0, width)
    self.height = max(0, height)
    verticalCellLength = Self.snappedAspectRatio(aspectRatio)
    isHorizontalLine = height == 1 && !(width == 1 && lineAxis == .vertical)
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
    if isHorizontalLine {
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
    if isHorizontalLine {
      for x in 0..<width {
        body(
          Cell(
            x: x, y: 0,
            incoming: Arm(direction: .west, side: .top),
            outgoing: Arm(direction: .east, side: .top),
            start: Double(x), length: 1, isCorner: false,
            incomingIsCap: x == 0, outgoingIsCap: x == width - 1))
      }
      return
    }
    for y in 0..<height {
      body(
        Cell(
          x: 0, y: y,
          incoming: Arm(direction: .north, side: .left),
          outgoing: Arm(direction: .south, side: .left),
          start: verticalCellLength * Double(y), length: verticalCellLength, isCorner: false,
          incomingIsCap: y == 0, outgoingIsCap: y == height - 1))
    }
  }

  /// The track position of the top-leading corner's vertex: the middle of the
  /// corner cell, where its two arms meet. SwiftUI starts a `Rectangle` path
  /// there.
  package var leadingCornerVertex: Double {
    isRing ? 0.5 : 0
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
  /// `sides`, the dash and the trim are all tests on position along the track.
  /// An arm is drawn when its edge is selected and the mask is on where the arm
  /// sits.
  ///
  /// - Parameter samplesEachArm: Samples the mask at each arm's midpoint, which
  ///   gives half-cell resolution. A pen without half-line glyphs passes `false`
  ///   and the mask is sampled once, at the middle of the cell.
  package func resolve(
    _ cell: Cell,
    sides: Edge.Set,
    mask: StrokeMask = .init(),
    samplesEachArm: Bool
  ) -> ResolvedCell {
    let incomingSelected = includes(cell.incoming.side, in: sides)
    let outgoingSelected = includes(cell.outgoing.side, in: sides)
    let incomingSample = samplesEachArm ? cell.incomingMidpoint : cell.midpoint
    let outgoingSample = samplesEachArm ? cell.outgoingMidpoint : cell.midpoint
    let solid = mask.isSolid
    let trackLength = length
    let incomingOn =
      incomingSelected && (solid || mask.isOn(at: incomingSample, trackLength: trackLength))
    let outgoingOn =
      outgoingSelected && (solid || mask.isOn(at: outgoingSample, trackLength: trackLength))

    var resolved = ResolvedCell()
    resolved[cell.incoming.direction] = incomingOn
    resolved[cell.outgoing.direction] = outgoingOn
    if cell.incomingIsCap, incomingOn {
      resolved.markSoft(cell.incoming.direction)
    }
    if cell.outgoingIsCap, outgoingOn {
      resolved.markSoft(cell.outgoing.direction)
    }

    // Where `sides` leaves out one edge of a corner, the remaining edge ends in
    // that cell. It is drawn to the cell's far edge, so a lone top border
    // reaches both ends of the frame.
    if cell.isCorner {
      if !incomingSelected, outgoingOn {
        resolved[cell.outgoing.direction.opposite] = true
        resolved.markSoft(cell.outgoing.direction.opposite)
      }
      if !outgoingSelected, incomingOn {
        resolved[cell.incoming.direction.opposite] = true
        resolved.markSoft(cell.incoming.direction.opposite)
      }
    }
    return resolved
  }

  /// A line has one row or one column, so its two long edges are the same
  /// cells. Either edge selects it.
  private func includes(_ side: BorderSide, in sides: Edge.Set) -> Bool {
    if !isRing {
      return isHorizontalLine
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

extension RectangleStrokeTrack {
  /// The edge whose paint a cell takes.
  ///
  /// A corner takes the paint of its horizontal edge when that edge is drawn,
  /// so a border with a highlighted top edge has highlighted top corners.
  package func paintSide(for cell: Cell, sides: Edge.Set) -> BorderSide {
    guard isRing else {
      return isHorizontalLine ? .top : .left
    }
    if cell.y == 0, sides.contains(.top) {
      return .top
    }
    if cell.y == height - 1, sides.contains(.bottom) {
      return .bottom
    }
    return cell.x == 0 ? .left : .right
  }

  /// Calls `body` for each cell the stroke draws, with its glyph.
  ///
  /// This is the one walk behind a border, a rectangle stroke and a rule. A
  /// cell the mask turns off is skipped, so whatever it held is left alone.
  ///
  /// - Parameter rows: The rows, relative to the rectangle, that need painting.
  ///   `nil` paints every row.
  package func forEachGlyph(
    pen: StrokePen,
    sides: Edge.Set = .all,
    mask: StrokeMask = .init(),
    rows: ((Int) -> Bool)? = nil,
    _ body: (Cell, Character) -> Void
  ) {
    forEachInk(pen: pen, sides: sides, mask: mask, rows: rows) { ink in
      body(ink.cell, ink.glyph)
    }
  }

  /// What a stroke draws in one cell: its glyph, and for a line pen the arms
  /// behind it, so that strokes sharing a cell can merge.
  package struct Ink: Equatable, Sendable {
    package var cell: Cell
    /// The glyph the stroke draws when it has the cell to itself.
    package var glyph: Character
    /// The arms the track and the mask call for. `nil` for an edge pen, which
    /// does not merge.
    package var hardArms: LineArms?
    /// The caps: arms that draw an end cell to its edge. A cap gives way to a
    /// line that crosses it.
    package var softArms = LineArms()
    package var roundsCorner: Bool
    /// The weight every arm takes when Unicode has no glyph for a merged mix.
    package var fallbackWeight: LineWeight
    /// How the pen turns merged arms back into a glyph.
    package var alphabet = LineAlphabet.boxDrawing
  }

  /// Calls `body` for each cell the stroke draws. See
  /// ``forEachGlyph(pen:sides:mask:rows:_:)``.
  package func forEachInk(
    pen: StrokePen,
    sides: Edge.Set = .all,
    mask: StrokeMask = .init(),
    rows: ((Int) -> Bool)? = nil,
    _ body: (Ink) -> Void
  ) {
    let samplesEachArm = pen.samplesEachArm
    forEachCell { cell in
      if let rows, !rows(cell.y) {
        return
      }
      let resolved = resolve(
        cell,
        sides: sides,
        mask: mask,
        samplesEachArm: samplesEachArm
      )
      if let glyph = pen.glyph(for: cell, resolved: resolved) {
        let line = pen.arms(for: cell, resolved: resolved)
        body(
          Ink(
            cell: cell, glyph: glyph, hardArms: line?.hard,
            softArms: line?.soft ?? LineArms(),
            roundsCorner: line?.roundsCorner ?? false,
            fallbackWeight: line?.fallbackWeight ?? .none,
            alphabet: line?.alphabet ?? .boxDrawing))
      }
    }
  }
}

/// How a line pen turns arms into a glyph.
package enum LineAlphabet: Equatable, Sendable {
  /// Unicode box drawing, which has a glyph for most sets of arms and weights.
  case boxDrawing
  /// Three glyphs, as the ASCII palette has: `-`, `|`, and `+` wherever both
  /// axes draw. It has no weights, no half-lines and no rounded corners.
  case plain(horizontal: Character, vertical: Character, junction: Character)

  /// The glyph for a set of arms, or `nil` when there is none.
  ///
  /// - Parameter fallbackWeight: The weight every arm takes when Unicode has no
  ///   glyph for the mix.
  package func glyph(
    for arms: LineArms, roundedCorner: Bool, fallbackWeight: LineWeight
  ) -> Character? {
    switch self {
    case .boxDrawing:
      return arms.glyph(roundedCorner: roundedCorner)
        ?? arms.reweighted(to: fallbackWeight).glyph(roundedCorner: roundedCorner)
    case .plain(let horizontal, let vertical, let junction):
      let drawsHorizontal = arms.east != .none || arms.west != .none
      let drawsVertical = arms.north != .none || arms.south != .none
      switch (drawsHorizontal, drawsVertical) {
      case (true, true): return junction
      case (true, false): return horizontal
      case (false, true): return vertical
      case (false, false): return nil
      }
    }
  }
}

/// How a stroke turns the arms of a track cell into a glyph.
///
/// A line pen picks its glyph from the arms, so a corner, a half-line and a
/// junction are one lookup. A plain line pen does the same with three glyphs,
/// as the ASCII palette has. An edge pen draws ink against a side of the cell,
/// as the half-block palettes do, so it picks its glyph from the side or
/// corner the cell is on. Line pens merge where they share a cell. An edge pen
/// does not.
package enum StrokePen: Equatable, Sendable {
  case line(horizontal: LineWeight, vertical: LineWeight, roundsCorners: Bool)
  case plainLine(horizontal: Character, vertical: Character, junction: Character)
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
    // One glyph for each axis and one for every corner, as `-`, `|` and `+`.
    if let horizontal = borderSet.top.first, let vertical = borderSet.left.first,
      let junction = borderSet.topLeading.first,
      !horizontal.isWhitespace, !vertical.isWhitespace,
      borderSet.bottom.first == horizontal, borderSet.right.first == vertical,
      borderSet.topTrailing.first == junction, borderSet.bottomLeading.first == junction,
      borderSet.bottomTrailing.first == junction
    {
      self = .plainLine(horizontal: horizontal, vertical: vertical, junction: junction)
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
    case .plainLine, .edge:
      false
    }
  }

  /// What a line pen draws in a cell, for merging. `nil` for an edge pen.
  package struct LineInk: Equatable, Sendable {
    /// The arms the track and the mask call for.
    package var hard = LineArms()
    /// The caps.
    package var soft = LineArms()
    package var roundsCorner = false
    package var fallbackWeight = LineWeight.light
    package var alphabet = LineAlphabet.boxDrawing
  }

  package func arms(
    for cell: RectangleStrokeTrack.Cell,
    resolved: RectangleStrokeTrack.ResolvedCell
  ) -> LineInk? {
    var ink = LineInk()
    let horizontal: LineWeight
    let vertical: LineWeight
    switch self {
    case .line(let horizontalWeight, let verticalWeight, let roundsCorners):
      horizontal = horizontalWeight
      vertical = verticalWeight
      ink.roundsCorner = roundsCorners && cell.isCorner
      ink.fallbackWeight = horizontalWeight
    case .plainLine(let horizontalGlyph, let verticalGlyph, let junction):
      // A plain alphabet has no weights. Light stands for "drawn".
      horizontal = .light
      vertical = .light
      ink.alphabet = .plain(
        horizontal: horizontalGlyph, vertical: verticalGlyph, junction: junction)
    case .edge:
      return nil
    }
    for direction in LineDirection.allCases where resolved[direction] {
      let weight = direction.isHorizontal ? horizontal : vertical
      if resolved.isSoft(direction) {
        ink.soft[direction] = weight
      } else {
        ink.hard[direction] = weight
      }
    }
    return ink
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
    case .plainLine(let horizontal, let vertical, let junction):
      return LineAlphabet.plain(horizontal: horizontal, vertical: vertical, junction: junction)
        .glyph(
          for: LineArms(
            north: resolved.north ? .light : .none, east: resolved.east ? .light : .none,
            south: resolved.south ? .light : .none, west: resolved.west ? .light : .none),
          roundedCorner: false, fallbackWeight: .light)
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
