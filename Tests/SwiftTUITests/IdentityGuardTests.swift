import Foundation
import Testing

@MainActor
@Suite
struct IdentityGuardTests {
  @Test("shared and web sources do not reintroduce legacy string identity paths")
  func sharedAndWebSourcesAvoidLegacyIdentityPaths() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    let forbiddenFragments = [
      "Identity(path:",
      "extension Identity: ExpressibleByStringLiteral",
    ]

    let matches = try forbiddenIdentityMatches(
      under: [
        packageRoot.appendingPathComponent("Sources"),
        packageRoot.appendingPathComponent("WebApp/WasmDemo/Sources"),
      ],
      forbiddenFragments: forbiddenFragments
    )

    if !matches.isEmpty {
      Issue.record("Found legacy identity usage:\n\(matches.joined(separator: "\n"))")
    }

    #expect(matches.isEmpty)
  }
}

private func forbiddenIdentityMatches(
  under roots: [URL],
  forbiddenFragments: [String]
) throws -> [String] {
  let fileManager = FileManager.default
  var matches: [String] = []

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
      guard fileURL.pathExtension == "swift" else {
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
