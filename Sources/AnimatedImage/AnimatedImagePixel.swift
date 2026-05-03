/// A single 8-bit RGBA pixel in a pre-composed animated image frame.
public struct AnimatedImagePixel: Equatable, Hashable, Sendable {
  public var red: UInt8
  public var green: UInt8
  public var blue: UInt8
  public var alpha: UInt8

  public init(
    red: UInt8,
    green: UInt8,
    blue: UInt8,
    alpha: UInt8 = 255
  ) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }
}
