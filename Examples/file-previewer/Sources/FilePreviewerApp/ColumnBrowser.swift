public import Foundation
public import SwiftTUI
import SwiftTUITerminal

public struct ColumnBrowser: View {
  @State private var path: [URL]
  @State private var selection: [URL: URL] = [:]
  @State private var activeColumn: Int = 0
  @State private var previewSession: TerminalProcessSession?
  @State private var previewedURL: URL?
  @FocusState private var isFocused: Bool

  private let registry: PreviewerRegistry

  public init(
    path: [URL],
    registry: PreviewerRegistry = .defaults
  ) {
    let normalizedPath =
      path.isEmpty
      ? [URL(fileURLWithPath: FileManager.default.currentDirectoryPath)]
      : path
    _path = State(initialValue: normalizedPath)
    self.registry = registry
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      header
      Divider()
      MillerLayout {
        ForEach(path.indices, id: \.self) { index in
          let directory = path[index]
          FileColumn(
            directory: directory,
            entries: entries(in: directory),
            selection: selection[directory],
            isActive: index == activeColumn
          )
        }

        previewPane
      }
    }
    .padding(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .focusable(true)
    .focused($isFocused)
    .defaultFocus($isFocused, true)
    .onKeyPress(perform: handleKeyPress)
  }

  private var header: some View {
    HStack(spacing: 2) {
      Text("File Previewer")
        .foregroundStyle(.tint)
      Text(activeDirectory.path)
        .foregroundStyle(.separator)
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer()
      Text(previewedURL?.lastPathComponent ?? "no preview")
        .foregroundStyle(.muted)
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }

  @ViewBuilder
  private var previewPane: some View {
    if let previewSession {
      TerminalView(session: previewSession)
        .border(.separator)
    } else {
      VStack(alignment: .leading, spacing: 1) {
        Text("Preview")
          .foregroundStyle(.muted)
        Divider()
        Text("(select a file)")
          .foregroundStyle(.separator)
      }
      .padding(1)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .border(.separator)
    }
  }

  private var activeDirectory: URL {
    path[min(activeColumn, max(0, path.count - 1))]
  }

  private func entries(in directory: URL) -> [FileEntry] {
    FileEntry.entries(in: directory)
  }

  private func handleKeyPress(_ keyPress: KeyPress) -> KeyPressResult {
    switch keyPress {
    case KeyPress(.arrowUp):
      moveSelection(by: -1)
      return .handled
    case KeyPress(.arrowDown):
      moveSelection(by: 1)
      return .handled
    case KeyPress(.arrowLeft):
      moveToParentColumn()
      return .handled
    case KeyPress(.arrowRight), KeyPress(.return):
      advanceOrPreview(directory: activeDirectory, selected: selection[activeDirectory])
      return .handled
    default:
      return .ignored
    }
  }

  private func moveSelection(by delta: Int) {
    let directory = activeDirectory
    let fileEntries = entries(in: directory)
    guard !fileEntries.isEmpty else {
      selection[directory] = nil
      clearDescendants(after: directory)
      return
    }

    let selectedURL = selection[directory]
    let currentIndex =
      selectedURL.flatMap { selected in
        fileEntries.firstIndex { $0.url == selected }
      } ?? (delta >= 0 ? -1 : fileEntries.count)
    let nextIndex = min(max(currentIndex + delta, 0), fileEntries.count - 1)
    let selected = fileEntries[nextIndex]
    selection[directory] = selected.url
    advanceOrPreview(directory: directory, selected: selected.url)
  }

  private func moveToParentColumn() {
    guard activeColumn > 0 else {
      return
    }
    activeColumn -= 1
    clearDescendants(after: activeDirectory)
    previewSession = nil
    previewedURL = nil
  }

  private func advanceOrPreview(
    directory: URL,
    selected: URL?
  ) {
    guard let selected else {
      previewSession = nil
      previewedURL = nil
      clearDescendants(after: directory)
      return
    }

    let isDirectory =
      (try? selected.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    if isDirectory {
      let prefix = pathPrefix(through: directory)
      path = prefix + [selected]
      activeColumn = max(0, path.count - 1)
      previewSession = nil
      previewedURL = nil
    } else {
      clearDescendants(after: directory)
      let command = registry.command(for: selected)
      previewSession = TerminalProcessSession(
        command: command.executable,
        arguments: command.arguments(selected),
        initialSize: CellSize(width: 80, height: 40)
      )
      previewedURL = selected
    }
  }

  private func pathPrefix(through directory: URL) -> [URL] {
    guard let index = path.firstIndex(of: directory) else {
      return [directory]
    }
    return Array(path.prefix(index + 1))
  }

  private func clearDescendants(after directory: URL) {
    path = pathPrefix(through: directory)
    activeColumn = min(activeColumn, max(0, path.count - 1))
  }
}

private struct FileColumn: View {
  var directory: URL
  var entries: [FileEntry]
  var selection: URL?
  var isActive: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(directory.lastPathComponent.isEmpty ? directory.path : directory.lastPathComponent)
        .foregroundStyle(isActive ? .tint : .muted)
        .lineLimit(1)
        .truncationMode(.middle)
      Divider()

      if entries.isEmpty {
        Text("(empty)")
          .foregroundStyle(.separator)
      } else {
        ForEach(entries, id: \.url) { entry in
          row(for: entry)
        }
      }

      Spacer(minLength: 0)
    }
    .padding(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .border(isActive ? .tint : .separator)
  }

  private func row(for entry: FileEntry) -> some View {
    HStack(spacing: 1) {
      Text(entry.url == selection ? ">" : " ")
        .foregroundStyle(.tint)
      Text(entry.displayName)
        .foregroundStyle(entry.url == selection ? .foreground : .separator)
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }
}
