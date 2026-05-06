import SwiftTUI

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

struct HostedAccessibilityAnnouncement: Equatable {
  let politeness: AccessibilityPoliteness
  let label: String
}

struct HostedAccessibilityAnnouncer: Equatable {
  private var hasBaseline = false
  private var previousLabelsByIdentity: [Identity: String] = [:]

  mutating func announcements(
    for snapshot: SemanticSnapshot
  ) -> [HostedAccessibilityAnnouncement] {
    let candidates = liveRegionCandidates(in: snapshot.accessibilityNodes)
    let currentLabelsByIdentity = Dictionary(
      uniqueKeysWithValues: candidates.map { ($0.identity, $0.label) }
    )
    defer {
      previousLabelsByIdentity = currentLabelsByIdentity
      hasBaseline = true
    }

    guard hasBaseline else {
      return []
    }

    let changed = candidates.filter { candidate in
      guard let previous = previousLabelsByIdentity[candidate.identity] else {
        return false
      }
      return previous != candidate.label
    }
    let assertive = changed.filter { $0.politeness == .assertive }
    let polite = changed.filter { $0.politeness == .polite }
    return (assertive + polite).map {
      HostedAccessibilityAnnouncement(
        politeness: $0.politeness,
        label: $0.label
      )
    }
  }

  mutating func reset() {
    hasBaseline = false
    previousLabelsByIdentity.removeAll()
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

@MainActor
enum NativeAccessibilityAnnouncementPoster {
  static func post(
    _ announcements: [HostedAccessibilityAnnouncement]
  ) {
    for announcement in announcements {
      post(announcement)
    }
  }

  private static func post(
    _ announcement: HostedAccessibilityAnnouncement
  ) {
    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
      let priority: NSAccessibilityPriorityLevel =
        announcement.politeness == .assertive ? .high : .medium
      NSAccessibility.post(
        element: NSApplication.shared,
        notification: .announcementRequested,
        userInfo: [
          .announcement: announcement.label,
          .priority: priority.rawValue,
        ]
      )
    #elseif canImport(UIKit)
      UIAccessibility.post(
        notification: .announcement,
        argument: announcement.label
      )
    #else
      _ = announcement
    #endif
  }
}

private struct LiveRegionCandidate: Equatable {
  var identity: Identity
  var politeness: AccessibilityPoliteness
  var label: String
}
