import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUI
@testable import SwiftTUIViews

@MainActor
@Suite
struct CaptureOnPressTests {
  @Test("InteractionRegion carries captureOnPress from SemanticMetadata")
  func regionCarriesCaptureFlag() throws {
    let identity = Identity(components: [IdentityComponent(rawValue: "root")])
    let meta = SemanticMetadata(
      participatesInPointerHitTesting: true,
      captureOnPress: true
    )
    #expect(meta.captureOnPress == true)

    let merged = SemanticMetadata().merging(meta)
    #expect(merged.captureOnPress == true)

    let region = InteractionRegion(
      identity: identity,
      rect: CellRect(origin: .zero, size: CellSize(width: 4, height: 1)),
      routeID: RouteID(identity: identity),
      hitTestOrder: 0,
      captureOnPress: true
    )
    #expect(region.captureOnPress == true)
  }

  @Test("Slider track region captures on press after migration")
  func sliderTrackRegionCaptures() throws {
    final class Model {
      var value: Double = 0.5
    }
    let model = Model()
    let identity = Identity(components: [IdentityComponent(rawValue: "root")])
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 20, height: 3)

    let artifacts = DefaultRenderer().render(
      Slider(
        "Test",
        value: Binding(
          mainActorGet: { model.value },
          set: { model.value = $0 }
        ), in: 0.0...1.0),
      context: .init(identity: identity, environmentValues: env),
      proposal: .init(width: 20, height: 3)
    )

    let trackRegion = try #require(
      artifacts.semanticSnapshot.interactionRegions.first { region in
        routeIDHasTerminalComponent(
          region.routeID,
          hasTerminalComponent: .sliderTrack
        )
      }
    )
    #expect(trackRegion.captureOnPress == true)
  }

  @Test("Button region does not capture on press")
  func buttonRegionDoesNotCapture() throws {
    let identity = Identity(components: [IdentityComponent(rawValue: "root")])
    var env = EnvironmentValues()
    env.terminalSize = CellSize(width: 10, height: 3)

    let artifacts = DefaultRenderer().render(
      Button("OK", action: {}),
      context: .init(identity: identity, environmentValues: env),
      proposal: .init(width: 10, height: 3)
    )

    let buttonRegion = try #require(
      artifacts.semanticSnapshot.interactionRegions.first
    )
    #expect(buttonRegion.captureOnPress == false)
  }
}
