import Testing

@testable import SwiftTUICLI

struct CLIModeTests {
  // MARK: - Default subcommand (`Run`)

  @Test("No arguments produces app mode")
  func noArgumentsProducesApp() {
    let mode = CLIMode.parse(["myapp"])
    #expect(mode == .app(instanceName: nil))
  }

  @Test("--instance name routes through default subcommand to named app mode")
  func instanceNameRoutesToDefaultSubcommand() {
    let mode = CLIMode.parse(["myapp", "--instance", "dev"])
    #expect(mode == .app(instanceName: "dev"))
  }

  @Test("Explicit `run --instance` form produces named app mode")
  func explicitRunWithInstance() {
    let mode = CLIMode.parse(["myapp", "run", "--instance", "dev"])
    #expect(mode == .app(instanceName: "dev"))
  }

  // MARK: - `instances` subcommand

  @Test("Subcommand 'instances' produces listInstances mode")
  func subcommandInstances() {
    let mode = CLIMode.parse(["myapp", "instances"])
    #expect(mode == .listInstances)
  }

  // MARK: - `scenes` subcommand

  @Test("Subcommand 'scenes' produces listScenes with no selector")
  func subcommandScenes() {
    let mode = CLIMode.parse(["myapp", "scenes"])
    #expect(mode == .listScenes(selector: .mostRecent))
  }

  @Test("Subcommand 'scenes --pid 1234' produces listScenes with pid selector")
  func subcommandScenesWithPid() {
    let mode = CLIMode.parse(["myapp", "scenes", "--pid", "1234"])
    #expect(mode == .listScenes(selector: .pid(1234)))
  }

  @Test("Subcommand 'scenes --instance dev' produces listScenes with name selector")
  func subcommandScenesWithInstance() {
    let mode = CLIMode.parse(["myapp", "scenes", "--instance", "dev"])
    #expect(mode == .listScenes(selector: .name("dev")))
  }

  // MARK: - `attach` subcommand

  @Test("Subcommand 'attach dashboard' produces attach mode")
  func subcommandAttach() {
    let mode = CLIMode.parse(["myapp", "attach", "dashboard"])
    #expect(mode == .attach(sceneID: "dashboard", selector: .mostRecent))
  }

  @Test("Subcommand 'attach dashboard --pid 5678' produces attach with pid")
  func subcommandAttachWithPid() {
    let mode = CLIMode.parse(["myapp", "attach", "dashboard", "--pid", "5678"])
    #expect(mode == .attach(sceneID: "dashboard", selector: .pid(5678)))
  }

  @Test("Subcommand 'attach dashboard --instance dev' produces attach with instance")
  func subcommandAttachWithInstance() {
    let mode = CLIMode.parse(["myapp", "attach", "dashboard", "--instance", "dev"])
    #expect(mode == .attach(sceneID: "dashboard", selector: .name("dev")))
  }

  // MARK: - Consumer-flag passthrough

  @Test("Consumer flags fall through to plain app mode")
  func consumerFlagsFallThroughToApp() {
    // A `SwiftTUICommand` consumer owns argv first; from CLIMode's perspective,
    // any non-runner-subcommand input should be treated as 'run mode'.
    let mode = CLIMode.parse(["myapp", "--widgets", "10", "--show-ids"])
    #expect(mode == .app(instanceName: nil))
  }
}
