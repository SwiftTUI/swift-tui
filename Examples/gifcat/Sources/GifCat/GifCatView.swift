import SwiftTUIAnimatedImage
import Foundation
import SwiftTUI

public struct GifCatItem: Equatable, Hashable, Identifiable, Sendable {
  public var id: Int
  public var originalPath: String
  public var path: String
  public var exists: Bool
  public var animation: AnimatedImageSequence?

  public init(
    id: Int,
    originalPath: String,
    path: String,
    exists: Bool,
    animation: AnimatedImageSequence? = nil
  ) {
    self.id = id
    self.originalPath = originalPath
    self.path = path
    self.exists = exists
    self.animation = animation
  }

  public var displayName: String {
    let name = URL(fileURLWithPath: path).lastPathComponent
    return name.isEmpty ? originalPath : name
  }
}

public enum GifCatInput {
  public static func items(
    from arguments: [String],
    currentDirectory: String = FileManager.default.currentDirectoryPath
  ) -> [GifCatItem] {
    arguments.dropFirst().enumerated().map { offset, rawPath in
      let path = normalizedPath(rawPath, currentDirectory: currentDirectory)
      let exists = FileManager.default.fileExists(atPath: path)
      return GifCatItem(
        id: offset,
        originalPath: rawPath,
        path: path,
        exists: exists,
        animation: exists ? try? AnimatedGIF.decode(contentsOf: path) : nil
      )
    }
  }

  public static func normalizedPath(
    _ rawPath: String,
    currentDirectory: String = FileManager.default.currentDirectoryPath
  ) -> String {
    if rawPath.hasPrefix("file://"),
      let url = URL(string: rawPath),
      url.isFileURL
    {
      return url.standardizedFileURL.path
    }

    let expandedPath = (rawPath as NSString).expandingTildeInPath
    if expandedPath.hasPrefix("/") {
      return URL(fileURLWithPath: expandedPath).standardizedFileURL.path
    }

    let baseURL = URL(fileURLWithPath: currentDirectory, isDirectory: true)
    return URL(fileURLWithPath: expandedPath, relativeTo: baseURL)
      .standardizedFileURL
      .path
  }
}

public struct GifCatGridPlan: Equatable, Sendable {
  public var itemCount: Int
  public var columns: Int
  public var rows: Int

  public init(
    itemCount: Int
  ) {
    self.itemCount = max(0, itemCount)

    guard itemCount > 0 else {
      columns = 0
      rows = 0
      return
    }

    let targetColumns = Int(Double(itemCount).squareRoot().rounded(.up))

    columns = max(1, targetColumns)
    rows = max(1, (itemCount + columns - 1) / columns)
  }

  public func itemIndices(inRow row: Int) -> Range<Int> {
    guard row >= 0, row < rows else {
      return 0..<0
    }
    let start = row * columns
    return start..<min(start + columns, itemCount)
  }
}

public struct GifCatView: View {
  private static let imageSpacing = 1

  public var items: [GifCatItem]

  public init(items: [GifCatItem]) {
    self.items = items
  }

  public var body: some View {
    if items.isEmpty {
      emptyState
    } else {
      grid(GifCatGridPlan(itemCount: items.count))
    }
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("gifcat").foregroundStyle(.foreground)
      Text("usage: gifcat <gif> [gif ...]")
        .foregroundStyle(.muted)
    }
    .padding(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func grid(_ plan: GifCatGridPlan) -> some View {
    VStack(alignment: .leading, spacing: Self.imageSpacing) {
      ForEach(0..<plan.rows, id: \.self) { row in
        HStack(alignment: .top, spacing: Self.imageSpacing) {
          ForEach(plan.itemIndices(inRow: row), id: \.self) { index in
            tile(item: items[index])
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .clipped()
  }

  @ViewBuilder
  private func tile(
    item: GifCatItem
  ) -> some View {
    if let animation = item.animation {
      AnimatedImage(animation)
    } else if item.exists {
      Image(path: item.path)
    } else {
      Text("missing: \(item.displayName)")
        .foregroundStyle(.muted)
        .lineLimit(1)
        .truncationMode(.tail)
    }
  }
}
