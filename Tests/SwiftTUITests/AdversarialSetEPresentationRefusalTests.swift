@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

// Campaign two F3 pass 2 (setE145–setE150): imperative presentation mutations
// refused during a view update (STUI-1226) and toast deadline tasks. A refused
// mutation records one `presentation.mutationDuringViewUpdate` warning and is
// refused in that frame and every later one (PresentationCoordinator.swift).

@MainActor
@Suite("Campaign F3 pass 2 refused presentation mutations and toast timers", .serialized)
struct AdversarialSetEPresentationRefusalTests {
  private static let code = PresentationMutationGuard.mutationDuringViewUpdateCode

  @Test(arguments: Array(145...148))
  func presentationRefusal(id: Int) throws {
    _ = ImperativeRuntimeIssueQueue.drain()
    var observed: [String] = []
    PresentationMutationGuard.onInvalidMutation = { observed.append($0) }
    defer {
      PresentationMutationGuard.onInvalidMutation = nil
      _ = ImperativeRuntimeIssueQueue.drain()
    }
    let capture = SetERefusalCapture()
    if id == 148 {
      try hostedRefusal(capture: capture) { observed.count }
      return
    }
    let renderer = DefaultRenderer()
    func render() -> (surface: String, warnings: Int) {
      let artifacts = renderer.render(
        SetERefusalProbe(capture: capture, generation: 0),
        context: .init(identity: testIdentity("setE", String(id))),
        proposal: .init(width: 40, height: 10))
      let warnings = artifacts.diagnostics.runtime.issues.filter { $0.code == Self.code }.count
      return (artifacts.rasterSurface.lines.joined(separator: "\n"), warnings)
    }
    let first = render()
    let handle = try #require(capture.handle)
    let item = try #require(capture.item)
    switch id {
    case 145:
      #expect(first.warnings == 0)
      handle.present(item)
      let presented = render()
      try #require(presented.surface.contains(SetERefusalCapture.title), "\(presented.surface)")
      capture.mode = .dismiss
      let refused = render()
      capture.mode = .idle
      #expect(refused.warnings == 1)
      #expect(refused.surface.contains(SetERefusalCapture.title), "refused dismissal applied")
      let later = render()
      #expect(later.warnings == 0)
      #expect(later.surface.contains(SetERefusalCapture.title), "refused dismissal replayed")
      handle.dismiss(id: item.id)
      #expect(!render().surface.contains(SetERefusalCapture.title))
      #expect(observed.count == 1)
    case 146:
      capture.mode = .present
      var frames = [first]
      frames.append(render())
      frames.append(render())
      capture.mode = .idle
      let after = render()
      #expect(frames.map(\.warnings) == [0, 1, 1])
      #expect(observed.count == 2)
      #expect(!(frames + [after]).contains { $0.surface.contains(SetERefusalCapture.title) })
      #expect(ImperativeRuntimeIssueQueue.pending.isEmpty)
    default:
      capture.mode = .present
      let refused = render()
      capture.mode = .idle
      #expect(refused.warnings == 1)
      #expect(!refused.surface.contains(SetERefusalCapture.title))
      handle.present(item)
      let shown = render()
      #expect(shown.warnings == 0)
      let occurrences = shown.surface.ranges(of: SetERefusalCapture.title).count
      #expect(occurrences == 1, "\(shown.surface)")
    }
  }

  private func hostedRefusal(capture: SetERefusalCapture, observed: () -> Int) throws {
    let issues = SetEIssueLog()
    let root = testIdentity("setE", "148")
    let h = try StressRuntimeHarness(rootIdentity: root, size: .init(width: 40, height: 10)) {
      VStack(alignment: .leading, spacing: 0) {
        SetERefusalProbe(capture: capture, generation: capture.generation)
      }
    }
    defer { h.shutdown() }
    h.runLoop.runtimeIssueSink = RuntimeIssueSink { issues.entries.append($0) }
    // A changing input re-resolves the probe on each frame instead of a reuse serve.
    capture.mode = .present
    capture.generation += 1
    _ = try h.renderAfterExternalMutation()
    capture.generation += 1
    _ = try h.renderAfterExternalMutation()
    capture.mode = .idle
    capture.generation += 1
    _ = try h.renderAfterExternalMutation()
    try #require(observed() == 2, "the probe did not re-resolve under the hosted runtime")
    #expect(issues.entries.filter { $0.code == Self.code }.count == 1, "\(issues.entries)")
    #expect(!h.frame.contains(SetERefusalCapture.title), "\(h.frame)")
  }

  @Test(arguments: [149, 150])
  func toastDeadline(id: Int) throws {
    let model = SetEToastModel()
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setE", String(id)), size: .init(width: 40, height: 10)
    ) {
      Text("Workspace").toast("Saved \(id)", isPresented: model.binding, duration: 3600)
    }
    defer { h.shutdown() }
    let baseline = h.activeTaskCount
    var shownCensus: [String: Int]?
    for cycle in 1...(id == 150 ? 3 : 1) {
      model.isPresented = true
      _ = try h.renderAfterExternalMutation()
      try #require(h.frame.contains("Saved"), "\(h.frame)")
      #expect(h.activeTaskCount == baseline + 1, "cycle \(cycle)")
      let census = setECensus(h)
      if let shownCensus { #expect(census == shownCensus) } else { shownCensus = census }
      model.isPresented = false
      _ = try h.renderAfterExternalMutation()
      #expect(h.activeTaskCount == baseline, "the deadline task outlived the dismissal")
      #expect(h.activeTaskDescriptorCount == baseline)
    }
  }
}

@MainActor
private final class SetEIssueLog {
  var entries: [RuntimeIssue] = []
}

@MainActor
private final class SetEToastModel {
  var isPresented = false
  var binding: Binding<Bool> {
    Binding(get: { self.isPresented }, set: { self.isPresented = $0 })
  }
}

@MainActor
private final class SetERefusalCapture {
  enum Mode { case idle, present, dismiss }
  static let title = "Imperative prompt"
  var mode = Mode.idle
  var generation = 0
  var handle: PresentationCoordinatorHandle<PromptPresentationItem>?
  var item: PromptPresentationItem?
}

/// Captures the live alert handle and an item during resolve, and presents
/// or dismisses it from inside the resolve when its mode says so.
private struct SetERefusalProbe: PrimitiveView, IterativeResolvableView {
  let capture: SetERefusalCapture
  let generation: Int

  package func makeResolveWork(in context: ResolveContext) -> ResolveWork<[ResolvedNode]> {
    let handle = context.environmentValues.alertPresentationCoordinator
    capture.handle = handle
    if capture.item == nil {
      let spec = alertPromptPresentationSpec()
      capture.item = PromptPresentationItem(
        id: presentationAttachmentID(for: context.identity, token: spec.token),
        title: SetERefusalCapture.title,
        surface: spec.prepareSurface(context),
        actionPayloads: portalAttachmentDeclaredBuilderChildren(
          from: Button("Dismiss") {}, edge: nil),
        messagePayloads: portalAttachmentDeclaredBuilderChildren(
          from: Text("Refusal probe."), edge: nil),
        contentPayloads: [],
        dismiss: {}
      )
    }
    if let item = capture.item {
      switch capture.mode {
      case .present: handle.present(item)
      case .dismiss: handle.dismiss(id: item.id)
      case .idle: break
      }
    }
    return Text("Workspace").resolveElementsWork(in: context)
  }
}
