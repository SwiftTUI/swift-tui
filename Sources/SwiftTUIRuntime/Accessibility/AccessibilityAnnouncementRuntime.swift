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
    if runtimeConfiguration.output == .accessible {
      return true
    }
    guard
      let semanticHostFrameSurface =
        presentationSurface as? any SemanticHostFramePresentationSurface
    else {
      return false
    }
    return semanticHostFrameSurface.semanticHostFrameCapabilities
      .contains(.accessibilityAnnouncements)
  }

  package func drainPendingAccessibilityAnnouncements() -> [AccessibilityAnnouncement] {
    let announcements = pendingAccessibilityAnnouncements
    pendingAccessibilityAnnouncements.removeAll(keepingCapacity: true)
    return announcements
  }
}
