import GIF

/// Errors thrown while encoding a `GIFDocument` into GIF89a bytes.
public typealias GIFEncoderError = GIF.EncodingError

/// Adapts the editor's document model into `swift-gif`'s indexed encoder.
public enum GIFEncoder {
  /// Encodes a flattened document into GIF89a bytes.
  ///
  /// `flattenedFrames[i]` is the result of `document.flatten(frameIndex: i)`,
  /// passed in by the caller so callers that want to do their own
  /// flattening (e.g. with effects on top) don't pay twice.
  public static func encode(
    document: GIFDocument,
    flattenedFrames: [PixelBuffer]? = nil
  ) throws -> [UInt8] {
    let flattened =
      flattenedFrames ?? (0..<document.frames.count).map { document.flatten(frameIndex: $0) }
    precondition(flattened.count == document.frames.count)

    let frames = zip(document.frames, flattened).map { frame, flattened in
      GIF.IndexedFrame(
        width: document.size.width,
        height: document.size.height,
        indices: flattened.pixels.map { $0 ?? ColorPalette.transparentSlot },
        transparentIndex: Int(ColorPalette.transparentSlot),
        delayCentiseconds: frame.delayCentiseconds,
        disposal: GIF.Disposal(editorDisposal: frame.disposal)
      )
    }

    let image = GIF.IndexedImage(
      size: (x: document.size.width, y: document.size.height),
      globalColorTable: document.palette.colors.map { color in
        (r: color.red, g: color.green, b: color.blue)
      },
      backgroundIndex: Int(ColorPalette.transparentSlot),
      loopCount: document.loopCount,
      frames: frames
    )

    return try GIF.Encoder.encode(image)
  }
}

extension GIF.Disposal {
  fileprivate init(editorDisposal: EditorFrame.FrameDisposal) {
    self = GIF.Disposal(rawValue: editorDisposal.rawValue) ?? .unspecified
  }
}
