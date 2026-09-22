import AppKit
import Foundation
import SwiftUI

/// Public SwiftUI/AppKit adapter. The fixture source is shared verbatim with
/// the SwiftTUI test target; no private symbols or pixel comparisons are used.
@main
@MainActor
struct PublicSemanticOracle {
  static func main() throws {
    NSApplication.shared.setActivationPolicy(.accessory)
    var results: [String: [String]] = [:]
    for name in PublicSemanticRecorder.fixtures {
      let recorder = PublicSemanticRecorder()
      let view = NSHostingView(rootView: PublicSemanticFixture(name: name, recorder: recorder))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 600, height: 100),
        styleMask: [.borderless], backing: .buffered, defer: false
      )
      window.contentView = view
      window.orderFront(nil)
      func settle() {
        // A fixed, versioned observation window, not a claimed SwiftUI
        // quiescence API. Public layout plus the main run loop drives updates.
        let deadline = Date().addingTimeInterval(0.2)
        repeat {
          view.layoutSubtreeIfNeeded()
          RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        } while Date() < deadline
      }
      settle()
      guard recorder.count == 0 else { throw Failure.unmounted(name) }
      recorder.events.removeAll()
      func action(_ key: String) throws {
        guard let perform = recorder.actions[key] else { throw Failure.missingAction(key) }
        perform()
        settle()
      }
      switch name {
      case "state-batching": try action("batch")
      case "equal-value-write": try action("equal")
      case "binding-projection": try action("project")
      default:
        try action("increment")
        try action("replace")
      }
      results[name] = recorder.events + ["final:\(recorder.count):\(recorder.pair)"]
      window.orderOut(nil)
      window.contentView = nil
    }
    let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
  }

  enum Failure: Error {
    case unmounted(String)
    case missingAction(String)
  }
}
