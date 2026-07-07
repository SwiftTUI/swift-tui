import Foundation
@_spi(Runners) import SwiftTUIProfiling
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Runtime coverage for the presentation-portal force-queue narrowing (F08
/// step 4): a selective frame with a non-empty invalidation set no longer
/// queues the portal root unconditionally. Declarative open/close and
/// source-removal prune are preserved by the post-evaluation reconcile
/// escalation, pinned here through the publication diagnostics TSV.
///
/// Serialized: the tests toggle the process-wide publication-diagnostics
/// configuration around each run.
@MainActor
@Suite(.serialized)
struct PresentationPortalForceQueueTests {
  @Test("unrelated invalidation leaves the portal root unqueued and unescalated")
  func unrelatedInvalidationLeavesPortalRootUnqueued() async throws {
    let outcome = try await runPortalForceQueueScenario(
      rootLabel: "PortalForceQueueCounterRoot",
      steps: { terminal in
        [
          .awaitCondition {
            terminal.frames.contains { $0.contains("Count 0") }
          },
          .press(KeyPress(.return)),
          .awaitCondition {
            terminal.frames.contains { $0.contains("Count 1") }
          },
          .press(KeyPress(.character("d"), modifiers: .ctrl)),
        ]
      },
      viewBuilder: {
        SheetForceQueueCounterProbe()
      }
    )

    #expect(outcome.frames.contains { $0.contains("Count 1") })
    let interactionRows = outcome.rows.filter { row in
      (Int(row["invalidated"] ?? "") ?? 0) > 0
        && row["runtime_dirty_plan_result"] == "formed"
    }
    #expect(!interactionRows.isEmpty)
    #expect(
      interactionRows.allSatisfy { row in
        row["runtime_publication_portal_root_queued"] == "0"
      }
    )
    #expect(
      interactionRows.allSatisfy { row in
        row["runtime_publication_portal_escalated"] != "1"
      }
    )
  }

  @Test("declarative sheet opens in the committed frame via reconcile escalation")
  func declarativeSheetOpensSameFrameViaEscalation() async throws {
    let outcome = try await runPortalForceQueueScenario(
      rootLabel: "PortalForceQueueSheetOpenRoot",
      steps: { terminal in
        [
          .awaitCondition {
            terminal.frames.contains { $0.contains("Open Sheet") }
          },
          .press(KeyPress(.return)),
          .awaitCondition {
            terminal.frames.contains { $0.contains("SheetBodyMarker") }
          },
          .press(KeyPress(.character("d"), modifiers: .ctrl)),
        ]
      },
      viewBuilder: {
        SheetForceQueueOpenProbe()
      }
    )

    // Same-frame visibility IS the escalation evidence for sheets: the
    // committed open frame is the eager focus-sync rerender (default focus
    // adopts into the modal), which only runs because the discarded selective
    // pass escalated and composed the sheet into its focus regions. The
    // committed row is therefore root-forced; the escalation flag is pinned
    // directly on the (focus-neutral) toast scenario instead.
    //
    // A formed row may queue the portal root only through the PRE-PLAN
    // reconcile prediction (a queued-dirty emitter for a declared source —
    // the open sheet's follow-up frames); the unconditional install-queue
    // stays retired.
    #expect(outcome.frames.contains { $0.contains("SheetBodyMarker") })
    let formedRows = outcome.rows.filter { row in
      row["runtime_dirty_plan_result"] == "formed"
    }
    #expect(!formedRows.isEmpty)
    #expect(
      formedRows.allSatisfy { row in
        row["runtime_publication_portal_root_queued"] == "0"
          || row["runtime_publication_portal_root_predicted"] == "1"
      }
    )
  }

  @Test("declarative toast open and close escalate the committed selective frame")
  func declarativeToastTogglesViaEscalation() async throws {
    let outcome = try await runPortalForceQueueScenario(
      rootLabel: "PortalForceQueueToastToggleRoot",
      steps: { terminal in
        [
          .awaitCondition {
            terminal.frames.contains { $0.contains("Toggle Toast") }
          },
          .press(KeyPress(.return)),
          .awaitCondition {
            terminal.frames.contains { $0.contains("ToastBodyMarker") }
          },
          .press(KeyPress(.return)),
          .awaitCondition {
            terminal.frames.last.map { !$0.contains("ToastBodyMarker") } ?? false
          },
          .press(KeyPress(.character("d"), modifiers: .ctrl)),
        ]
      },
      viewBuilder: {
        ToastForceQueueToggleProbe()
      }
    )

    #expect(outcome.frames.contains { $0.contains("ToastBodyMarker") })
    let finalFrame = try #require(outcome.frames.last)
    #expect(!finalFrame.contains("ToastBodyMarker"))
    // Toasts adopt no focus, so no eager focus-sync rerender replaces the
    // reconciling pass. The OPEN reaches the portal via the post-plan
    // escalation (the source is not yet declared, so the pre-plan prediction
    // cannot see it): a formed, never install-queued selective plan whose
    // emitter observation escalates. The CLOSE reaches it via the pre-plan
    // prediction instead (declared source + queued-dirty emitter), so the
    // committed close frame roots the plan at the portal directly — one
    // pass, no narrow-plan-then-escalation double resolve.
    let escalatedRows = outcome.rows.filter { row in
      row["runtime_publication_portal_escalated"] == "1"
    }
    #expect(escalatedRows.count >= 1)
    #expect(
      escalatedRows.allSatisfy { row in
        row["runtime_publication_portal_root_queued"] == "0"
          && row["runtime_dirty_plan_result"] == "formed"
      }
    )
    let predictedRows = outcome.rows.filter { row in
      row["runtime_publication_portal_root_predicted"] == "1"
    }
    #expect(predictedRows.count >= 1)
    #expect(
      predictedRows.allSatisfy { row in
        row["runtime_publication_portal_root_queued"] == "1"
      }
    )
  }

  @Test("declarative sheet dismiss prunes the overlay via reconcile escalation")
  func declarativeSheetClosesViaEscalation() async throws {
    let outcome = try await runPortalForceQueueScenario(
      rootLabel: "PortalForceQueueSheetCloseRoot",
      steps: { terminal in
        [
          .awaitCondition {
            terminal.frames.contains { $0.contains("Open Sheet") }
          },
          .press(KeyPress(.return)),
          .awaitCondition {
            terminal.frames.contains { $0.contains("SheetBodyMarker") }
          },
          .press(KeyPress(.escape)),
          .awaitCondition {
            terminal.frames.last.map { !$0.contains("SheetBodyMarker") } ?? false
          },
          .press(KeyPress(.character("d"), modifiers: .ctrl)),
        ]
      },
      viewBuilder: {
        SheetForceQueueOpenProbe()
      }
    )

    // Visibility both ways is the contract; the committed open/close frames
    // are focus-sync rerenders (focus moves into and back out of the modal),
    // so the escalation flag is pinned on the toast scenario instead.
    #expect(outcome.frames.contains { $0.contains("SheetBodyMarker") })
    let finalFrame = try #require(outcome.frames.last)
    #expect(!finalFrame.contains("SheetBodyMarker"))
  }

  @Test("removing a declared source subtree prunes its overlay")
  func declaredSourceRemovalPrunesOverlay() async throws {
    let outcome = try await runPortalForceQueueScenario(
      rootLabel: "PortalForceQueueToastRemovalRoot",
      steps: { terminal in
        [
          .awaitCondition {
            terminal.frames.contains { $0.contains("Show Toast") }
          },
          .press(KeyPress(.return)),
          .awaitCondition {
            terminal.frames.contains { $0.contains("ToastBodyMarker") }
          },
          .press(KeyPress(.tab)),
          .press(KeyPress(.return)),
          .awaitCondition {
            terminal.frames.last.map { frame in
              frame.contains("SectionRemoved") && !frame.contains("ToastBodyMarker")
            } ?? false
          },
          .press(KeyPress(.character("d"), modifiers: .ctrl)),
        ]
      },
      viewBuilder: {
        ToastForceQueueRemovalProbe()
      }
    )

    #expect(outcome.frames.contains { $0.contains("ToastBodyMarker") })
    let finalFrame = try #require(outcome.frames.last)
    #expect(finalFrame.contains("SectionRemoved"))
    #expect(!finalFrame.contains("ToastBodyMarker"))
  }

  @Test("focus-sync rerender passes do not re-carry the trigger into a portal-root pass")
  func rerenderPassesDropInertTriggerReCarry() async throws {
    let outcome = try await runPortalForceQueueScenario(
      rootLabel: "PortalForceQueueRerenderReCarryRoot",
      steps: { terminal in
        [
          .awaitCondition {
            terminal.frames.contains { $0.contains("Open Sheet") }
          },
          .press(KeyPress(.return)),
          .awaitCondition {
            terminal.frames.contains { $0.contains("SheetBodyMarker") }
          },
          .press(KeyPress(.character("x"))),
          .awaitCondition {
            terminal.frames.contains { $0.contains("x") }
          },
          .press(KeyPress(.escape)),
          .awaitCondition {
            terminal.frames.last.map { !$0.contains("SheetBodyMarker") } ?? false
          },
          .press(KeyPress(.character("d"), modifiers: .ctrl)),
        ]
      },
      viewBuilder: {
        SheetRerenderReCarryProbe()
      }
    )

    // Behavior contract: the sheet opens same-frame, focus relocates into its
    // TextField (the typed character echoes), and ESC dismisses it — all the
    // semantics the trigger's ORIGINAL invalidation (pass 1) provides.
    #expect(outcome.frames.contains { $0.contains("SheetBodyMarker") })
    #expect(outcome.frames.contains { $0.contains("x") })
    let finalFrame = try #require(outcome.frames.last)
    #expect(!finalFrame.contains("SheetBodyMarker"))
    #expect(finalFrame.contains("Background"))
    // Narrowing contract: the committed row is the focus-sync rerender pass
    // (focus relocation into/out of the modal reruns the frame body). The
    // rerender re-carries the original invalidation set for reuse-denial
    // safety, but the presentation trigger is a childless zero-size leaf —
    // re-carrying it re-queues it dirty, which predicts a portal reconcile
    // escalation and roots the ENTIRE rerender pass at the portal
    // (re-resolving background + overlay a second time each open). The
    // trigger's activation was fully consumed by the eager pass; the
    // committed rerender rows must plan narrowly.
    #expect(
      outcome.rows.allSatisfy { row in
        row["runtime_publication_portal_root_predicted"] != "1"
      }
    )
    #expect(
      outcome.rows.allSatisfy { row in
        row["runtime_publication_portal_escalated"] != "1"
      }
    )
  }

  @Test("imperative presentation still opens without the portal force-queue")
  func imperativePresentationUnaffected() async throws {
    let outcome = try await runPortalForceQueueScenario(
      rootLabel: "PortalForceQueueImperativeRoot",
      steps: { terminal in
        [
          .awaitCondition {
            terminal.frames.contains { $0.contains("Show Imperative") }
          },
          .press(KeyPress(.return)),
          .awaitCondition {
            terminal.frames.contains { $0.contains("ImpToastUp") }
          },
          .press(KeyPress(.character("d"), modifiers: .ctrl)),
        ]
      },
      viewBuilder: {
        ImperativeToastForceQueueProbe()
      }
    )

    #expect(outcome.frames.contains { $0.contains("HandleLive") })
    #expect(outcome.frames.contains { $0.contains("Presses 1") })
    #expect(outcome.frames.contains { $0.contains("ImpToastUp") })
  }
}

// MARK: - Live-state handle unit probe

extension PresentationPortalForceQueueTests {
  @Test("live-state handles present onto the live registry and survive a draft publish")
  func liveStateHandlePresentsOntoLiveRegistry() {
    let state = PresentationPortalState()
    var environment = EnvironmentValues()
    state.injectHandles(
      into: &environment,
      hostIdentity: testIdentity("Host"),
      invalidator: nil
    )

    let portalEntryID = PortalEntryID(
      sourceIdentity: Identity(components: ["__ImperativePresentation", "unit-toast"]),
      token: "unit-toast"
    )
    // Present while a draft is in flight: the publish must replay the
    // operation instead of wiping it.
    let draft = state.makeDraft()
    environment.toastPresentationCoordinator.present(
      ToastPresentationItem(
        id: "unit-toast",
        portalEntryID: portalEntryID,
        contentPayloads: portalAttachmentDeclaredBuilderChildren(
          from: Text("UnitToast"),
          portalEntryID: portalEntryID,
          modalPolicy: .nonModal
        ),
        presentation: AnyToastStyle.info.presentation(for: ToastStyleConfiguration()),
        duration: nil,
        dismiss: {}
      )
    )
    #expect(state.overlayEntries().count == 1)
    draft.commit()
    #expect(state.overlayEntries().count == 1)
    #expect(state.makeDraft().overlayEntries().count == 1)
  }
}

// MARK: - Scenario Runner

private struct PortalForceQueueOutcome {
  var frames: [String]
  var rows: [[String: String]]
}

@MainActor
private func runPortalForceQueueScenario<V: View>(
  rootLabel: String,
  steps: (PortalForceQueueRecordingTerminalHost) -> [PortalForceQueueInputStep],
  viewBuilder: @escaping @MainActor () -> V
) async throws -> PortalForceQueueOutcome {
  let wasEnabled = RuntimeRegistrationPublicationDiagnosticsConfiguration.isEnabled
  RuntimeRegistrationPublicationDiagnosticsConfiguration.isEnabled = true
  defer {
    RuntimeRegistrationPublicationDiagnosticsConfiguration.isEnabled = wasEnabled
  }

  let terminal = PortalForceQueueRecordingTerminalHost(
    surfaceSize: .init(width: 60, height: 16)
  )
  let rootIdentity = testIdentity(rootLabel)
  let diagnosticsURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("termui-portal-force-queue-\(UUID().uuidString).tsv")
  defer {
    try? FileManager.default.removeItem(at: diagnosticsURL)
  }

  let timeoutLog = PortalForceQueueTimeoutLog()
  let inputReader = PortalForceQueueAwaitedInputReader(
    frameSignal: terminal.frameSignal,
    timeoutLog: timeoutLog,
    steps: steps(terminal)
  )
  let runLoop = RunLoop(
    rootIdentity: rootIdentity,
    presentationSurface: terminal,
    inputReader: inputReader,
    signalReader: PortalForceQueueEmptySignalReader(),
    stateContainer: StateContainer(
      initialState: 0,
      invalidationIdentities: [rootIdentity]
    ),
    focusTracker: FocusTracker(invalidationIdentities: [rootIdentity]),
    proposal: .init(width: 60, height: 16),
    viewBuilder: { _, _ in
      viewBuilder()
    }
  )
  runLoop.frameSink = TSVFileSink(path: diagnosticsURL.path)

  let result = try await runLoop.run()
  #expect(result.exitReason == .userExit(KeyPress(.character("d"), modifiers: .ctrl)))
  if !timeoutLog.timedOutSteps.isEmpty {
    Issue.record(
      """
      input steps \(timeoutLog.timedOutSteps) timed out awaiting their frame \
      condition; last frames:
      \(terminal.frames.suffix(3).joined(separator: "\n=== frame ===\n"))
      """
    )
  }

  let diagnostics = try String(contentsOf: diagnosticsURL, encoding: .utf8)
  try? diagnostics.write(toFile: "/tmp/pfq-last.tsv", atomically: true, encoding: .utf8)
  return PortalForceQueueOutcome(
    frames: terminal.frames,
    rows: portalForceQueueDiagnosticRows(diagnostics)
  )
}

// MARK: - Fixtures

private struct SheetForceQueueCounterProbe: View {
  @State private var count = 0
  @State private var isPresented = false

  var body: some View {
    VStack {
      Button("Count \(count)") {
        count += 1
      }
      Text("Filler")
        .sheet(isPresented: $isPresented) {
          Text("SheetBodyMarker")
        }
    }
  }
}

private struct SheetForceQueueOpenProbe: View {
  @State private var isPresented = false

  var body: some View {
    VStack {
      Button("Open Sheet") {
        isPresented = true
      }
      .sheet(isPresented: $isPresented) {
        Text("SheetBodyMarker")
      }
      Text("Background")
    }
  }
}

private struct SheetRerenderReCarryProbe: View {
  @State private var isPresented = false

  var body: some View {
    VStack {
      Button("Open Sheet") {
        isPresented = true
      }
      .sheet(isPresented: $isPresented) {
        SheetRerenderReCarryContent()
      }
      Text("Background")
    }
  }
}

/// Sheet content modeled on the gallery command palette: a TextField that
/// takes default focus on open, so the open frame is guaranteed to run the
/// focus-sync rerender (relocation into the modal).
private struct SheetRerenderReCarryContent: View {
  @State private var query = ""
  @Namespace private var focusNamespace

  var body: some View {
    VStack {
      Text("SheetBodyMarker")
      TextField("Query", text: $query)
        .prefersDefaultFocus(in: focusNamespace)
    }
    .focusScope(focusNamespace)
  }
}

private struct ToastForceQueueToggleProbe: View {
  @State private var isPresented = false

  var body: some View {
    VStack {
      Button("Toggle Toast") {
        isPresented.toggle()
      }
      .toast(isPresented: $isPresented, duration: nil) {
        Text("ToastBodyMarker")
      }
      Text("Background")
    }
  }
}

private struct ToastForceQueueRemovalProbe: View {
  @State private var showsSection = true
  @State private var isPresented = false

  var body: some View {
    VStack {
      if showsSection {
        Button("Show Toast") {
          isPresented = true
        }
        .toast(isPresented: $isPresented, duration: nil) {
          Text("ToastBodyMarker")
        }
      } else {
        Text("SectionRemoved")
      }
      Button("Remove Section") {
        showsSection = false
      }
    }
  }
}

private struct ImperativeToastForceQueueProbe: View {
  var body: some View {
    ImperativeToastForceQueueButton()
  }
}

private struct ImperativeToastForceQueueButton: View {
  @Environment(\.toastPresentationCoordinator) private var toastCoordinator
  @State private var presses = 0

  var body: some View {
    // Body-time read: @Environment resolves against the resolve-context
    // storage, so the handle VALUE must be captured here — a dispatch-time
    // read inside the action closure would see the environment default.
    let coordinator = toastCoordinator
    return VStack {
      Button("Show Imperative") {
        presses += 1
        let portalEntryID = PortalEntryID(
          sourceIdentity: Identity(components: ["__ImperativePresentation", "imperative-toast"]),
          token: "imperative-toast"
        )
        coordinator.present(
          ToastPresentationItem(
            id: "imperative-toast",
            portalEntryID: portalEntryID,
            contentPayloads: portalAttachmentDeclaredBuilderChildren(
              from: Text("ImpToastUp"),
              portalEntryID: portalEntryID,
              modalPolicy: .nonModal
            ),
            presentation: AnyToastStyle.info.presentation(for: ToastStyleConfiguration()),
            duration: nil,
            dismiss: {}
          )
        )
      }
      Text(toastCoordinator.isAvailable ? "HandleLive" : "HandleDead")
      Text("Presses \(presses)")
    }
  }
}

// MARK: - Harness (modeled on PortalPrimitiveTests fixtures)

private func portalForceQueueDiagnosticRows(_ text: String) -> [[String: String]] {
  let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
  guard let headerLine = lines.first else {
    return []
  }
  let headers = headerLine.components(separatedBy: "\t")
  return lines.dropFirst().map { line in
    let fields = line.components(separatedBy: "\t")
    var row: [String: String] = [:]
    for (index, header) in headers.enumerated() where index < fields.count {
      row[header] = fields[index]
    }
    return row
  }
}

private final class PortalForceQueueRecordingTerminalHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance
  private(set) var frames: [String] = []
  private var lastPresentedSurface: RasterSurface?

  let frameSignal = MainActorConditionSignal()

  init(
    surfaceSize: CellSize,
    capabilityProfile: TerminalCapabilityProfile = .previewUnicode,
    appearance: TerminalAppearance = .fallback
  ) {
    self.surfaceSize = surfaceSize
    self.capabilityProfile = capabilityProfile
    self.appearance = appearance
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let renderer = TerminalSurfaceRenderer(
      capabilityProfile: capabilityProfile
    )
    let rendered = renderer.render(surface)
    frames.append(rendered.replacingOccurrences(of: "\r\n", with: "\n"))
    lastPresentedSurface = surface
    notifyFrameObservers()
    return TerminalPresentationMetrics(
      bytesWritten: 0,
      linesTouched: 0,
      cellsChanged: 0,
      strategy: .fullRepaint
    )
  }

  func write(_ output: String) throws {
    frames.append(output.replacingOccurrences(of: "\r\n", with: "\n"))
    notifyFrameObservers()
  }

  private func notifyFrameObservers() {
    let frameSignal = self.frameSignal
    MainActor.assumeIsolated {
      frameSignal.notify()
    }
  }
}

private enum PortalForceQueueInputStep {
  case press(KeyPress)
  case awaitCondition(predicate: @MainActor () -> Bool)
}

/// Records await steps that hit their deadline so a wrong predicate fails the
/// test with diagnosable state instead of hanging the serialized suite.
@MainActor
private final class PortalForceQueueTimeoutLog {
  private(set) var timedOutSteps: [Int] = []

  func recordTimeout(step: Int) {
    timedOutSteps.append(step)
  }
}

private final class PortalForceQueueAwaitedInputReader: InputReading {
  private let steps: [PortalForceQueueInputStep]
  private let frameSignal: MainActorConditionSignal
  private let timeoutLog: PortalForceQueueTimeoutLog

  init(
    frameSignal: MainActorConditionSignal,
    timeoutLog: PortalForceQueueTimeoutLog,
    steps: [PortalForceQueueInputStep]
  ) {
    self.frameSignal = frameSignal
    self.timeoutLog = timeoutLog
    self.steps = steps
  }

  func events() -> AsyncStream<KeyPress> {
    AsyncStream { continuation in
      let steps = self.steps
      let frameSignal = self.frameSignal
      let timeoutLog = self.timeoutLog
      let task = Task { @MainActor in
        for (index, step) in steps.enumerated() {
          switch step {
          case .press(let event):
            continuation.yield(event)
          case .awaitCondition(let predicate):
            let waitTask = Task { @MainActor in
              await frameSignal.wait(until: predicate)
            }
            let timeoutTask = Task { @MainActor in
              try? await Task.sleep(for: .seconds(20))
              waitTask.cancel()
            }
            await waitTask.value
            timeoutTask.cancel()
            if !predicate() {
              timeoutLog.recordTimeout(step: index)
            }
          }
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

private final class PortalForceQueueEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { continuation in
      continuation.finish()
    }
  }
}
