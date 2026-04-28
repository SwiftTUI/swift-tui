/// A namespace for the GIF decoder.
///
/// Nested ``RGBA``, ``BytestreamSource``, ``Image``, and ``DecodingError``, with
/// ``Image/decompress(stream:)`` as the primary entry point.
public enum GIF {

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

  /// A source bytestream (compatible in shape with PNG/JPEG sources).
  public protocol BytestreamSource {
    mutating func read(count: Int) -> [UInt8]?
  }
}

extension GIF.RGBA {
  /// The fully-opaque alpha value for this integer type (`T.max`).
  @inlinable
  public static var opaqueAlpha: T { T.max }

  /// The fully-transparent alpha value (zero).
  @inlinable
  public static var clearAlpha: T { 0 }
}
