import Testing

@testable import SwiftTUIGraph

@MainActor
struct OwnedDormantStateTests {
  private final class Model { var value = 0 }
  private struct Payload { var models: [String: Model?] }
  private final class Probe { weak var value: Model? }

  @Test("detached reference envelopes release their last model owner")
  func releasesDetachedOwnership() {
    let probe = Probe()
    captureAndRelease(probe)
    #expect(probe.value == nil)
  }

  private func captureAndRelease(_ probe: Probe) {
    let model = Model()
    probe.value = model
    let slot = withOwnedDormantStateSlot { AnyStateSlot(model) }
    let snapshot = slot.dormantSnapshot()!
    let restored = AnyStateSlot(restoringDormant: snapshot)
    #expect(restored.dormantPolicy == .owned)
  }

  @Test("authored ownership survives nested envelopes and keeps its provenance")
  func ownedProjection() throws {
    let model = Model()
    let slot = withOwnedDormantStateSlot { AnyStateSlot(Payload(models: ["model": model])) }
    let snapshot = try #require(slot.dormantSnapshot())
    let restored = AnyStateSlot(restoringDormant: snapshot)
    #expect(restored.dormantPolicy == .owned)
    #expect(restored.value(as: Payload.self).models["model"]! === model)
    #expect(restored.dormantSnapshot() != nil)
    let frameworkSlot = withPersistentDormantStateSlot { AnyStateSlot(model) }
    #expect(frameworkSlot.dormantSnapshot() == nil)
    let nested = withPersistentDormantStateSlot { AnyStateSlot([snapshot]) }
    #expect(nested.dormantSnapshot() != nil)
  }

  @Test("owned state still rejects direct closures and runtime identities")
  func runtimeEdgesRemainUnsupported() {
    let closure = withOwnedDormantStateSlot { AnyStateSlot({ 1 }) }
    let metatype = withOwnedDormantStateSlot { AnyStateSlot(Model.self) }
    let identity = withOwnedDormantStateSlot { AnyStateSlot(ObjectIdentifier(Model())) }
    #expect(closure.dormantSnapshot() == nil)
    #expect(metatype.dormantSnapshot() == nil)
    #expect(identity.dormantSnapshot() == nil)
  }

  private struct Palette: Equatable {
    var accent: Color
    var cells: [RasterCell]
  }

  private struct Redacted: CustomReflectable {
    var visible = 1
    var hidden = Model()

    var customMirror: Mirror {
      Mirror(self, children: ["visible": visible])
    }
  }

  // A colour holds a colour profile and a raster cell holds its style in a
  // shared attributes object; both types reflect their value through a custom
  // mirror. Framework persistence refuses custom mirrors it cannot trust, and
  // must not refuse these: a tab that keeps a colour in `@State` would restart
  // it on every revisit.
  @Test("framework persistence archives colours, colour profiles and raster cells")
  func frameworkValueTypesWithCustomMirrorsArchive() throws {
    let customProfile = RGBColorProfile(
      name: "Custom",
      primaries: RGBColorProfile.displayP3.primaries,
      whitePoint: RGBColorProfile.sRGB.whitePoint,
      transferFunction: RGBColorProfile.sRGB.transferFunction
    )
    let wide = Color(white: 0.25, profile: customProfile)
    let styled = RasterCell(
      character: "x",
      style: ResolvedTextStyle(foregroundColor: wide),
      hyperlink: "https://example.com"
    )

    func archived<Value: Equatable>(_ value: Value) throws -> Value {
      let slot = withPersistentDormantStateSlot { AnyStateSlot(value) }
      let snapshot = try #require(slot.dormantSnapshot(), "\(Value.self) was refused")
      return AnyStateSlot(restoringDormant: snapshot).value(as: Value.self)
    }

    #expect(try archived(Color(white: 0.5)) == Color(white: 0.5))
    #expect(try archived(wide) == wide)
    #expect(try archived(RGBColorProfile.displayP3) == .displayP3)
    #expect(try archived(customProfile) == customProfile)
    #expect(try archived(RasterCell.empty) == .empty)
    #expect(try archived(styled) == styled)
    let palette = Palette(accent: wide, cells: [.empty, styled])
    #expect(try archived(palette) == palette)
    #expect(try archived(Optional(wide)) == wide)
  }

  @Test("a custom mirror the framework cannot vouch for is still refused")
  func untrustedCustomMirrorIsRefused() {
    let slot = withPersistentDormantStateSlot { AnyStateSlot(Redacted()) }
    #expect(slot.dormantSnapshot() == nil)
    let nested = withPersistentDormantStateSlot { AnyStateSlot([Redacted()]) }
    #expect(nested.dormantSnapshot() == nil)
  }

  @Test("checkpoint rollback restores reference ownership without cloning models")
  func checkpointRestoresOwnership() {
    let node = ViewNode(viewNodeID: ViewNodeID(rawValue: 1), identity: testIdentity("Owner"))
    let original = Model()
    withOwnedDormantStateSlot { node.setStateSlotSilently(ordinal: 0, value: original) }
    let checkpoint = node.makeCheckpoint()
    let replacement = Model()
    node.setStateSlotSilently(ordinal: 0, value: replacement)
    original.value = 42
    node.restoreCheckpoint(checkpoint)
    let restored: Model = node.stateSlot(ordinal: 0, seed: Model())
    #expect(restored === original)
    #expect(restored.value == 42)
    #expect(node.stateSlotStorage(ordinal: 0)?.dormantPolicy == .owned)
  }
}
