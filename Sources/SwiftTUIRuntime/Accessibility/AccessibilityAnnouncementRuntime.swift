import SwiftTUICore
import SwiftTUIViews

extension RunLoop: AccessibilityAnnouncementSink {
  package func announceAccessibility(_ announcement: AccessibilityAnnouncement) {
    guard publishesAccessibilityAnnouncements else {
      return
    }

    pendingAccessibilityAnnouncements.append(announcement)
    scheduler.requestInvalidation(of: [rootIdentity])
  }

  private var publishesAccessibilityAnnouncements: Bool {
    runtimeConfiguration.output == .accessible
      || presentationSurface is any SemanticPresentationSurface
  }

  package func drainPendingAccessibilityAnnouncements() -> [AccessibilityAnnouncement] {
    let announcements = pendingAccessibilityAnnouncements
    pendingAccessibilityAnnouncements.removeAll(keepingCapacity: true)
    return announcements
  }
}
