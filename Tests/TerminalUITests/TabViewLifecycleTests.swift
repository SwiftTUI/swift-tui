import Testing

@testable import Core
@testable import TerminalUI
@testable import View

/// Regression tests for the "TabView speculatively resolves every tab
/// body on every frame" bug.
///
/// Before the fix, TabView resolved the whole child list up front while
/// determining labels and selection tags. The side effect was that inactive
/// tabs' .onAppear and .task handlers fired on frame 1 while the user was
/// still looking at a different tab. Because lifecycle events are scheduled
/// from the resolved tree, inactive tabs landed in the commit plan for tabs
/// the user had never visited.
///
/// The fix: enumerate declared `Tab(...)` entries, read their eager metadata
/// without resolving their bodies, and only invoke resolveView on the tab
/// whose tag matches the current selection. Inactive tabs never enter
/// beginEvaluation, so no lifecycle events fire.
@MainActor
@Suite
struct TabViewLifecycleTests {
  @Test("TabView does not fire .onAppear for inactive tab children")
  func inactiveTabsDoNotFireOnAppear() {
    let probe = LifecycleProbe()

    let lifecycleRegistry = LocalLifecycleRegistry()
    let taskRegistry = LocalTaskRegistry()
    let artifacts = DefaultRenderer().render(
      TabView(selection: .constant("home")) {
        Tab("Home", value: "home") {
          Text("Home content")
            .onAppear { probe.homeAppearCount += 1 }
        }

        Tab("Settings", value: "settings") {
          Text("Settings content")
            .onAppear { probe.settingsAppearCount += 1 }
        }

        Tab("Logs", value: "logs") {
          Text("Logs content")
            .onAppear { probe.logsAppearCount += 1 }
        }
      },
      context: .init(
        identity: testIdentity("Root"),
        localLifecycleRegistry: lifecycleRegistry,
        localTaskRegistry: taskRegistry,
        applyEnvironmentValues: true
      )
    )

    // The commit plan must contain only one appear entry — the active
    // "home" tab. If the fix regresses, all three tabs' handlers are
    // scheduled on frame 1 and at least two of these asserts will fire.
    let appearEntries = artifacts.commitPlan.lifecycle.filter {
      if case .appear = $0.operation { return true }
      return false
    }

    // Every .onAppear handler that was scheduled must belong to the
    // active tab's surface ("Home content"). Inactive surfaces must
    // contribute zero appear entries.
    LifecycleCoordinator().applyCommittedFrame(
      plan: artifacts.commitPlan,
      currentLifecycleRegistry: lifecycleRegistry,
      currentTaskRegistry: taskRegistry
    )

    #expect(probe.homeAppearCount == 1)
    #expect(probe.settingsAppearCount == 0)
    #expect(probe.logsAppearCount == 0)
    #expect(!appearEntries.isEmpty)
  }

  @Test("TabView first-time activation fires a previously-inactive tab's .onAppear")
  func firstTimeActivationFiresOnAppear() {
    let probe = LifecycleProbe()

    @MainActor
    func renderWithSelection(_ tag: String) -> FrameArtifacts {
      let lifecycleRegistry = LocalLifecycleRegistry()
      let taskRegistry = LocalTaskRegistry()
      let artifacts = DefaultRenderer().render(
        TabView(selection: .constant(tag)) {
          Tab("Home", value: "home") {
            Text("Home content")
              .onAppear { probe.homeAppearCount += 1 }
          }

          Tab("Settings", value: "settings") {
            Text("Settings content")
              .onAppear { probe.settingsAppearCount += 1 }
          }
        },
        context: .init(
          identity: testIdentity("Root"),
          localLifecycleRegistry: lifecycleRegistry,
          localTaskRegistry: taskRegistry,
          applyEnvironmentValues: true
        )
      )
      LifecycleCoordinator().applyCommittedFrame(
        plan: artifacts.commitPlan,
        currentLifecycleRegistry: lifecycleRegistry,
        currentTaskRegistry: taskRegistry
      )
      return artifacts
    }

    _ = renderWithSelection("home")
    #expect(probe.homeAppearCount == 1)
    #expect(probe.settingsAppearCount == 0)

    // Each render stands up a fresh ViewGraph (via a new renderer
    // instance), so this is really "when settings is the active tab
    // at initial render, its .onAppear fires exactly once" — which
    // is the semantic requirement: inactive tabs must not be
    // resolved speculatively, but a tab that is active the first
    // time it is rendered must light up normally.
    _ = renderWithSelection("settings")
    #expect(probe.homeAppearCount == 1)
    #expect(probe.settingsAppearCount == 1)
  }

  @Test(
    "TabView does not schedule a .task for inactive tab children"
  )
  func inactiveTabsDoNotScheduleTasks() {
    let lifecycleRegistry = LocalLifecycleRegistry()
    let taskRegistry = LocalTaskRegistry()
    let artifacts = DefaultRenderer().render(
      TabView(selection: .constant("home")) {
        Tab("Home", value: "home") {
          Text("Home content")
        }

        Tab("Settings", value: "settings") {
          Text("Settings content")
            .task(priority: .userInitiated) {
              // Must never be reached — this tab is not active.
            }
        }
      },
      context: .init(
        identity: testIdentity("Root"),
        localLifecycleRegistry: lifecycleRegistry,
        localTaskRegistry: taskRegistry,
        applyEnvironmentValues: true
      )
    )

    // No task-start entries must be present in the commit plan: the
    // tab that carries a .task is not active, and the active tab
    // carries no .task.
    let taskStarts = artifacts.commitPlan.lifecycle.filter {
      if case .taskStart = $0.operation { return true }
      return false
    }
    #expect(taskStarts.isEmpty)
  }

  @Test(
    "TabView peeks label and tag metadata from plain modifier chains without resolving inactive children"
  )
  func plainTaggedChildrenStayInactiveDuringMetadataPeeking() {
    let probe = LifecycleProbe()
    let lifecycleRegistry = LocalLifecycleRegistry()
    let taskRegistry = LocalTaskRegistry()

    let artifacts = DefaultRenderer().render(
      TabView(selection: .constant("settings")) {
        Text("Home content")
          .onAppear { probe.homeAppearCount += 1 }
          .semanticMetadata(.init(tabItemLabel: TabItemLabel("Home")))
          .tag("home")

        Text("Settings content")
          .onAppear { probe.settingsAppearCount += 1 }
          .semanticMetadata(.init(tabItemLabel: TabItemLabel("Settings")))
          .tag("settings")
      },
      context: .init(
        identity: testIdentity("Root"),
        localLifecycleRegistry: lifecycleRegistry,
        localTaskRegistry: taskRegistry,
        applyEnvironmentValues: true
      ),
      proposal: .init(width: 32, height: 4)
    )

    LifecycleCoordinator().applyCommittedFrame(
      plan: artifacts.commitPlan,
      currentLifecycleRegistry: lifecycleRegistry,
      currentTaskRegistry: taskRegistry
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Home"))
    #expect(surface.contains("Settings"))
    #expect(probe.homeAppearCount == 0)
    #expect(probe.settingsAppearCount == 1)
  }

  @Test("switching selected tabs keeps distinct local-state storage per tab content root")
  func switchingTabsKeepsDistinctContentStateIdentities() {
    let renderer = DefaultRenderer()
    let rootIdentity = testIdentity("TabSwitchStateIsolation")
    let proposal = ProposedSize(width: .finite(32), height: .finite(6))

    _ = renderer.render(
      TabView(selection: .constant("count")) {
        Tab("Count", value: "count") {
          CountStateTabRoot()
        }

        Tab("Label", value: "label") {
          LabelStateTabRoot()
        }
      },
      context: .init(
        identity: rootIdentity,
        applyEnvironmentValues: true
      ),
      proposal: proposal
    )

    let second = renderer.render(
      TabView(selection: .constant("label")) {
        Tab("Count", value: "count") {
          CountStateTabRoot()
        }

        Tab("Label", value: "label") {
          LabelStateTabRoot()
        }
      },
      context: .init(
        identity: rootIdentity,
        applyEnvironmentValues: true
      ),
      proposal: proposal
    )

    let surface = second.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("label seeded"))
  }
}

@MainActor
private final class LifecycleProbe {
  var homeAppearCount = 0
  var settingsAppearCount = 0
  var logsAppearCount = 0
}

private struct CountStateTabRoot: View {
  @State private var count = 0

  var body: some View {
    Text("count \(count)")
  }
}

private struct LabelStateTabRoot: View {
  @State private var label = "seeded"

  var body: some View {
    Text("label \(label)")
  }
}
