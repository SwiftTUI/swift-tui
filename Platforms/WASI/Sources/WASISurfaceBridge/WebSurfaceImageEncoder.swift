@_spi(Runners) package import SwiftTUIRuntime

// Web-surface image encoding.
//
// This is the image-attachment half of the web-surface JSON encoder: it
// resolves an attachment's bytes (embedded, file path, or inline data),
// sniffs the container format from the magic bytes, derives a stable
// content-hash image ID so unchanged images are transmitted only once, and
// base64-encodes the payload.
//
// Split out of `WebSurfaceFrameEncoder.swift`. `encodeImages` is widened to
// `package` (still namespaced under `WebSurfaceFrameEncoder`) because the
// frame encoder's orchestrator calls it; the cluster's other helpers stay
// `private`. It relies on two `package` leaves left behind in the core file —
// `jsonString` and `encodeRect`.

/// Container format the web-surface transport advertises to the JS
/// side. Mirrors the JSON `format` field on each transmitted image
/// record, and disambiguates the MIME type that the consumer will
/// pass to `Blob`/`<img>` when decoding.
enum WebSurfaceImageFormat: Sendable, Equatable {
  case png
  case jpeg
  case gif

  /// String that appears in the surface JSON's `format` field — and
  /// becomes the suffix of `image/<value>` in the consumer's MIME.
  var jsonValue: String {
    switch self {
    case .png: return "png"
    case .jpeg: return "jpeg"
    case .gif: return "gif"
    }
  }
}

private let webSurfaceImageBlendCompositor = ImageBlendCompositor()

extension WebSurfaceFrameEncoder {
  package static func imageBlendCacheSnapshot() -> ImageBlendCompositorCacheSnapshot {
    webSurfaceImageBlendCompositor.cacheSnapshot()
  }

  package static func encodeImages(
    _ attachments: [RasterImageAttachment],
    fallbackBackground: Color,
    knownImageIDs: inout Set<String>
  ) -> [String] {
    attachments.compactMap { attachment in
      encodeImage(
        attachment,
        fallbackBackground: fallbackBackground,
        knownImageIDs: &knownImageIDs
      )
    }
  }

  private static func encodeImage(
    _ attachment: RasterImageAttachment,
    fallbackBackground: Color,
    knownImageIDs: inout Set<String>
  ) -> String? {
    guard !attachment.visibleBounds.isEmpty else {
      return nil
    }

    let payload = imagePayload(
      for: attachment,
      fallbackBackground: fallbackBackground
    )
    guard let payload else {
      return nil
    }

    let imageID = payload.id
    let shouldTransmitData = knownImageIDs.insert(imageID).inserted
    var fields = [
      "\"id\":\(jsonString(imageID))",
      "\"format\":\(jsonString(payload.format.jsonValue))",
      "\"bounds\":\(encodeRect(payload.bounds))",
      "\"visibleBounds\":\(encodeRect(payload.visibleBounds))",
      "\"scalingMode\":\(jsonString(attachment.scalingMode.rawValue))",
    ]
    if let pixelSize = payload.pixelSize {
      fields.append("\"pixelSize\":\(encodeSize(pixelSize))")
    }
    if shouldTransmitData {
      fields.append("\"dataBase64\":\(jsonString(base64Encoded(payload.bytes)))")
    }
    return "{" + fields.joined(separator: ",") + "}"
  }

  private struct ImagePayload {
    var bytes: [UInt8]
    var format: WebSurfaceImageFormat
    var id: String
    var pixelSize: PixelSize?
    var bounds: CellRect
    var visibleBounds: CellRect
  }

  private static func imagePayload(
    for attachment: RasterImageAttachment,
    fallbackBackground: Color
  ) -> ImagePayload? {
    if let blended = HostWireFrameModel.blendedImagePayload(
      for: attachment,
      compositor: webSurfaceImageBlendCompositor,
      fallbackBackground: fallbackBackground
    ) {
      return ImagePayload(
        bytes: blended.bytes,
        format: .png,
        id: blended.id,
        pixelSize: blended.pixelSize,
        bounds: attachment.visibleBounds,
        visibleBounds: attachment.visibleBounds
      )
    }

    guard let bytes = imageBytes(for: attachment) else {
      return nil
    }
    let format = imageFormat(for: bytes)
    return ImagePayload(
      bytes: bytes,
      format: format,
      id: webImageID(for: bytes, format: format),
      pixelSize: attachment.pixelSize,
      bounds: attachment.bounds,
      visibleBounds: attachment.visibleBounds
    )
  }

  private static func imageBytes(
    for attachment: RasterImageAttachment
  ) -> [UInt8]? {
    switch attachment.resolvedReference {
    case .embeddedImage(let bytes):
      return bytes
    case .filePath(let path):
      return webSurfaceReadFileBytes(at: path)
    case .namedResource, nil:
      break
    }

    if case .data(let bytes) = attachment.source {
      return bytes
    }
    return nil
  }

  /// Detects the container format from the leading magic bytes. Used
  /// to set the JSON `format` field and pick a MIME type on the JS
  /// side. Defaults to PNG so unknown blobs at least try the most
  /// common path.
  private static func imageFormat(
    for bytes: [UInt8]
  ) -> WebSurfaceImageFormat {
    if bytes.count >= 8,
      bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47,
      bytes[4] == 0x0D, bytes[5] == 0x0A, bytes[6] == 0x1A, bytes[7] == 0x0A
    {
      return .png
    }
    if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
      return .jpeg
    }
    if bytes.count >= 6,
      bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x38,
      bytes[4] == 0x37 || bytes[4] == 0x39, bytes[5] == 0x61
    {
      return .gif
    }
    return .png
  }

  private static func encodeSize(
    _ size: PixelSize
  ) -> String {
    "[\(size.width),\(size.height)]"
  }

  private static func webImageID(
    for bytes: [UInt8],
    format: WebSurfaceImageFormat
  ) -> String {
    "\(format.jsonValue):\(hexString(fnv1a64(bytes))):\(bytes.count)"
  }

  private static func fnv1a64(
    _ bytes: [UInt8]
  ) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in bytes {
      hash ^= UInt64(byte)
      hash &*= 0x100_0000_01b3
    }
    return hash
  }

  private static func hexString(
    _ value: UInt64
  ) -> String {
    var text = String(value, radix: 16, uppercase: false)
    while text.count < 16 {
      text = "0" + text
    }
    return text
  }

  private static func base64Encoded(
    _ bytes: [UInt8]
  ) -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
    var result: [UInt8] = []
    result.reserveCapacity(((bytes.count + 2) / 3) * 4)

    var index = 0
    while index < bytes.count {
      let first = Int(bytes[index])
      let second = index + 1 < bytes.count ? Int(bytes[index + 1]) : 0
      let third = index + 2 < bytes.count ? Int(bytes[index + 2]) : 0
      let combined = (first << 16) | (second << 8) | third

      result.append(alphabet[(combined >> 18) & 0x3F])
      result.append(alphabet[(combined >> 12) & 0x3F])
      result.append(
        index + 1 < bytes.count ? alphabet[(combined >> 6) & 0x3F] : UInt8(ascii: "=")
      )
      result.append(index + 2 < bytes.count ? alphabet[combined & 0x3F] : UInt8(ascii: "="))
      index += 3
    }

    return String(decoding: result, as: UTF8.self)
  }
}

private func webSurfaceReadFileBytes(
  at path: String
) -> [UInt8]? {
  let fileDescriptor = webSurfaceOpenRead(path)
  guard fileDescriptor >= 0 else {
    return nil
  }
  defer {
    _ = webSurfaceClose(fileDescriptor)
  }

  var bytes: [UInt8] = []
  var buffer = [UInt8](repeating: 0, count: 8 * 1024)
  let bufferCount = buffer.count
  while true {
    let readCount = unsafe buffer.withUnsafeMutableBytes { rawBuffer in
      unsafe webSurfaceRead(
        fileDescriptor,
        rawBuffer.baseAddress,
        bufferCount
      )
    }
    if readCount < 0 {
      return nil
    }
    if readCount == 0 {
      return bytes
    }
    bytes.append(contentsOf: buffer.prefix(readCount))
  }
}
