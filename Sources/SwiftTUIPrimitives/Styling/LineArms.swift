/// The weight of one arm of a line glyph.
package enum LineWeight: UInt8, Equatable, Hashable, Sendable {
  case none = 0
  case light = 1
  case heavy = 2
  case double = 3
}

/// The direction of one arm of a line glyph, from the center of its cell.
package enum LineDirection: Int, CaseIterable, Equatable, Hashable, Sendable {
  case north = 0
  case east = 1
  case south = 2
  case west = 3

  package var opposite: LineDirection {
    switch self {
    case .north: .south
    case .east: .west
    case .south: .north
    case .west: .east
    }
  }

  package var isHorizontal: Bool {
    self == .east || self == .west
  }
}

/// The four arms of a line glyph: one weight toward each neighboring cell.
///
/// A line glyph is fully described by which neighbors it connects to and how
/// heavily. `┌` is a light south arm and a light east arm. `╴` is a light west
/// arm alone, which is what the end of a dash or a trim looks like. `├` is
/// three arms, which is what two strokes sharing a cell look like.
///
/// Choosing the glyph from the arms keeps every line stroke on one lookup: a
/// border, a rule, a dash end and a junction differ only in their arms.
package struct LineArms: Equatable, Hashable, Sendable {
  package var north: LineWeight
  package var east: LineWeight
  package var south: LineWeight
  package var west: LineWeight

  package init(
    north: LineWeight = .none,
    east: LineWeight = .none,
    south: LineWeight = .none,
    west: LineWeight = .none
  ) {
    self.north = north
    self.east = east
    self.south = south
    self.west = west
  }

  package static let none = LineArms()

  package var isEmpty: Bool {
    self == .none
  }

  package subscript(direction: LineDirection) -> LineWeight {
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

  /// The arms that are present, each set to `weight`.
  package func reweighted(to weight: LineWeight) -> LineArms {
    LineArms(
      north: north == .none ? .none : weight,
      east: east == .none ? .none : weight,
      south: south == .none ? .none : weight,
      west: west == .none ? .none : weight
    )
  }

  /// The Unicode box-drawing glyph for these arms, or `nil` when Unicode has
  /// none.
  ///
  /// Light and heavy arms mix freely. Light and double arms mix only when each
  /// axis has one weight. Heavy and double arms never mix, and double has no
  /// half-line. No arms is a space.
  ///
  /// - Parameter roundedCorner: Draws the arc glyph where one exists. Unicode
  ///   has arcs only for a corner of two light arms, so every other shape keeps
  ///   its square glyph.
  package func glyph(roundedCorner: Bool = false) -> Character? {
    if roundedCorner, let arc = arcGlyph {
      return arc
    }
    let glyph = Self.glyphTable[tableIndex]
    return glyph == Self.missingGlyph ? nil : glyph
  }

  /// The arms a box-drawing glyph draws, or `nil` for any other character.
  ///
  /// An arc reads as the square corner it rounds.
  package init?(glyph: Character) {
    switch glyph {
    case "╭": self.init(east: .light, south: .light)
    case "╮": self.init(south: .light, west: .light)
    case "╯": self.init(north: .light, west: .light)
    case "╰": self.init(north: .light, east: .light)
    default:
      // Every line glyph is one scalar in the box-drawing block, so any other
      // character is rejected without scanning the table.
      let scalars = glyph.unicodeScalars
      guard scalars.count == 1, let scalar = scalars.first,
        (0x2500...0x257F).contains(scalar.value),
        let index = Self.glyphTable.firstIndex(of: glyph)
      else {
        return nil
      }
      self.init(tableIndex: index)
    }
  }

  private init(tableIndex: Int) {
    self.init(
      north: LineWeight(rawValue: UInt8(tableIndex & 0b11)) ?? .none,
      east: LineWeight(rawValue: UInt8((tableIndex >> 2) & 0b11)) ?? .none,
      south: LineWeight(rawValue: UInt8((tableIndex >> 4) & 0b11)) ?? .none,
      west: LineWeight(rawValue: UInt8((tableIndex >> 6) & 0b11)) ?? .none
    )
  }

  private var tableIndex: Int {
    Int(north.rawValue)
      | Int(east.rawValue) << 2
      | Int(south.rawValue) << 4
      | Int(west.rawValue) << 6
  }

  private var arcGlyph: Character? {
    switch (north, east, south, west) {
    case (.none, .light, .light, .none): "╭"
    case (.none, .none, .light, .light): "╮"
    case (.light, .none, .none, .light): "╯"
    case (.light, .light, .none, .none): "╰"
    default: nil
    }
  }

  private static let missingGlyph: Character = "."

  /// Indexed by two bits per arm: north, then east, south and west.
  ///
  /// Generated from the Unicode names of U+2500 to U+257F, leaving out the
  /// dashed, diagonal and arc glyphs. `LineArmsTests` rebuilds it from
  /// `Unicode.Scalar.Properties.name` and compares every entry.
  private static let glyphTable: [Character] = Array(
    " ╵╹.╶└┖╙╺┕┗..╘.╚╷│╿.┌├┞.┍┝┡.╒╞..╻╽┃.┎┟┠.┏┢┣........║╓..╟....╔..╠"
      + "╴┘┚╜─┴┸╨╼┶┺.....┐┤┦.┬┼╀.┮┾╄.....┒┧┨.┰╁╂.┲╆╊.....╖..╢╥..╫........"
      + "╸┙┛.╾┵┹.━┷┻.....┑┥┩.┭┽╃.┯┿╇.....┓┪┫.┱╅╉.┳╈╋....................."
      + ".╛.╝........═╧.╩╕╡..........╤╪..................╗..╣........╦..╬"
  )
}
