import Foundation
import Testing

@MainActor
@Suite
struct StylingGuardTests {
  @Test("styling sources and docs do not reintroduce legacy mode-based APIs")
  func stylingSourcesAndDocsAvoidLegacyModeBasedAPIs() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    let forbiddenFragments = [
      "ThemeColors",
      "preferredColorScheme",
      "lightVariant",
      "darkVariant",
      "lightTheme",
      "darkTheme",
      "lightPalette",
      "darkPalette",
      "colorSchemeMode",
      "WebTUIColorScheme",
      "resolveWebTUIColorScheme",
      "defaultLight",
      "defaultDark",
      "semanticTheme(",
    ]

    let matches = try forbiddenStylingMatches(
      under: [
        packageRoot.appendingPathComponent("Sources"),
        packageRoot.appendingPathComponent("GUI"),
        packageRoot.appendingPathComponent("Examples"),
        packageRoot.appendingPathComponent("docs"),
      ],
      allowedFileExtensions: ["swift", "ts", "md"],
      forbiddenFragments: forbiddenFragments
    )

    if !matches.isEmpty {
      Issue.record("Found legacy styling surface usage:\n\(matches.joined(separator: "\n"))")
    }

    #expect(matches.isEmpty)
  }
}

private func forbiddenStylingMatches(
  under roots: [URL],
  allowedFileExtensions: Set<String>,
  forbiddenFragments: [String]
) throws -> [String] {
  let fileManager = FileManager.default
  var matches: [String] = []
  let ignoredSuffixes = [
    "/Tests/TerminalUITests/StylingGuardTests.swift"
  ]
  let ignoredPathFragments = [
    "/.build/",
    "/node_modules/",
  ]

  for root in roots where fileManager.fileExists(atPath: root.path) {
    guard
      let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey]
      )
    else {
      continue
    }

    for case let fileURL as URL in enumerator {
      if ignoredPathFragments.contains(where: { fileURL.path.contains($0) }) {
        if fileURL.hasDirectoryPath {
          enumerator.skipDescendants()
        }
        continue
      }
      guard allowedFileExtensions.contains(fileURL.pathExtension) else {
        continue
      }
      let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
      guard resourceValues.isRegularFile == true else {
        continue
      }
      if ignoredSuffixes.contains(where: { fileURL.path.hasSuffix($0) }) {
        continue
      }

      let contents = try String(contentsOf: fileURL, encoding: .utf8)
      for fragment in forbiddenFragments where contents.contains(fragment) {
        matches.append("\(fileURL.path): \(fragment)")
      }
    }
  }

  return matches.sorted()
}
