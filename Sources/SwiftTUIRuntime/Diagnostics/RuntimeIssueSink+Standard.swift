import SwiftTUICore
import SwiftTUIViews
import Synchronization

extension RuntimeIssueSink {
  /// Reports to the active bundle first, then stderr if it is not an owned
  /// presentation terminal. A separate TTY, file or pipe streams live. Unsafe
  /// or failed destinations use a bounded buffer, flushed after teardown.
  public static var standardError: RuntimeIssueSink { standardError(to: 2) }

  package static func standardError(to descriptor: Int32) -> RuntimeIssueSink {
    RuntimeIssueSink { issue in
      let line = issue.description + "\n"
      if DebugLogRouter.emit(
        line,
        toFileAt: DebugLogRouter.resolvedFilePath(
          override: nil, bundleFileName: "runtime-issues.log"),
        fallback: .safeStandardError, standardErrorDescriptor: descriptor)
      {
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
    guard !TerminalScreenOwnership.isScreenOwned else { return }
    BodyChangeOutput.flushSuppressed()
    let lines = DeferredRuntimeIssueBuffer.drain()
    guard !lines.isEmpty else {
      return
    }
    if !DebugLogRouter.writeDiagnostic(lines.joined(), to: 2) {
      // Keep bounded evidence for a later successful flush; no silent loss.
      for line in lines { DeferredRuntimeIssueBuffer.append(line) }
    }
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
