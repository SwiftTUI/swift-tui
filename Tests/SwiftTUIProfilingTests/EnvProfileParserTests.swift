import Foundation
import SwiftTUICore
import Testing

@testable import SwiftTUIProfiling

@Suite
struct EnvProfileParserTests {
  @Test("Unset, empty, and whitespace-only values disable profiling")
  func disabledInputs() {
    #expect(EnvProfileParser.parse(nil) == nil)
    #expect(EnvProfileParser.parse("") == nil)
    #expect(EnvProfileParser.parse("   ") == nil)
  }

  @Test("Single signals parse with their defaults")
  func singleSignals() {
    #expect(EnvProfileParser.parse("frames")?.signals == [.frames])
    #expect(
      EnvProfileParser.parse("memory")?.signals
        == [.memory(interval: ProfileConfig.defaultMemoryInterval)]
    )
    #expect(
      EnvProfileParser.parse("cpu")?.signals
        == [.cpu(interval: ProfileConfig.defaultCPUInterval)]
    )
  }

  @Test("Signals carry explicit intervals")
  func intervals() {
    #expect(
      EnvProfileParser.parse("memory@500ms")?.signals == [.memory(interval: .milliseconds(500))])
    #expect(EnvProfileParser.parse("cpu@2s")?.signals == [.cpu(interval: .seconds(2))])
  }

  @Test("Multiple signals combine; whitespace around tokens is ignored")
  func multipleSignals() {
    let config = EnvProfileParser.parse(" frames , memory@1s ")
    #expect(config?.signals == [.frames, .memory(interval: .seconds(1))])
  }

  @Test("Sink list parses after the semicolon")
  func sinks() {
    let config = EnvProfileParser.parse("frames,memory@1s;tsv=/tmp/run.tsv")
    #expect(config?.signals == [.frames, .memory(interval: .seconds(1))])
    #expect(config?.sinks == [.tsv(path: "/tmp/run.tsv")])

    let multi = EnvProfileParser.parse("frames;jsonl=/a.jsonl,summary")
    #expect(multi?.sinks == [.jsonl(path: "/a.jsonl"), .summary])

    let memoryOnly = EnvProfileParser.parse("memory@500ms;summary")
    #expect(memoryOnly?.signals == [.memory(interval: .milliseconds(500))])
    #expect(memoryOnly?.sinks == [.summary])
  }

  @Test("Bare tsv/jsonl sinks parse with an empty debug-bundle marker path")
  func bareSinksParse() {
    #expect(EnvProfileParser.parse("frames;tsv")?.sinks == [.tsv(path: "")])
    #expect(EnvProfileParser.parse("frames;jsonl,summary")?.sinks == [.jsonl(path: ""), .summary])
  }

  @Test("Bare sinks resolve into the debug bundle or drop without one")
  func bareSinksResolve() {
    DebugLogRouter.resetInstalledDefaultDirectoryForTesting()
    #expect(ProfileActivation.resolvedDescriptors([.tsv(path: ""), .summary]) == [.summary])

    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("swifttui-profile-\(UUID().uuidString)").path
    defer {
      DebugLogRouter.resetInstalledDefaultDirectoryForTesting()
      try? FileManager.default.removeItem(atPath: directory)
    }
    DebugLogRouter.installDefaultDebugDirectory(directory)
    #expect(
      ProfileActivation.resolvedDescriptors([
        .tsv(path: ""), .jsonl(path: ""), .tsv(path: "/explicit.tsv"),
      ]) == [
        .tsv(path: directory + "/profile.tsv"),
        .jsonl(path: directory + "/profile.jsonl"),
        .tsv(path: "/explicit.tsv"),
      ]
    )
  }

  @Test("Malformed input disables profiling entirely")
  func malformed() {
    #expect(EnvProfileParser.parse("bogus") == nil)
    #expect(EnvProfileParser.parse("memory@") == nil)
    #expect(EnvProfileParser.parse("memory@xyz") == nil)
    #expect(EnvProfileParser.parse("frames,") == nil)
    #expect(EnvProfileParser.parse("frames;") == nil)
    #expect(EnvProfileParser.parse("frames;;tsv=/x") == nil)
    #expect(EnvProfileParser.parse("frames;tsv=") == nil)
    #expect(EnvProfileParser.parse("frames;bogus") == nil)
  }

  @Test("Duration grammar")
  func durations() {
    #expect(EnvProfileParser.parseDuration("100ms") == .milliseconds(100))
    #expect(EnvProfileParser.parseDuration("1s") == .seconds(1))
    #expect(EnvProfileParser.parseDuration("2s500ms") == .seconds(2) + .milliseconds(500))
    #expect(EnvProfileParser.parseDuration("") == nil)
    #expect(EnvProfileParser.parseDuration("5") == nil)
    #expect(EnvProfileParser.parseDuration("5x") == nil)
    #expect(EnvProfileParser.parseDuration("ms") == nil)
  }
}
