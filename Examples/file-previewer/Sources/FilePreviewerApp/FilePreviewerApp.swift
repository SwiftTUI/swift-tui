public import Foundation
public import SwiftTUI

public struct FilePreviewerRootView: View {
  private let root: URL
  private let registry: PreviewerRegistry

  public init(
    root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
    registry: PreviewerRegistry = .defaults
  ) {
    self.root = root
    self.registry = registry
  }

  public var body: some View {
    ColumnBrowser(
      path: [root],
      registry: registry
    )
  }
}
