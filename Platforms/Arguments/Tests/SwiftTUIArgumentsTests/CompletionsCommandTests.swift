import ArgumentParser
import Foundation
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

  @Test("CompletionsCommand.install parses shell argument")
  func parsesInstallWithZsh() throws {
    let command = try CompletionsCommand.Install.parse(["zsh"])
    #expect(command.shell.rawValue == "zsh")
  }

  @Test("CompletionsCommand.install parses output after shell argument")
  func parsesInstallOutputAfterShell() throws {
    let command = try CompletionsCommand.Install.parse([
      "fish", "--output", "/tmp/myapp.fish",
    ])
    #expect(command.shell.rawValue == "fish")
    #expect(command.outputPath == "/tmp/myapp.fish")
  }

  @Test("CompletionsCommand.install resolves user-writable default paths")
  func installDefaultPaths() throws {
    let environment = ["HOME": "/tmp/swifttui-home"]

    let zshURL = try CompletionsCommand.Install.defaultInstallURL(
      for: .zsh,
      commandName: "myapp",
      environment: environment
    )
    #expect(zshURL.path == "/tmp/swifttui-home/.zsh/completions/_myapp")

    let bashURL = try CompletionsCommand.Install.defaultInstallURL(
      for: .bash,
      commandName: "myapp",
      environment: environment
    )
    #expect(bashURL.path == "/tmp/swifttui-home/.local/share/bash-completion/completions/myapp")

    let fishURL = try CompletionsCommand.Install.defaultInstallURL(
      for: .fish,
      commandName: "myapp",
      environment: environment
    )
    #expect(fishURL.path == "/tmp/swifttui-home/.config/fish/completions/myapp.fish")
  }

  @Test("SwiftTUIApp default configuration exposes completions print")
  func swiftTUIAppDefaultConfigurationExposesCompletionsPrint() throws {
    let command = try TestSwiftTUIApp.parseAsRoot(["completions", "print", "zsh"])
    let printCommand = try #require(command as? CompletionsCommand.Print)
    #expect(printCommand.shell.rawValue == "zsh")
  }

  @Test("SwiftTUIApp detects completions before root argument parsing")
  func swiftTUIAppDetectsCompletionsBeforeRootArgumentParsing() throws {
    let command = try TestSwiftTUIApp.completionCommand(forRawArguments: [
      "completions", "install", "fish", "--output", "/tmp/myapp.fish",
    ])
    let installCommand = try #require(command as? CompletionsCommand.Install)
    #expect(installCommand.shell.rawValue == "fish")
    #expect(installCommand.outputPath == "/tmp/myapp.fish")
  }

  @Test("SwiftTUIApp emits root completion script for completions print")
  func swiftTUIAppEmitsRootCompletionScript() throws {
    let command = try TestSwiftTUIApp.parseAsRoot(["completions", "print", "zsh"])
    let script = try #require(TestSwiftTUIApp.completionScript(forParsedCommand: command))
    #expect(script.contains("--accessible"))
    #expect(script.contains("--cursor-follows-focus"))
    #expect(script.contains("--widgets"))
    #expect(script.contains("completions"))
  }

  @Test("SwiftTUIApp installs root completion script for completions install")
  func swiftTUIAppInstallsRootCompletionScript() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-tui-completions-\(UUID().uuidString)", isDirectory: true)
    let outputURL = directory.appendingPathComponent("test-app.fish")
    defer {
      try? FileManager.default.removeItem(at: directory)
    }

    let command = try TestSwiftTUIApp.parseAsRoot([
      "completions", "install", "fish", "--output", outputURL.path,
    ])
    let installedURL = try TestSwiftTUIApp.installCompletionScript(forParsedCommand: command)
    let installed = try #require(installedURL)

    #expect(installed.path == outputURL.path)
    let script = try String(contentsOf: installed, encoding: .utf8)
    #expect(script.contains("-l 'accessible'"))
    #expect(script.contains("-l 'widgets'"))
    #expect(script.contains("completions"))
  }
}
