import Foundation
import SwiftTUI

public struct GifCatItem: Equatable, Hashable, Identifiable, Sendable {
  public var id: Int
  public var originalPath: String
  public var path: String
  public var exists: Bool
  public var animation: GifCatAnimation?

  public init(
    id: Int,
    originalPath: String,
    path: String,
    exists: Bool,
    animation: GifCatAnimation? = nil
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
        animation: exists ? try? GifCatAnimation.load(contentsOf: path) : nil
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
  @State private var frameIndices: [Int: Int] = [:]

  public init(items: [GifCatItem]) {
    self.items = items
  }

  public var body: some View {
    if items.isEmpty {
      emptyState
    } else {
      grid(GifCatGridPlan(itemCount: items.count))
        .task(id: playbackSignature) { @MainActor in
          await playAnimations()
        }
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
      GifCatAnimatedImage(
        animation: animation,
        frameIndex: frameIndex(for: item)
      )
    } else if item.exists {
      Image(path: item.path)
    } else {
      Text("missing: \(item.displayName)")
        .foregroundStyle(.muted)
        .lineLimit(1)
        .truncationMode(.tail)
    }
  }

  private var playbackSignature: String {
    items.map { item in
      "\(item.id):\(item.animation?.frames.count ?? 0)"
    }.joined(separator: "|")
  }

  private func frameIndex(for item: GifCatItem) -> Int {
    guard let animation = item.animation else {
      return 0
    }
    return min(frameIndices[item.id, default: 0], animation.frames.count - 1)
  }

  @MainActor
  private func playAnimations() async {
    let animatedItems = items.filter { item in
      item.animation.map { $0.frames.count > 1 } == true
    }
    guard !animatedItems.isEmpty else {
      return
    }

    var currentFrames = frameIndices
    var remainingDelays = animatedItems.reduce(into: [Int: Int]()) { delays, item in
      let frameIndex = frameIndex(for: item)
      delays[item.id] = item.animation?.frames[frameIndex].delayMilliseconds
    }

    while !Task.isCancelled {
      let sleepMilliseconds = max(20, remainingDelays.values.min() ?? 100)
      try? await Task.sleep(nanoseconds: UInt64(sleepMilliseconds) * 1_000_000)
      if Task.isCancelled {
        break
      }

      var advancedAnyFrame = false
      for item in animatedItems {
        guard let animation = item.animation else {
          continue
        }

        let currentFrame = min(currentFrames[item.id, default: 0], animation.frames.count - 1)
        let remaining =
          (remainingDelays[item.id] ?? animation.frames[currentFrame].delayMilliseconds)
          - sleepMilliseconds
        if remaining > 0 {
          remainingDelays[item.id] = remaining
          continue
        }

        let nextFrame = (currentFrame + 1) % animation.frames.count
        currentFrames[item.id] = nextFrame
        remainingDelays[item.id] = animation.frames[nextFrame].delayMilliseconds + remaining
        advancedAnyFrame = true
      }

      if advancedAnyFrame {
        frameIndices = currentFrames
      }
    }
  }
}

private struct GifCatAnimatedImage: View {
  var animation: GifCatAnimation
  var frameIndex: Int

  var body: some View {
    Image(data: animation.frames[boundedFrameIndex].bytes)
  }

  private var boundedFrameIndex: Int {
    min(frameIndex, animation.frames.count - 1)
  }
}
