import SwiftTUI
import Testing

@testable import SwiftUIHost

@MainActor
@Test
func host_announcer_suppresses_first_frame_and_announces_changed_labels() {
  var announcer = HostedAccessibilityAnnouncer()

  let first = announcer.announcements(
    for: snapshot([
      liveNode("Status", label: "Loading", politeness: .polite)
    ])
  )
  let second = announcer.announcements(
    for: snapshot([
      liveNode("Status", label: "Loaded", politeness: .polite)
    ])
  )

  #expect(first.isEmpty)
  #expect(second == [.init(politeness: .polite, label: "Loaded")])
}

@MainActor
@Test
func host_announcer_orders_assertive_before_polite() {
  var announcer = HostedAccessibilityAnnouncer()
  _ = announcer.announcements(
    for: snapshot([
      liveNode("Polite", label: "Idle", politeness: .polite),
      liveNode("Assertive", label: "Ready", politeness: .assertive),
    ])
  )

  let output = announcer.announcements(
    for: snapshot([
      liveNode("Polite", label: "Saved", politeness: .polite),
      liveNode("Assertive", label: "Failed", politeness: .assertive),
    ])
  )

  #expect(
    output == [
      .init(politeness: .assertive, label: "Failed"),
      .init(politeness: .polite, label: "Saved"),
    ])
}

@MainActor
@Test
func host_announcer_orders_mixed_imperative_and_live_region_changes() {
  var announcer = HostedAccessibilityAnnouncer()
  _ = announcer.announcements(
    for: snapshot([
      liveNode("Status", label: "Idle", politeness: .polite)
    ])
  )

  let output = announcer.announcements(
    for: SemanticSnapshot(
      accessibilityNodes: [
        liveNode("Status", label: "Saved", politeness: .polite)
      ],
      accessibilityAnnouncements: [
        AccessibilityAnnouncement(message: "Failed", politeness: .assertive)
      ]
    )
  )

  #expect(
    output == [
      .init(politeness: .assertive, label: "Failed"),
      .init(politeness: .polite, label: "Saved"),
    ])
}

@MainActor
@Test
func host_announcer_suppresses_unchanged_removed_reappeared_and_off_regions() {
  var announcer = HostedAccessibilityAnnouncer()
  _ = announcer.announcements(
    for: snapshot([
      liveNode("Status", label: "Loading", politeness: .polite),
      liveNode("Off", label: "Quiet", politeness: .off),
    ])
  )

  let unchanged = announcer.announcements(
    for: snapshot([
      liveNode("Status", label: "Loading", politeness: .polite),
      liveNode("Off", label: "Noisy", politeness: .off),
    ])
  )
  let removed = announcer.announcements(for: snapshot([]))
  let reappeared = announcer.announcements(
    for: snapshot([
      liveNode("Status", label: "Loaded", politeness: .polite)
    ])
  )

  #expect(unchanged.isEmpty)
  #expect(removed.isEmpty)
  #expect(reappeared.isEmpty)
}

@MainActor
@Test
func host_announcer_sanitizes_live_region_labels() {
  var announcer = HostedAccessibilityAnnouncer()
  _ = announcer.announcements(
    for: snapshot([
      liveNode("Status", label: "Loading", politeness: .polite)
    ])
  )

  let output = announcer.announcements(
    for: snapshot([
      liveNode("Status", label: "  Loaded\n✓  ", politeness: .polite)
    ])
  )

  #expect(output == [.init(politeness: .polite, label: "Loaded ?")])
}

@MainActor
@Test
func host_announcer_emits_imperative_announcements_without_live_region_baseline() {
  var announcer = HostedAccessibilityAnnouncer()

  let output = announcer.announcements(
    for: SemanticSnapshot(
      accessibilityAnnouncements: [
        AccessibilityAnnouncement(message: "Saved\n✓", politeness: .assertive),
        AccessibilityAnnouncement(message: "Queued", politeness: .polite),
      ]
    )
  )

  #expect(
    output == [
      .init(politeness: .assertive, label: "Saved ?"),
      .init(politeness: .polite, label: "Queued"),
    ])
}

private func snapshot(
  _ nodes: [AccessibilityNode]
) -> SemanticSnapshot {
  SemanticSnapshot(accessibilityNodes: nodes)
}

private func liveNode(
  _ id: String,
  label: String,
  politeness: AccessibilityPoliteness
) -> AccessibilityNode {
  AccessibilityNode(
    identity: Identity(components: [id]),
    rect: .init(origin: .zero, size: .init(width: 1, height: 1)),
    role: .status,
    label: label,
    liveRegion: politeness
  )
}
