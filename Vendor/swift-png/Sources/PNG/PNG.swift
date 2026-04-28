/// A namespace for the PNG decoder.
///
/// ``RGBA``, ``BytestreamSource``, and ``Image`` are nested under this
/// namespace, and ``Image/decompress(stream:)`` is the primary entry
/// point. The public surface is the same shape as `JPEG.Image` and
/// `GIF.Image` — the same generic pixel type, the same source protocol,
/// the same `decompress` / `unpack` methods — so a single adapter can
/// dispatch into all three decoders.
public enum PNG {

  /// A four-component pixel.
  @frozen
  public struct RGBA<T>: Hashable where T: FixedWidthInteger & UnsignedInteger {
    public var r: T
    public var g: T
    public var b: T
    public var a: T

    public init(_ r: T, _ g: T, _ b: T, _ a: T) {
      self.r = r
      self.g = g
      self.b = b
      self.a = a
    }
  }

  /// A source bytestream.
  ///
  /// Conform a type to this protocol to feed bytes to the decoder. The
  /// protocol is identical in shape to `JPEG.BytestreamSource` and
  /// `GIF.BytestreamSource` so the same adapter can serve all three
  /// decoders.
  public protocol BytestreamSource {
    /// Reads the next `count` bytes from the stream, or returns `nil` if
    /// fewer than `count` bytes remain.
    mutating func read(count: Int) -> [UInt8]?
  }
}

extension PNG.RGBA {
  /// The fully-opaque alpha value for this integer type (`T.max`).
  @inlinable
  public static var opaqueAlpha: T { T.max }

  /// The fully-transparent alpha value (zero).
  @inlinable
  public static var clearAlpha: T { 0 }
}
