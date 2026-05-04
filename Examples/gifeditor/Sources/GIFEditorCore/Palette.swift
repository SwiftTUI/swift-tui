import Foundation

/// An sRGB color stored as 8-bit-per-channel RGBA.
///
/// `GIFEditorCore` deliberately avoids depending on the framework's much
/// richer `SwiftTUICore.Color` so the model layer stays platform-neutral. The UI
/// layer converts between this and `SwiftTUICore.Color` at the boundary.
public struct EditorColor: Hashable, Sendable, Codable {
  public var red: UInt8
  public var green: UInt8
  public var blue: UInt8
  public var alpha: UInt8

  public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  /// Constructs from a 0xRRGGBB literal, full alpha.
  public init(rgbHex: UInt32) {
    self.init(
      red: UInt8((rgbHex >> 16) & 0xFF),
      green: UInt8((rgbHex >> 8) & 0xFF),
      blue: UInt8(rgbHex & 0xFF),
      alpha: 255
    )
  }

  public static let black = EditorColor(rgbHex: 0x000000)
  public static let white = EditorColor(rgbHex: 0xFFFFFF)
  public static let transparent = EditorColor(red: 0, green: 0, blue: 0, alpha: 0)

  /// Squared RGB distance — sufficient for nearest-color quantization.
  public func distanceSquared(to other: EditorColor) -> Int {
    let dr = Int(red) - Int(other.red)
    let dg = Int(green) - Int(other.green)
    let db = Int(blue) - Int(other.blue)
    return dr * dr + dg * dg + db * db
  }
}

/// Index into a palette. GIF restricts palettes to 256 entries.
public typealias PaletteIndex = UInt8

/// A 256-color palette shared across the document.
///
/// Slot 0 is reserved as the document's "transparent" sentinel for
/// export — pixels stored as `nil` map to slot 0 and slot 0 is marked as
/// the GIF's transparent index. Authors can still pick slot 0 as a
/// drawing color; we just guarantee at least one slot is available for
/// the transparency role.
public struct ColorPalette: Hashable, Sendable, Codable {
  /// Always exactly `Self.capacity` entries; unused slots are duplicates
  /// of the last meaningful color so nearest-color matching never returns
  /// undefined indices.
  public private(set) var colors: [EditorColor]
  public static let capacity: Int = 256

  /// Reserved slot used to represent "transparent" when flattening a
  /// document for GIF export. Authors editing this slot will see that
  /// the GIF's transparent pixels recolor accordingly.
  public static let transparentSlot: PaletteIndex = 0

  public init(colors: [EditorColor]) {
    var bounded = Array(colors.prefix(Self.capacity))
    if bounded.isEmpty {
      bounded = [.transparent]
    }
    while bounded.count < Self.capacity {
      bounded.append(bounded.last ?? .black)
    }
    self.colors = bounded
  }

  public subscript(index: PaletteIndex) -> EditorColor {
    get { colors[Int(index)] }
    set { colors[Int(index)] = newValue }
  }

  /// The number of "meaningful" colors before we started padding. The
  /// authoring UI uses this to decide how many palette swatches to
  /// render; the encoder pads up to a power of two.
  public var distinctColorCount: Int {
    var seen = Set<EditorColor>()
    for color in colors {
      seen.insert(color)
      if seen.count == Self.capacity { break }
    }
    return seen.count
  }

  /// Nearest color in the palette by squared RGB distance, ignoring
  /// transparent slots (alpha == 0).
  public func nearestIndex(to color: EditorColor) -> PaletteIndex {
    var best: (index: PaletteIndex, distance: Int) = (0, .max)
    for (i, candidate) in colors.enumerated() {
      if candidate.alpha == 0 { continue }
      let d = color.distanceSquared(to: candidate)
      if d < best.distance {
        best = (PaletteIndex(i), d)
        if d == 0 { break }
      }
    }
    return best.index
  }

  /// The default 32-color authoring palette. Slot 0 is transparent; the
  /// remaining 31 colors are a usable mix of greys, primaries, and
  /// pastels suitable for general doodling.
  public static let `default`: ColorPalette = {
    let entries: [EditorColor] = [
      .transparent,
      .black,
      .white,
      EditorColor(rgbHex: 0x808080),
      EditorColor(rgbHex: 0x404040),
      EditorColor(rgbHex: 0xC0C0C0),
      EditorColor(rgbHex: 0xE05757),  // red
      EditorColor(rgbHex: 0xEB7A3C),  // orange
      EditorColor(rgbHex: 0xEBB33C),  // yellow
      EditorColor(rgbHex: 0x61C67B),  // green
      EditorColor(rgbHex: 0x2E8B57),  // dark green
      EditorColor(rgbHex: 0x5BA3FF),  // blue
      EditorColor(rgbHex: 0x1E5AAE),  // dark blue
      EditorColor(rgbHex: 0x56B6C2),  // cyan
      EditorColor(rgbHex: 0xB46EFF),  // magenta
      EditorColor(rgbHex: 0xFF8FB4),  // pink
      EditorColor(rgbHex: 0x8B5A2B),  // brown
      EditorColor(rgbHex: 0xC9A878),  // tan
      EditorColor(rgbHex: 0xF5DEB3),  // wheat
      EditorColor(rgbHex: 0xFFD7E4),  // light pink
      EditorColor(rgbHex: 0xFFEFAA),  // light yellow
      EditorColor(rgbHex: 0xCEEBC1),  // mint
      EditorColor(rgbHex: 0xC4DEFF),  // light blue
      EditorColor(rgbHex: 0xE3D3FF),  // lavender
      EditorColor(rgbHex: 0x7A1F1F),  // wine
      EditorColor(rgbHex: 0x40220F),  // espresso
      EditorColor(rgbHex: 0x143D2A),  // forest
      EditorColor(rgbHex: 0x0D2C66),  // navy
      EditorColor(rgbHex: 0x6E1B8C),  // royal purple
      EditorColor(rgbHex: 0xFF005D),  // hot pink
      EditorColor(rgbHex: 0x00C896),  // teal
      EditorColor(rgbHex: 0xC0FF33),  // lime
    ]
    return ColorPalette(colors: entries)
  }()
}
