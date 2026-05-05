import Testing

@testable import SwiftTUICLI

struct CLIModeTests {
  @Test("No arguments produces app mode")
  func noArgumentsProducesApp() throws {
    let mode = try CLIMode.parse(["myapp"])
    #expect(mode == .app(instanceName: nil))
  }

  @Test("--instance name produces named app mode")
  func instanceNameProducesNamedApp() throws {
    let mode = try CLIMode.parse(["myapp", "--instance", "dev"])
    #expect(mode == .app(instanceName: "dev"))
  }

  @Test("--instances produces listInstances mode")
  func listInstances() throws {
    let mode = try CLIMode.parse(["myapp", "--instances"])
    #expect(mode == .listInstances)
  }

  @Test("--scenes produces listScenes with no selector")
  func listScenesNoSelector() throws {
    let mode = try CLIMode.parse(["myapp", "--scenes"])
    #expect(mode == .listScenes(selector: .mostRecent))
  }

  @Test("--scenes --pid 1234 produces listScenes with pid selector")
  func listScenesWithPid() throws {
    let mode = try CLIMode.parse(["myapp", "--scenes", "--pid", "1234"])
    #expect(mode == .listScenes(selector: .pid(1234)))
  }

  @Test("--scenes --instance dev produces listScenes with name selector")
  func listScenesWithInstance() throws {
    let mode = try CLIMode.parse(["myapp", "--scenes", "--instance", "dev"])
    #expect(mode == .listScenes(selector: .name("dev")))
  }

  @Test("--attach dashboard produces attach mode")
  func attachScene() throws {
    let mode = try CLIMode.parse(["myapp", "--attach", "dashboard"])
    #expect(mode == .attach(sceneID: "dashboard", selector: .mostRecent))
  }

  @Test("--attach dashboard --pid 5678 produces attach with pid")
  func attachWithPid() throws {
    let mode = try CLIMode.parse(["myapp", "--attach", "dashboard", "--pid", "5678"])
    #expect(mode == .attach(sceneID: "dashboard", selector: .pid(5678)))
  }

  @Test("Missing value for --attach throws error")
  func missingAttachValue() {
    #expect(throws: CLIModeError.self) {
      try CLIMode.parse(["myapp", "--attach"])
    }
  }

  @Test("Missing value for --pid throws error")
  func missingPidValue() {
    #expect(throws: CLIModeError.self) {
      try CLIMode.parse(["myapp", "--scenes", "--pid"])
    }
  }

  @Test("Invalid pid throws error")
  func invalidPid() {
    #expect(throws: CLIModeError.self) {
      try CLIMode.parse(["myapp", "--scenes", "--pid", "abc"])
    }
  }

  @Test("Subcommand 'instances' produces listInstances mode")
  func subcommandInstances() throws {
    let mode = try CLIMode.parse(["myapp", "instances"])
    #expect(mode == .listInstances)
  }

  @Test("Subcommand 'scenes' produces listScenes with no selector")
  func subcommandScenes() throws {
    let mode = try CLIMode.parse(["myapp", "scenes"])
    #expect(mode == .listScenes(selector: .mostRecent))
  }

  @Test("Subcommand 'scenes --pid 1234' produces listScenes with pid selector")
  func subcommandScenesWithPid() throws {
    let mode = try CLIMode.parse(["myapp", "scenes", "--pid", "1234"])
    #expect(mode == .listScenes(selector: .pid(1234)))
  }

  @Test("Subcommand 'scenes --instance dev' produces listScenes with name selector")
  func subcommandScenesWithInstance() throws {
    let mode = try CLIMode.parse(["myapp", "scenes", "--instance", "dev"])
    #expect(mode == .listScenes(selector: .name("dev")))
  }

  @Test("Subcommand 'attach dashboard' produces attach mode")
  func subcommandAttach() throws {
    let mode = try CLIMode.parse(["myapp", "attach", "dashboard"])
    #expect(mode == .attach(sceneID: "dashboard", selector: .mostRecent))
  }

  @Test("Subcommand 'attach dashboard --pid 5678' produces attach with pid")
  func subcommandAttachWithPid() throws {
    let mode = try CLIMode.parse(["myapp", "attach", "dashboard", "--pid", "5678"])
    #expect(mode == .attach(sceneID: "dashboard", selector: .pid(5678)))
  }

  @Test("Subcommand 'attach dashboard --instance dev' produces attach with instance")
  func subcommandAttachWithInstance() throws {
    let mode = try CLIMode.parse(["myapp", "attach", "dashboard", "--instance", "dev"])
    #expect(mode == .attach(sceneID: "dashboard", selector: .name("dev")))
  }

  @Test("Unknown consumer flags fall through to app mode")
  func unknownSubcommandFallsThroughToApp() throws {
    // A consumer's parser owns argv first; from CLIMode's perspective,
    // any non-runner-subcommand input should be treated as 'run mode'.
    let mode = try CLIMode.parse(["myapp", "--widgets", "10", "--show-ids"])
    #expect(mode == .app(instanceName: nil))
  }
}
