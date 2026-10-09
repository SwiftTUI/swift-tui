import SwiftTUICore

/// Routes reader input to existing scene owners. No graph, state or action token is copied.
@MainActor
package final class TerminalReaderSceneHub {
  private struct Entry {
    var id: String
    var title: String?
    var surface: TerminalReaderSurface
    var input: SharedSceneInputReader
  }
  private var entries: [Entry] = []
  private var selected = 0

  package init(endpoints: [SharedSceneEndpoint]) {
    entries = endpoints.compactMap { endpoint in
      guard let surface = endpoint.surface.terminal as? TerminalReaderSurface else { return nil }
      return .init(
        id: endpoint.descriptor.id.rawValue, title: endpoint.descriptor.title,
        surface: surface, input: endpoint.input)
    }
  }

  package var selectedSurface: TerminalReaderSurface? {
    entries.indices.contains(selected) ? entries[selected].surface : nil
  }
  package var listing: String {
    "Scenes:\n"
      + entries.enumerated().map {
        "\($0.offset == selected ? "Current: " : "")\(TerminalReaderModel.safe($0.element.id))"
          + ($0.element.title.map { " — " + TerminalReaderModel.safe($0) } ?? "")
      }.joined(separator: "\n") + "\nUse scene ID to review and operate a scene."
  }

  package func select(_ id: String) -> String {
    guard let index = entries.firstIndex(where: { $0.id == id }) else {
      return "Unknown scene. " + listing
    }
    reset()
    selected = index
    guard let primary = entries.first else { return "No scenes available." }
    if index != 0 {
      primary.surface.suppressReaderPresentation = true
      entries[index].surface.externalReaderOutput =
        primary.surface.terminal as? any TerminalCommandPresentationSurface
    }
    return "Scene \(TerminalReaderModel.safe(id)).\n" + entries[index].surface.commands.model.read()
  }

  package func route(_ events: [InputEvent]) -> [InputEvent] {
    guard selected != 0, entries.indices.contains(selected) else { return events }
    for event in events { entries[selected].input.sendReaderEvent(event) }
    return []
  }

  package func reset() {
    for entry in entries {
      entry.surface.externalReaderOutput = nil
      entry.surface.suppressReaderPresentation = false
      entry.surface.commands.editor = nil
      entry.surface.commandIsBeingTyped = false
    }
    selected = 0
  }
}
