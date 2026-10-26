import SwiftTUICore

// ANSI color-code resolution for the terminal cell text renderer.
//
// SGR sequence assembly (`styleSequence`, `appendColorCodes`, …) stays in
// `TerminalCellTextRenderer.swift`; this file owns the lower layer that turns a
// `Color` into a concrete palette code: nearest-ANSI-16 matching with a small
// delta-E cache, and the ANSI-256 6×6×6 cube mapping.
//
// `backgroundCode`, `closestANSI16ForegroundCode`, `ansi256Code`,
// `directColorBytes`, and `colorByte` are file-internal rather than `private`
// so the SGR assembler can reach them; the cache and palette stay `private` to
// this file.
extension TerminalCellTextRenderer {
  func backgroundCode(
    forForegroundCode code: Int
  ) -> Int {
    code + 10
  }

  /// The 0...255 SGR parameter for one color component.
  ///
  /// `Color` deliberately keeps out-of-gamut components — wide-gamut profiles
  /// and bicubic gradient interpolation both produce them — but SGR has no room
  /// for that range, and terminals truncate an out-of-range parameter into an
  /// unrelated color. Gamut clamping belongs at this boundary.
  func colorByte(
    _ component: Double
  ) -> Int {
    Int(min(1, max(0, component)) * 255)
  }

  /// The `38;2`/`48;2`/`58;2` components of `color`. Direct-colour
  /// parameters are sRGB display values, so a colour in another profile
  /// (Display P3, linear sRGB from compositing) converts to sRGB first, with
  /// the same per-channel clip the 256-colour cube applies (STUI-1320). An
  /// sRGB colour is not converted: its components reach ``colorByte(_:)``
  /// unchanged.
  func directColorBytes(
    for color: Color
  ) -> (red: Int, green: Int, blue: Int) {
    let srgb = color.converted(to: .sRGB, gamutMapping: .clip)
    return (colorByte(srgb.red), colorByte(srgb.green), colorByte(srgb.blue))
  }

  /// Cache for recent ANSI16 color lookups. The deltaE computation is
  /// expensive; apps typically use a small set of colors so a tiny cache
  /// eliminates almost all redundant work across a frame.
  private static let ansi16Cache = ANSI16Cache()

  private final class ANSI16Cache: Sendable {
    private struct Storage {
      // Fixed-size ring of the last 8 mappings.
      var entries: [(color: Color, code: Int)] = []
      var cursor: Int = 0
    }

    private let storage = OSAllocatedUnfairLock<Storage>(uncheckedState: .init())

    func lookup(for color: Color) -> Int? {
      storage.withLock { storage in
        storage.entries.first(where: { $0.color == color })?.code
      }
    }

    func store(color: Color, code: Int) {
      storage.withLock { storage in
        if storage.entries.count < 8 {
          storage.entries.append((color, code))
        } else {
          storage.entries[storage.cursor] = (color, code)
          storage.cursor = (storage.cursor + 1) % 8
        }
      }
    }
  }

  // Canonical ANSI palette values. The terminal can theme these slots, but
  // quantization must account for both normal and bright intensities.
  static let ansi16Palette: [(Int, Color)] = [
    (30, .init(hexRGB: 0x000000)), (31, .init(hexRGB: 0x800000)),
    (32, .init(hexRGB: 0x008000)), (33, .init(hexRGB: 0x808000)),
    (34, .init(hexRGB: 0x000080)), (35, .init(hexRGB: 0x800080)),
    (36, .init(hexRGB: 0x008080)), (37, .init(hexRGB: 0xC0C0C0)),
    (90, .init(hexRGB: 0x808080)), (91, .init(hexRGB: 0xFF0000)),
    (92, .init(hexRGB: 0x00FF00)), (93, .init(hexRGB: 0xFFFF00)),
    (94, .init(hexRGB: 0x0000FF)), (95, .init(hexRGB: 0xFF00FF)),
    (96, .init(hexRGB: 0x00FFFF)), (97, .init(hexRGB: 0xFFFFFF)),
  ]

  func closestANSI16ForegroundCode(
    for color: Color
  ) -> Int {
    if let cached = Self.ansi16Cache.lookup(for: color) {
      return cached
    }

    let code =
      Self.ansi16Palette.min {
        color.deltaE(to: $0.1) < color.deltaE(to: $1.1)
      }?.0 ?? 97

    Self.ansi16Cache.store(color: color, code: code)
    return code
  }

  func ansi256Code(
    for color: Color
  ) -> Int {
    let color = color.converted(to: .sRGB, gamutMapping: .clip)
    let levels = [0.0, 95.0, 135.0, 175.0, 215.0, 255.0]
    let channels = [color.red * 255, color.green * 255, color.blue * 255]
    let indices = channels.map { value in
      levels.indices.min { abs(levels[$0] - value) < abs(levels[$1] - value) }!
    }
    let cube = 16 + 36 * indices[0] + 6 * indices[1] + indices[2]
    let cubeError = zip(channels, indices).reduce(0.0) { total, pair in
      let delta = pair.0 - levels[pair.1]
      return total + delta * delta
    }
    let mean = channels.reduce(0, +) / 3
    let gray = min(23, max(0, Int(((mean - 8) / 10).rounded())))
    let grayLevel = Double(8 + gray * 10)
    let grayError = channels.reduce(0.0) { $0 + ($1 - grayLevel) * ($1 - grayLevel) }
    // Exact cube colors keep their own slots; alpha does not select a palette.
    return grayError < cubeError ? 232 + gray : cube
  }
}
