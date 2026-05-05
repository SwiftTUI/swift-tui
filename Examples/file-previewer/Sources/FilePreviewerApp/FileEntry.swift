public import Foundation

public struct FileEntry: Sendable, Hashable {
  public var url: URL
  public var isDirectory: Bool

  public init(
    url: URL,
    isDirectory: Bool
  ) {
    self.url = url
    self.isDirectory = isDirectory
  }

  public var displayName: String {
    let name = url.lastPathComponent
    guard !name.isEmpty else {
      return url.path
    }
    return isDirectory ? "\(name)/" : name
  }
}

extension FileEntry {
  public static func entries(
    in directory: URL,
    fileManager: FileManager = .default
  ) -> [FileEntry] {
    guard
      let urls = try? fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    return
      urls
      .map { url in
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return FileEntry(url: url, isDirectory: values?.isDirectory ?? false)
      }
      .sorted()
  }
}

extension FileEntry: Comparable {
  public static func < (lhs: FileEntry, rhs: FileEntry) -> Bool {
    if lhs.isDirectory != rhs.isDirectory {
      return lhs.isDirectory
    }
    return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
  }
}
