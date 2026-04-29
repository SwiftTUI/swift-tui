public import Core

private enum PointerInputCapabilitiesKey: EnvironmentKey {
  static let defaultValue: PointerInputCapabilities = .cellOnly
}

extension EnvironmentValues {
  /// Pointer precision and feature support for the current input host.
  public var pointerInputCapabilities: PointerInputCapabilities {
    get { self[PointerInputCapabilitiesKey.self] }
    set { self[PointerInputCapabilitiesKey.self] = newValue }
  }
}
