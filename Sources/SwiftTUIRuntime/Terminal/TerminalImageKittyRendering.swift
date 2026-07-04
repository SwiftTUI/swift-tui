import SwiftTUICore

/// Container format for a Kitty graphics payload. Maps directly onto
/// the protocol's `f=` key plus the supplemental `s=`/`v=` pixel-size
/// keys required for raw pixel buffers.
///
/// Kitty's `f=` only knows three values: 100 (PNG), 32 (RGBA), 24 (RGB).
/// JPEG isn't decodable by the terminal, so we serialize its already-decoded
/// pixels as RGBA and ship those instead.
enum KittyPayloadFormat: Sendable, Equatable {
  case png
  case rgba(pixelSize: PixelSize)

  /// Numeric value emitted as `f=` in the kitty control data.
  var formatKey: Int {
    switch self {
    case .png: return 100
    case .rgba: return 32
    }
  }
}

struct KittyPayload: Sendable {
  /// Base64-encoded image payload, pre-split into transmission chunks.
  /// Every chunk holds at most ``kittyPayloadChunkByteLimit`` bytes, and
  /// every chunk except the last holds whole base64 quartets so the
  /// receiver can reassemble the stream by concatenation. Full repaints
  /// retransmit kitty images, so the split is stored with the payload
  /// rather than recomputed from one large string per emission.
  var encodedChunks: [String]
  /// Container format the payload is shipped in.
  var format: KittyPayloadFormat

  /// Approximate wire size of the payload, for cache byte budgeting.
  var approxByteCount: Int {
    encodedChunks.reduce(0) { $0 + $1.utf8.count }
  }
}

func makeKittyPayload(
  for image: DecodedImage,
  rgbaOutputSize: PixelSize? = nil,
  preferRawRGBA: Bool = false
) -> KittyPayload? {
  // Blended variants are already the exact display footprint in decoded pixels,
  // so they ship as raw `f=32` RGBA directly: no PNG framing on our side, no
  // PNG decode on the terminal's, and none of the generic downsample (which
  // keys off terminal cell metrics that can differ from the blend's cell size).
  if preferRawRGBA {
    guard !image.pixels.isEmpty else {
      return nil
    }
    let outputSize = rgbaOutputSize ?? image.pixelSize
    let needsResample =
      outputSize.width != image.pixelSize.width
      || outputSize.height != image.pixelSize.height
    let pixels =
      needsResample
      ? scaledRGBAPixels(from: image, outputSize: outputSize)
      : image.pixels
    return KittyPayload(
      encodedChunks: base64EncodedChunks(SwiftTUI_rgbaBytes(from: pixels)),
      format: .rgba(pixelSize: outputSize)
    )
  }

  guard !image.encodedBytes.isEmpty else {
    return nil
  }

  switch image.encodedFormat {
  case .png:
    // Ship the PNG bytes as `f=100`. Kitty decodes and scales them
    // natively, smaller on the wire than RGBA and without any
    // software-scaling artifacts on our side.
    return KittyPayload(
      encodedChunks: base64EncodedChunks(image.encodedBytes),
      format: .png
    )
  case .jpeg:
    // Kitty has no JPEG decoder. Serialize the already-decoded pixels
    // as raw RGBA and let kitty ingest them via `f=32` with explicit
    // pixel-size keys (`s=`, `v=`). Raw pixels carry no compression, so
    // callers pass `rgbaOutputSize` (see ``kittyRGBATransmitSize``) to
    // cap the buffer at the placement's displayable footprint.
    let outputSize = rgbaOutputSize ?? image.pixelSize
    let needsResample =
      outputSize.width != image.pixelSize.width
      || outputSize.height != image.pixelSize.height
    let pixels =
      needsResample
      ? scaledRGBAPixels(from: image, outputSize: outputSize)
      : image.pixels
    return KittyPayload(
      encodedChunks: base64EncodedChunks(SwiftTUI_rgbaBytes(from: pixels)),
      format: .rgba(pixelSize: outputSize)
    )
  }
}

/// Pixel size at which a non-PNG image is serialized as raw RGBA for
/// kitty transmission. PNG payloads ship their compressed bytes
/// untouched, but `f=32` buffers are uncompressed pixels: shipping more
/// of them than the placement can display only inflates the escape
/// stream. Caps the buffer at the placement's pixel footprint
/// (cells x cell pixel size), scaling to fill so neither axis drops
/// below display resolution, and never upscales.
func kittyRGBATransmitSize(
  imagePixelSize: PixelSize,
  encodedFormat: ImageEncodedFormat,
  placementCellSize: CellSize,
  cellPixelSize: PixelSize?
) -> PixelSize {
  guard encodedFormat != .png else {
    return imagePixelSize
  }
  guard imagePixelSize.width > 0, imagePixelSize.height > 0 else {
    return imagePixelSize
  }
  let cellPixels = cellPixelSize ?? kittyAssumedCellPixelSize
  let targetWidth = max(1, placementCellSize.width * max(1, cellPixels.width))
  let targetHeight = max(1, placementCellSize.height * max(1, cellPixels.height))
  guard imagePixelSize.width > targetWidth || imagePixelSize.height > targetHeight else {
    return imagePixelSize
  }
  let scale = max(
    Double(targetWidth) / Double(imagePixelSize.width),
    Double(targetHeight) / Double(imagePixelSize.height)
  )
  guard scale < 1 else {
    return imagePixelSize
  }
  return PixelSize(
    width: min(
      imagePixelSize.width,
      max(1, Int((Double(imagePixelSize.width) * scale).rounded()))
    ),
    height: min(
      imagePixelSize.height,
      max(1, Int((Double(imagePixelSize.height) * scale).rounded()))
    )
  )
}

/// Mirror of the sixel path's assumed cell size when the terminal did
/// not report pixel metrics.
private let kittyAssumedCellPixelSize = PixelSize(width: 8, height: 16)

struct KittySourceRect: Sendable, Equatable {
  var x: Int
  var y: Int
  var width: Int
  var height: Int
}

struct KittyPlacement: Sendable, Equatable {
  var origin: CellPoint
  var cellColumns: Int
  var cellRows: Int
  var sourceRect: KittySourceRect?
}

func kittyPlacement(
  for attachment: RasterImageAttachment,
  imagePixelSize: PixelSize
) -> KittyPlacement? {
  let logicalBounds = attachment.bounds
  let visibleBounds = attachment.visibleBounds
  guard logicalBounds.size.width > 0, logicalBounds.size.height > 0,
    visibleBounds.size.width > 0, visibleBounds.size.height > 0
  else {
    return nil
  }

  // Cells of the logical placement that are clipped away by an ancestor
  // (e.g. a ScrollView's content rect, or a sibling toolbar reserving
  // space via safeAreaInset). Both top/left AND bottom/right must be
  // honored: cells written before the kitty stream remain in the buffer,
  // so any kitty rows extending into a sibling region (toolbar, footer)
  // would paint over those cells. Limiting cellRows/cellColumns to the
  // visible rect, and cropping the source pixels proportionally, keeps
  // the on-screen scale identical to the unclipped case while preventing
  // overdraw.
  let hiddenLeft = max(0, visibleBounds.origin.x - logicalBounds.origin.x)
  let hiddenTop = max(0, visibleBounds.origin.y - logicalBounds.origin.y)
  let hiddenRight = max(
    0,
    (logicalBounds.origin.x + logicalBounds.size.width)
      - (visibleBounds.origin.x + visibleBounds.size.width)
  )
  let hiddenBottom = max(
    0,
    (logicalBounds.origin.y + logicalBounds.size.height)
      - (visibleBounds.origin.y + visibleBounds.size.height)
  )

  let placement = KittyPlacement(
    origin: .init(
      x: logicalBounds.origin.x + hiddenLeft,
      y: logicalBounds.origin.y + hiddenTop
    ),
    cellColumns: max(1, logicalBounds.size.width - hiddenLeft - hiddenRight),
    cellRows: max(1, logicalBounds.size.height - hiddenTop - hiddenBottom),
    sourceRect: kittySourceRect(
      hiddenLeftCells: hiddenLeft,
      hiddenTopCells: hiddenTop,
      hiddenRightCells: hiddenRight,
      hiddenBottomCells: hiddenBottom,
      logicalCellSize: logicalBounds.size,
      imagePixelSize: imagePixelSize
    )
  )
  return placement.cellColumns > 0 && placement.cellRows > 0 ? placement : nil
}

private func kittySourceRect(
  hiddenLeftCells: Int,
  hiddenTopCells: Int,
  hiddenRightCells: Int,
  hiddenBottomCells: Int,
  logicalCellSize: CellSize,
  imagePixelSize: PixelSize
) -> KittySourceRect? {
  guard
    hiddenLeftCells > 0 || hiddenTopCells > 0
      || hiddenRightCells > 0 || hiddenBottomCells > 0
  else {
    return nil
  }

  let sourceX = proportionalPixelOffset(
    hiddenCells: hiddenLeftCells,
    totalCells: logicalCellSize.width,
    totalPixels: imagePixelSize.width
  )
  let sourceY = proportionalPixelOffset(
    hiddenCells: hiddenTopCells,
    totalCells: logicalCellSize.height,
    totalPixels: imagePixelSize.height
  )
  let trimRight = proportionalPixelOffset(
    hiddenCells: hiddenRightCells,
    totalCells: logicalCellSize.width,
    totalPixels: imagePixelSize.width
  )
  let trimBottom = proportionalPixelOffset(
    hiddenCells: hiddenBottomCells,
    totalCells: logicalCellSize.height,
    totalPixels: imagePixelSize.height
  )
  return KittySourceRect(
    x: sourceX,
    y: sourceY,
    width: max(1, imagePixelSize.width - sourceX - trimRight),
    height: max(1, imagePixelSize.height - sourceY - trimBottom)
  )
}

private func proportionalPixelOffset(
  hiddenCells: Int,
  totalCells: Int,
  totalPixels: Int
) -> Int {
  guard hiddenCells > 0, totalCells > 0, totalPixels > 0 else {
    return 0
  }
  let numerator = Int64(hiddenCells) * Int64(totalPixels)
  let rounded = (numerator + Int64(totalCells / 2)) / Int64(totalCells)
  return min(totalPixels - 1, max(0, Int(rounded)))
}

func kittyTransmitAndPlaceCommands(
  payload: KittyPayload,
  imageID: UInt32,
  cellColumns: Int,
  cellRows: Int,
  sourceRect: KittySourceRect?
) -> [String] {
  let chunks = payload.encodedChunks

  guard !chunks.isEmpty else {
    return []
  }

  return chunks.enumerated().map { index, chunk in
    let hasMore = index + 1 < chunks.count ? 1 : 0
    if index == 0 {
      // First chunk carries the full control data:
      //   a=T  transmit and display
      //   q=2  suppress all responses (we already probed for support)
      //   t=d  direct transmission (payload is base64 in this escape code)
      //   f    pixel format (100 for PNG, 32 for RGBA, 24 for RGB)
      //   s,v  source-image pixel width/height, required by `f=32`
      //        and `f=24`, ignored for `f=100`
      //   C=1  do not advance the cursor after placement
      //   c,r  display rectangle in terminal cells (Kitty scales to fit)
      //   i    stable image id so we can re-place the image by id later
      //   m    1 if more chunks follow, 0 otherwise
      var controlData =
        "_Ga=T,q=2,t=d,f=\(payload.format.formatKey),C=1,c=\(cellColumns),r=\(cellRows),i=\(imageID)"
      if case .rgba(let pixelSize) = payload.format {
        controlData.append(",s=\(pixelSize.width),v=\(pixelSize.height)")
      }
      // Note: the kitty protocol explicitly says the root-frame gap
      // *must* be set via a follow-up `a=a,r=1,z=...` control message
      // (see Animation in graphics-protocol.rst). `z=` on the initial
      // transmit applies only to additional frames, not frame 1.
      if let sourceRect {
        controlData.append(
          ",x=\(sourceRect.x),y=\(sourceRect.y),w=\(sourceRect.width),h=\(sourceRect.height)"
        )
      }
      controlData.append(",m=\(hasMore)")
      return "\u{001B}\(controlData);\(chunk)\u{001B}\\"
    }
    // Continuation chunks may only carry the `m` (and optionally `q`) key.
    return "\u{001B}_Gm=\(hasMore);\(chunk)\u{001B}\\"
  }
}

/// Flattens an array of decoded RGBA pixels into the row-major byte
/// stream Kitty expects under `f=32` (4 bytes per pixel: R, G, B, A).
func SwiftTUI_rgbaBytes(from pixels: [RGBAImagePixel]) -> [UInt8] {
  var out = [UInt8]()
  out.reserveCapacity(pixels.count * 4)
  for pixel in pixels {
    out.append(UInt8(pixel.red))
    out.append(UInt8(pixel.green))
    out.append(UInt8(pixel.blue))
    out.append(UInt8(pixel.alpha))
  }
  return out
}

func kittyPlacementCommand(
  imageID: UInt32,
  cellColumns: Int,
  cellRows: Int,
  sourceRect: KittySourceRect?
) -> String {
  // Re-place a previously transmitted image at the current cursor position
  // using the same cell rectangle. `a=p` does not re-transmit the image data.
  var controlData = "_Ga=p,q=2,C=1,c=\(cellColumns),r=\(cellRows),i=\(imageID)"
  if let sourceRect {
    controlData.append(
      ",x=\(sourceRect.x),y=\(sourceRect.y),w=\(sourceRect.width),h=\(sourceRect.height)"
    )
  }
  return "\u{001B}\(controlData)\u{001B}\\"
}

/// Stable kitty image id for a source reference. When a non-PNG payload
/// was downsampled for transmission (`rgbaTransmitSize` present), the
/// transmit size participates in the id: the terminal's stored buffer
/// and the placement's source-rect coordinates are in transmit-pixel
/// space, so a placement resized to a different transmit size must
/// retransmit under a fresh id rather than re-place a buffer with
/// mismatched geometry.
func kittyImageID(
  reference: ImageAssetReference,
  rgbaTransmitSize: PixelSize? = nil
) -> UInt32 {
  stableIdentifier(
    from: stableBytes(for: reference) + rgbaTransmitSuffixBytes(rgbaTransmitSize)
  )
}

/// Blended-variant counterpart of ``kittyImageID(reference:rgbaTransmitSize:)``.
func kittyVariantImageID(
  variantID: String,
  rgbaTransmitSize: PixelSize? = nil
) -> UInt32 {
  stableIdentifier(
    from: Array(variantID.utf8) + rgbaTransmitSuffixBytes(rgbaTransmitSize)
  )
}

private func rgbaTransmitSuffixBytes(
  _ size: PixelSize?
) -> [UInt8] {
  guard let size else {
    return []
  }
  return Array(":rgba=\(size.width)x\(size.height)".utf8)
}

private func stableBytes(
  for reference: ImageAssetReference
) -> [UInt8] {
  switch reference {
  case .namedResource(let name):
    Array(("named:\(name)").utf8)
  case .filePath(let path):
    Array(("file:\(path)").utf8)
  case .embeddedImage(let bytes):
    Array("embedded:".utf8) + bytes
  }
}

func stableIdentifier(
  from bytes: [UInt8]
) -> UInt32 {
  var hash: UInt32 = 2_166_136_261
  for byte in bytes {
    hash ^= UInt32(byte)
    hash &*= 16_777_619
  }
  return hash == 0 ? 1 : hash
}

func terminalSaveCursorSequence() -> String {
  "\u{001B}7"
}

func terminalRestoreCursorSequence() -> String {
  "\u{001B}8"
}

func terminalCursorSequence(
  to point: CellPoint
) -> String {
  let row = max(1, point.y + 1)
  let column = max(1, point.x + 1)
  return "\u{001B}[\(row);\(column)H"
}

/// Byte budget for one kitty escape-code payload chunk. The graphics
/// protocol rejects chunks larger than 4096 bytes of base64 data.
let kittyPayloadChunkByteLimit = 4096

/// Base64-encodes `bytes`, split into chunks of at most `maxChunkBytes`
/// characters in one pass over the input. `maxChunkBytes` must be a
/// positive multiple of 4 so every non-final chunk carries whole base64
/// quartets and the receiver can reassemble the stream by concatenation.
func base64EncodedChunks(
  _ bytes: [UInt8],
  maxChunkBytes: Int = kittyPayloadChunkByteLimit
) -> [String] {
  precondition(
    maxChunkBytes > 0 && maxChunkBytes.isMultiple(of: 4),
    "base64 chunk limits must be positive multiples of 4"
  )
  guard !bytes.isEmpty else {
    return []
  }

  let alphabet = Array(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8
  )
  let padding = UInt8(ascii: "=")
  var chunks: [String] = []
  var chunk = [UInt8]()
  chunk.reserveCapacity(min(maxChunkBytes, ((bytes.count + 2) / 3) * 4))
  var index = 0

  while index < bytes.count {
    let first = Int(bytes[index])
    let second = index + 1 < bytes.count ? Int(bytes[index + 1]) : 0
    let third = index + 2 < bytes.count ? Int(bytes[index + 2]) : 0
    let combined = (first << 16) | (second << 8) | third

    chunk.append(alphabet[(combined >> 18) & 0x3F])
    chunk.append(alphabet[(combined >> 12) & 0x3F])
    chunk.append(index + 1 < bytes.count ? alphabet[(combined >> 6) & 0x3F] : padding)
    chunk.append(index + 2 < bytes.count ? alphabet[combined & 0x3F] : padding)

    if chunk.count == maxChunkBytes {
      chunks.append(String(decoding: chunk, as: UTF8.self))
      chunk.removeAll(keepingCapacity: true)
    }
    index += 3
  }

  if !chunk.isEmpty {
    chunks.append(String(decoding: chunk, as: UTF8.self))
  }
  return chunks
}
