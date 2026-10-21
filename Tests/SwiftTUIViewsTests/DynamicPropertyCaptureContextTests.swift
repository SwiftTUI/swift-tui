import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct DynamicPropertyCaptureContextTests {
  private struct Probe: DynamicProperty, CaptureBindableDynamicProperty {
    var capture: DynamicPropertyCaptureContext?

    mutating func bindCapture(_ context: DynamicPropertyCaptureContext) {
      capture = context
    }
  }

  private struct Nested: DynamicProperty {
    var probe = Probe()
  }

  private struct Container {
    var direct = Probe()
    var nested = Nested()
  }

  @Test("graphless forwarded preparation carries services and clears a previous owner")
  func graphlessServices() throws {
    let enabled = StateCaptureBindingConfiguration.isEnabled
    StateCaptureBindingConfiguration.isEnabled = true
    defer { StateCaptureBindingConfiguration.isEnabled = enabled }
    var environment = EnvironmentValues()
    environment.imageResourceRoots = ["declaration"]
    let prepared = EnvironmentValuesStorage.binding(environment) {
      bindingForwardedDynamicPropertyCaptures(Container())
    }
    let capture = try #require(prepared.direct.capture)
    #expect(capture.ownedSlot == nil)
    #expect(capture.environment.imageResourceRoots == ["declaration"])
    #expect(prepared.nested.probe.capture?.environment.imageResourceRoots == ["declaration"])

    let graph = ViewGraph()
    let node = graph.prepareDynamicPropertyUpdate(identity: testIdentity("capture-context"))
    let scope = AuthoringContext(
      viewIdentity: node.identity, focusedValues: .init(), viewNode: node)
    let mounted = withAuthoringContext(scope) {
      bindingForwardedDynamicPropertyCaptures(prepared)
    }
    #expect(mounted.direct.capture?.ownedSlot?.owner == node.stateOwnerHandle)
    #expect(mounted.nested.probe.capture?.ownedSlot?.path == StateSlotPath.root.appending(1))
    let graphless = bindingForwardedDynamicPropertyCaptures(mounted)
    #expect(graphless.direct.capture?.ownedSlot == nil)
    #expect(graphless.nested.probe.capture?.ownedSlot == nil)
    #expect(prepared.direct.capture?.ownedSlot == nil)
  }
}
