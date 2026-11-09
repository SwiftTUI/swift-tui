import Foundation
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct AccessibilityWireBudgetTests {
  private func node(_ label: String, role: AccessibilityRole = .group) -> AccessibilityNode {
    AccessibilityNode(
      identity: testIdentity("Budget"),
      rect: .init(origin: .zero, size: .init(width: 1, height: 1)), role: role, label: label)
  }

  private func model(_ nodes: [AccessibilityNode], character: Character = "A") -> HostWireFrameModel
  {
    HostWireFrameModel(
      surface: RasterSurface(
        size: .init(width: 1, height: 1),
        cells: [[RasterCell(character: character)]]),
      sequence: 1, semanticSnapshot: SemanticSnapshot(accessibilityNodes: nodes),
      focusedIdentity: nil,
      damage: .init(textRows: [.init(row: 0, columnRanges: [0..<1])]),
      preferredLayoutSize: nil)
  }

  private func surface(_ output: String) throws -> [String: Any] {
    #expect(output.hasPrefix("\u{1e}surface:"))
    #expect(output.utf8.count <= HostWireBudget.recordBytes + 1)
    #expect(output.filter { $0 == "\n" }.count == 1)
    return try #require(
      JSONSerialization.jsonObject(
        with: Data(output.dropFirst("\u{1e}surface:".count).utf8)) as? [String: Any])
  }

  @Test(arguments: ["label", "value", "aggregate", "escaping", "encodedOverhead", "nodeCount"])
  func oversizedMetadataKeepsTheVisualFrame(kind: String) throws {
    let budget = HostWireBudget.recordBytes
    var nodes: [AccessibilityNode]
    switch kind {
    case "value":
      var editor = node("Editor", role: .textField)
      editor.actionTarget = "editor"
      editor.control = .init(
        actions: [.editText, .selectText],
        value: .text(String(repeating: "x", count: budget + 1)))
      nodes = [editor]
    case "aggregate": nodes = (0..<9).map { _ in node(String(repeating: "x", count: budget / 8)) }
    case "escaping": nodes = [node(String(repeating: "\u{0}", count: budget / 6))]
    case "encodedOverhead": nodes = [node(String(repeating: "x", count: budget - 64))]
    case "nodeCount": nodes = Array(repeating: node(""), count: HostWireBudget.metadataEntries + 1)
    default: nodes = [node(String(repeating: "x", count: budget + 1))]
    }
    var state = HostWireCapabilities().negotiatedEncodingState()
    let result = WebSurfaceFrameEncoder.encodeReportingFailure(
      model(nodes),
      fallbackBackground: .black, state: &state)
    let frame = try surface(result.record)
    #expect((frame["accessibilityTree"] as? [Any] ?? []).isEmpty)
    #expect(result.record.contains("A"))
    #expect(result.failureDescription == nil)
    #expect(result.runtimeIssue?.code == "accessibility.budgetExceeded")
    #expect(state.recordsEncoded == 1)
  }

  @Test func omissionAndRecoveryKeepContiguousDeltaGenerations() throws {
    var state = HostWireCapabilities(acceptsDeltaFrames: true, styleAppend: true)
      .negotiatedEncodingState()
    for (index, label) in [
      "normal", String(repeating: "x", count: HostWireBudget.recordBytes),
      "restored",
    ].enumerated() {
      let result = WebSurfaceFrameEncoder.encodeReportingFailure(
        model([node(label)]),
        fallbackBackground: .black, state: &state)
      let frame = try surface(result.record)
      #expect(frame["gen"] as? Int == index + 1)
      if index > 0 {
        #expect(frame["encoding"] as? String == "delta")
        #expect(frame["baselineGen"] as? Int == index)
      }
      let tree = frame["accessibilityTree"] as? [[String: Any]] ?? []
      #expect(tree.count == (index == 1 ? 0 : 1))
      if index != 1 { #expect(tree.first?["label"] as? String == label) }
    }
  }

  @Test func redactedSecureValuesDoNotTriggerOmission() throws {
    var secure = node("Password", role: .secureField)
    secure.actionTarget = "secure"
    secure.control = .init(
      actions: [.setValue],
      value: .text(String(repeating: "s", count: HostWireBudget.recordBytes + 1)))
    var state = HostWireCapabilities().negotiatedEncodingState()
    let result = WebSurfaceFrameEncoder.encodeReportingFailure(
      model([secure]),
      fallbackBackground: .black, state: &state)
    let tree = try surface(result.record)["accessibilityTree"] as? [[String: Any]]
    #expect(tree?.first?["label"] as? String == "Password")
    #expect(tree?.first?["value"] == nil)
    #expect(result.runtimeIssue == nil)
  }

  @Test func diagnosticsAreOncePerOmissionEpisodeAndVisualOverflowStillRejects() throws {
    let oversized = [node(String(repeating: "x", count: HostWireBudget.recordBytes))]
    var state = HostWireCapabilities(acceptsDeltaFrames: true).negotiatedEncodingState()
    func encode(_ nodes: [AccessibilityNode]) -> WebSurfaceFrameEncoder.EncodingOutcome {
      WebSurfaceFrameEncoder.encodeReportingFailure(
        model(nodes),
        fallbackBackground: .black, state: &state)
    }
    #expect(encode(oversized).runtimeIssue != nil)
    #expect(encode(oversized).runtimeIssue == nil)
    #expect(encode([node("recovered")]).runtimeIssue == nil)
    #expect(encode(oversized).runtimeIssue != nil)
    let generation = state.recordsEncoded
    let invalid = HostWireFrameModel(
      surface: RasterSurface(size: .init(width: Int.max, height: 1), cells: []),
      sequence: nil, semanticSnapshot: SemanticSnapshot(accessibilityNodes: oversized),
      focusedIdentity: nil, damage: nil, preferredLayoutSize: nil)
    let rejected = WebSurfaceFrameEncoder.encodeReportingFailure(
      invalid,
      fallbackBackground: .black, state: &state)
    #expect(rejected.record == HostWireBudget.rejectionRecord)
    #expect(rejected.failureDescription != nil)
    #expect(rejected.runtimeIssue == nil)
    #expect(state.recordsEncoded == generation)
    #expect(!state.hasBaseline)
    let recovered = try surface(encode([node("normal")]).record)
    #expect(recovered["encoding"] == nil)
    #expect(recovered["gen"] as? Int == Int(generation + 1))
  }

  @Test func diagnosticDoesNotConsumeTheMaximumVisualRecordBudget() throws {
    func linkedModel(_ link: String, nodes: [AccessibilityNode]) -> HostWireFrameModel {
      var cell = RasterCell(character: "A")
      cell.hyperlink = link
      return HostWireFrameModel(
        surface: RasterSurface(size: .init(width: 1, height: 1), cells: [[cell]]),
        sequence: 1, semanticSnapshot: SemanticSnapshot(accessibilityNodes: nodes),
        focusedIdentity: nil, damage: nil, preferredLayoutSize: nil)
    }
    let initial = HostWireCapabilities().negotiatedEncodingState()
    var baseline = initial
    let prefix = "https://example.test/"
    let small = WebSurfaceFrameEncoder.encodeReportingFailure(
      linkedModel(prefix, nodes: []),
      fallbackBackground: .black, state: &baseline)
    let available = HostWireBudget.recordBytes + 1 - small.record.utf8.count
    let link = prefix + String(repeating: "x", count: available)
    var state = initial
    let result = WebSurfaceFrameEncoder.encodeReportingFailure(
      linkedModel(link, nodes: [node(String(repeating: "a", count: HostWireBudget.recordBytes))]),
      fallbackBackground: .black, state: &state)
    #expect(result.record.utf8.count == HostWireBudget.recordBytes + 1)
    #expect(result.record.hasPrefix("\u{1e}surface:"))
    #expect(result.record.filter { $0 == "\n" }.count == 1)
    #expect(result.runtimeIssue?.code == "accessibility.budgetExceeded")
  }
}
