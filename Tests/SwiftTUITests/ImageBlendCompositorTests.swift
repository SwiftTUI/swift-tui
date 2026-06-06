import PNG
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

@Suite
struct ImageBlendCompositorTests {
  @Test("direct image blend precomposes source pixels over destination backdrop")
  func directImageBlendPrecomposesSourcePixelsOverDestinationBackdrop() throws {
    let source = Color(red: 1, green: 0, blue: 0)
    let destination = Color(red: 0, green: 0, blue: 1)
    let pngBytes = try makePNGBytes(
      width: 1,
      height: 1,
      pixels: [rgbaPixel(red: 255, green: 0, blue: 0)]
    )
    let attachment = blendedAttachment(
      pngBytes: pngBytes,
      compositing: imageCompositing(
        blendMode: .multiply,
        destination: destination
      )
    )

    let variant = try #require(
      ImageBlendCompositor().decodedVariant(
        for: attachment,
        fallbackBackground: .black
      )
    )

    #expect(variant.attachment.bounds == attachment.visibleBounds)
    #expect(variant.image.pixelSize == .init(width: 1, height: 1))
    #expect(
      variant.image.pixels
        == [expectedPixel(source.composited(over: destination, mode: .multiply))]
    )
  }

  @Test("transparent source pixels preserve the captured destination backdrop")
  func transparentSourcePixelsPreserveCapturedDestinationBackdrop() throws {
    let source = Color(red: 1, green: 0, blue: 0, alpha: 0)
    let destination = Color(red: 0, green: 0, blue: 1)
    let pngBytes = try makePNGBytes(
      width: 1,
      height: 1,
      pixels: [rgbaPixel(red: 255, green: 0, blue: 0, alpha: 0)]
    )
    let attachment = blendedAttachment(
      pngBytes: pngBytes,
      compositing: imageCompositing(
        blendMode: .multiply,
        destination: destination
      )
    )

    let variant = try #require(
      ImageBlendCompositor().decodedVariant(
        for: attachment,
        fallbackBackground: .black
      )
    )

    #expect(
      variant.image.pixels
        == [expectedPixel(source.composited(over: destination, mode: .multiply))]
    )
  }

  @Test("post-group image blend flattens source backdrop before blending with destination")
  func postGroupImageBlendFlattensSourceBackdropBeforeDestinationBlend() throws {
    let source = Color(red: 1, green: 0, blue: 0, alpha: 0)
    let sourceBackdrop = Color(red: 0, green: 0, blue: 1)
    let destination = Color(red: 1, green: 0, blue: 0)
    let pngBytes = try makePNGBytes(
      width: 1,
      height: 1,
      pixels: [rgbaPixel(red: 255, green: 0, blue: 0, alpha: 0)]
    )
    let attachment = blendedAttachment(
      pngBytes: pngBytes,
      compositing: imageCompositing(
        blendMode: .multiply,
        destination: destination,
        source: sourceBackdrop
      )
    )

    let variant = try #require(
      ImageBlendCompositor().decodedVariant(
        for: attachment,
        fallbackBackground: .black
      )
    )

    let flattenedSource = source.composited(over: sourceBackdrop)
    #expect(
      variant.image.pixels
        == [expectedPixel(flattenedSource.composited(over: destination, mode: .multiply))]
    )
  }
}

private func expectedPixel(
  _ color: Color
) -> RGBAImagePixel {
  let converted = color.converted(to: .sRGB, gamutMapping: .clip)
  return RGBAImagePixel(
    red: byte(from: converted.red),
    green: byte(from: converted.green),
    blue: byte(from: converted.blue),
    alpha: byte(from: converted.alpha)
  )
}

private func byte(
  from component: Double
) -> Int {
  Int((max(0.0, min(1.0, component)) * 255.0).rounded())
}

private func blendedAttachment(
  pngBytes: [UInt8],
  compositing: RasterImageCompositing
) -> RasterImageAttachment {
  RasterImageAttachment(
    identity: testIdentity("Root", "Image"),
    bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
    source: .data(pngBytes),
    resolvedReference: .embeddedImage(pngBytes),
    pixelSize: .init(width: 1, height: 1),
    cellPixelSize: .init(width: 1, height: 1),
    compositing: compositing
  )
}

private func imageCompositing(
  blendMode: BlendMode,
  destination: Color,
  source: Color? = nil
) -> RasterImageCompositing {
  let bounds = CellRect(origin: .zero, size: .init(width: 1, height: 1))
  let destinationBackdrop = RasterImageBackdrop(
    bounds: bounds,
    cells: [.init(backgroundColor: destination)]
  )
  let sourceBackdrop = source.map { color in
    RasterImageBackdrop(
      bounds: bounds,
      cells: [.init(backgroundColor: color)]
    )
  }
  return RasterImageCompositing(
    blendMode: blendMode,
    destinationBackdrop: destinationBackdrop,
    sourceBackdrop: sourceBackdrop,
    cellPixelSize: .init(width: 1, height: 1),
    backdropSignature: source == nil ? 1 : 2
  )
}
