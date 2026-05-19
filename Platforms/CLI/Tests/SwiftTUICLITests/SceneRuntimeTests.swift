import Dispatch
@_spi(Runners) import SwiftTUI
@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@testable import SwiftTUICLI

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@Suite
@MainActor
struct SceneRuntimeTests {
  @Test("RuntimeConfiguration.debug enables frame diagnostics")
  func debugConfigurationEnablesFrameDiagnostics() {
    #expect(
      SceneRuntime.diagnosticsFilePath(
        configuration: .init(debug: true),
        environment: [:]
      ) == "/tmp/termui-diagnostics.tsv")
    #expect(
      SceneRuntime.diagnosticsFilePath(
        configuration: .default,
        environment: [:]
      ) == nil)
  }

  @Test("TERMUI_DIAGNOSTICS custom path still controls diagnostics output")
  func termuiDiagnosticsCustomPathControlsDiagnosticsOutput() {
    #expect(
      SceneRuntime.diagnosticsFilePath(
        configuration: .init(debug: true),
        environment: ["TERMUI_DIAGNOSTICS": "/tmp/custom-swifttui.tsv"]
      ) == "/tmp/custom-swifttui.tsv")
    #expect(
      SceneRuntime.diagnosticsFilePath(
        configuration: .default,
        environment: ["TERMUI_DIAGNOSTICS": "yes"]
      ) == "/tmp/termui-diagnostics.tsv")
    #expect(
      SceneRuntime.diagnosticsFilePath(
        configuration: .default,
        environment: ["TERMUI_DIAGNOSTICS": "0"]
      ) == nil)
  }

  @Test("Secondary scene input end suspends and reattaches")
  func secondarySceneSuspendsAndReattaches() async throws {
    let selection = collectWindowSceneSelections(
      from: WindowGroup("Secondary", id: WindowIdentifier("secondary")) {
        Text("Secondary")
      }
    )[0]

    let invocationCount = Mutex<Int>(0)
    let attachmentEvents = Mutex<[Bool]>([])
    // Fired by the test to release the first mock session; AsyncEvent.wait()
    // is cancellation-aware, so the second session parks on a never-fired
    // event until the runtime's run task is cancelled.
    let firstSessionShouldEnd = AsyncEvent()
    // Notified on every lifecycle-relevant change — attachment transitions
    // (after SceneRuntime has already updated lifecycle.state) and each mock
    // session invocation — so the test awaits state poll-free.
    let lifecycleSignal = MainActorConditionSignal()
    var firstClientFD: Int32 = -1
    var secondClientFD: Int32 = -1

    let runtime = try SceneRuntime(
      selection: selection,
      isPrimary: false,
      sessionRunner: { _, _ in
        let invocation = invocationCount.withLock { count -> Int in
          count += 1
          return count
        }
        lifecycleSignal.notify()

        if invocation == 1 {
          await firstSessionShouldEnd.wait()
        } else {
          // Park until the runtime's run task is cancelled.
          await AsyncEvent().wait()
        }

        return RunLoopResult(
          finalState: SceneSessionState(),
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
          // `onAttachmentChanged` is invoked by the MainActor-isolated
          // SceneRuntime after the lifecycle state has already transitioned.
          MainActor.assumeIsolated {
            lifecycleSignal.notify()
          }
        }
      )
    }
    defer {
      firstSessionShouldEnd.fire()
      task.cancel()
      if firstClientFD >= 0 {
        sceneClose(firstClientFD)
      }
      if secondClientFD >= 0 {
        sceneClose(secondClientFD)
      }
      runtime.shutdown()
    }

    guard let slavePath = runtime.sceneInfo.ptyPath else {
      throw RuntimeTestError.missingSlavePath
    }
    #expect(runtime.lifecycle.state == .created)

    firstClientFD = sceneOpen(slavePath, O_RDWR | O_NOCTTY)
    #expect(firstClientFD >= 0)

    await lifecycleSignal.wait {
      invocationCount.withLock { $0 } == 1 && runtime.lifecycle.state == .rendering
    }

    firstSessionShouldEnd.fire()
    sceneClose(firstClientFD)
    firstClientFD = -1

    await lifecycleSignal.wait {
      runtime.lifecycle.state == .suspended
    }

    secondClientFD = sceneOpen(slavePath, O_RDWR | O_NOCTTY)
    #expect(secondClientFD >= 0)

    await lifecycleSignal.wait {
      invocationCount.withLock { $0 } == 2 && runtime.lifecycle.state == .rendering
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
