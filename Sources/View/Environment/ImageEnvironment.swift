package import Core

private enum ImageResourceRootsKey: EnvironmentKey {
  static let defaultValue: [String] = []
}

package typealias ImageAssetResolver =
  @Sendable (ImageSource, [String], Size) -> ResolvedImageAsset?

extension EnvironmentValues {
  public var imageResourceRoots: [String] {
    get { self[ImageResourceRootsKey.self] }
    set { self[ImageResourceRootsKey.self] = newValue }
  }
}
