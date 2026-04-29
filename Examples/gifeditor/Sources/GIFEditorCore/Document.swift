import Foundation

/// One layer inside a frame. Layers paint bottom-to-top — the topmost
/// layer wins at every cell where its pixel is not transparent.
public struct EditorLayer: Hashable, Sendable, Codable, Identifiable {
  public let id: UUID
  public var name: String
  public var isVisible: Bool
  public var pixels: PixelBuffer

  public init(
    id: UUID = UUID(),
    name: String,
    isVisible: Bool = true,
    pixels: PixelBuffer
  ) {
    self.id = id
    self.name = name
    self.isVisible = isVisible
    self.pixels = pixels
  }
}

/// A single animation frame: a stack of layers plus its display delay
/// and disposal mode (which the encoder uses to decide how the frame's
/// region is reset before the next one paints).
public struct EditorFrame: Hashable, Sendable, Codable, Identifiable {
  public let id: UUID
  public var layers: [EditorLayer]
  /// Display delay in centiseconds (1/100 sec).
  public var delayCentiseconds: Int
  public var disposal: FrameDisposal

  public init(
    id: UUID = UUID(),
    layers: [EditorLayer],
    delayCentiseconds: Int = 10,
    disposal: FrameDisposal = .background
  ) {
    self.id = id
    self.layers = layers
    self.delayCentiseconds = max(0, delayCentiseconds)
    self.disposal = disposal
  }

  public enum FrameDisposal: UInt8, Hashable, Sendable, Codable {
    case unspecified = 0
    case keep = 1
    case background = 2
    case previous = 3
  }
}

/// The complete editor document. Everything else in the editor reads
/// from or writes into this value type.
///
/// `path` is non-nil when the document was loaded from disk or has been
/// saved at least once; it drives the `Ctrl+S` "save back" behaviour.
public struct GIFDocument: Hashable, Sendable, Codable {
  public var size: PixelSize
  public var palette: ColorPalette
  public var frames: [EditorFrame]
  public var path: URL?
  /// Number of times the GIF should loop on playback. Zero = infinite.
  public var loopCount: Int

  public init(
    size: PixelSize,
    palette: ColorPalette = .default,
    frames: [EditorFrame],
    path: URL? = nil,
    loopCount: Int = 0
  ) {
    precondition(!frames.isEmpty, "GIFDocument must have at least one frame")
    self.size = size
    self.palette = palette
    self.frames = frames
    self.path = path
    self.loopCount = loopCount
  }

  /// A blank document: one frame, one transparent layer.
  public static func blank(
    size: PixelSize,
    palette: ColorPalette = .default
  ) -> GIFDocument {
    let layer = EditorLayer(
      name: "Layer 1",
      pixels: PixelBuffer(size: size)
    )
    let frame = EditorFrame(layers: [layer])
    return GIFDocument(size: size, palette: palette, frames: [frame])
  }

  /// Composites every visible layer of `frame` into a single flat buffer
  /// (bottom-to-top). The returned buffer is independent of any layer
  /// and is the format the renderer/encoder consumes.
  public func flatten(frameIndex: Int) -> PixelBuffer {
    precondition(frames.indices.contains(frameIndex), "frame index out of range")
    var result = PixelBuffer(size: size)
    for layer in frames[frameIndex].layers where layer.isVisible {
      // Paint the layer onto the running composite, treating the layer's
      // `nil` pixels as fully transparent so deeper layers show through.
      result.stamp(layer.pixels, at: .zero, respectingTransparency: true)
    }
    return result
  }

  /// Composites a frame as `[EditorColor]`, evaluating the palette so
  /// the renderer doesn't need to know about palette indices.
  public func flattenedColors(frameIndex: Int) -> [EditorColor?] {
    let buffer = flatten(frameIndex: frameIndex)
    return buffer.pixels.map { idx in
      guard let idx else { return nil }
      let color = palette[idx]
      return color.alpha == 0 ? nil : color
    }
  }
}
