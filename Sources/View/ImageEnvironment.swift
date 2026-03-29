package import Core

private enum ImageResourceRootsKey: EnvironmentKey {
  static let defaultValue: [String] = []
}

private enum TerminalCellPixelSizeKey: EnvironmentKey {
  static let defaultValue = Size(width: 8, height: 16)
}

package typealias ImageAssetResolver =
  @Sendable (ImageSource, [String], Size) -> ResolvedImageAsset?

extension EnvironmentValues {
  public var imageResourceRoots: [String] {
    get { self[ImageResourceRootsKey.self] }
    set { self[ImageResourceRootsKey.self] = newValue }
  }

  package var terminalCellPixelSize: Size {
    get { self[TerminalCellPixelSizeKey.self] }
    set { self[TerminalCellPixelSizeKey.self] = newValue }
  }
}
