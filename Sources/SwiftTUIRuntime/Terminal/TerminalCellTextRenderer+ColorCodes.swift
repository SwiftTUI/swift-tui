import SwiftTUICore

// ANSI color-code resolution for the terminal cell text renderer.
//
// SGR sequence assembly (`styleSequence`, `appendColorCodes`, …) stays in
// `TerminalCellTextRenderer.swift`; this file owns the lower layer that turns a
// `Color` into a concrete palette code: nearest-ANSI-16 matching with a small
// delta-E cache, and the ANSI-256 6×6×6 cube mapping.
//
// `backgroundCode`, `closestANSI16ForegroundCode`, `ansi256Code`, and
// `colorByte` are file-internal rather than `private` so the SGR assembler can
// reach them; the cache and palette stay `private` to this file.
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

  private static let ansi16Palette: [(Int, Color)] = [
    (30, .init(hexRGB: 0x000000)),
    (91, .init(hexRGB: 0xFF5555)),
    (92, .init(hexRGB: 0x50C878)),
    (93, .init(hexRGB: 0xFFD700)),
    (94, .init(hexRGB: 0x6495ED)),
    (95, .init(hexRGB: 0xDA70D6)),
    (96, .init(hexRGB: 0x40E0D0)),
    (97, .init(hexRGB: 0xF5F5F5)),
    (90, .init(hexRGB: 0x808080)),
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
    switch color {
    case .black:
      return 16
    case .red:
      return 203
    case .green:
      return 114
    case .yellow:
      return 179
    case .blue:
      return 111
    case .magenta:
      return 176
    case .cyan:
      return 117
    case .white:
      return 255
    case .gray:
      return 145
    default:
      break
    }

    let red = cubeIndex(color.red)
    let green = cubeIndex(color.green)
    let blue = cubeIndex(color.blue)
    return 16 + (36 * red) + (6 * green) + blue
  }

  /// The 0...5 axis index for one component of the ANSI-256 color cube.
  ///
  /// Clamped for the same reason as ``colorByte(_:)``: an out-of-gamut
  /// component would index outside the cube and select an unrelated code.
  private func cubeIndex(
    _ component: Double
  ) -> Int {
    Int((min(1, max(0, component)) * 5).rounded())
  }
}
