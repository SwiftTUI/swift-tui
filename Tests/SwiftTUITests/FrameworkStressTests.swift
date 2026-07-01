import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI framework stress behavior", .serialized)
struct FrameworkStressTests {
  @Test("mixed deferred runtime surfaces survive repeated teardown and recreation")
  func mixedDeferredRuntimeSurfacesSurviveRepeatedTeardownAndRecreation() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("MixedDeferredStressRoot"),
      size: .init(width: 72, height: 20)
    ) {
      MixedDeferredStressFixture()
    }
    defer { harness.shutdown() }

    var maxLifecycleRegistrations = harness.lifecycleRegistrationCount

    for cycle in 1...6 {
      let rootButtonPoint = try #require(harness.point(forText: "Increment Root"))

      var frame = try harness.clickText("Increment Root")
      #expect(frame.contains("Root count \(cycle)"))

      frame = try harness.clickText("Open Sheet")
      #expect(frame.contains("Sheet body"))
      #expect(frame.contains("Root count \(cycle)"))
      frame = try harness.click(rootButtonPoint)
      #expect(frame.contains("Sheet body"))
      #expect(frame.contains("Root count \(cycle)"))
      #expect(!frame.contains("Root count \(cycle + 1)"))
      frame = try harness.clickText("Close Sheet", chooseLast: true)
      #expect(!frame.contains("Sheet body"))
      #expect(frame.contains("Root count \(cycle)"))

      frame = try harness.clickText("Next Tab")
      #expect(frame.contains("Nav root"))
      #expect(frame.contains("Root count \(cycle)"))
      frame = try harness.clickText("Push Detail")
      #expect(frame.contains("Destination body"))
      frame = try harness.clickText("Pop Detail", chooseLast: true)
      #expect(!frame.contains("Destination body"))
      #expect(frame.contains("Nav root"))

      frame = try harness.clickText("Next Tab")
      #expect(frame.contains("Presentation root"))
      #expect(frame.contains("Root count \(cycle)"))
      frame = try harness.clickText("Open Confirm")
      #expect(frame.contains("Confirm body"))
      frame = try harness.clickText("Close Confirm", chooseLast: true)
      #expect(!frame.contains("Confirm body"))
      frame = try harness.clickText("Open Popover")
      #expect(frame.contains("Popover body"))
      frame = try harness.clickText("Close Popover", chooseLast: true)
      #expect(!frame.contains("Popover body"))

      frame = try harness.clickText("Next Tab")
      #expect(frame.contains("Geometry tab"))
      #expect(frame.contains("Root count \(cycle)"))
      #expect(!frame.contains("Destination body"))
      #expect(!frame.contains("Confirm body"))
      #expect(!frame.contains("Popover body"))

      maxLifecycleRegistrations = max(
        maxLifecycleRegistrations,
        harness.lifecycleRegistrationCount
      )
    }

    #expect(
      maxLifecycleRegistrations <= 24,
      """
      Deferred surface churn must not accumulate lifecycle handlers without \
      bound; max=\(maxLifecycleRegistrations)
      """
    )
  }

  @Test(".task(id:) stays bounded across lazy-tab selection, descriptor, and identity churn")
  func taskIDStaysBoundedAcrossLazyTabSelectionDescriptorAndIdentityChurn() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("TaskCancellationStressRoot"),
      size: .init(width: 48, height: 12)
    ) {
      TaskCancellationStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.activeTaskCount == 1)
    var maxActiveTasks = harness.activeTaskCount

    for generation in 1...40 {
      let frame = try harness.clickText("Cycle Task")
      maxActiveTasks = max(maxActiveTasks, harness.activeTaskCount)

      #expect(frame.contains("generation \(generation)"))
      #expect(harness.activeTaskCount == 1)
      #expect(harness.activeTaskDescriptorCount == 1)
    }

    #expect(maxActiveTasks == 1)
    harness.shutdown()
    #expect(harness.activeTaskCount == 0)
  }

  @Test("lazy tab actions keep hoisted state isolated across repeated recreation")
  func lazyTabActionsKeepHoistedStateIsolatedAcrossRepeatedRecreation() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("LazyTabStateStressRoot"),
      size: .init(width: 52, height: 12)
    ) {
      LazyTabStateStressFixture()
    }
    defer { harness.shutdown() }

    var frame = harness.frame
    #expect(frame.contains("Totals alpha 0 beta 0"))
    #expect(frame.contains("Alpha action view"))
    #expect(!frame.contains("Beta action view"))

    for iteration in 1...12 {
      frame = try harness.clickText("Increment Alpha")
      #expect(frame.contains("Totals alpha \(iteration) beta \(iteration - 1)"))
      #expect(frame.contains("Alpha action view"))
      #expect(!frame.contains("Beta action view"))

      frame = try harness.clickText("Next Counter Tab")
      #expect(frame.contains("Totals alpha \(iteration) beta \(iteration - 1)"))
      #expect(frame.contains("Beta action view"))
      #expect(!frame.contains("Alpha action view"))

      frame = try harness.clickText("Increment Beta")
      #expect(frame.contains("Totals alpha \(iteration) beta \(iteration)"))
      #expect(frame.contains("Beta action view"))
      #expect(!frame.contains("Alpha action view"))

      frame = try harness.clickText("Next Counter Tab")
      #expect(frame.contains("Totals alpha \(iteration) beta \(iteration)"))
      #expect(frame.contains("Alpha action view"))
      #expect(!frame.contains("Beta action view"))
    }
  }

  @Test("deferred presentation sources prune overlays when their owner is recreated")
  func deferredPresentationSourcesPruneOverlaysWhenTheirOwnerIsRecreated() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DeferredSourcePruningStressRoot"),
      size: .init(width: 64, height: 16)
    ) {
      DeferredSourcePruningStressFixture()
    }
    defer { harness.shutdown() }

    var sourceVersion = 0
    var maxLifecycleRegistrations = harness.lifecycleRegistrationCount

    for iteration in 1...15 {
      let surface = DeferredSourcePruningSurface(iteration: iteration)
      var frame = try harness.clickText(surface.openLabel)
      #expect(frame.contains(surface.bodyText))

      frame = try harness.clickText("Replace Source", chooseLast: true)
      sourceVersion += 1
      #expect(frame.contains("Owner version \(sourceVersion)"))
      #expect(!frame.contains("Sheet body"))
      #expect(!frame.contains("Alert body"))
      #expect(!frame.contains("Popover body"))

      maxLifecycleRegistrations = max(
        maxLifecycleRegistrations,
        harness.lifecycleRegistrationCount
      )
    }

    #expect(
      maxLifecycleRegistrations <= 24,
      """
      Presentation owner churn must prune stale overlay lifecycle handlers; \
      max=\(maxLifecycleRegistrations)
      """
    )
  }

  @Test("collection identity churn keeps row actions and tasks bounded")
  func collectionIdentityChurnKeepsRowActionsAndTasksBounded() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("CollectionIdentityChurnStressRoot"),
      size: .init(width: 48, height: 14)
    ) {
      CollectionIdentityChurnStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.activeTaskCount == CollectionIdentityChurnStressFixture.rowCount)
    #expect(
      harness.activeTaskDescriptorCount == CollectionIdentityChurnStressFixture.rowCount)

    var expectedTotal = 0
    var maxActionRegistrations = harness.actionRegistrationCount
    var maxLifecycleRegistrations = harness.lifecycleRegistrationCount
    var maxActiveTasks = harness.activeTaskCount

    for epoch in 0..<20 {
      let firstRowID = CollectionIdentityChurnStressFixture.firstRowID(for: epoch)
      expectedTotal += firstRowID

      var frame = try harness.clickText("Row \(firstRowID)")
      #expect(frame.contains("epoch \(epoch) total \(expectedTotal)"))
      #expect(harness.activeTaskCount == CollectionIdentityChurnStressFixture.rowCount)
      #expect(
        harness.activeTaskDescriptorCount == CollectionIdentityChurnStressFixture.rowCount)

      frame = try harness.clickText("Rebuild Rows")
      #expect(frame.contains("epoch \(epoch + 1) total \(expectedTotal)"))
      #expect(harness.activeTaskCount == CollectionIdentityChurnStressFixture.rowCount)
      #expect(
        harness.activeTaskDescriptorCount == CollectionIdentityChurnStressFixture.rowCount)

      maxActionRegistrations = max(maxActionRegistrations, harness.actionRegistrationCount)
      maxLifecycleRegistrations = max(
        maxLifecycleRegistrations,
        harness.lifecycleRegistrationCount
      )
      maxActiveTasks = max(maxActiveTasks, harness.activeTaskCount)
    }

    #expect(maxActiveTasks == CollectionIdentityChurnStressFixture.rowCount)
    #expect(
      maxActionRegistrations <= CollectionIdentityChurnStressFixture.rowCount + 1,
      """
      Row action registrations should stay bounded by the visible rows plus \
      the rebuild action; max=\(maxActionRegistrations)
      """
    )
    #expect(
      maxLifecycleRegistrations <= CollectionIdentityChurnStressFixture.rowCount * 2,
      """
      Row lifecycle registrations should stay bounded by the visible rows; \
      max=\(maxLifecycleRegistrations)
      """
    )
  }

  @Test("gesture branch replacement keeps recognizers and gesture state bounded")
  func gestureBranchReplacementKeepsRecognizersAndGestureStateBounded() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("GestureBranchReplacementStressRoot"),
      size: .init(width: 52, height: 10)
    ) {
      GestureBranchReplacementStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.pointerHandlerCount == 1)
    #expect(harness.gestureRecognizerCount == 1)
    #expect(harness.gestureStateBindingCount == 1)

    var expectedTotal = 0
    var maxPointerHandlers = harness.pointerHandlerCount
    var maxGestureRecognizers = harness.gestureRecognizerCount
    var maxGestureStateBindings = harness.gestureStateBindingCount

    for iteration in 1...16 {
      let start = try #require(harness.point(forText: "Drag Pad"))
      expectedTotal += 4
      var frame = try harness.drag(
        from: start,
        to: Point(x: start.x + 4, y: start.y)
      )
      #expect(frame.contains("total \(expectedTotal)"))

      frame = try harness.clickText("Swap Gesture Branch")
      #expect(frame.contains("gesture version \(iteration) total \(expectedTotal)"))
      #expect(frame.contains("Drag Pad \(iteration.isMultiple(of: 2) ? "A" : "B")"))

      maxPointerHandlers = max(maxPointerHandlers, harness.pointerHandlerCount)
      maxGestureRecognizers = max(maxGestureRecognizers, harness.gestureRecognizerCount)
      maxGestureStateBindings = max(
        maxGestureStateBindings,
        harness.gestureStateBindingCount
      )

      #expect(harness.pointerHandlerCount == 1)
      #expect(harness.gestureRecognizerCount == 1)
      #expect(harness.gestureStateBindingCount == 1)
    }

    #expect(maxPointerHandlers == 1)
    #expect(maxGestureRecognizers == 1)
    #expect(maxGestureStateBindings == 1)
  }

  @Test("navigation destinations are pruned when their source subtree is recreated")
  func navigationDestinationsArePrunedWhenTheirSourceSubtreeIsRecreated() throws {
    // Hypothesis: replacing the source owner while a destination is active must
    // retire the destination and its Escape pop action instead of carrying stale
    // navigation state into the new owner.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("NavigationSourcePruningStressRoot"),
      size: .init(width: 58, height: 12)
    ) {
      NavigationSourcePruningStressFixture()
    }
    defer { harness.shutdown() }

    var sourceVersion = 0
    var maxLifecycleRegistrations = harness.lifecycleRegistrationCount

    for iteration in 1...12 {
      var frame = try harness.clickText("Show Detail")
      #expect(frame.contains("Detail body v\(sourceVersion)"))

      frame = try harness.clickText("Replace Navigation Source")
      sourceVersion += 1
      #expect(frame.contains("Nav owner \(sourceVersion)"))
      #expect(!frame.contains("Detail body"))

      frame = try harness.pressKey(KeyPress(.escape))
      #expect(frame.contains("Nav owner \(sourceVersion)"))
      #expect(!frame.contains("Detail body"))

      maxLifecycleRegistrations = max(
        maxLifecycleRegistrations,
        harness.lifecycleRegistrationCount
      )
      #expect(
        frame.contains("Nav epoch \(iteration + 1)"),
        "replacement loop should advance monotonically without stale navigation"
      )
    }

    #expect(
      maxLifecycleRegistrations <= 16,
      """
      Navigation source churn must not accumulate destination lifecycle \
      handlers; max=\(maxLifecycleRegistrations)
      """
    )
  }

  @Test("focus owner replacement keeps focus registries bounded")
  func focusOwnerReplacementKeepsFocusRegistriesBounded() throws {
    // Hypothesis: replacing a subtree that owns @FocusState bindings and
    // namespace default-focus registrations must not accumulate stale focus
    // entries from prior owners.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("FocusOwnerReplacementStressRoot"),
      size: .init(width: 62, height: 10)
    ) {
      FocusOwnerReplacementStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.focusBindingRegistrationCount == 2)
    #expect(harness.defaultFocusRegistrationCount == 2)
    #expect(harness.focusRegionCount == 3)

    var maxFocusBindings = harness.focusBindingRegistrationCount
    var maxDefaultFocusRegistrations = harness.defaultFocusRegistrationCount
    var maxFocusRegions = harness.focusRegionCount
    var maxActions = harness.actionRegistrationCount

    for generation in 1...24 {
      let frame = try harness.clickText("Replace Focus Owner")
      #expect(frame.contains("focus owner generation \(generation)"))
      #expect(frame.contains("Primary Focus \(generation)"))
      #expect(frame.contains("Preferred Focus \(generation)"))

      maxFocusBindings = max(maxFocusBindings, harness.focusBindingRegistrationCount)
      maxDefaultFocusRegistrations = max(
        maxDefaultFocusRegistrations,
        harness.defaultFocusRegistrationCount
      )
      maxFocusRegions = max(maxFocusRegions, harness.focusRegionCount)
      maxActions = max(maxActions, harness.actionRegistrationCount)

      #expect(harness.focusBindingRegistrationCount == 2)
      #expect(harness.defaultFocusRegistrationCount == 2)
      #expect(harness.focusRegionCount == 3)
    }

    #expect(maxFocusBindings == 2)
    #expect(maxDefaultFocusRegistrations == 2)
    #expect(maxFocusRegions == 3)
    #expect(maxActions == 3)
  }

  @Test("multiple preference observers stay paired under owner churn")
  func multiplePreferenceObserversStayPairedUnderOwnerChurn() throws {
    // Hypothesis: two preference observers on the same resolved owner should
    // keep distinct registrations and both observe every changed generation as
    // the owner is repeatedly recreated.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("PreferenceObserverChurnStressRoot"),
      size: .init(width: 66, height: 8)
    ) {
      PreferenceObserverChurnStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.preferenceObservationRegistrationCount == 2)

    var expectedTotal = 0
    var maxPreferenceObservers = harness.preferenceObservationRegistrationCount
    var maxLifecycleRegistrations = harness.lifecycleRegistrationCount

    for generation in 1...24 {
      expectedTotal += generation

      let frame = try harness.clickText("Advance Preference Owner")
      #expect(frame.contains("preference generation \(generation)"))
      #expect(frame.contains("first \(expectedTotal) second \(expectedTotal)"))
      #expect(harness.preferenceObservationRegistrationCount == 2)

      maxPreferenceObservers = max(
        maxPreferenceObservers,
        harness.preferenceObservationRegistrationCount
      )
      maxLifecycleRegistrations = max(
        maxLifecycleRegistrations,
        harness.lifecycleRegistrationCount
      )
    }

    #expect(maxPreferenceObservers == 2)
    #expect(
      maxLifecycleRegistrations <= 2,
      """
      Preference owner churn must retire stale lifecycle handlers; \
      max=\(maxLifecycleRegistrations)
      """
    )
  }

  @Test("multiple task modifiers stay paired and bounded under identity churn")
  func multipleTaskModifiersStayPairedAndBoundedUnderIdentityChurn() throws {
    // Hypothesis: repeated identity and descriptor churn on a node with two
    // tasks must preserve both authored task descriptors while cancelling old
    // generations promptly.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("MultipleTaskModifierStressRoot"),
      size: .init(width: 54, height: 8)
    ) {
      MultipleTaskModifierStressFixture()
    }
    defer { harness.shutdown() }

    #expect(harness.activeTaskCount == 2)
    #expect(harness.activeTaskDescriptorCount == 2)

    withKnownIssue(
      """
      Initial render starts both tasks, but after the first button-driven \
      generation/identity churn the runtime cancels them and does not start the \
      new pair. This pins the failure while keeping the stress path in the \
      regular suite; remove the known-issue wrapper when activeTaskCount and \
      activeTaskDescriptorCount remain 2 after each Cycle Multi Tasks click.
      """
    ) {
      var maxActiveTasks = harness.activeTaskCount
      var maxTaskDescriptors = harness.activeTaskDescriptorCount

      for generation in 1...36 {
        let frame = try harness.clickText("Cycle Multi Tasks")
        maxActiveTasks = max(maxActiveTasks, harness.activeTaskCount)
        maxTaskDescriptors = max(maxTaskDescriptors, harness.activeTaskDescriptorCount)

        #expect(frame.contains("multi-task generation \(generation)"))
        if harness.activeTaskCount != 2 || harness.activeTaskDescriptorCount != 2 {
          #expect(harness.activeTaskCount == 2)
          #expect(harness.activeTaskDescriptorCount == 2)
          return
        }
      }

      #expect(maxActiveTasks == 2)
      #expect(maxTaskDescriptors == 2)
    }

    harness.shutdown()
    #expect(harness.activeTaskCount == 0)
  }
}

private struct MixedDeferredStressFixture: View {
  @State private var rootCount = 0
  @State private var selectedTab = "geometry"
  @State private var destinationPresented = false
  @State private var sheetPresented = false
  @State private var confirmationPresented = false
  @State private var popoverPresented = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Root count \(rootCount)")
      HStack(spacing: 1) {
        Button("Increment Root") { rootCount += 1 }
        Button("Next Tab") { selectedTab = nextTab(after: selectedTab) }
      }

      TabView(selection: $selectedTab) {
        Tab("Geometry", value: "geometry") {
          geometryTab
        }

        Tab("Navigation", value: "navigation") {
          navigationTab
        }

        Tab("Presentation", value: "presentation") {
          presentationTab
        }
      }
      .tabViewStyle(.literalTabs)
    }
    .frame(width: 72, height: 20, alignment: .topLeading)
  }

  private var geometryTab: some View {
    VStack(alignment: .leading, spacing: 0) {
      GeometryReader { proxy in
        VStack(alignment: .leading, spacing: 0) {
          Text("Geometry tab \(proxy.size.width)x\(proxy.size.height)")
            .onAppear {}
            .onDisappear {}
          Text("Geometry body")
        }
      }
      .frame(height: 2)

      ForEach(0..<6) { index in
        Text("Geometry row \(index)")
      }
      Button("Open Sheet") { sheetPresented = true }
    }
    .sheet("Stress Sheet", isPresented: $sheetPresented) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Sheet body")
        Button("Close Sheet") { sheetPresented = false }
      }
      .onAppear {}
      .onDisappear {}
    }
  }

  private var navigationTab: some View {
    NavigationStack(id: "mixed-deferred-stress-navigation") {
      VStack(alignment: .leading, spacing: 0) {
        Text("Nav root")
          .onAppear {}
          .onDisappear {}
        Button("Push Detail") { destinationPresented = true }
      }
      .navigationDestination(isPresented: $destinationPresented) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Destination body")
          Button("Pop Detail") { destinationPresented = false }
        }
        .onAppear {}
        .onDisappear {}
      }
    }
  }

  private var presentationTab: some View {
    let base = VStack(alignment: .leading, spacing: 0) {
      Text("Presentation root")
        .onAppear {}
        .onDisappear {}
      Button("Open Confirm") { confirmationPresented = true }
      Button("Open Popover") { popoverPresented = true }
    }

    return
      base
      .confirmationDialog(
        "Stress Confirm",
        isPresented: $confirmationPresented,
        actions: {
          Button("Close Confirm") { confirmationPresented = false }
        },
        message: {
          Text("Confirm body")
        }
      )
      .popover(isPresented: $popoverPresented, arrowEdge: .trailing) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Popover body")
          Button("Close Popover") { popoverPresented = false }
        }
        .onAppear {}
        .onDisappear {}
      }
  }

  private func nextTab(after current: String) -> String {
    switch current {
    case "geometry": "navigation"
    case "navigation": "presentation"
    default: "geometry"
    }
  }
}

private struct TaskCancellationStressFixture: View {
  @State private var selectedTab = "left"
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Cycle Task") {
        generation += 1
        selectedTab = selectedTab == "left" ? "right" : "left"
      }
      Text("selection \(selectedTab) generation \(generation)")

      TabView(selection: $selectedTab) {
        Tab("Left", value: "left") {
          TaskCancellationStressPane(label: "left", generation: generation)
            .id("left-\(generation % 5)")
        }

        Tab("Right", value: "right") {
          TaskCancellationStressPane(label: "right", generation: generation)
            .id("right-\(generation % 5)")
        }
      }
      .tabViewStyle(.literalTabs)
    }
    .frame(width: 48, height: 12, alignment: .topLeading)
  }
}

private struct TaskCancellationStressPane: View {
  let label: String
  let generation: Int

  var body: some View {
    GeometryReader { proxy in
      Text("task \(label) generation \(generation) size \(proxy.size.width)x\(proxy.size.height)")
        .task(
          id: TaskCancellationStressID(
            label: label,
            generation: generation,
            width: proxy.size.width,
            height: proxy.size.height
          )
        ) {
          while !Task.isCancelled {
            await Task.yield()
          }
        }
    }
  }
}

private struct TaskCancellationStressID: Equatable, Sendable {
  var label: String
  var generation: Int
  var width: Int
  var height: Int
}

private struct LazyTabStateStressFixture: View {
  @State private var selectedTab = "alpha"
  @State private var alphaTotal = 0
  @State private var betaTotal = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Next Counter Tab") {
        selectedTab = selectedTab == "alpha" ? "beta" : "alpha"
      }
      Text("counter selection \(selectedTab)")
      Text("Totals alpha \(alphaTotal) beta \(betaTotal)")

      TabView(selection: $selectedTab) {
        Tab("Alpha", value: "alpha") {
          LazyTabCounterPane(label: "Alpha") {
            alphaTotal += 1
          }
        }

        Tab("Beta", value: "beta") {
          LazyTabCounterPane(label: "Beta") {
            betaTotal += 1
          }
        }
      }
      .tabViewStyle(.literalTabs)
    }
    .frame(width: 52, height: 12, alignment: .topLeading)
  }
}

private struct LazyTabCounterPane: View {
  let label: String
  let increment: @MainActor () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("\(label) action view")
      Button("Increment \(label)") { increment() }
    }
    .onAppear {}
    .onDisappear {}
  }
}

private enum DeferredSourcePruningSurface {
  case sheet
  case alert
  case popover

  init(iteration: Int) {
    switch iteration % 3 {
    case 1: self = .sheet
    case 2: self = .alert
    default: self = .popover
    }
  }

  var openLabel: String {
    switch self {
    case .sheet: "Open Sheet Source"
    case .alert: "Open Alert Source"
    case .popover: "Open Popover Source"
    }
  }

  var bodyText: String {
    switch self {
    case .sheet: "Sheet body"
    case .alert: "Alert body"
    case .popover: "Popover body"
    }
  }
}

private struct DeferredSourcePruningStressFixture: View {
  @State private var sourceVersion = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Source root version \(sourceVersion)")
      DeferredSourcePruningOwner(version: sourceVersion) {
        sourceVersion += 1
      }
      .id("source-\(sourceVersion)")
    }
    .frame(width: 64, height: 16, alignment: .topLeading)
  }
}

private struct DeferredSourcePruningOwner: View {
  let version: Int
  let replaceSource: @MainActor () -> Void

  @State private var sheetPresented = false
  @State private var alertPresented = false
  @State private var popoverPresented = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Owner version \(version)")
        .onAppear {}
        .onDisappear {}
      Button("Open Sheet Source") { sheetPresented = true }
      Button("Open Alert Source") { alertPresented = true }
      Button("Open Popover Source") { popoverPresented = true }
    }
    .sheet("Source Sheet", isPresented: $sheetPresented) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Sheet body v\(version)")
        Button("Replace Source") { replaceSource() }
      }
      .onAppear {}
      .onDisappear {}
    }
    .alert(
      "Source Alert",
      isPresented: $alertPresented,
      actions: {
        Button("Replace Source") { replaceSource() }
      },
      message: {
        Text("Alert body v\(version)")
      }
    )
    .popover(isPresented: $popoverPresented, arrowEdge: .trailing) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Popover body v\(version)")
        Button("Replace Source") { replaceSource() }
      }
      .onAppear {}
      .onDisappear {}
    }
  }
}

private struct CollectionIdentityChurnStressFixture: View {
  static let rowCount = 6

  static func firstRowID(for epoch: Int) -> Int {
    epoch * 100 + 1
  }

  @State private var epoch = 0
  @State private var total = 0

  private var rowIDs: [Int] {
    (0..<Self.rowCount).map { Self.firstRowID(for: epoch) + $0 }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Rebuild Rows") { epoch += 1 }
      Text("epoch \(epoch) total \(total)")

      ForEach(rowIDs, id: \.self) { id in
        CollectionIdentityChurnRow(id: id) {
          total += id
        }
      }
    }
    .frame(width: 48, height: 14, alignment: .topLeading)
  }
}

private struct CollectionIdentityChurnRow: View {
  let id: Int
  let increment: @MainActor () -> Void

  var body: some View {
    Button("Row \(id)") { increment() }
      .onAppear {}
      .onDisappear {}
      .task(id: CollectionIdentityChurnTaskID(rowID: id)) {
        while !Task.isCancelled {
          await Task.yield()
        }
      }
  }
}

private struct CollectionIdentityChurnTaskID: Equatable, Sendable {
  var rowID: Int
}

private struct GestureBranchReplacementStressFixture: View {
  @State private var version = 0
  @State private var total = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Swap Gesture Branch") { version += 1 }
      Text("gesture version \(version) total \(total)")

      if version.isMultiple(of: 2) {
        GestureBranchReplacementPad(label: "A", version: version) { value in
          total += Int(value.translation.dx.rounded())
        }
        .id("gesture-pad-\(version)")
      } else {
        GestureBranchReplacementPad(label: "B", version: version) { value in
          total += Int(value.translation.dx.rounded())
        }
        .id("gesture-pad-\(version)")
      }
    }
    .frame(width: 52, height: 10, alignment: .topLeading)
  }
}

private struct GestureBranchReplacementPad: View {
  let label: String
  let version: Int
  let onEnded: @MainActor (DragGesture.Value) -> Void

  @GestureState private var dragOffset = Vector(dx: 0, dy: 0)

  var body: some View {
    Text("Drag Pad \(label) \(version) offset \(Int(dragOffset.dx.rounded()))")
      .frame(width: 32, height: 1, alignment: .leading)
      .gesture(
        DragGesture()
          .updating($dragOffset) { value, state, _ in
            state = value.translation
          }
          .onEnded { value in
            onEnded(value)
          }
      )
      .onAppear {}
      .onDisappear {}
  }
}

private struct NavigationSourcePruningStressFixture: View {
  @State private var sourceVersion = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Nav epoch \(sourceVersion + 1)")
      NavigationSourcePruningOwner(version: sourceVersion) {
        sourceVersion += 1
      }
      .id("navigation-source-\(sourceVersion)")
    }
    .frame(width: 58, height: 12, alignment: .topLeading)
  }
}

private struct NavigationSourcePruningOwner: View {
  let version: Int
  let replaceSource: @MainActor () -> Void

  @State private var detailPresented = false

  var body: some View {
    NavigationStack(id: "navigation-source-pruning-\(version)") {
      VStack(alignment: .leading, spacing: 0) {
        Text("Nav owner \(version)")
          .onAppear {}
          .onDisappear {}
        Button("Show Detail") { detailPresented = true }
      }
      .navigationDestination(isPresented: $detailPresented) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Detail body v\(version)")
          Button("Replace Navigation Source") { replaceSource() }
        }
        .onAppear {}
        .onDisappear {}
      }
    }
  }
}

private enum FocusOwnerReplacementField: Hashable {
  case primary
  case preferred
}

private struct FocusOwnerReplacementStressFixture: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Replace Focus Owner") { generation += 1 }
      Text("focus owner generation \(generation)")
      FocusOwnerReplacementOwner(generation: generation)
        .id("focus-owner-\(generation)")
    }
    .frame(width: 62, height: 10, alignment: .topLeading)
  }
}

private struct FocusOwnerReplacementOwner: View {
  @Namespace private var namespace
  @FocusState private var focusedField: FocusOwnerReplacementField?

  let generation: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Primary Focus \(generation)") {}
        .id(testIdentity("FocusOwnerReplacement", "\(generation)", "primary"))
        .focused($focusedField, equals: .primary)
      Button("Preferred Focus \(generation)") {}
        .id(testIdentity("FocusOwnerReplacement", "\(generation)", "preferred"))
        .focused($focusedField, equals: .preferred)
        .prefersDefaultFocus(in: namespace)
    }
    .focusScope(namespace)
    .onAppear {}
    .onDisappear {}
  }
}

private enum PreferenceObserverStressKey: PreferenceKey {
  static let defaultValue = 0

  static func reduce(value: inout Int, nextValue: () -> Int) {
    value = nextValue()
  }
}

private struct PreferenceObserverChurnStressFixture: View {
  @State private var generation = 0
  @State private var firstTotal = 0
  @State private var secondTotal = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Preference Owner") { generation += 1 }
      Text("preference generation \(generation)")
      Text("preference totals first \(firstTotal) second \(secondTotal)")
      PreferenceObserverChurnOwner(
        generation: generation,
        onFirst: { firstTotal += $0 },
        onSecond: { secondTotal += $0 }
      )
      .id("preference-owner-\(generation)")
    }
    .frame(width: 66, height: 8, alignment: .topLeading)
  }
}

private struct PreferenceObserverChurnOwner: View {
  let generation: Int
  let onFirst: @MainActor (Int) -> Void
  let onSecond: @MainActor (Int) -> Void

  var body: some View {
    Text("Preference Source \(generation)")
      .preference(key: PreferenceObserverStressKey.self, value: generation)
      .onPreferenceChange(PreferenceObserverStressKey.self) { value in
        onFirst(value)
      }
      .onPreferenceChange(PreferenceObserverStressKey.self) { value in
        onSecond(value)
      }
      .onAppear {}
      .onDisappear {}
  }
}

private struct MultipleTaskModifierStressFixture: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Cycle Multi Tasks") { generation += 1 }
      Text("multi-task generation \(generation)")
        .id("multi-task-\(generation % 7)")
        .task(id: MultipleTaskModifierStressID(slot: "first", generation: generation)) {
          while !Task.isCancelled {
            await Task.yield()
          }
        }
        .task(id: MultipleTaskModifierStressID(slot: "second", generation: generation)) {
          while !Task.isCancelled {
            await Task.yield()
          }
        }
    }
    .frame(width: 54, height: 8, alignment: .topLeading)
  }
}

private struct MultipleTaskModifierStressID: Equatable, Sendable {
  var slot: String
  var generation: Int
}

@MainActor
private final class StressRuntimeHarness<Content: View> {
  private let terminal: StressRecordingHost
  private let runLoop: SwiftTUIRuntime.RunLoop<Int, Content>
  private var renderedFrames = 0
  private var didShutdown = false

  init(
    rootIdentity: Identity,
    size: CellSize,
    @ViewBuilder content: @escaping () -> Content
  ) throws {
    let terminal = StressRecordingHost(surfaceSize: size)
    let scheduler = FrameScheduler()
    let focusTracker = FocusTracker(invalidationIdentities: [rootIdentity])
    let runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: rootIdentity,
      presentationSurface: terminal,
      inputReader: StressEmptyKeyReader(),
      signalReader: StressEmptySignalReader(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [rootIdentity]),
      focusTracker: focusTracker,
      proposal: .init(width: size.width, height: size.height),
      viewBuilder: { _, _ in content() }
    )
    focusTracker.invalidator = scheduler
    self.terminal = terminal
    self.runLoop = runLoop

    scheduler.requestInvalidation(of: [rootIdentity])
    _ = try render()
  }

  var frame: String {
    terminal.frames.last ?? ""
  }

  var activeTaskCount: Int {
    runLoop.lifecycleCoordinator.activeTaskCount
  }

  var activeTaskDescriptorCount: Int {
    runLoop.lifecycleCoordinator.activeTaskDescriptors.values.reduce(0) {
      $0 + $1.count
    }
  }

  var lifecycleRegistrationCount: Int {
    let snapshot = runLoop.localLifecycleRegistry.snapshot()
    return snapshot.appearHandlers.count
      + snapshot.disappearHandlers.count
      + snapshot.changeHandlers.count
  }

  var actionRegistrationCount: Int {
    runLoop.localActionRegistry.snapshot().count
  }

  var pointerHandlerCount: Int {
    runLoop.localPointerHandlerRegistry.snapshot().count
  }

  var gestureRecognizerCount: Int {
    runLoop.localGestureRegistry.snapshot().count
  }

  var gestureStateBindingCount: Int {
    runLoop.localGestureStateRegistry.snapshot().values.reduce(0) { count, bindings in
      count + bindings.count
    }
  }

  var defaultFocusRegistrationCount: Int {
    let snapshot = runLoop.localDefaultFocusRegistry.snapshot()
    return snapshot.scopes.count + snapshot.candidates.count
  }

  var focusBindingRegistrationCount: Int {
    runLoop.localFocusBindingRegistry.snapshot().count
  }

  var focusRegionCount: Int {
    runLoop.focusTracker.focusRegions.count
  }

  var preferenceObservationRegistrationCount: Int {
    runLoop.localPreferenceObservationRegistry.snapshot().count
  }

  func shutdown() {
    guard !didShutdown else {
      return
    }
    didShutdown = true
    runLoop.lifecycleCoordinator.shutdown()
  }

  @discardableResult
  func render() throws -> String {
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    return try #require(terminal.frames.last)
  }

  func point(forText text: String, chooseLast: Bool = false) -> Point? {
    terminal.centerOfText(text, chooseLast: chooseLast)
  }

  @discardableResult
  func clickText(_ label: String, chooseLast: Bool = false) throws -> String {
    let point = try #require(
      terminal.centerOfText(label, chooseLast: chooseLast),
      "could not find '\(label)' in frame:\n\(frame)"
    )
    return try click(point)
  }

  @discardableResult
  func click(_ point: Point) throws -> String {
    #expect(
      runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .down(.primary), location: point)))
      ) == nil
    )
    _ = try render()
    #expect(
      runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: .up(.primary), location: point)))
      ) == nil
    )
    return try render()
  }

  @discardableResult
  func pressKey(_ keyPress: KeyPress) throws -> String {
    #expect(runLoop.handleKeyPress(keyPress) == nil)
    return try render()
  }

  @discardableResult
  func drag(from start: Point, to end: Point) throws -> String {
    _ = try sendMouse(.down(.primary), at: start)
    _ = try sendMouse(.dragged(.primary), at: end)
    return try sendMouse(.up(.primary), at: end)
  }

  @discardableResult
  private func sendMouse(_ kind: MouseEvent.Kind, at point: Point) throws -> String {
    #expect(
      runLoop.handle(
        RuntimeEvent.input(InputEvent.mouse(.init(kind: kind, location: point)))
      ) == nil
    )
    return try render()
  }
}

private final class StressRecordingHost: PresentationSurface {
  let surfaceSize: CellSize
  let capabilityProfile: TerminalCapabilityProfile = .previewUnicode
  let appearance: TerminalAppearance = .fallback
  private(set) var frames: [String] = []
  private var lastPresentedSurface: RasterSurface?

  init(surfaceSize: CellSize) {
    self.surfaceSize = surfaceSize
  }

  func enableRawMode() throws {}
  func disableRawMode() throws {}
  func clearScreen() throws {}
  func moveCursor(to _: CellPoint) throws {}

  @discardableResult
  func present(_ surface: RasterSurface) throws -> TerminalPresentationMetrics {
    let rendered = TerminalSurfaceRenderer(capabilityProfile: capabilityProfile).render(surface)
    frames.append(String(rendered.filter { $0 != "\r" }))
    lastPresentedSurface = surface
    return .init(
      bytesWritten: 0,
      linesTouched: surface.size.height,
      cellsChanged: surface.size.width * surface.size.height,
      strategy: .fullRepaint
    )
  }

  func write(_ output: String) throws {
    frames.append(String(output.filter { $0 != "\r" }))
  }

  func centerOfText(_ target: String, chooseLast: Bool = false) -> Point? {
    guard let surface = lastPresentedSurface else {
      return nil
    }

    let rows = chooseLast ? Array(surface.lines.indices.reversed()) : Array(surface.lines.indices)
    for row in rows {
      let line = surface.lines[row]
      let options: String.CompareOptions = chooseLast ? .backwards : []
      guard let range = line.range(of: target, options: options) else {
        continue
      }
      let column = line.distance(from: line.startIndex, to: range.lowerBound)
      return Point(CellPoint(x: column + target.count / 2, y: row))
    }
    return nil
  }
}

private final class StressEmptyKeyReader: InputReading {
  func events() -> AsyncStream<KeyPress> {
    AsyncStream { $0.finish() }
  }
}

private final class StressEmptySignalReader: SignalReading {
  func events() -> AsyncStream<String> {
    AsyncStream { $0.finish() }
  }
}
