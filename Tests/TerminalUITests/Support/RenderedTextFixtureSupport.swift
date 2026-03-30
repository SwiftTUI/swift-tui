import Foundation
import Testing

@testable import Core
@testable import TerminalUI
@testable import View

enum RenderedTextFixtureMode: Sendable {
  case automatic
  case record
  case verify

  static let recordEnvironmentVariable = "PARALLEL_RECORD_RENDERED_FIXTURES"

  var isRecording: Bool {
    switch self {
    case .automatic:
      ProcessInfo.processInfo.environment[Self.recordEnvironmentVariable] == "1"
    case .record:
      true
    case .verify:
      false
    }
  }
}

struct RenderedTextFixtureTerminalConfiguration: Equatable, Sendable {
  let name: String
  let capabilityProfile: TerminalCapabilityProfile
  let appearance: TerminalAppearance

  init(
    name: String,
    capabilityProfile: TerminalCapabilityProfile,
    appearance: TerminalAppearance = .fallback
  ) {
    self.name = name
    self.capabilityProfile = capabilityProfile
    self.appearance = appearance
  }

  var fixtureFileName: String {
    "\(sanitizePathComponent(name)).txt"
  }

  static let supported: [Self] = [
    .init(name: "preview-unicode", capabilityProfile: .previewUnicode),
    .init(name: "preview-ascii", capabilityProfile: .previewASCII),
    .init(name: "ansi16", capabilityProfile: .ansi16),
    .init(name: "ansi256", capabilityProfile: .ansi256),
    .init(name: "true-color", capabilityProfile: .trueColor),
  ]
}

@MainActor
func assertRenderedTextFixtures<V: View>(
  named fixtureName: String,
  size: Size,
  view: V,
  fixtureDirectory: URL? = nil,
  relativeTo sourceFilePath: StaticString = #filePath,
  terminalConfigurations: [RenderedTextFixtureTerminalConfiguration] =
    RenderedTextFixtureTerminalConfiguration.supported,
  identity: Identity = testIdentity("Fixture"),
  environmentValues: EnvironmentValues = .init(),
  mode: RenderedTextFixtureMode = .automatic,
  renderer: DefaultRenderer = .init()
) throws {
  try assertRenderedTextFixtures(
    named: fixtureName,
    size: size,
    fixtureDirectory: fixtureDirectory,
    relativeTo: sourceFilePath,
    terminalConfigurations: terminalConfigurations,
    identity: identity,
    environmentValues: environmentValues,
    mode: mode,
    renderer: renderer
  ) {
    view
  }
}

@MainActor
func assertRenderedTextFixtures<Content: View>(
  named fixtureName: String,
  size: Size,
  fixtureDirectory: URL? = nil,
  relativeTo sourceFilePath: StaticString = #filePath,
  terminalConfigurations: [RenderedTextFixtureTerminalConfiguration] =
    RenderedTextFixtureTerminalConfiguration.supported,
  identity: Identity = testIdentity("Fixture"),
  environmentValues: EnvironmentValues = .init(),
  mode: RenderedTextFixtureMode = .automatic,
  renderer: DefaultRenderer = .init(),
  @ViewBuilder view: () -> Content
) throws {
  let configurationNames = terminalConfigurations.map(\.fixtureFileName)
  guard Set(configurationNames).count == configurationNames.count else {
    Issue.record(
      RenderedTextFixtureIssue.duplicateTerminalConfigurations(
        fileNames: configurationNames
      )
    )
    return
  }
  let rootView = composedFixtureRoot(from: declaredBuilderChildren(from: view()))

  let fixtureRootDirectory =
    fixtureDirectory
    ?? defaultFixtureDirectory(
      relativeTo: sourceFilePath
    )
  let fixtureCaseDirectory = fixtureRootDirectory.appendingPathComponent(
    sanitizePathComponent(fixtureName),
    isDirectory: true
  )
  let previewCaseDirectory = previewDirectory(
    relativeTo: sourceFilePath,
    fixtureName: fixtureName
  )

  let snapshots = terminalConfigurations.map { configuration in
    (
      configuration,
      renderFixtureSnapshot(
        named: fixtureName,
        size: size,
        configuration: configuration,
        identity: identity,
        environmentValues: environmentValues,
        renderer: renderer,
        view: rootView
      )
    )
  }

  try FileManager.default.createDirectory(
    at: previewCaseDirectory,
    withIntermediateDirectories: true
  )

  for (configuration, snapshot) in snapshots {
    let previewURL = previewCaseDirectory.appendingPathComponent(
      configuration.fixtureFileName
    )
    try writeFixtureSnapshot(snapshot, to: previewURL)
  }

  if mode.isRecording {
    try recordRenderedFixtureSnapshots(
      snapshots,
      into: fixtureCaseDirectory
    )
  }

  let actualFixtureFileNames = Set(
    try fixtureFileNames(in: fixtureCaseDirectory)
  )
  let expectedFixtureFileNames = Set(
    snapshots.map { $0.0.fixtureFileName }
  )

  if actualFixtureFileNames != expectedFixtureFileNames {
    Issue.record(
      RenderedTextFixtureIssue.fixtureSetMismatch(
        fixtureName: fixtureName,
        fixtureCaseDirectory: fixtureCaseDirectory,
        expectedFixtureFileNames: expectedFixtureFileNames,
        actualFixtureFileNames: actualFixtureFileNames
      )
    )
  }

  for (configuration, snapshot) in snapshots {
    let fixtureURL = fixtureCaseDirectory.appendingPathComponent(
      configuration.fixtureFileName
    )
    let previewURL = previewCaseDirectory.appendingPathComponent(
      configuration.fixtureFileName
    )

    guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
      Issue.record(
        RenderedTextFixtureIssue.missingFixture(
          fixtureName: fixtureName,
          configurationName: configuration.name,
          fixtureURL: fixtureURL,
          previewURL: previewURL
        )
      )
      continue
    }

    let expected = try String(contentsOf: fixtureURL, encoding: .utf8)
    if snapshot != normalizeNewlines(expected) {
      Issue.record(
        RenderedTextFixtureIssue.fixtureMismatch(
          fixtureName: fixtureName,
          configurationName: configuration.name,
          fixtureURL: fixtureURL,
          previewURL: previewURL
        )
      )
    }
  }
}

@MainActor
private func renderFixtureSnapshot<V: View>(
  named fixtureName: String,
  size: Size,
  configuration: RenderedTextFixtureTerminalConfiguration,
  identity: Identity,
  environmentValues: EnvironmentValues,
  renderer: DefaultRenderer,
  view: V
) -> String {
  var effectiveEnvironmentValues = environmentValues
  effectiveEnvironmentValues.terminalAppearance = configuration.appearance

  let fixedRoot = view.frame(
    width: size.width,
    height: size.height,
    alignment: .topLeading
  )

  let artifacts = renderer.render(
    fixedRoot,
    context: .init(
      identity: identity,
      environmentValues: effectiveEnvironmentValues
    ),
    proposal: .init(width: size.width, height: size.height)
  )

  let terminalOutput = TerminalSurfaceRenderer(
    capabilityProfile: configuration.capabilityProfile
  ).render(artifacts.rasterSurface)

  return serializeRenderedSnapshot(
    fixtureName: fixtureName,
    terminalOutput: terminalOutput,
    surfaceSize: artifacts.rasterSurface.size,
    configuration: configuration
  )
}

private func serializeRenderedSnapshot(
  fixtureName: String,
  terminalOutput: String,
  surfaceSize: Size,
  configuration: RenderedTextFixtureTerminalConfiguration
) -> String {
  let normalizedOutput = normalizeNewlines(terminalOutput)
  let renderedLines = normalizedOutput.split(
    separator: "\n",
    omittingEmptySubsequences: false
  ).map(String.init)
  let lineNumberWidth = max(2, String(max(surfaceSize.height, renderedLines.count)).count)

  let header = [
    "fixture \(fixtureName)",
    "configuration \(configuration.name)",
    "surface \(surfaceSize.width)x\(surfaceSize.height)",
    "capability glyph=\(configuration.capabilityProfile.glyphLevel.rawValue) color=\(configuration.capabilityProfile.colorLevel.rawValue) styles=\(configuration.capabilityProfile.emitsStyleEscapeSequences)",
    "appearance fg=\(hexString(configuration.appearance.foregroundColor)) bg=\(hexString(configuration.appearance.backgroundColor)) tint=\(hexString(configuration.appearance.tintColor)) scheme=\(configuration.appearance.colorScheme.rawValue) contrast=\(configuration.appearance.colorSchemeContrast.rawValue) source=\(configuration.appearance.source.rawValue)",
  ]

  let body = renderedLines.enumerated().map { index, line in
    "\(String(format: "%0*d", lineNumberWidth, index + 1))│\(displayLine(line))"
  }

  return (header + body).joined(separator: "\n") + "\n"
}

private func recordRenderedFixtureSnapshots(
  _ snapshots: [(configuration: RenderedTextFixtureTerminalConfiguration, snapshot: String)],
  into fixtureCaseDirectory: URL
) throws {
  try FileManager.default.createDirectory(
    at: fixtureCaseDirectory,
    withIntermediateDirectories: true
  )

  let expectedFileNames = Set(
    snapshots.map { $0.configuration.fixtureFileName }
  )

  for existingFileName in try fixtureFileNames(in: fixtureCaseDirectory)
  where !expectedFileNames.contains(existingFileName) {
    let existingURL = fixtureCaseDirectory.appendingPathComponent(existingFileName)
    try FileManager.default.removeItem(at: existingURL)
  }

  for (configuration, snapshot) in snapshots {
    let fixtureURL = fixtureCaseDirectory.appendingPathComponent(
      configuration.fixtureFileName
    )
    try writeFixtureSnapshot(snapshot, to: fixtureURL)
  }
}

private func writeFixtureSnapshot(
  _ snapshot: String,
  to fileURL: URL
) throws {
  try FileManager.default.createDirectory(
    at: fileURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  try normalizeNewlines(snapshot).write(
    to: fileURL,
    atomically: true,
    encoding: .utf8
  )
}

private func fixtureFileNames(
  in fixtureCaseDirectory: URL
) throws -> [String] {
  guard FileManager.default.fileExists(atPath: fixtureCaseDirectory.path) else {
    return []
  }

  return try FileManager.default.contentsOfDirectory(
    at: fixtureCaseDirectory,
    includingPropertiesForKeys: nil
  )
  .filter { $0.pathExtension == "txt" }
  .map(\.lastPathComponent)
  .sorted()
}

private func defaultFixtureDirectory(
  relativeTo sourceFilePath: StaticString
) -> URL {
  sourceDirectory(for: sourceFilePath)
    .appendingPathComponent("Fixtures", isDirectory: true)
}

private func previewDirectory(
  relativeTo sourceFilePath: StaticString,
  fixtureName: String
) -> URL {
  let sourceFileURL = URL(fileURLWithPath: String(describing: sourceFilePath))
  let sourceFileName = sourceFileURL.deletingPathExtension().lastPathComponent

  return URL(
    fileURLWithPath: FileManager.default.currentDirectoryPath,
    isDirectory: true
  )
  .appendingPathComponent(".build", isDirectory: true)
  .appendingPathComponent("rendered-text-fixtures", isDirectory: true)
  .appendingPathComponent(sanitizePathComponent(sourceFileName), isDirectory: true)
  .appendingPathComponent(sanitizePathComponent(fixtureName), isDirectory: true)
}

private func sourceDirectory(
  for sourceFilePath: StaticString
) -> URL {
  URL(fileURLWithPath: String(describing: sourceFilePath))
    .deletingLastPathComponent()
}

private func normalizeNewlines(
  _ value: String
) -> String {
  value.replacingOccurrences(of: "\r\n", with: "\n")
    .replacingOccurrences(of: "\r", with: "\n")
}

private func displayLine(
  _ line: String
) -> String {
  var rendered = ""

  for scalar in line.unicodeScalars {
    switch scalar.value {
    case 0x20:
      rendered.append("·")
    case 0x09:
      rendered.append("\\t")
    case 0x1B:
      rendered.append("\\u{001B}")
    default:
      if CharacterSet.controlCharacters.contains(scalar) {
        rendered += String(format: "\\u{%04X}", scalar.value)
      } else {
        rendered.unicodeScalars.append(scalar)
      }
    }
  }

  return rendered
}

private func hexString(
  _ color: Color
) -> String {
  String(
    format: "#%02X%02X%02X",
    color.red,
    color.green,
    color.blue
  )
}

private func sanitizePathComponent(
  _ value: String
) -> String {
  let invalidCharacters = CharacterSet.alphanumerics
    .union(CharacterSet(charactersIn: "-_."))
    .inverted
  let parts = value.components(separatedBy: invalidCharacters).filter { !$0.isEmpty }
  return parts.isEmpty ? "unnamed" : parts.joined(separator: "-")
}

private func composedFixtureRoot(
  from children: [AnyView]
) -> AnyView {
  switch children.count {
  case 0:
    AnyView(EmptyView())
  case 1:
    children[0]
  default:
    AnyView(Group(children: children))
  }
}

private enum RenderedTextFixtureIssue: Error, CustomStringConvertible {
  case duplicateTerminalConfigurations(fileNames: [String])
  case fixtureSetMismatch(
    fixtureName: String,
    fixtureCaseDirectory: URL,
    expectedFixtureFileNames: Set<String>,
    actualFixtureFileNames: Set<String>
  )
  case missingFixture(
    fixtureName: String,
    configurationName: String,
    fixtureURL: URL,
    previewURL: URL
  )
  case fixtureMismatch(
    fixtureName: String,
    configurationName: String,
    fixtureURL: URL,
    previewURL: URL
  )

  var description: String {
    switch self {
    case .duplicateTerminalConfigurations(let fileNames):
      """
      Rendered fixture terminal configuration names must be unique.
      Names: \(fileNames.joined(separator: ", "))
      """

    case .fixtureSetMismatch(
      let fixtureName,
      let fixtureCaseDirectory,
      let expectedFixtureFileNames,
      let actualFixtureFileNames
    ):
      """
      Fixture file set mismatch for \(fixtureName).
      Fixture directory: \(fixtureCaseDirectory.path)
      Expected: \(expectedFixtureFileNames.sorted().joined(separator: ", "))
      Actual: \(actualFixtureFileNames.sorted().joined(separator: ", "))
      Re-run with \(RenderedTextFixtureMode.recordEnvironmentVariable)=1 to update fixtures.
      """

    case .missingFixture(let fixtureName, let configurationName, let fixtureURL, let previewURL):
      """
      Missing rendered fixture for \(fixtureName)/\(configurationName).
      Expected fixture: \(fixtureURL.path)
      Actual snapshot: \(previewURL.path)
      Re-run with \(RenderedTextFixtureMode.recordEnvironmentVariable)=1 to create fixtures.
      """

    case .fixtureMismatch(let fixtureName, let configurationName, let fixtureURL, let previewURL):
      """
      Rendered fixture mismatch for \(fixtureName)/\(configurationName).
      Expected fixture: \(fixtureURL.path)
      Actual snapshot: \(previewURL.path)
      Re-run with \(RenderedTextFixtureMode.recordEnvironmentVariable)=1 to update fixtures.
      """
    }
  }
}
