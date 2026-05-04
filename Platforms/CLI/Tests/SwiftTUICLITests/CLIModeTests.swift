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
}
