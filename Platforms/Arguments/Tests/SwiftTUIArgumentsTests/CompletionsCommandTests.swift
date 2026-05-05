import Testing
import ArgumentParser
@testable import SwiftTUIArguments

struct CompletionsCommandTests {
  @Test("CompletionsCommand.print parses shell argument")
  func parsesPrintWithZsh() throws {
    let command = try CompletionsCommand.Print.parse(["zsh"])
    #expect(command.shell == "zsh")
  }

  @Test("CompletionsCommand.print rejects empty input")
  func rejectsEmpty() {
    #expect(throws: (any Error).self) {
      _ = try CompletionsCommand.Print.parse([])
    }
  }
}
