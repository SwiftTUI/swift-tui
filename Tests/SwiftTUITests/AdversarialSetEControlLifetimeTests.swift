import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
func setEKnown(_ message: String, _ body: () -> Void) {
  if ProcessInfo.processInfo.environment["SWIFTTUI_SETE_UNMARKED"] == "1" {
    body()
  } else {
    withKnownIssue(Comment(rawValue: message)) { body() }
  }
}

@MainActor
@Suite("Campaign F3 finite control lifetimes", .serialized)
struct AdversarialSetEControlLifetimeTests {
  @Test(arguments: Array(1...10))
  func controlLifetime(id: Int) throws {
    let model = SetEControlModel()
    let keepID = testIdentity("setEKeep", String(id))
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("setE", String(id)), size: .init(width: 40, height: 10)
    ) { SetELifetimeControlRoot(kind: id, model: model, keepID: keepID) }
    defer { h.shutdown() }
    let baseline = setECensus(h)
    var mounted: [String: Int]?
    for cycle in 0..<3 {
      model.number = 0
      model.flag = false
      model.text = "seed"
      _ = try h.clickText("Toggle lifetime")
      let current = setECensus(h)
      if let mounted { #expect(current == mounted) } else { mounted = current }
      try #require(current["focus", default: 0] > baseline["focus", default: 0])
      let region = try #require(h.runLoop.focusTracker.focusRegions.first { $0.identity != keepID })
      let retiredPoint = Point(region.rect.origin)
      let keepRegion = try #require(
        h.runLoop.focusTracker.focusRegions.first { $0.identity == keepID })
      try #require(!keepRegion.rect.contains(retiredPoint.containingCell))
      _ = try h.focus(region.identity)
      let key: KeyPress
      switch id {
      case 1, 10: key = .init(.return)
      case 2: key = .init(.space)
      case 3, 4, 6: key = .init(.arrowRight)
      case 5: key = .init(.arrowDown)
      default: key = .init(.character("z"))
      }
      _ = try h.pressKey(key)
      #expect(model.actions == cycle + 1)
      _ = try h.clickText("Toggle lifetime")
      #expect(setECensus(h) == baseline)
      #expect(!h.runLoop.focusTracker.focusRegions.contains { $0.identity == region.identity })
      _ = try h.click(retiredPoint)
      #expect(model.actions == cycle + 1)
      #expect(setECensus(h) == baseline)
    }
  }
}

@MainActor
func setECensus<Content: View>(_ h: StressRuntimeHarness<Content>) -> [String: Int] {
  var counts: [String: Int] = [:]
  for (key, count) in h.runLoop.runtimeRegistrations.publicationOracleFingerprint() {
    counts[String(key.prefix { $0 != "|" }), default: 0] += count
  }
  // Count every stacked wheel contribution independently of the publication oracle.
  counts["wheel"] = h.runLoop.localPointerHandlerRegistry.snapshotWheel().values.reduce(0) {
    $0 + $1.count
  }
  counts["focus"] = h.focusRegionCount
  counts["taskBodies"] = h.activeTaskCount
  counts["taskDescriptors"] = h.activeTaskDescriptorCount
  return counts
}

@MainActor
private final class SetEControlModel {
  var number = 0
  var flag = false
  var text = "seed"
  var actions = 0
  var numberBinding: Binding<Int> {
    .init(
      get: { self.number },
      set: {
        self.number = $0
        self.actions += 1
      })
  }
  var flagBinding: Binding<Bool> {
    .init(
      get: { self.flag },
      set: {
        self.flag = $0
        self.actions += 1
      })
  }
  var textBinding: Binding<String> {
    .init(
      get: { self.text },
      set: {
        self.text = $0
        self.actions += 1
      })
  }
}

private struct SetELifetimeControlRoot: View {
  let kind: Int
  let model: SetEControlModel
  let keepID: Identity
  @State private var mounted = false
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Button("Toggle lifetime") { mounted.toggle() }.id(keepID)
      if mounted { subject }
    }
  }
  @ViewBuilder private var subject: some View {
    switch kind {
    case 1: Button("Subject") { model.actions += 1 }
    case 2: Toggle("Subject", isOn: model.flagBinding)
    case 3: Stepper("Subject", value: model.numberBinding, in: 0...5)
    case 4: Slider("Subject", value: model.numberBinding, in: 0...5)
    case 5:
      Picker("Subject", selection: model.numberBinding) {
        Text("Zero").tag(0)
        Text("One").tag(1)
      }
    case 6:
      Picker("Subject", selection: model.numberBinding) {
        Text("Zero").tag(0)
        Text("One").tag(1)
      }.pickerStyle(.segmented)
    case 7: TextField("Subject", text: model.textBinding)
    case 8: SecureField("Subject", text: model.textBinding)
    case 9: TextEditor(text: model.textBinding).frame(width: 25, height: 3)
    default: DisclosureGroup("Subject", isExpanded: model.flagBinding) { Text("Expanded") }
    }
  }
}
