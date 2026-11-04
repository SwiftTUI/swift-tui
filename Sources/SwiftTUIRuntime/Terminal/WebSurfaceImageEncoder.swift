import SwiftTUICore

// Web-surface image encoding.
//
// This is the image-attachment half of the web-surface JSON encoder: it
// resolves an attachment's bytes (embedded, file path, or inline data),
// sniffs the container format from the magic bytes, derives a stable
// source-owned image ID so unchanged images are transmitted only once, and
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
@_spi(Runners) public enum WebSurfaceImageFormat: String, CaseIterable, Sendable {
  case png, jpeg, gif
}

package struct ImageWireID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
  package let rawValue: String
  package init(rawValue: String) { self.rawValue = rawValue }
  package init(stringLiteral value: String) { self.init(rawValue: value) }

  package static func encoded(_ format: WebSurfaceImageFormat, digest: UInt64, count: Int) -> Self {
    let hex = String(digest, radix: 16)
    return Self(
      rawValue: "\(format.rawValue):\(String(repeating: "0", count: 16 - hex.count))\(hex):\(count)"
    )
  }
  package static func blended(_ digest: String) -> Self { Self(rawValue: "blend:png:\(digest)") }
}

private let webSurfaceImageBlendCompositor = ImageBlendCompositor()

extension WebSurfaceFrameEncoder {
  package static func imageBlendCacheSnapshot() -> ImageBlendCompositorCacheSnapshot {
    webSurfaceImageBlendCompositor.cacheSnapshot()
  }

  package static func encodeImages(
    _ attachments: [RasterImageAttachment],
    fallbackBackground: Color,
    knownImageIDs: inout Set<ImageWireID>,
    contentRepository: ImageContentRepository = .shared,
    presentationLayers: [RasterPresentationLayer] = []
  ) -> [String] {
    (try? encodeImagesBounded(
      attachments, fallbackBackground: fallbackBackground, knownImageIDs: &knownImageIDs,
      contentRepository: contentRepository, presentationLayers: presentationLayers
    )) ?? []
  }

  package static func encodeImagesBounded(
    _ attachments: [RasterImageAttachment],
    fallbackBackground: Color,
    knownImageIDs: inout Set<ImageWireID>,
    contentRepository: ImageContentRepository = .shared,
    presentationLayers: [RasterPresentationLayer] = []
  ) throws -> [String] {
    guard attachments.count <= HostWireBudget.images else { throw HostWireBudget.Exceeded.limit }
    var surface = RasterSurface(size: .zero, cells: [], imageAttachments: attachments)
    surface.presentationLayers = presentationLayers
    let prepared = webSurfaceImageBlendCompositor.orderedAttachments(
      in: surface, fallbackBackground: fallbackBackground)
    var placements: [(attachment: RasterImageAttachment, payload: ImagePayload)] = []
    for attachment in prepared where !attachment.visibleBounds.isEmpty {
      guard
        let payload = imagePayload(
          for: attachment,
          fallbackBackground: fallbackBackground,
          contentRepository: contentRepository
        )
      else { continue }
      guard payload.id.rawValue.utf8.count <= 1024 else { throw HostWireBudget.Exceeded.limit }
      _ = try HostWireBudget.jsonStringBytes(payload.id.rawValue)
      guard payload.bytes.count <= (HostWireBudget.recordBytes - 2) / 4 * 3 else {
        throw HostWireBudget.Exceeded.limit
      }
      placements.append((attachment, payload))
    }
    forgetUnreferencedImageIDs(
      toAdmit: Set(placements.map(\.payload.id)), knownImageIDs: &knownImageIDs)
    var result: [String] = []
    var bytes = 0
    for placement in placements {
      let encoded = encodeImage(
        placement.attachment, payload: placement.payload, knownImageIDs: &knownImageIDs)
      let count = encoded.utf8.count + (result.isEmpty ? 0 : 1)
      guard count <= HostWireBudget.recordBytes - bytes else {
        throw HostWireBudget.Exceeded.limit
      }
      bytes += count
      result.append(encoded)
    }
    return result
  }

  /// Keeps transmit-once history within ``HostWireBudget/images`` once this
  /// record's IDs are admitted, by forgetting only IDs the record does not
  /// place. Forgetting is safe (a later use carries its bytes again), but
  /// forgetting a placed ID re-sends, in this same record, a payload the host
  /// already holds. Re-sending every placed image at once can overflow the
  /// record budget, and because a rejected record keeps the prior history, a
  /// static scene would then be rejected on every frame. A record places at
  /// most ``HostWireBudget/images`` attachments, so enough unplaced IDs exist.
  private static func forgetUnreferencedImageIDs(
    toAdmit referencedIDs: Set<ImageWireID>,
    knownImageIDs: inout Set<ImageWireID>
  ) {
    let overflow =
      knownImageIDs.count + referencedIDs.subtracting(knownImageIDs).count - HostWireBudget.images
    guard overflow > 0 else { return }
    for imageID in knownImageIDs.subtracting(referencedIDs).prefix(overflow) {
      knownImageIDs.remove(imageID)
    }
  }

  private static func encodeImage(
    _ attachment: RasterImageAttachment,
    payload: ImagePayload,
    knownImageIDs: inout Set<ImageWireID>
  ) -> String {
    let imageID = payload.id
    let shouldTransmitData = knownImageIDs.insert(imageID).inserted
    var fields = [
      "\"id\":\(jsonString(imageID.rawValue))",
      "\"format\":\(jsonString(payload.format.rawValue))",
      "\"bounds\":\(encodeRect(payload.bounds))",
      "\"visibleBounds\":\(encodeRect(payload.visibleBounds))",
      "\"scalingMode\":\(jsonString(attachment.scalingMode.rawValue))",
      "\"opacity\":\(attachment.opacity)",
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
    var id: ImageWireID
    var pixelSize: PixelSize?
    var bounds: CellRect
    var visibleBounds: CellRect
  }

  private static func imagePayload(
    for attachment: RasterImageAttachment,
    fallbackBackground: Color,
    contentRepository: ImageContentRepository
  ) -> ImagePayload? {
    if let blended = HostWireFrameModel.blendedImagePayload(
      for: attachment,
      compositor: webSurfaceImageBlendCompositor,
      fallbackBackground: fallbackBackground
    ) {
      return ImagePayload(
        bytes: blended.bytes,
        format: .png,
        id: blended.wireID,
        pixelSize: blended.pixelSize,
        bounds: attachment.visibleBounds,
        visibleBounds: attachment.visibleBounds
      )
    }

    guard let content = contentRepository.content(for: attachment) else {
      return nil
    }
    let bytes = content.bytes
    return ImagePayload(
      bytes: bytes,
      format: content.format,
      id: content.encodedID,
      pixelSize: attachment.pixelSize,
      bounds: attachment.bounds,
      visibleBounds: attachment.visibleBounds
    )
  }

  private static func encodeSize(
    _ size: PixelSize
  ) -> String {
    "[\(size.width),\(size.height)]"
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

func imageContentReadFileBytes(
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
    let readCount = buffer.withUnsafeMutableBytes { rawBuffer in
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
