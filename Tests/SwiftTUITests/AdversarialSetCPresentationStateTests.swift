import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// F1 pass 3 (STUI-1282), area 4: state lifetime and lifecycle delivery across
/// sheet, popover, alert, navigation destination, tab dormancy and windowed
/// rows. Crosses STUI-1173/1174 (wave 2), STUI-1233/1234/1241 (wave 3) and
/// STUI-1226. Contracts: `State-Keying.md:42-46, 155-173`,
/// `Dormant-Tab-State.md:33-46, 97-110, 121-126`, `Runtime.md:117-146`.
@MainActor
@Suite(.serialized)
struct AdversarialSetCPresentationStateTests {
  // MARK: Retired writes in presentation and navigation containers

  @Test func setC245SheetRetiredWriteDoesNotSeedRepresent() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC245"), size: .init(width: 40, height: 10)
    ) { SetCPSSheetRoot(log: log) }
    defer { h.shutdown() }
    _ = try h.clickText("Open")
    let live = try #require(log.writes.last)
    live(5)
    _ = try h.render()
    try #require(h.frame.contains("leaf 5"), "\(h.frame)")
    _ = try h.clickText("Close")
    try #require(!h.frame.contains("leaf"), "\(h.frame)")
    let issues = setCRetiredWrite { live(9) }
    #expect(issues.contains { $0.message.contains("discarded") }, "\(issues.map(\.message))")
    _ = try h.clickText("Open")
    #expect(h.frame.contains("leaf 0"), "\(h.frame)")
  }

  @Test func setC246DestinationRetiredWriteDoesNotSeedRepush() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC246"), size: .init(width: 40, height: 10)
    ) { SetCPSNavigationRoot(log: log) }
    defer { h.shutdown() }
    _ = try h.clickText("Push")
    let live = try #require(log.writes.last)
    live(5)
    _ = try h.render()
    try #require(h.frame.contains("leaf 5"), "\(h.frame)")
    _ = try h.clickText("Back")
    try #require(!h.frame.contains("leaf"), "\(h.frame)")
    _ = setCRetiredWrite { live(9) }
    _ = try h.clickText("Push")
    #expect(h.frame.contains("leaf 0"), "\(h.frame)")
  }

  @Test func setC247DormantTabWriteKeepsArchivedValue() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC247"), size: .init(width: 40, height: 10)
    ) { SetCPSTabsRoot(log: log) }
    defer { h.shutdown() }
    let live = try #require(log.writes.last)
    live(3)
    _ = try h.render()
    try #require(h.frame.contains("leaf 3"), "\(h.frame)")
    log.selection = "b"
    _ = try h.renderAfterExternalMutation()
    try #require(h.frame.contains("tab b"), "\(h.frame)")
    _ = setCRetiredWrite { live(9) }
    log.selection = "a"
    _ = try h.renderAfterExternalMutation()
    #expect(h.frame.contains("leaf 3"), "\(h.frame)")
  }

  @Test func setC248RemovedTabWriteDoesNotSeedReinsertion() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC248"), size: .init(width: 40, height: 10)
    ) { SetCPSTabsRoot(log: log) }
    defer { h.shutdown() }
    let live = try #require(log.writes.last)
    live(3)
    _ = try h.render()
    log.selection = "b"
    _ = try h.renderAfterExternalMutation()
    log.includesA = false
    _ = try h.renderAfterExternalMutation()
    _ = setCRetiredWrite { live(9) }
    log.includesA = true
    log.selection = "a"
    _ = try h.renderAfterExternalMutation()
    #expect(h.frame.contains("leaf 0"), "\(h.frame)")
  }

  @Test func setC249PopoverRepresentStartsFresh() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC249"), size: .init(width: 40, height: 10)
    ) { SetCPSPopoverRoot(log: log) }
    defer { h.shutdown() }
    _ = try h.clickText("Pop")
    let live = try #require(log.writes.last)
    live(4)
    _ = try h.render()
    try #require(h.frame.contains("leaf 4"), "\(h.frame)")
    _ = try h.clickText("Close")
    try #require(!h.frame.contains("leaf"), "\(h.frame)")
    _ = try h.clickText("Pop")
    #expect(h.frame.contains("leaf 0"), "\(h.frame)")
  }

  @Test func setC250AlertActionWritesLivePresenter() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC250"), size: .init(width: 40, height: 10)
    ) { SetCPSAlertRoot(log: log) }
    defer { h.shutdown() }
    _ = try h.clickText("Warn")
    try #require(h.frame.contains("Heads up"), "\(h.frame)")
    let retained = try #require(log.alertAction)
    _ = try h.clickText("OK")
    try #require(!h.frame.contains("Heads up"), "\(h.frame)")
    retained()
    _ = try h.render()
    #expect(h.frame.contains("count 10"), "\(h.frame)")
  }

  @Test func setC251RetainedPresenterBindingWritesAfterDismissal() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC251"), size: .init(width: 40, height: 10)
    ) { SetCPSSheetRoot(log: log) }
    defer { h.shutdown() }
    _ = try h.clickText("Open")
    let binding = try #require(log.presenterBinding)
    _ = try h.clickText("Close")
    binding.wrappedValue = 6
    _ = try h.render()
    #expect(h.frame.contains("presenter 6"), "\(h.frame)")
  }

  @Test func setC252RootClosureWritesWhileDestinationPushed() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC252"), size: .init(width: 40, height: 10)
    ) { SetCPSNavigationRoot(log: log) }
    defer { h.shutdown() }
    _ = try h.clickText("Push")
    let rootWrite = try #require(log.rootWrite)
    rootWrite(7)
    _ = try h.render()
    _ = try h.clickText("Back")
    #expect(h.frame.contains("root 7"), "\(h.frame)")
  }

  // MARK: Initial onChange inside conditionals in other containers

  @Test func setC253SheetConditionalInitialChangeRuns() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC253"), size: .init(width: 40, height: 10)
    ) { SetCPSSheetRoot(log: log, initialProbe: true) }
    defer { h.shutdown() }
    try #require(log.initial.isEmpty)
    _ = try h.clickText("Open")
    try #require(h.frame.contains("cond"), "\(h.frame)")
    #expect(log.initial == ["cond"], "\(log.initial)")
  }

  @Test func setC254DestinationConditionalInitialChangeRuns() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC254"), size: .init(width: 40, height: 10)
    ) { SetCPSNavigationRoot(log: log, initialProbe: true) }
    defer { h.shutdown() }
    try #require(log.initial.isEmpty)
    _ = try h.clickText("Push")
    try #require(h.frame.contains("cond"), "\(h.frame)")
    #expect(log.initial == ["cond"], "\(log.initial)")
  }

  @Test func setC255TabConditionalInitialChangeRuns() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC255"), size: .init(width: 40, height: 10)
    ) { SetCPSTabsRoot(log: log, initialProbeInB: true) }
    defer { h.shutdown() }
    try #require(log.initial.isEmpty)
    log.selection = "b"
    _ = try h.renderAfterExternalMutation()
    try #require(h.frame.contains("cond"), "\(h.frame)")
    #expect(log.initial == ["cond"], "\(log.initial)")
  }

  @Test func setC256TabReturnRerunsInitialChange() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC256"), size: .init(width: 40, height: 10)
    ) { SetCPSTabsRoot(log: log, plainInitialInA: true) }
    defer { h.shutdown() }
    try #require(log.initial == ["plain"], "\(log.initial)")
    log.selection = "b"
    _ = try h.renderAfterExternalMutation()
    log.selection = "a"
    _ = try h.renderAfterExternalMutation()
    #expect(log.initial == ["plain", "plain"], "\(log.initial)")
  }

  @Test func setC257LazyRowConditionalInitialChangeRuns() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC257"), size: .init(width: 30, height: 6)
    ) {
      List(Array(0..<60), id: \.self) { i in SetCPSRowProbe(index: i, log: log) }
    }
    defer { h.shutdown() }
    try #require(!log.initial.contains("row 30"))
    let point = try #require(h.point(forText: "r00"))
    for _ in 0..<5 { _ = try h.scrollPointer(at: point, deltaY: 6) }
    try #require(h.frame.contains("r30"), "\(h.frame)")
    #expect(log.initial.filter { $0 == "row 30" }.count == 1, "\(log.initial)")
  }

  // MARK: Task cancellation at presentation departure

  @Test func setC258SheetTaskCancelledAtDismissal() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC258"), size: .init(width: 40, height: 10)
    ) { SetCPSSheetRoot(log: log, taskProbe: true) }
    defer { h.shutdown() }
    let baseline = h.activeTaskCount
    _ = try h.clickText("Open")
    try #require(h.activeTaskCount == baseline + 1, "\(h.activeTaskCount)")
    _ = try h.clickText("Close")
    #expect(h.activeTaskCount == baseline)
  }

  @Test func setC259DestinationTaskCancelledAtPop() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC259"), size: .init(width: 40, height: 10)
    ) { SetCPSNavigationRoot(log: log, taskProbe: true) }
    defer { h.shutdown() }
    let baseline = h.activeTaskCount
    _ = try h.clickText("Push")
    try #require(h.activeTaskCount == baseline + 1, "\(h.activeTaskCount)")
    _ = try h.clickText("Back")
    #expect(h.activeTaskCount == baseline)
  }

  @Test func setC260SheetTaskIDRestartsOnce() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC260"), size: .init(width: 40, height: 10)
    ) { SetCPSSheetRoot(log: log, taskProbe: true) }
    defer { h.shutdown() }
    let baseline = h.activeTaskCount
    _ = try h.clickText("Open")
    for _ in 0..<3 { _ = try h.clickText("Bump") }
    #expect(h.activeTaskCount == baseline + 1)
    #expect(h.activeTaskDescriptorCount == baseline + 1)
  }

  @Test func setC261WindowedRowTasksTrackRealizedRows() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC261"), size: .init(width: 30, height: 6)
    ) {
      List(Array(0..<200), id: \.self) { i in
        Text("t\(i)").task { await suspendUntilCancelled() }
      }
    }
    defer { h.shutdown() }
    let initial = h.activeTaskCount
    try #require(initial > 0 && initial < 40, "\(initial)")
    let point = try #require(h.point(forText: "t0"))
    for _ in 0..<stressIterations(full: 30, hotPath: 10) {
      _ = try h.scrollPointer(at: point, deltaY: 15)
    }
    try #require(!h.frame.contains("t0 "))
    #expect(h.activeTaskCount <= initial + 2, "\(h.activeTaskCount) vs \(initial)")
    _ = log
  }

  @Test func setC262SheetLifecycleCountsAcrossRepresent() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC262"), size: .init(width: 40, height: 10)
    ) { SetCPSSheetRoot(log: log) }
    defer { h.shutdown() }
    _ = try h.clickText("Open")
    _ = try h.clickText("Close")
    _ = try h.clickText("Open")
    #expect(log.lifecycle == ["appear", "disappear", "appear"], "\(log.lifecycle)")
  }

  @Test func setC263RemovedPresenterTakesSheetAndTask() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC263"), size: .init(width: 40, height: 10)
    ) {
      VStack(alignment: .leading, spacing: 0) {
        Text("host")
        if log.presenterShown { SetCPSSheetRoot(log: log, taskProbe: true) }
      }
    }
    defer { h.shutdown() }
    let baseline = h.activeTaskCount
    _ = try h.clickText("Open")
    try #require(h.frame.contains("leaf 0"), "\(h.frame)")
    log.presenterShown = false
    _ = try h.renderAfterExternalMutation()
    #expect(!h.frame.contains("leaf"), "\(h.frame)")
    #expect(h.activeTaskCount == baseline, "\(h.activeTaskCount) vs \(baseline)")
  }

  // MARK: Presentation from lifecycle actions (STUI-1226 neighbours)

  @Test func setC264OnAppearStateWritePresentsSheet() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC264"), size: .init(width: 40, height: 10)
    ) { SetCPSAutoPresentRoot(log: log, viaInitialChange: false) }
    defer { h.shutdown() }
    _ = try h.render()
    #expect(h.frame.contains("auto sheet"), "\(h.frame)")
    #expect(
      !ImperativeRuntimeIssueQueue.drain().contains {
        $0.code == PresentationMutationGuard.mutationDuringViewUpdateCode
      })
  }

  @Test func setC265InitialChangeActionPresentsSheet() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC265"), size: .init(width: 40, height: 10)
    ) { SetCPSAutoPresentRoot(log: log, viaInitialChange: true) }
    defer { h.shutdown() }
    _ = try h.render()
    #expect(h.frame.contains("auto sheet"), "\(h.frame)")
  }

  @Test func setC266SheetDismissesFromOwnOnAppear() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC266"), size: .init(width: 40, height: 10)
    ) { SetCPSSelfDismissRoot(log: log) }
    defer { h.shutdown() }
    _ = try h.clickText("Open")
    _ = try h.render()
    try #require(log.lifecycle.contains("appear"))
    #expect(!h.frame.contains("self dismissing"), "\(h.frame)")
  }

  @Test func setC267RekeyedSheetContentDiscardsOldWrite() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC267"), size: .init(width: 40, height: 10)
    ) { SetCPSSheetRoot(log: log, keyed: true) }
    defer { h.shutdown() }
    _ = try h.clickText("Open")
    let old = try #require(log.writes.last)
    old(5)
    _ = try h.render()
    try #require(h.frame.contains("leaf 5"), "\(h.frame)")
    _ = try h.clickText("Rekey")
    try #require(h.frame.contains("leaf 0"), "\(h.frame)")
    _ = setCRetiredWrite { old(9) }
    _ = try h.render()
    #expect(h.frame.contains("leaf 0"), "\(h.frame)")
  }

  @Test func setC268FocusReturnsToPresenterAfterDismissal() throws {
    let log = SetCPSLog()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setC268"), size: .init(width: 40, height: 10)
    ) { SetCPSSheetRoot(log: log) }
    defer { h.shutdown() }
    _ = try h.focusText("Open")
    _ = try h.pressKey(.init(.return))
    try #require(h.frame.contains("leaf 0"), "\(h.frame)")
    _ = try h.focusText("Close")
    _ = try h.pressKey(.init(.return))
    try #require(!h.frame.contains("leaf"), "\(h.frame)")
    _ = try h.pressKey(.init(.return))
    #expect(h.frame.contains("leaf 0"), "focus did not return to Open: \(h.frame)")
  }
}

// MARK: - Support

/// Runs a write against a removed owner with the soundness trace off, as
/// setC006 does, so its two deliberate diagnostics are asserted locally and
/// the suite's soundness scan still rejects unexpected ones.
@MainActor
func setCRetiredWrite(_ body: () -> Void) -> [RuntimeIssue] {
  let savedTrace = SoundnessProbeConfiguration.isTraceEnabled
  let savedSeed = SoundnessProbeConfiguration.stateSeedFallbackViolationCount
  let savedMiss = SoundnessProbeConfiguration.stateCaptureMissViolationCount
  SoundnessProbeConfiguration.isTraceEnabled = false
  defer {
    SoundnessProbeConfiguration.isTraceEnabled = savedTrace
    SoundnessProbeConfiguration.stateSeedFallbackViolationCount = savedSeed
    SoundnessProbeConfiguration.stateCaptureMissViolationCount = savedMiss
  }
  _ = ImperativeRuntimeIssueQueue.drain()
  body()
  return ImperativeRuntimeIssueQueue.drain()
}

@MainActor
private final class SetCPSLog {
  var writes: [(Int) -> Void] = []
  var rootWrite: ((Int) -> Void)?
  var alertAction: (() -> Void)?
  var presenterBinding: Binding<Int>?
  var initial: [String] = []
  var lifecycle: [String] = []
  var selection = "a"
  var includesA = true
  var presenterShown = true

  var selectionBinding: Binding<String> {
    Binding(get: { self.selection }, set: { self.selection = $0 })
  }

  func retainAlertAction(_ action: @escaping () -> Void) {
    alertAction = action
  }
}

private struct SetCPSLeaf: View {
  @State private var value = 0
  let log: SetCPSLog

  var body: some View {
    log.writes.append { value = $0 }
    return Text("leaf \(value)")
  }
}

/// The STUI-1174 shape: a conditional at the body root whose branch carries
/// the initial observer beside a sibling observer.
private struct SetCPSInitialProbe: View {
  @State private var value = 1
  @State private var sibling = 1
  let flag: Bool
  let label: String
  let log: SetCPSLog

  var body: some View {
    if flag {
      Text(label).onChange(of: value, initial: true) { log.initial.append(label) }
        .onChange(of: sibling) {}
    } else {
      Text("none")
    }
  }
}

private struct SetCPSRowProbe: View {
  let index: Int
  let log: SetCPSLog

  var body: some View {
    if index == 30 {
      Text("r\(index)").onChange(of: index, initial: true) { log.initial.append("row 30") }
    } else {
      Text(index < 10 ? "r0\(index)" : "r\(index)")
    }
  }
}

private struct SetCPSSheetContent: View {
  @Binding var isPresented: Bool
  @Binding var presenter: Int
  let log: SetCPSLog
  let initialProbe: Bool
  let taskProbe: Bool
  let keyed: Bool
  @State private var token = 0
  @State private var generation = 0

  var body: some View {
    log.presenterBinding = $presenter
    return VStack(alignment: .leading, spacing: 0) {
      if keyed {
        SetCPSLeaf(log: log).id("leaf-\(generation)")
        Button("Rekey") { generation += 1 }
      } else {
        SetCPSLeaf(log: log)
      }
      if initialProbe { SetCPSInitialProbe(flag: true, label: "cond", log: log) }
      if taskProbe {
        Text("token \(token)").task(id: token) { await suspendUntilCancelled() }
        Button("Bump") { token += 1 }
      }
      Button("Close") { isPresented = false }
    }
    .onAppear { log.lifecycle.append("appear") }
    .onDisappear { log.lifecycle.append("disappear") }
  }
}

private struct SetCPSSheetRoot: View {
  let log: SetCPSLog
  var initialProbe = false
  var taskProbe = false
  var keyed = false
  @State private var shown = false
  @State private var presenter = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("presenter \(presenter)")
      Button("Open") { shown = true }
    }
    .sheet(isPresented: $shown) {
      SetCPSSheetContent(
        isPresented: $shown, presenter: $presenter, log: log,
        initialProbe: initialProbe, taskProbe: taskProbe, keyed: keyed)
    }
  }
}

private struct SetCPSNavigationRoot: View {
  let log: SetCPSLog
  var initialProbe = false
  var taskProbe = false
  @State private var pushed = false
  @State private var rootCount = 0

  var body: some View {
    log.rootWrite = { rootCount = $0 }
    return NavigationStack {
      VStack(alignment: .leading, spacing: 0) {
        Text("root \(rootCount)")
        Button("Push") { pushed = true }
      }
      .navigationDestination(isPresented: $pushed) {
        VStack(alignment: .leading, spacing: 0) {
          SetCPSLeaf(log: log)
          if initialProbe { SetCPSInitialProbe(flag: true, label: "cond", log: log) }
          if taskProbe { Text("destination task").task { await suspendUntilCancelled() } }
          Button("Back") { pushed = false }
        }
      }
    }
  }
}

private struct SetCPSTabsRoot: View {
  let log: SetCPSLog
  var initialProbeInB = false
  var plainInitialInA = false

  var body: some View {
    TabView(selection: log.selectionBinding) {
      if log.includesA {
        Tab("A", value: "a") {
          VStack(alignment: .leading, spacing: 0) {
            SetCPSLeaf(log: log)
            if plainInitialInA {
              Text("plain").onChange(of: 1, initial: true) { log.initial.append("plain") }
            }
          }
        }
      }
      Tab("B", value: "b") {
        VStack(alignment: .leading, spacing: 0) {
          Text("tab b")
          if initialProbeInB { SetCPSInitialProbe(flag: true, label: "cond", log: log) }
        }
      }
    }
    .tabViewStyle(.literalTabs)
  }
}

private struct SetCPSPopoverRoot: View {
  let log: SetCPSLog
  @State private var shown = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Pop") { shown = true }
        .popover(isPresented: $shown) {
          VStack(alignment: .leading, spacing: 0) {
            SetCPSLeaf(log: log)
            Button("Close") { shown = false }
          }
        }
    }
  }
}

private struct SetCPSAlertRoot: View {
  let log: SetCPSLog
  @State private var alert = false
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("count \(count)")
      Button("Warn") { alert = true }
    }
    .alert("Heads up", isPresented: $alert) {
      let action = { count += 10 }
      let _ = log.retainAlertAction(action)
      // Correction C2: alert actions do not dismiss implicitly here; the
      // action clears the binding, as Dismissal-Is-Data describes.
      Button("OK") { alert = false }
    } message: {
      Text("alert body")
    }
  }
}

private struct SetCPSAutoPresentRoot: View {
  let log: SetCPSLog
  let viaInitialChange: Bool
  @State private var shown = false

  var body: some View {
    let base = Text("auto base").sheet(isPresented: $shown) { Text("auto sheet") }
    if viaInitialChange {
      base.onChange(of: 1, initial: true) { shown = true }
    } else {
      base.onAppear { shown = true }
    }
  }
}

private struct SetCPSSelfDismissRoot: View {
  let log: SetCPSLog
  @State private var shown = false

  var body: some View {
    Button("Open") { shown = true }
      .sheet(isPresented: $shown) {
        Text("self dismissing").onAppear {
          log.lifecycle.append("appear")
          shown = false
        }
      }
  }
}
