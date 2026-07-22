import SwiftTUICore
import Testing

@testable import SwiftTUIRuntime

/// The ratchet for the cross-host serialization bug class: every stored
/// property of a source-of-truth wire type must have an explicit
/// ``HostWireSchema`` mapping — a wire key, a decomposition, or a
/// deliberate not-serialized rationale. Adding a stored property to any of
/// these types without deciding its wire treatment fails here; the encoder
/// totality suites (`WebSurfaceWireTotalityTests`,
/// `AndroidHostWireTotalityTests`) then hold the mapping to reality.
@Suite
struct HostWireSchemaContractTests {
  private static func fixtures() -> [(typeName: String, instance: Any)] {
    [
    (
      "HostFrameProjection",
      HostFrameProjection(
        SemanticHostFrame(
          sequence: 1,
          raster: RasterSurface(size: CellSize(width: 1, height: 1), lines: [" "]),
          semantics: SemanticSnapshot(),
          focusedIdentity: nil
        )
      )
    ),
    ("RasterSurface", RasterSurface()),
    ("RasterCell", RasterCell.empty),
    ("ResolvedTextStyle", ResolvedTextStyle()),
    ("TextLineStyle", TextLineStyle()),
    (
      "RasterImageAttachment",
      RasterImageAttachment(
        identity: Identity(components: ["image"]),
        bounds: CellRect(origin: .zero, size: CellSize(width: 1, height: 1)),
        source: .data([1])
      )
    ),
    (
      "AccessibilityNode",
      AccessibilityNode(
        identity: Identity(components: ["node"]),
        rect: CellRect(origin: .zero, size: CellSize(width: 1, height: 1)),
        role: .group
      )
    ),
    ("AccessibilityAnnouncement", AccessibilityAnnouncement(message: "m")),
    (
      "ScrollRoute",
      ScrollRoute(
        identity: Identity(components: ["list"]),
        viewportRect: CellRect(origin: .zero, size: CellSize(width: 1, height: 1)),
        contentBounds: CellRect(origin: .zero, size: CellSize(width: 1, height: 2))
      )
    ),
    ("FocusPresentation", FocusPresentation.none),
    ("PresentationDamage", PresentationDamage()),
    ("PresentationDamage.TextRow", PresentationDamage.TextRow(row: 0)),
    ]
  }

  @Test("every mapped type's stored properties match its manifest mapping exactly")
  func storedPropertiesMatchManifestMappings() {
    for (typeName, instance) in Self.fixtures() {
      let stored = Set(Mirror(reflecting: instance).children.compactMap(\.label))
      let mapped = Set(
        (HostWireSchema.sourceFieldMappings[typeName] ?? []).map(\.property)
      )
      #expect(
        stored == mapped,
        """
        \(typeName): stored properties and HostWireSchema mappings diverge. \
        Unmapped stored properties (decide a wire treatment): \
        \(stored.subtracting(mapped).sorted()). \
        Mapped-but-gone properties (stale manifest entries): \
        \(mapped.subtracting(stored).sorted()).
        """
      )
    }
  }

  @Test("the manifest maps exactly the fixture-covered types")
  func manifestTypeCoverageMatchesFixtures() {
    let fixtureTypes = Set(Self.fixtures().map(\.typeName))
    let mappedTypes = Set(HostWireSchema.sourceFieldMappings.keys)
    #expect(
      fixtureTypes == mappedTypes,
      """
      Types mapped in HostWireSchema but missing a Mirror fixture here: \
      \(mappedTypes.subtracting(fixtureTypes).sorted()). Fixture types with no \
      manifest mapping: \(fixtureTypes.subtracting(mappedTypes).sorted()).
      """
    )
  }

  @Test("capability mappings match HostWireCapabilities stored properties exactly")
  func capabilityMappingsMatchStoredProperties() {
    let stored = Set(
      Mirror(reflecting: HostWireCapabilities()).children.compactMap(\.label)
    )
    let mapped = Set(HostWireSchema.capabilityMappings.map(\.field))
    #expect(
      stored == mapped,
      """
      HostWireCapabilities and HostWireSchema.capabilityMappings diverge. \
      Unmapped stored properties (name each transport's ingress + default): \
      \(stored.subtracting(mapped).sorted()). \
      Mapped-but-gone properties (stale manifest entries): \
      \(mapped.subtracting(stored).sorted()).
      """
    )
  }

  @Test("every capability mapping names its default and all three ingresses")
  func capabilityMappingsCarryDefaultsAndIngresses() {
    for mapping in HostWireSchema.capabilityMappings {
      #expect(!mapping.defaultValue.isEmpty, "\(mapping.field): empty default")
      #expect(!mapping.wasiIngress.isEmpty, "\(mapping.field): empty WASI ingress")
      #expect(!mapping.webSocketIngress.isEmpty, "\(mapping.field): empty WebSocket ingress")
      #expect(!mapping.androidIngress.isEmpty, "\(mapping.field): empty Android ingress")
    }
  }

  @Test("every not-serialized treatment carries a rationale")
  func notSerializedTreatmentsCarryRationales() {
    for (typeName, mappings) in HostWireSchema.sourceFieldMappings {
      for mapping in mappings {
        for treatment in [mapping.web, mapping.android] {
          if case .notSerialized(let rationale) = treatment {
            #expect(
              !rationale.isEmpty,
              "\(typeName).\(mapping.property): empty not-serialized rationale"
            )
          }
        }
      }
    }
  }
}
