import SwiftTUICore

/// Semantic review state belongs to a terminal session, never to the application's focus.
package struct TerminalReaderModel {
  package struct ReviewIdentity: Hashable {
    var source: Identity
    var occurrence: Int
  }
  package struct Chunk: Equatable {
    var id: ReviewIdentity
    var parent: ReviewIdentity?
    var node: AccessibilityNode
    var text: String
  }

  package private(set) var chunks: [Chunk] = []
  package var current: ReviewIdentity?
  package var sections = false
  package var announcesUpdates = false
  package var paused = false
  package private(set) var history: [String] = []
  package private(set) var pending: [String] = []
  package private(set) var historyEvicted = false
  package private(set) var updatesEvicted = false
  private var sequence: UInt64?
  private var focusGeneration: UInt64?
  private var modal: Identity?
  private var modalReturns: [(scope: Identity, previous: ReviewIdentity?)] = []
  private var progressUpdates: [ReviewIdentity: String] = [:]

  package var currentChunk: Chunk? { chunks.first { $0.id == current } }

  /// Frames may repaint without changing meaning. Only semantic changes enter the update queue.
  package mutating func update(_ frame: SemanticHostFrame) -> [String] {
    if let sequence, frame.sequence <= sequence { return [] }
    let initial = sequence == nil
    sequence = frame.sequence
    let old = Dictionary(
      chunks.map { ($0.id, $0.text) }, uniquingKeysWith: { a, _ in a })
    let oldPosition = chunks.firstIndex { $0.id == current } ?? 0
    let visible = Self.visibleNodes(frame.semantics.accessibilityNodes)
    let nodes = Self.meaningfulNodes(Self.readableNodes(visible))
    let byID = Dictionary(nodes.map { ($0.identity, $0) }, uniquingKeysWith: { a, _ in a })
    // Public identities intentionally omit duplicate-ForEach occurrence suffixes.
    // Review must still visit every node. Actions always retain the committed token.
    var occurrences: [Identity: Int] = [:]
    var parents: [Identity: ReviewIdentity] = [:]
    chunks = nodes.map { node in
      let source = node.actionIdentity ?? node.identity
      let occurrence = occurrences[source, default: 0]
      occurrences[source] = occurrence + 1
      let key = ReviewIdentity(source: source, occurrence: occurrence)
      let parent = node.parentIdentity.flatMap { parents[$0] }
      parents[node.identity] = key
      return .init(id: key, parent: parent, node: node, text: Self.describe(node, nodes: byID))
    }
    let nextModal = nodes.first { $0.properties?.modal == true }?.identity
    var notices: [String] = []
    if nextModal != modal {
      let visibleScopes = Set(visible.filter { $0.properties?.modal == true }.map(\.identity))
      while let top = modalReturns.last, !visibleScopes.contains(top.scope) {
        current = top.previous
        modalReturns.removeLast()
        notices.append("Returned from modal reading scope.")
      }
      if let nextModal, modalReturns.last?.scope != nextModal {
        modalReturns.append((nextModal, current))
        if modalReturns.count > 32 { modalReturns.removeFirst() }
        current = chunks.first { $0.node.identity == nextModal }?.id
        notices.append("Entered modal reading scope.")
      }
      modal = nextModal
    }
    if !chunks.contains(where: { $0.id == current }) {
      if current != nil {
        notices.append("Previous chunk removed. Review moved to a remaining chunk.")
      }
      current = chunks.isEmpty ? nil : chunks[min(oldPosition, chunks.count - 1)].id
    }
    if let focus = frame.semantics.accessibilityFocusRequest, focus.generation != focusGeneration {
      focusGeneration = focus.generation
      if let node = chunks.first(where: { $0.node.actionTarget == focus.target }) {
        current = node.id
        notices.append("Application moved assistive focus. " + node.text)
      }
    }
    let wasEmpty = pending.isEmpty && progressUpdates.isEmpty
    for chunk in chunks {
      guard let before = old[chunk.id] else {
        if !initial { enqueue("New: " + chunk.text) }
        continue
      }
      guard before != chunk.text else { continue }
      let message = "Update: " + chunk.text
      let completed: Bool
      if case .number(let value) = chunk.node.control?.value,
        let maximum = chunk.node.control?.maximum
      {
        completed = value >= maximum
      } else {
        completed = false
      }
      if !completed && chunk.node.properties?.invalid != true
        && (chunk.node.role == .progressBar || chunk.node.role == .timer)
      {
        // Keep the latest progress per live node; errors and imperative completions remain ordered.
        if progressUpdates.count < 128 || progressUpdates[chunk.id] != nil {
          progressUpdates[chunk.id] = message
        } else {
          updatesEvicted = true
        }
      } else {
        progressUpdates.removeValue(forKey: chunk.id)
        enqueue(message)
      }
    }
    for announcement in frame.semantics.accessibilityAnnouncements
    where announcement.politeness != .off {
      enqueue(
        "\(announcement.politeness == .assertive ? "Urgent" : "Announcement"): "
          + Self.safe(announcement.message))
    }
    if announcesUpdates && !paused {
      // Intermediate progress remains available on demand, even in announce mode.
      // Completion/error changes enter the ordered queue above.
      notices += takeUpdates(includeProgress: false)
    } else if wasEmpty && (!pending.isEmpty || !progressUpdates.isEmpty) && !paused {
      notices.append("Updates queued. Use updates to review.")
    }
    return notices
  }

  package mutating func read() -> String {
    guard let index = chunks.firstIndex(where: { $0.id == current }) else {
      return "No readable content in this scene. Use updates or grid."
    }
    var text = "Current \(index + 1) of \(chunks.count). " + chunks[index].text
    if sections {
      text += chunks.filter { $0.parent == current }
        .map { "\n" + $0.text }.joined()
    }
    text = Self.safe(text, limit: 16_384)
    history.append(text)
    while history.count > 128 || history.reduce(0, { $0 + $1.utf8.count }) > 131_072 {
      history.removeFirst()
      historyEvicted = true
    }
    return text
  }

  package mutating func navigate(_ direction: Int) -> String {
    guard let index = chunks.firstIndex(where: { $0.id == current }) else {
      return read()
    }
    let target = index + direction
    guard chunks.indices.contains(target) else {
      return direction > 0
        ? "End of review. Use actions on a collection to reach offscreen records."
        : "Start of review."
    }
    current = chunks[target].id
    return read()
  }

  package mutating func hierarchy(up: Bool) -> String {
    let target =
      up
      ? currentChunk?.parent
      : chunks.first { $0.parent == current }?.id
    guard let target else {
      return up ? "No parent chunk." : "No child chunk."
    }
    current = target
    return read()
  }

  package mutating func find(_ query: String) -> String {
    guard !query.isEmpty else { return "Usage: find TEXT" }
    let start = (chunks.firstIndex { $0.id == current } ?? -1) + 1
    for offset in 0..<chunks.count {
      let index = (start + offset) % chunks.count
      if Self.fullText(chunks[index].node).lowercased().contains(query.lowercased())
        || chunks[index].text.lowercased().contains(query.lowercased())
      {
        current = chunks[index].id
        return read()
      }
    }
    return
      "No match in current semantic content. Collection search actions can reach unmounted records."
  }

  package func textPage(from offset: Int) -> String {
    guard let node = currentChunk?.node else { return "No current chunk." }
    guard node.role != .secureField else { return "Protected value." }
    let text = Self.fullText(node)
    guard offset >= 0 && offset <= text.count else {
      return "Text position must be between 0 and \(text.count)."
    }
    let page = String(text.dropFirst(offset).prefix(2048))
    return Self.safe(page, limit: 32_768)
      + "\nCharacters \(offset) to \(offset + page.count) of \(text.count). Use text \(offset + page.count) to continue."
  }

  private static func fullText(_ node: AccessibilityNode) -> String {
    guard node.role != .secureField else { return node.label ?? "Protected value" }
    if case .text(let text) = node.control?.value { return text }
    return [node.label, node.properties?.description, node.hint].compactMap { $0 }.joined(
      separator: "\n")
  }

  package var categories: [String] {
    ["Headings", "Controls", "Links"]
      + Set(chunks.flatMap { $0.node.navigationCategories }).sorted()
  }

  package mutating func category(_ name: String) -> String {
    let start = (chunks.firstIndex { $0.id == current } ?? -1) + 1
    for offset in 0..<chunks.count {
      let index = (start + offset) % chunks.count
      let node = chunks[index].node
      let matches: Bool
      switch name.lowercased() {
      case "headings":
        if case .heading = node.role {
          matches = true
        } else {
          matches = node.properties?.headingLevel != nil
        }
      case "controls": matches = node.control?.actions.isEmpty == false
      case "links": matches = node.role == .link
      default: matches = node.navigationCategories.contains { $0.lowercased() == name.lowercased() }
      }
      if matches {
        current = chunks[index].id
        return read()
      }
    }
    return "No matching category in current content. Use categories for navigation groups."
  }

  package mutating func takeUpdates(includeProgress: Bool = true) -> [String] {
    var result = pending
    if includeProgress {
      result += progressUpdates.sorted {
        ($0.key.source.path, $0.key.occurrence) < ($1.key.source.path, $1.key.occurrence)
      }.map(\.value)
    }
    if updatesEvicted {
      result.insert("Older pending updates were evicted by the storage limit.", at: 0)
    }
    pending.removeAll(keepingCapacity: true)
    if includeProgress { progressUpdates.removeAll(keepingCapacity: true) }
    updatesEvicted = false
    return result
  }

  private mutating func enqueue(_ message: String) {
    pending.append(Self.safe(message))
    while pending.count > 128 || pending.reduce(0, { $0 + $1.utf8.count }) > 131_072 {
      pending.removeFirst()
      updatesEvicted = true
    }
  }

  package static func safe(_ text: String, limit: Int = 8192) -> String {
    var result = ""
    var count = 0
    for scalar in text.unicodeScalars {
      if count == limit {
        result += "\n[Text truncated; use text review or an application data action.]"
        break
      }
      let value = scalar.value
      guard
        value == 10 || value == 9
          || (value >= 32 && !(127...159).contains(value)
            && !(0x202A...0x202E).contains(value) && !(0x2066...0x2069).contains(value)
            && value != 0x061C && value != 0x200E && value != 0x200F)
      else { continue }
      result.unicodeScalars.append(scalar)
      count += 1
    }
    return result
  }

  private static func visibleNodes(_ source: [AccessibilityNode]) -> [AccessibilityNode] {
    let byID = Dictionary(source.map { ($0.identity, $0) }, uniquingKeysWith: { a, _ in a })
    return source.filter { node in
      var next: Identity? = node.identity
      var seen: Set<Identity> = []
      while let id = next, seen.insert(id).inserted, let ancestor = byID[id] {
        if ancestor.hidden { return false }
        next = ancestor.parentIdentity
      }
      return true
    }
  }

  private static func meaningfulNodes(_ source: [AccessibilityNode]) -> [AccessibilityNode] {
    let byID = Dictionary(source.map { ($0.identity, $0) }, uniquingKeysWith: { a, _ in a })
    let retained = source.filter { node in
      node.role != .group || node.control != nil || node.properties != nil
        || !node.navigationCategories.isEmpty || !(node.label ?? "").isEmpty
        || !(node.hint ?? "").isEmpty
    }
    let identities = Set(retained.map(\.identity))
    return retained.map { node in
      var node = node
      var parent = node.parentIdentity
      var seen: Set<Identity> = []
      while let id = parent, !identities.contains(id), seen.insert(id).inserted {
        parent = byID[id]?.parentIdentity
      }
      node.parentIdentity = parent
      return node
    }
  }

  private static func readableNodes(_ source: [AccessibilityNode]) -> [AccessibilityNode] {
    let byID = Dictionary(source.map { ($0.identity, $0) }, uniquingKeysWith: { a, _ in a })
    let modal = source.last { !$0.hidden && $0.properties?.modal == true }?.identity
    return source.filter { node in
      var next: Identity? = node.identity
      var seen: Set<Identity> = []
      var inModal = modal == nil
      while let id = next, seen.insert(id).inserted, let ancestor = byID[id] {
        if ancestor.hidden { return false }
        if id == modal { inModal = true }
        next = ancestor.parentIdentity
      }
      return inModal && (!node.hidden)
    }
  }

  private static func describe(_ node: AccessibilityNode, nodes: [Identity: AccessibilityNode])
    -> String
  {
    let p = node.properties
    var parts = [node.role.description]
    if let label = node.label, !label.isEmpty { parts.append(label) }
    for id in p?.labelledBy ?? [] {
      if let label = nodes[id]?.label { parts.append(label) }
    }
    if node.role == .secureField {
      parts.append("Protected value")
    } else if let description = p?.valueDescription {
      parts.append(description)
    } else if let value = node.control?.value {
      switch value {
      case .boolean(let value): parts.append(value ? "On" : "Off")
      case .number(let value): parts.append(String(value))
      case .text(let text):
        let value = node.control?.selection?.options.first { $0.id == text }?.label ?? text
        if value != node.label { parts.append(value) }
      }
    }
    if let minimum = node.control?.minimum, let maximum = node.control?.maximum {
      parts.append("Range \(minimum) to \(maximum)")
    }
    if !node.isEnabled { parts.append("Disabled") }
    if p?.readOnly == true { parts.append("Read only") }
    if p?.required == true { parts.append("Required") }
    if p?.invalid == true { parts.append("Invalid") }
    if p?.busy == true { parts.append("Busy") }
    if let selected = p?.selected { parts.append(selected ? "Selected" : "Not selected") }
    if let expanded = p?.expanded { parts.append(expanded ? "Expanded" : "Collapsed") }
    if let row = p?.rowIndex { parts.append("Row \(row)") }
    if let column = p?.columnIndex { parts.append("Column \(column)") }
    if let count = p?.rowCount { parts.append("\(count) rows") }
    if let count = p?.columnCount { parts.append("\(count) columns") }
    if let position = p?.positionInSet { parts.append("Item \(position) of \(p?.setSize ?? -1)") }
    if let level = p?.level { parts.append("Level \(level)") }
    if let level = p?.headingLevel { parts.append("Heading level \(level)") }
    if let language = p?.language { parts.append("Language \(language)") }
    if let kind = p?.textKind, kind != .plain { parts.append(kind.rawValue) }
    if let sort = p?.sort { parts.append("Sort \(sort.rawValue)") }
    if let text = p?.description { parts.append(text) }
    if let text = node.hint { parts.append(text) }
    for id in (p?.describedBy ?? []) + (p?.errorMessage ?? []) {
      if let text = nodes[id]?.label { parts.append(text) }
    }
    if node.control?.actions.isEmpty == false {
      parts.append("Use actions for available operations")
    }
    return safe(parts.joined(separator: ". "))
  }
}
