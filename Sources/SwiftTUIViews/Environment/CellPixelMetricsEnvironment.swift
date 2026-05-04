public import SwiftTUICore

private enum CellPixelMetricsKey: EnvironmentKey {
  static let defaultValue: CellPixelMetrics = .estimated
}

extension EnvironmentValues {
  /// Read-only cell pixel dimensions for the current terminal surface,
  /// with a confidence flag distinguishing reported values from the
  /// conventional 8x16 fallback.
  public var cellPixelMetrics: CellPixelMetrics {
    get { self[CellPixelMetricsKey.self] }
    set { self[CellPixelMetricsKey.self] = newValue }
  }
}
