import Foundation
import Testing

@testable import TerminalUI
@testable import View

@Suite
@MainActor
struct RenderedTextFixtureSupportTests {
  @Test("rendered text fixture support records and verifies every supported terminal configuration")
  func recordsAndVerifiesSnapshots() throws {
    let fixtureDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
      try? FileManager.default.removeItem(at: fixtureDirectory)
    }

    try assertRenderedTextFixtures(
      named: "smoke-card",
      size: .init(width: 16, height: 5),
      fixtureDirectory: fixtureDirectory,
      mode: .record
    ) {
      GroupBox("Status") {
        Text("Hello")
      }
    }

    let recordedDirectory =
      fixtureDirectory
      .appendingPathComponent("smoke-card", isDirectory: true)
    let recordedFileNames = try FileManager.default.contentsOfDirectory(
      at: recordedDirectory,
      includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "txt" }
    .map(\.lastPathComponent)
    .sorted()

    #expect(
      recordedFileNames
        == RenderedTextFixtureTerminalConfiguration.supported
        .map(\.fixtureFileName)
        .sorted()
    )

    try assertRenderedTextFixtures(
      named: "smoke-card",
      size: .init(width: 16, height: 5),
      fixtureDirectory: fixtureDirectory,
      mode: .verify
    ) {
      GroupBox("Status") {
        Text("Hello")
      }
    }
  }
}
