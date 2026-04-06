import Dispatch
import Synchronization
@_spi(Runners) import TerminalUI
import Testing

@testable import TerminalUICLI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@Suite
@MainActor
struct SceneRuntimeTests {
  @Test("Secondary scene input end suspends and reattaches")
  func secondarySceneSuspendsAndReattaches() async throws {
    let selection = collectWindowSceneSelections(
      from: WindowGroup("Secondary", id: WindowIdentifier("secondary")) {
        Text("Secondary")
      }
    )[0]

    let invocationCount = Mutex<Int>(0)
    let attachmentEvents = Mutex<[Bool]>([])
    let firstSessionShouldEnd = Mutex<Bool>(false)

    let runtime = try SceneRuntime(
      selection: selection,
      isPrimary: false,
      sessionRunner: { _, _ in
        let invocation = invocationCount.withLock { count -> Int in
          count += 1
          return count
        }

        if invocation == 1 {
          while !firstSessionShouldEnd.withLock({ $0 }) {
            try? await Task.sleep(nanoseconds: 10_000_000)
          }

          return RunLoopResult(
            finalState: TerminalUISceneSessionState(),
            renderedFrames: 1,
            exitReason: .inputEnded
          )
        }

        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: 10_000_000)
        }

        return RunLoopResult(
          finalState: TerminalUISceneSessionState(),
          renderedFrames: 1,
          exitReason: .inputEnded
        )
      }
    )

    let task = Task { @MainActor in
      try await runtime.run(
        sessionName: "SceneRuntimeTests",
        onAttachmentChanged: { isAttached in
          attachmentEvents.withLock {
            $0.append(isAttached)
          }
        }
      )
    }

    guard let slavePath = runtime.sceneInfo.ptyPath else {
      throw RuntimeTestError.missingSlavePath
    }
    #expect(runtime.lifecycle.state == .created)

    var firstClientFD = sceneOpen(slavePath, O_RDWR | O_NOCTTY)
    #expect(firstClientFD >= 0)

    try await waitUntil("first attach") {
      let invocation = invocationCount.withLock { $0 }
      return invocation == 1 && runtime.lifecycle.state == .rendering
    }

    firstSessionShouldEnd.withLock {
      $0 = true
    }
    sceneClose(firstClientFD)
    firstClientFD = -1

    try await waitUntil("detach to suspended") {
      runtime.lifecycle.state == .suspended
    }

    var secondClientFD = sceneOpen(slavePath, O_RDWR | O_NOCTTY)
    #expect(secondClientFD >= 0)

    try await waitUntil("second attach") {
      let invocation = invocationCount.withLock { $0 }
      return invocation == 2 && runtime.lifecycle.state == .rendering
    }

    task.cancel()
    sceneClose(secondClientFD)
    secondClientFD = -1

    runtime.shutdown()
    _ = try? await task.value

    #expect(attachmentEvents.withLock { $0 } == [true, false, true])
  }
}

private enum RuntimeTestError: Error {
  case missingSlavePath
}

@MainActor
private func waitUntil(
  _ label: String,
  timeoutNanoseconds: UInt64 = 2_000_000_000,
  pollNanoseconds: UInt64 = 20_000_000,
  condition: @escaping @MainActor () -> Bool
) async throws {
  let start = DispatchTime.now().uptimeNanoseconds
  while !condition() {
    let elapsed = DispatchTime.now().uptimeNanoseconds - start
    if elapsed >= timeoutNanoseconds {
      throw RuntimeTestErrorTimedOut(label)
    }
    try await Task.sleep(nanoseconds: pollNanoseconds)
  }
}

private struct RuntimeTestErrorTimedOut: Error, CustomStringConvertible {
  let label: String

  init(_ label: String) {
    self.label = label
  }

  var description: String {
    "Timed out waiting for \(label)"
  }
}
