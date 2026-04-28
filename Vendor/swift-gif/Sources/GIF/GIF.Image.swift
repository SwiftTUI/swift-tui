extension GIF {

  /// A decoded GIF, including all frames.
  ///
  /// The public surface mirrors `PNG.Image` and `JPEG.Image`: ``size`` is
  /// the logical-screen dimensions, ``decompress(stream:)`` reads from a
  /// `BytestreamSource`, and ``unpack(as:)`` returns a flat row-major
  /// array of `RGBA` pixels for the **first frame composited onto the
  /// logical screen**. For animation, walk ``frames`` directly.
  public struct Image: Sendable {
    public let size: (x: Int, y: Int)

    /// All decoded frames in source order.
    public let frames: [GIF.Frame]

    /// The optional logical-screen background color (from the global
    /// color table at the LSD's `backgroundColorIndex`).
    public let backgroundColor: (r: UInt8, g: UInt8, b: UInt8)?

    init(
      size: (Int, Int),
      frames: [GIF.Frame],
      backgroundColor: (r: UInt8, g: UInt8, b: UInt8)?
    ) {
      self.size = size
      self.frames = frames
      self.backgroundColor = backgroundColor
    }

    /// Decodes the GIF bytestream produced by `stream`.
    public static func decompress<Source>(
      stream: inout Source
    ) throws -> GIF.Image where Source: GIF.BytestreamSource {
      let bytes = GIF.Image.loadAllBytes(from: &stream)
      var decoder = GIF.Decoder(bytes: bytes)
      let result = try decoder.decode()
      return GIF.Image(
        size: (result.screenWidth, result.screenHeight),
        frames: result.frames,
        backgroundColor: result.backgroundColor
      )
    }

    /// Renders the **first frame** onto the logical screen and returns
    /// the result as a flat row-major array of `RGBA<T>` pixels. Pixels
    /// outside the first frame's bounds are transparent (alpha = 0).
    public func unpack<T>(as type: GIF.RGBA<T>.Type) -> [GIF.RGBA<T>]
    where T: FixedWidthInteger & UnsignedInteger {
      composited(frameIndex: 0, as: type)
    }

    /// Renders frame `i` (with all required prior compositing applied)
    /// onto the logical screen as `RGBA<T>` pixels.
    ///
    /// For frame 0, the canvas starts as fully transparent and only
    /// the first frame's pixels are painted. For later frames, the
    /// disposal method of each prior frame is applied before the next
    /// frame is composited (`keep`, `background`, or `previous`).
    public func composited<T>(
      frameIndex i: Int,
      as type: GIF.RGBA<T>.Type
    ) -> [GIF.RGBA<T>]
    where T: FixedWidthInteger & UnsignedInteger {
      precondition(
        (0..<frames.count).contains(i),
        "frame index \(i) out of bounds (count \(frames.count))"
      )
      let total = size.x * size.y
      var canvas = [GIF.RGBA<T>](
        repeating: GIF.RGBA<T>(0, 0, 0, GIF.RGBA<T>.clearAlpha),
        count: total
      )
      // For frame 0 we just paint over a transparent canvas.
      // For later frames, replay the chain.
      var previous = canvas
      for k in 0...i {
        let f = frames[k]
        // Capture pre-frame state for `previous` disposal.
        let preFrameSnapshot = canvas

        paintFrame(f, into: &canvas, as: type)

        if k < i {
          // Apply this frame's disposal before painting the next.
          switch f.disposal {
          case .unspecified, .keep:
            previous = canvas
          case .background:
            clearRect(
              into: &canvas,
              left: f.left, top: f.top,
              width: f.width, height: f.height,
              background: backgroundColor,
              as: type
            )
            previous = preFrameSnapshot
          case .previous:
            canvas = previous
          }
        }
      }
      return canvas
    }

    /// Paints frame `f` onto `canvas`, honoring the frame's transparent
    /// index (those pixels leave the canvas unchanged).
    private func paintFrame<T>(
      _ f: GIF.Frame,
      into canvas: inout [GIF.RGBA<T>],
      as: GIF.RGBA<T>.Type
    ) where T: FixedWidthInteger & UnsignedInteger {
      let opaque = GIF.RGBA<T>.opaqueAlpha
      for row in 0..<f.height {
        let dstRow = (f.top + row) * size.x
        let srcRow = row * f.width
        for col in 0..<f.width {
          let idx = Int(f.indices[srcRow + col])
          if let t = f.transparentIndex, idx == t {
            continue
          }
          if idx >= f.palette.count {
            // Out-of-range index in a way that's not the transparent
            // marker — treat as transparent rather than crashing.
            continue
          }
          let rgb = f.palette[idx]
          canvas[dstRow + f.left + col] = GIF.RGBA<T>(
            scale(UInt8: rgb.r),
            scale(UInt8: rgb.g),
            scale(UInt8: rgb.b),
            opaque
          )
        }
      }
    }

    private func clearRect<T>(
      into canvas: inout [GIF.RGBA<T>],
      left: Int, top: Int,
      width: Int, height: Int,
      background: (r: UInt8, g: UInt8, b: UInt8)?,
      as: GIF.RGBA<T>.Type
    ) where T: FixedWidthInteger & UnsignedInteger {
      let fill: GIF.RGBA<T>
      if let bg = background {
        fill = GIF.RGBA<T>(
          scale(UInt8: bg.r),
          scale(UInt8: bg.g),
          scale(UInt8: bg.b),
          GIF.RGBA<T>.opaqueAlpha
        )
      } else {
        fill = GIF.RGBA<T>(0, 0, 0, GIF.RGBA<T>.clearAlpha)
      }
      for row in 0..<height {
        let base = (top + row) * size.x + left
        for col in 0..<width {
          canvas[base + col] = fill
        }
      }
    }

    /// Reads as many bytes as the source will provide, with adaptive
    /// chunk sizing (matching the JPEG/PNG vendor decoders).
    static func loadAllBytes<S: GIF.BytestreamSource>(from source: inout S) -> [UInt8] {
      var data: [UInt8] = []
      let chunkSize = 4096
      while let chunk = source.read(count: chunkSize) {
        data.append(contentsOf: chunk)
      }
      while let byte = source.read(count: 1) {
        data.append(byte[0])
      }
      return data
    }
  }
}

// MARK: - Internal helpers

@inline(__always)
private func scale<T>(UInt8 value: UInt8) -> T
where T: FixedWidthInteger & UnsignedInteger {
  if T.bitWidth == 8 {
    return T(value)
  }
  if T.bitWidth == 16 {
    let v = UInt16(value)
    return T(truncatingIfNeeded: (v << 8) | v)
  }
  let denom = T.max / T(255)
  return T(value) &* denom
}
