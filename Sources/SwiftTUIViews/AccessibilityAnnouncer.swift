public import SwiftTUICore

/// Sends app-triggered messages to assistive-technology announcement targets.
@MainActor
public enum AccessibilityAnnouncer {
  /// Announces a message through the active runtime accessibility target.
  ///
  /// Calls made outside a running SwiftTUI runtime are ignored.
  public static func announce(
    _ message: String,
    politeness: AccessibilityPoliteness = .polite
  ) {
    AccessibilityAnnouncementStorage.effectiveSink?.announceAccessibility(
      AccessibilityAnnouncement(message: message, politeness: politeness)
    )
  }
}

@MainActor
package protocol AccessibilityAnnouncementSink: AnyObject, Sendable {
  func announceAccessibility(_ announcement: AccessibilityAnnouncement)
}

@MainActor
package enum AccessibilityAnnouncementStorage {
  @TaskLocal package static var currentTaskSink: (any AccessibilityAnnouncementSink)?
  package static weak var currentSink: (any AccessibilityAnnouncementSink)?

  package static var effectiveSink: (any AccessibilityAnnouncementSink)? {
    currentTaskSink ?? currentSink
  }

  package static func withSink<Result>(
    _ sink: any AccessibilityAnnouncementSink,
    operation: () async throws -> Result
  ) async rethrows -> Result {
    try await $currentTaskSink.withValue(sink) {
      try await operation()
    }
  }
}
