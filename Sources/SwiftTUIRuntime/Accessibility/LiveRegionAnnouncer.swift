import SwiftTUICore

package struct LiveRegionAnnouncement: Equatable, Sendable {
  package var politeness: AccessibilityPoliteness
  package var label: String

  package init(
    politeness: AccessibilityPoliteness,
    label: String
  ) {
    self.politeness = politeness
    self.label = label
  }
}

package struct LiveRegionAnnouncer: Equatable, Sendable {
  private var hasBaseline = false
  private var previousLabelsByKey: [LiveRegionKey: String] = [:]

  package init() {}

  package mutating func announcements(
    for snapshot: SemanticSnapshot
  ) -> [LiveRegionAnnouncement] {
    let candidates = liveRegionCandidates(in: snapshot.accessibilityNodes)
    let currentLabelsByKey = Dictionary(
      uniqueKeysWithValues: candidates.map { ($0.key, $0.label) }
    )
    defer {
      previousLabelsByKey = currentLabelsByKey
      hasBaseline = true
    }

    guard hasBaseline else {
      return []
    }

    let changed = candidates.filter { candidate in
      guard let previous = previousLabelsByKey[candidate.key] else {
        return false
      }
      return previous != candidate.label
    }
    let assertive = changed.filter { $0.politeness == .assertive }
    let polite = changed.filter { $0.politeness == .polite }
    return (assertive + polite).map {
      LiveRegionAnnouncement(politeness: $0.politeness, label: $0.label)
    }
  }

  package mutating func renderAnnouncements(
    for snapshot: SemanticSnapshot
  ) -> String {
    let lines = ordered(announcements(for: snapshot) + imperativeAnnouncements(in: snapshot)).map {
      "\($0.politeness.description): \($0.label)"
    }
    guard !lines.isEmpty else {
      return ""
    }
    return lines.joined(separator: "\n") + "\n"
  }

  private func liveRegionCandidates(
    in nodes: [AccessibilityNode]
  ) -> [LiveRegionCandidate] {
    nodes.compactMap { node in
      guard let politeness = node.liveRegion,
        politeness != .off,
        let label = sanitized(node.label)
      else {
        return nil
      }
      return LiveRegionCandidate(
        key: node.viewNodeID.map(LiveRegionKey.viewNode) ?? .identity(node.identity),
        identity: node.identity,
        politeness: politeness,
        label: label
      )
    }
  }

  private func sanitized(
    _ value: String?
  ) -> String? {
    guard let value else {
      return nil
    }

    var scalars: [Unicode.Scalar] = []
    scalars.reserveCapacity(value.unicodeScalars.count)
    var previousWasSpace = false

    func appendSpaceIfNeeded() {
      guard !previousWasSpace else {
        return
      }
      scalars.append(Unicode.Scalar(0x20)!)
      previousWasSpace = true
    }

    for scalar in value.unicodeScalars {
      switch scalar.value {
      case 0x20:
        appendSpaceIfNeeded()
      case 0x21...0x7E:
        scalars.append(scalar)
        previousWasSpace = false
      case 0x09, 0x0A, 0x0B, 0x0C, 0x0D:
        appendSpaceIfNeeded()
      default:
        scalars.append(Unicode.Scalar(0x3F)!)
        previousWasSpace = false
      }
    }

    let trimmed = trimmingAsciiSpaces(scalars)
    guard !trimmed.isEmpty else {
      return nil
    }
    return String(String.UnicodeScalarView(trimmed))
  }

  private func imperativeAnnouncements(
    in snapshot: SemanticSnapshot
  ) -> [LiveRegionAnnouncement] {
    let announcements: [LiveRegionAnnouncement] = snapshot.accessibilityAnnouncements.compactMap {
      announcement in
      guard announcement.politeness != .off,
        let label = sanitized(announcement.message)
      else {
        return nil
      }
      return LiveRegionAnnouncement(
        politeness: announcement.politeness,
        label: label
      )
    }
    let assertive = announcements.filter { $0.politeness == .assertive }
    let polite = announcements.filter { $0.politeness == .polite }
    return assertive + polite
  }

  private func ordered(
    _ announcements: [LiveRegionAnnouncement]
  ) -> [LiveRegionAnnouncement] {
    let assertive = announcements.filter { $0.politeness == .assertive }
    let polite = announcements.filter { $0.politeness == .polite }
    return assertive + polite
  }

  private func trimmingAsciiSpaces(
    _ scalars: [Unicode.Scalar]
  ) -> [Unicode.Scalar] {
    var start = scalars.startIndex
    var end = scalars.endIndex

    while start < end, scalars[start].value == 0x20 {
      start = scalars.index(after: start)
    }
    while start < end {
      let previous = scalars.index(before: end)
      guard scalars[previous].value == 0x20 else {
        break
      }
      end = previous
    }

    return Array(scalars[start..<end])
  }
}

private struct LiveRegionCandidate: Equatable, Sendable {
  var key: LiveRegionKey
  var identity: Identity
  var politeness: AccessibilityPoliteness
  var label: String
}

private enum LiveRegionKey: Hashable, Sendable {
  case viewNode(ViewNodeID)
  case identity(Identity)
}
