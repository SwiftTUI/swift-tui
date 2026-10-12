import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct DisclosureGroupContentLayoutTests {
  @Test("custom disclosure columns retain every authored layout element")
  func columnContent() throws {
    let artifacts = DefaultRenderer().render(
      DisclosureGroup("Details", isExpanded: .constant(true)) {
        Text("First")
        Text("Second")
        HStack(spacing: 1) {
          Text("Third")
          Text("row")
        }
      }.disclosureGroupStyle(ColumnDisclosureStyle()),
      proposal: ProposedViewSize(width: 24, height: 6))
    let lines = artifacts.rasterSurface.lines
    #expect(lines[1].hasPrefix("    First"))
    #expect(lines[2].hasPrefix("    Second"))
    #expect(lines[3].hasPrefix("    Third row"))
    let nodes = artifacts.semanticSnapshot.accessibilityNodes
    let trigger = try #require(nodes.first { $0.label == "Details" })
    let region = try #require(nodes.first { $0.role == .region })
    #expect(trigger.properties?.controls == [region.identity])
    #expect(region.properties?.labelledBy == [trigger.identity])
    #expect(region.parentIdentity == trigger.parentIdentity)
    #expect(
      region.rect
        == CellRect(
          origin: CellPoint(x: 4, y: 1), size: CellSize(width: 9, height: 3)))
    #expect(nodes.first { $0.label == "First" }?.parentIdentity == region.identity)
    #expect(nodes.first { $0.label == "Second" }?.parentIdentity == region.identity)
  }

  @Test("custom disclosure rows distribute unwrapped content horizontally")
  func rowContent() {
    let artifacts = DefaultRenderer().render(
      DisclosureGroup("Details", isExpanded: .constant(true)) {
        Text("First")
        Text("Second")
      }.disclosureGroupStyle(RowDisclosureStyle()),
      proposal: ProposedViewSize(width: 24, height: 4))
    #expect(artifacts.rasterSurface.lines[1].hasPrefix("First Second"))
  }

  @Test("explicit authored rows keep nested controls independent of the content region")
  func explicitRowContent() throws {
    let artifacts = DefaultRenderer().render(
      DisclosureGroup("Details", isExpanded: .constant(true)) {
        HStack(spacing: 1) {
          Text("First")
          Button("Action") {}
        }
      }.disclosureGroupStyle(ColumnDisclosureStyle()),
      proposal: ProposedViewSize(width: 24, height: 4))
    #expect(artifacts.rasterSurface.lines[1].contains("First"))
    #expect(artifacts.rasterSurface.lines[1].contains("Action"))
    let nodes = artifacts.semanticSnapshot.accessibilityNodes
    let region = try #require(nodes.first { $0.role == .region })
    let button = try #require(nodes.first { $0.label == "Action" })
    let row = try #require(nodes.first { $0.identity == button.parentIdentity })
    #expect(button.role == .button)
    #expect(row.parentIdentity == region.identity)
    #expect(button.control?.actions.contains(.activate) == true)
  }

  @Test("nested disclosures preserve authored accessibility groups and independent regions")
  func nestedContent() throws {
    let artifacts = DefaultRenderer().render(
      DisclosureGroup("Outer", isExpanded: .constant(true)) {
        Text("Introduction")
        VStack(alignment: .leading, spacing: 0) {
          Text("Grouped")
          DisclosureGroup("Inner", isExpanded: .constant(true)) {
            Text("Nested")
            Button("Nested action") {}
          }.disclosureGroupStyle(ColumnDisclosureStyle())
        }.accessibilityElement(children: .contain).accessibilityLabel("Authored section")
      }.disclosureGroupStyle(ColumnDisclosureStyle()),
      proposal: ProposedViewSize(width: 32, height: 8))
    let lines = artifacts.rasterSurface.lines
    #expect(lines[1].hasPrefix("    Introduction"))
    #expect(lines[4].hasPrefix("        Nested"))
    #expect(lines[5].contains("Nested action"))
    let nodes = artifacts.semanticSnapshot.accessibilityNodes
    let outer = try #require(nodes.first { $0.label == "Outer" })
    let inner = try #require(nodes.first { $0.label == "Inner" })
    let section = try #require(nodes.first { $0.label == "Authored section" })
    let outerRegion = try #require(nodes.first { $0.properties?.labelledBy == [outer.identity] })
    let innerRegion = try #require(nodes.first { $0.properties?.labelledBy == [inner.identity] })
    let innerContainer = try #require(nodes.first { $0.identity == inner.parentIdentity })
    #expect(outer.properties?.controls == [outerRegion.identity])
    #expect(section.parentIdentity == outerRegion.identity)
    #expect(nodes.first { $0.label == "Grouped" }?.parentIdentity == section.identity)
    #expect(innerContainer.parentIdentity == section.identity)
    #expect(innerRegion.parentIdentity == innerContainer.identity)
    #expect(inner.properties?.controls == [innerRegion.identity])
    #expect(nodes.first { $0.label == "Nested action" }?.parentIdentity == innerRegion.identity)
    #expect(nodes.first { $0.label == "Nested action" }?.role == .button)
  }

  @Test(
    "nested expansion relationships remain isolated in every expansion state",
    arguments: [false, true], [false, true])
  func nestedExpansion(outerExpanded: Bool, innerExpanded: Bool) throws {
    let artifacts = DefaultRenderer().render(
      DisclosureGroup("Outer", isExpanded: .constant(outerExpanded)) {
        Text("Outer content")
        DisclosureGroup("Inner", isExpanded: .constant(innerExpanded)) {
          Text("Inner content")
        }.disclosureGroupStyle(ColumnDisclosureStyle())
      }.disclosureGroupStyle(ColumnDisclosureStyle()),
      proposal: ProposedViewSize(width: 32, height: 6))
    let nodes = artifacts.semanticSnapshot.accessibilityNodes
    let outer = try #require(nodes.first { $0.label == "Outer" })
    #expect(outer.properties?.expanded == outerExpanded)
    guard outerExpanded else {
      #expect(outer.properties?.controls == [])
      #expect(!nodes.contains { $0.role == .region || $0.label == "Inner" })
      #expect(!nodes.contains { $0.label == "Outer content" || $0.label == "Inner content" })
      return
    }
    let outerRegion = try #require(nodes.first { $0.properties?.labelledBy == [outer.identity] })
    let inner = try #require(nodes.first { $0.label == "Inner" })
    let innerContainer = try #require(nodes.first { $0.identity == inner.parentIdentity })
    #expect(outerRegion.role == .region)
    #expect(outer.properties?.controls == [outerRegion.identity])
    #expect(outerRegion.parentIdentity == outer.parentIdentity)
    #expect(nodes.first { $0.label == "Outer content" }?.parentIdentity == outerRegion.identity)
    #expect(innerContainer.parentIdentity == outerRegion.identity)
    #expect(inner.properties?.expanded == innerExpanded)
    guard innerExpanded else {
      #expect(inner.properties?.controls == [])
      #expect(nodes.filter { $0.role == .region }.count == 1)
      #expect(!nodes.contains { $0.label == "Inner content" })
      return
    }
    let innerRegion = try #require(nodes.first { $0.properties?.labelledBy == [inner.identity] })
    #expect(innerRegion.role == .region)
    #expect(innerRegion.identity != outerRegion.identity)
    #expect(inner.properties?.controls == [innerRegion.identity])
    #expect(innerRegion.parentIdentity == innerContainer.identity)
    #expect(nodes.first { $0.label == "Inner content" }?.parentIdentity == innerRegion.identity)
    #expect(nodes.filter { $0.role == .region }.count == 2)
  }

  @Test("empty disclosure slots publish a region only while expanded", arguments: [false, true])
  func emptyContent(expanded: Bool) throws {
    let artifacts = DefaultRenderer().render(
      DisclosureGroup("Empty", isExpanded: .constant(expanded)) {
        EmptyView()
      }.disclosureGroupStyle(ColumnDisclosureStyle()),
      proposal: ProposedViewSize(width: 24, height: 4))
    let nodes = artifacts.semanticSnapshot.accessibilityNodes
    let trigger = try #require(nodes.first { $0.label == "Empty" })
    let region = nodes.first { $0.role == .region }
    #expect((region != nil) == expanded)
    #expect(trigger.properties?.expanded == expanded)
    #expect(trigger.properties?.controls == region.map { [$0.identity] } ?? [])
    if let region {
      #expect(region.properties?.labelledBy == [trigger.identity])
    }
  }
}

private struct ColumnDisclosureStyle: DisclosureGroupStyle {
  func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      configuration.trigger { configuration.label }
      VStack(alignment: .leading, spacing: 0) {
        configuration.content
      }.padding(.leading, 4)
    }
  }
}

private struct RowDisclosureStyle: DisclosureGroupStyle {
  func makeBody(configuration: DisclosureGroupStyleConfiguration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      configuration.trigger { configuration.label }
      HStack(spacing: 1) {
        configuration.content
      }
    }
  }
}
