import SwiftTUICore
import SwiftTUIViews
import Synchronization

extension RuntimeIssueSink {
  /// Reports runtime issues to standard error, deferring while a terminal
  /// host owns the screen.
  ///
  /// With no owned screen, issues write to stderr immediately, as they always
  /// have. While a terminal host owns an alternate-screen session, fd 2 is
  /// the same tty as the frame the issue describes, so a raw write would
  /// corrupt the screen: instead the issue appends to `runtime-issues.log`
  /// in the active debug bundle when one is armed, and otherwise lands in a
  /// bounded deferral buffer that the CLI runner flushes to stderr after
  /// teardown restores the primary screen — including for sessions that end
  /// by throwing, which is when the warnings matter most.
  public static var standardError: RuntimeIssueSink {
    RuntimeIssueSink { issue in
      let line = issue.description + "\n"
      guard TerminalScreenOwnership.isScreenOwned else {
        Standard.Error().write(line)
        return
      }
      if let filePath = DebugLogRouter.resolvedFilePath(
        override: nil,
        bundleFileName: "runtime-issues.log"
      ), DebugLogRouter.appendToFile(line, at: filePath) {
        return
      }
      DeferredRuntimeIssueBuffer.append(line)
    }
  }

  /// Writes any screen-deferred runtime issues to standard error.
  ///
  /// The CLI runner calls this after session teardown, when the primary
  /// screen is restored and stderr is safe to write again. A no-op when
  /// nothing was deferred.
  package static func flushDeferredStandardErrorIssues() {
    let lines = DeferredRuntimeIssueBuffer.drain()
    guard !lines.isEmpty else {
      return
    }
    Standard.Error().write(lines.joined())
  }
}

/// Bounded holding buffer for runtime issues reported while a terminal host
/// owned the screen and no debug bundle was armed. Drained to stderr by
/// `RuntimeIssueSink.flushDeferredStandardErrorIssues()` after teardown.
enum DeferredRuntimeIssueBuffer {
  static let capacity = 256

  private struct State {
    var lines: [String] = []
    var droppedCount = 0
  }

  private static let state = Mutex<State>(State())

  static func append(_ line: String) {
    state.withLock { state in
      if state.lines.count < capacity {
        state.lines.append(line)
      } else {
        state.droppedCount += 1
      }
    }
  }

  /// Removes and returns the buffered lines, appending a summary line when
  /// the bounded buffer dropped issues past its capacity.
  static func drain() -> [String] {
    state.withLock { state in
      var lines = state.lines
      if state.droppedCount > 0 {
        lines.append(
          "SwiftTUI runtime issues: \(state.droppedCount) additional issue(s) "
            + "were dropped by the bounded deferral buffer.\n"
        )
      }
      state = State()
      return lines
    }
  }
}
