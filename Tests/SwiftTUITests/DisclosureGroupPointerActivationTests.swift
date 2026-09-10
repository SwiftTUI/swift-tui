import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Owns the expansion state the way an app does: a plain class the graph
/// cannot observe, so every assertion renders after an explicit invalidation.
@MainActor
private final class DisclosureExpansionProbe {
  var isExpanded: Bool
  var innerActivations = 0

  init(isExpanded: Bool) {
    self.isExpanded = isExpanded
  }

  var binding: Binding<Bool> {
    Binding(get: { self.isExpanded }, set: { self.isExpanded = $0 })
  }
}

/// A `DisclosureGroup` toggles from a press on its label row only. A press on
/// its expanded content — plain text or a control of its own — must leave the
/// expansion alone (org review of the 0.12.1 style system).
@MainActor
struct DisclosureGroupPointerActivationTests {
  @Test(
    "clicking the expanded content of a DisclosureGroup does not collapse it",
    arguments: [0, 1, 2])
  func disclosureGroupContentClickKeepsExpansion(_ index: Int) throws {
    let styles: [AnyDisclosureGroupStyle] = [
      .automatic, .compact, .init(ConsumerDisclosureGroupStyle()),
    ]
    let probe = DisclosureExpansionProbe(isExpanded: true)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("DisclosureContentClick"), size: .init(width: 32, height: 8)
    ) {
      DisclosureGroup("Details", isExpanded: probe.binding) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Body copy")
          Button("Inner") { probe.innerActivations += 1 }
        }
      }
      .disclosureGroupStyle(styles[index])
    }
    defer { harness.shutdown() }
    #expect(harness.frame.contains("Body copy"))

    // Content that is not a control: the group stays open.
    _ = try harness.clickText("Body copy")
    _ = try harness.renderAfterExternalMutation()
    #expect(probe.isExpanded)
    #expect(harness.frame.contains("Body copy"))

    // A control inside the content activates itself, not the disclosure.
    _ = try harness.clickText("Inner")
    _ = try harness.renderAfterExternalMutation()
    #expect(probe.innerActivations == 1)
    #expect(probe.isExpanded)
    #expect(harness.frame.contains("Body copy"))

    // The label row remains the pointer activation region.
    _ = try harness.clickText("Details")
    _ = try harness.renderAfterExternalMutation()
    #expect(!probe.isExpanded)
    #expect(!harness.frame.contains("Body copy"))
  }
}
