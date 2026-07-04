import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime

/// Correctness gate for the F20 fast blend pipeline (`ImageBlendFastPixels`).
///
/// The fast path composites in linear sRGB space with a decode LUT, skipping the
/// XYZ matrix round-trips the reference `Color.composited` performs. It is
/// therefore *more* numerically correct than the reference (no matrix float
/// error), so it matches exactly on primaries and within one 8-bit step on
/// midtones — never more. These tests pin both bounds; if either regresses the
/// fast path has diverged from the semantics the reference (and the shipped
/// blended-image fixtures) rely on.
@Suite
struct ImageBlendFastPixelsTests {
  /// Reference pixel: the exact `Color`-based route the fast path replaces.
  private func referencePixel(
    source: RGBAImagePixel,
    backdrop: Color,
    mode: BlendMode
  ) -> RGBAImagePixel {
    let composited = source.color.composited(over: backdrop, mode: mode)
    let converted = composited.converted(to: .sRGB, gamutMapping: .clip)
    func byte(_ component: Double) -> Int {
      Int((max(0.0, min(1.0, component)) * 255.0).rounded())
    }
    return RGBAImagePixel(
      red: byte(converted.red),
      green: byte(converted.green),
      blue: byte(converted.blue),
      alpha: byte(converted.alpha)
    )
  }

  private func fastPixel(
    source: RGBAImagePixel,
    backdrop: Color,
    mode: BlendMode
  ) throws -> RGBAImagePixel {
    let backdropLinear = try #require(ImageBlendFastPixels.linear(from: backdrop))
    let sourceLinear = ImageBlendFastPixels.linear(fromPixel: source)
    return ImageBlendFastPixels.pixel(
      from: ImageBlendFastPixels.composited(sourceLinear, over: backdropLinear, mode: mode)
    )
  }

  private let allModes: [BlendMode] = [
    .normal, .multiply, .screen, .overlay, .darken, .lighten,
  ]

  @Test("Fast blend matches the Color reference within one 8-bit step across a dense sweep")
  func fastBlendMatchesReferenceWithinOneStep() throws {
    // A dense grid straddling the sRGB transfer-function knee (~0.04) and the
    // rounding boundaries where the reference's matrix float error can nudge a
    // byte by one.
    let byteSamples = [0, 1, 5, 10, 32, 63, 64, 96, 127, 128, 160, 191, 200, 245, 254, 255]
    let alphaSamples = [0, 64, 128, 200, 255]
    let backdropComponents = [0.0, 0.02, 0.25, 0.5, 0.75, 0.98, 1.0]

    var maxDelta = 0
    for mode in allModes {
      for red in byteSamples {
        for sourceAlpha in alphaSamples {
          for backdropValue in backdropComponents {
            let source = RGBAImagePixel(
              red: red,
              green: (red * 7) % 256,
              blue: (red * 13) % 256,
              alpha: sourceAlpha
            )
            let backdrop = Color(
              red: backdropValue,
              green: min(1.0, backdropValue + 0.1),
              blue: max(0.0, backdropValue - 0.1),
              alpha: 0.8
            )
            let reference = referencePixel(source: source, backdrop: backdrop, mode: mode)
            let fast = try fastPixel(source: source, backdrop: backdrop, mode: mode)
            maxDelta = max(
              maxDelta,
              max(
                abs(fast.red - reference.red),
                max(
                  abs(fast.green - reference.green),
                  max(abs(fast.blue - reference.blue), abs(fast.alpha - reference.alpha))
                )
              )
            )
          }
        }
      }
    }
    #expect(maxDelta <= 1)
  }

  @Test("Fast blend is byte-exact for primary/extreme colors")
  func fastBlendIsExactForPrimaries() throws {
    let extremes = [0, 255]
    for mode in allModes {
      for red in extremes {
        for green in extremes {
          for blue in extremes {
            for alpha in extremes {
              for backdropChannel in extremes {
                let source = RGBAImagePixel(red: red, green: green, blue: blue, alpha: alpha)
                let backdrop = Color(
                  red: Double(backdropChannel),
                  green: Double(1 - backdropChannel / 255),
                  blue: Double(backdropChannel),
                  alpha: 1.0
                )
                let reference = referencePixel(source: source, backdrop: backdrop, mode: mode)
                let fast = try fastPixel(source: source, backdrop: backdrop, mode: mode)
                #expect(fast == reference)
              }
            }
          }
        }
      }
    }
  }

  @Test("Non-sRGB backdrop colors disqualify the fast path")
  func nonSRGBBackdropDisqualifiesFastPath() {
    let displayP3 = Color(red: 0.5, green: 0.4, blue: 0.3, profile: .displayP3)
    #expect(ImageBlendFastPixels.linear(from: displayP3) == nil)

    let sRGB = Color(red: 0.5, green: 0.4, blue: 0.3)
    #expect(ImageBlendFastPixels.linear(from: sRGB) != nil)
  }
}
