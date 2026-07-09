import Testing

@testable import SwiftTUIGraph

/// Locks the duplicate-registration alarm (F104): the single-handler-per-
/// identity families (action, bare key handler, drop destination, and
/// keyCommand at binding granularity) silently overwrite on a second same-key
/// registration within one capture session. Last-write-wins stays the
/// contract; these tests pin that the overwrite now raises the
/// `duplicateRegistrationOverwriteCount` soundness alarm — and, just as
/// load-bearing, that the designed accumulation shapes (fresh capture
/// sessions, distinct identities, same-scope different-binding commands) do
/// NOT raise it.
@MainActor
@Suite("Duplicate registration probe")
struct DuplicateRegistrationProbeTests {
  /// Arms the probe latch and restores every probe global it touches, so the
  /// alarm state never leaks into unrelated suites.
  private func withArmedProbe(_ body: () throws -> Void) rethrows {
    let enabled = SoundnessProbeConfiguration.isEnabled
    let latch = SoundnessProbeConfiguration.isSampledFrame
    let count = SoundnessProbeConfiguration.duplicateRegistrationOverwriteCount
    let detail = SoundnessProbeConfiguration.lastViolationDetail
    defer {
      SoundnessProbeConfiguration.isEnabled = enabled
      SoundnessProbeConfiguration.isSampledFrame = latch
      SoundnessProbeConfiguration.duplicateRegistrationOverwriteCount = count
      SoundnessProbeConfiguration.lastViolationDetail = detail
    }
    SoundnessProbeConfiguration.isEnabled = true
    SoundnessProbeConfiguration.isSampledFrame = true
    try body()
  }

  private var alarmCount: Int {
    SoundnessProbeConfiguration.duplicateRegistrationOverwriteCount
  }

  @Test("a second same-identity action record within one capture session raises the alarm")
  func actionDoubleRecordRaisesAlarm() {
    let identity = testIdentity("Root", "Button")
    let node = RegistrationKindDriver.makeRecordingNode(identity: identity)
    withArmedProbe {
      let before = alarmCount
      ViewNodeContext.withValue(node) {
        node.recordActionRegistration(
          identity: identity, handler: { false }, followUpInvalidationIdentity: nil
        )
        #expect(alarmCount == before, "the first record must not alarm")
        node.recordActionRegistration(
          identity: identity, handler: { true }, followUpInvalidationIdentity: nil
        )
      }
      #expect(alarmCount == before + 1)
      #expect(SoundnessProbeConfiguration.lastViolationDetail?.contains("action handler") == true)
    }
  }

  @Test("distinct-identity action records within one capture session do not alarm")
  func distinctIdentityActionRecordsDoNotAlarm() {
    let node = RegistrationKindDriver.makeRecordingNode(identity: testIdentity("Root"))
    withArmedProbe {
      let before = alarmCount
      ViewNodeContext.withValue(node) {
        node.recordActionRegistration(
          identity: testIdentity("Root", "A"), handler: { false },
          followUpInvalidationIdentity: nil
        )
        node.recordActionRegistration(
          identity: testIdentity("Root", "B"), handler: { false },
          followUpInvalidationIdentity: nil
        )
      }
      #expect(alarmCount == before)
    }
  }

  @Test("re-recording the same identity in a fresh capture session does not alarm")
  func freshCaptureSessionDoesNotAlarm() {
    let identity = testIdentity("Root", "Button")
    let node = RegistrationKindDriver.makeRecordingNode(identity: identity)
    withArmedProbe {
      let before = alarmCount
      ViewNodeContext.withValue(node) {
        node.recordActionRegistration(
          identity: identity, handler: { false }, followUpInvalidationIdentity: nil
        )
      }
      // Entering a new capture session resets the node's record; the same
      // identity re-registering here is a normal re-resolve, not a collision.
      ViewNodeContext.withValue(node) {
        node.recordActionRegistration(
          identity: identity, handler: { false }, followUpInvalidationIdentity: nil
        )
      }
      #expect(alarmCount == before)
    }
  }

  @Test("a second same-identity bare key-handler record raises the alarm")
  func keyHandlerDoubleRecordRaisesAlarm() {
    let identity = testIdentity("Root", "Field")
    let node = RegistrationKindDriver.makeRecordingNode(identity: identity)
    withArmedProbe {
      let before = alarmCount
      ViewNodeContext.withValue(node) {
        node.recordKeyHandlerRegistration(identity: identity) { _ in false }
        node.recordKeyHandlerRegistration(identity: identity) { _ in true }
      }
      #expect(alarmCount == before + 1)
      #expect(SoundnessProbeConfiguration.lastViolationDetail?.contains("key handler") == true)
    }
  }

  @Test("stacked key-press contributions at one identity do not alarm")
  func stackedKeyPressContributionsDoNotAlarm() {
    let identity = testIdentity("Root", "Field")
    let node = RegistrationKindDriver.makeRecordingNode(identity: identity)
    withArmedProbe {
      let before = alarmCount
      ViewNodeContext.withValue(node) {
        node.recordKeyPressHandlerRegistration(identity: identity, ordinal: 0) { _ in false }
        node.recordKeyPressHandlerRegistration(identity: identity, ordinal: 0) { _ in false }
      }
      #expect(alarmCount == before, "contributed families append by design")
    }
  }

  @Test("a second same-scope drop-destination record raises the alarm")
  func dropDestinationDoubleRecordRaisesAlarm() {
    let scope = testIdentity("Root", "Scope")
    let node = RegistrationKindDriver.makeRecordingNode(identity: scope)
    withArmedProbe {
      let before = alarmCount
      ViewNodeContext.withValue(node) {
        node.recordDropDestinationRegistration(
          DropDestinationRegistrySnapshot(handlersByScope: [scope: { _, _ in true }])
        )
        node.recordDropDestinationRegistration(
          DropDestinationRegistrySnapshot(handlersByScope: [scope: { _, _ in false }])
        )
      }
      #expect(alarmCount == before + 1)
      #expect(
        SoundnessProbeConfiguration.lastViolationDetail?.contains("drop destination") == true
      )
    }
  }

  @Test("the keyCommand family never alarms — its live table carries over across frames")
  func keyCommandFamilyIsDeliberatelyUnchecked() {
    // The command registry is written eagerly during resolve while its live
    // table still holds the previous frame's entries, so a same-binding
    // re-registration is the NORMAL per-frame shape (a trace-enabled gate
    // run false-positived 91 times on a source-level check). The family is
    // deliberately unchecked; this pins that neither shape alarms.
    let registry = CommandRegistry()
    let scope = testIdentity("Root", "Scope")
    let binding = KeyBinding(key: .functionKey(1), modifiers: [])
    withArmedProbe {
      let before = alarmCount
      registry.registerKeyCommand(
        at: scope, binding: binding, description: "first", isEnabled: true, action: {}
      )
      registry.registerKeyCommand(
        at: scope, binding: binding, description: "replacement", isEnabled: true, action: {}
      )
      registry.registerKeyCommand(
        at: scope, binding: KeyBinding(key: .functionKey(2), modifiers: []),
        description: "second", isEnabled: true, action: {}
      )
      #expect(alarmCount == before)
    }
  }

  @Test("an out-of-session refresh over last frame's record entry does not alarm")
  func outOfSessionRefreshDoesNotAlarm() {
    // The F63 toolbar-refresh path (`ViewGraph.refreshActionRegistration`)
    // writes into a dormant node's persistent record, where the existing
    // entry is the PREVIOUS frame's registration — designed refresh, not a
    // collision. The alarm is gated on an active capture session.
    let identity = testIdentity("Root", "Toolbar", "Layout")
    let node = RegistrationKindDriver.makeRecordingNode(identity: identity)
    withArmedProbe {
      let before = alarmCount
      ViewNodeContext.withValue(node) {
        node.recordActionRegistration(
          identity: identity, handler: { false }, followUpInvalidationIdentity: nil
        )
      }
      node.recordActionRegistration(
        identity: identity, handler: { true }, followUpInvalidationIdentity: nil
      )
      #expect(alarmCount == before)
    }
  }

  @Test("an unarmed probe never alarms on a genuine duplicate")
  func unarmedProbeStaysSilent() {
    let identity = testIdentity("Root", "Button")
    let node = RegistrationKindDriver.makeRecordingNode(identity: identity)
    withArmedProbe {
      SoundnessProbeConfiguration.isSampledFrame = false
      let before = alarmCount
      ViewNodeContext.withValue(node) {
        node.recordActionRegistration(
          identity: identity, handler: { false }, followUpInvalidationIdentity: nil
        )
        node.recordActionRegistration(
          identity: identity, handler: { true }, followUpInvalidationIdentity: nil
        )
      }
      #expect(alarmCount == before, "off-sample frames must pay one Bool read, nothing more")
    }
  }
}
