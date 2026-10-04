import Synchronization

/// A connection can retire after parsing while its input is still in the pump.
/// The lease survives that queue and is checked immediately before dispatch.
package final class InputConnectionLease: Sendable {
  private let live = Mutex(true)

  package init() {}
  package var isCurrent: Bool { live.withLock { $0 } }
  package func retire() { live.withLock { $0 = false } }
}

package enum InputOrigin: Sendable {
  case terminal
  case browser
}

package struct ScopedInputEvent: Sendable {
  package var event: InputEvent
  package let origin: InputOrigin
  package let lease: InputConnectionLease?

  package init(_ event: InputEvent, origin: InputOrigin, lease: InputConnectionLease? = nil) {
    self.event = event
    self.origin = origin
    self.lease = lease
  }

  package var isCurrent: Bool { lease?.isCurrent ?? true }
}

/// Internal ingress keeps provenance without changing public input payloads.
package protocol ScopedInputReading: TerminalInputReading {
  func scopedInputEvents() -> AsyncStream<ScopedInputEvent>
}

package enum InputDispatchContext {
  @TaskLocal package static var origin: InputOrigin?
}
