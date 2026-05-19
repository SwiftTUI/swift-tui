import SwiftTUICore

#if canImport(PNG)
  import PNG
#endif

#if canImport(JPEG)
  import JPEG
#endif

struct RGBAImagePixel: Equatable, Hashable, Sendable {
  var red: Int
  var green: Int
  var blue: Int
  var alpha: Int

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
    self.red = min(255, max(0, red))
    self.green = min(255, max(0, green))
    self.blue = min(255, max(0, blue))
    self.alpha = min(255, max(0, alpha))
  }

  #if canImport(PNG)
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

  #if canImport(JPEG)
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
