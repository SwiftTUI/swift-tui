import FilePreviewerApp
import Foundation
import Testing

struct PreviewerRegistryTests {
  @Test("lookup is case-insensitive")
  func lookupIsCaseInsensitive() {
    let registry = PreviewerRegistry(
      byExtension: [
        "MD": PreviewCommand(executable: "markdown", arguments: { [$0.path] })
      ],
      fallback: PreviewCommand(executable: "fallback", arguments: { [$0.path] })
    )

    let command = registry.command(for: URL(fileURLWithPath: "/tmp/readme.md"))

    #expect(command.executable == "markdown")
  }

  @Test("unknown extensions use fallback")
  func fallbackForUnknownExtension() {
    let registry = PreviewerRegistry(
      byExtension: [:],
      fallback: PreviewCommand(executable: "fallback", arguments: { ["--", $0.path] })
    )
    let url = URL(fileURLWithPath: "/tmp/archive.unknown")
    let command = registry.command(for: url)

    #expect(command.executable == "fallback")
    #expect(command.arguments(url) == ["--", "/tmp/archive.unknown"])
  }
}
