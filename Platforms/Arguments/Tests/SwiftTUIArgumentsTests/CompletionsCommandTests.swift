import ArgumentParser
import Testing

@testable import SwiftTUIArguments

@MainActor
struct CompletionsCommandTests {
  @Test("CompletionsCommand.print parses shell argument")
  func parsesPrintWithZsh() throws {
    let command = try CompletionsCommand.Print.parse(["zsh"])
    #expect(command.shell.rawValue == "zsh")
  }

  @Test("CompletionsCommand.print rejects empty input")
  func rejectsEmpty() {
    #expect(throws: (any Error).self) {
      _ = try CompletionsCommand.Print.parse([])
    }
  }

  @Test("SwiftTUIApp default configuration exposes completions print")
  func swiftTUIAppDefaultConfigurationExposesCompletionsPrint() throws {
    let command = try TestSwiftTUIApp.parseAsRoot(["completions", "print", "zsh"])
    let printCommand = try #require(command as? CompletionsCommand.Print)
    #expect(printCommand.shell.rawValue == "zsh")
  }

  @Test("SwiftTUIApp emits root completion script for completions print")
  func swiftTUIAppEmitsRootCompletionScript() throws {
    let command = try TestSwiftTUIApp.parseAsRoot(["completions", "print", "zsh"])
    let script = try #require(TestSwiftTUIApp.completionScript(forParsedCommand: command))
    #expect(script.contains("--accessible"))
    #expect(script.contains("--widgets"))
    #expect(script.contains("completions"))
  }
}
