import SwiftTUICore

#if canImport(SwiftTUIVendorPNG)
  import SwiftTUIVendorPNG
#endif

#if canImport(SwiftTUIVendorJPEG)
  import SwiftTUIVendorJPEG
#endif

struct RGBAImagePixel: Equatable, Hashable, Sendable {
  // Channels are 0-255, so pack into four bytes (4 bytes/pixel) instead of four
  // `Int`s (32 bytes/pixel on 64-bit) — an 8x shrink in every retained pixel
  // buffer (repository decode cache, blend variants). The `Int` accessors keep
  // every call site (LUT indexing, luminance sums, `UInt8(...)` casts) unchanged.
  private var storedRed: UInt8
  private var storedGreen: UInt8
  private var storedBlue: UInt8
  private var storedAlpha: UInt8

  var red: Int { Int(storedRed) }
  var green: Int { Int(storedGreen) }
  var blue: Int { Int(storedBlue) }
  var alpha: Int { Int(storedAlpha) }

  var color: Color {
    Color(
      red: Double(red) / 255.0, green: Double(green) / 255.0, blue: Double(blue) / 255.0,
      alpha: Double(alpha) / 255.0)
  }

  init(
    red: Int,
    green: Int,
    blue: Int,
    alpha: Int
  ) {
    storedRed = UInt8(min(255, max(0, red)))
    storedGreen = UInt8(min(255, max(0, green)))
    storedBlue = UInt8(min(255, max(0, blue)))
    storedAlpha = UInt8(min(255, max(0, alpha)))
  }

  #if canImport(SwiftTUIVendorPNG)
    init(
      _ pixel: PNG.RGBA<UInt8>
    ) {
      self.init(
        red: Int(pixel.r),
        green: Int(pixel.g),
        blue: Int(pixel.b),
        alpha: Int(pixel.a)
      )
    }
  #endif

  #if canImport(SwiftTUIVendorJPEG)
    init(
      _ pixel: JPEG.RGBA<UInt8>
    ) {
      self.init(
        red: Int(pixel.r),
        green: Int(pixel.g),
        blue: Int(pixel.b),
        alpha: Int(pixel.a)
      )
    }
  #endif
}

/// Compressed-image container format detected from magic bytes by
/// ``ImageAssetRepository``. Surfaces on ``DecodedImage`` so the
/// terminal renderer can pick the right Kitty graphics format key
/// (`f=100` for PNG, `f=32` raw RGBA for everything else) and the
/// WASI/web transport can pick the right MIME type.
enum ImageEncodedFormat: Sendable, Equatable {
  case png
  case jpeg
}

struct DecodedImage: Sendable {
  var encodedBytes: [UInt8]
  /// The source container format the bytes in ``encodedBytes`` came in as.
  /// Despite the field's historical name, ``encodedBytes`` carries any
  /// supported format - this enum disambiguates without a second
  /// magic-byte sniff downstream.
  var encodedFormat: ImageEncodedFormat
  var pixelSize: PixelSize
  /// Row-major RGBA pixels for the image. The kitty renderer ships
  /// these as `f=32` for non-PNG sources.
  var pixels: [RGBAImagePixel]
}
