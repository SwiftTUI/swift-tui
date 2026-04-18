/// Controls which gestures receive events when multiple are attached.
/// Matches SwiftUI's `GestureMask`.
public struct GestureMask: OptionSet, Equatable, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  /// The gesture attached at this view participates.
  public static let gesture = GestureMask(rawValue: 1 << 0)
  /// Subview gestures participate.
  public static let subviews = GestureMask(rawValue: 1 << 1)
  /// Both this view's and subview gestures participate.
  public static let all: GestureMask = [.gesture, .subviews]
  /// No gestures participate.
  public static let none: GestureMask = []
}
