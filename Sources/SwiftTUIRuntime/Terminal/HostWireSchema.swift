import SwiftTUICore

/// The canonical manifest of the cross-host wire schema: which source-of-truth
/// fields each host wire carries, under which key, and which divergences are
/// deliberate.
///
/// ``HostFrameProjection`` is the single seam both host encoders *read* a frame
/// through; this manifest is the single place the *serialized* surface is
/// named. The two are pinned against reality by three totality suites:
/// - `WebSurfaceWireTotalityTests` (WASI) and `AndroidHostWireTotalityTests`
///   (Android) encode a fully-populated frame and assert the emitted JSON key
///   sets equal the manifest's — both directions, so an encoder-only field or
///   a manifest-only field each fail.
/// - `HostWireSchemaContractTests` (runtime) mirrors the source-of-truth types
///   and asserts every stored property has a mapping here — the ratchet for
///   the "add a field, wire one encoder, forget the other" bug class.
///
/// ## Wire-evolution policy (load-bearing)
///
/// Deployed decoders (browser `WebHostSurfaceTransport.ts`, Android
/// `SwiftTUIFrame.parse`) are positive-check allowlists:
/// - Unknown *object keys* are ignored, so new data MUST ship as new optional
///   object keys (additive evolution). Absent means "feature not present".
/// - The web cell/rect/point/size *tuples* are validated with exact-length
///   guards; an extra element degrades the whole record to a text diagnostic
///   on deployed clients. Never extend a tuple — add a parallel keyed field.
/// - The web `version` literals are hard-matched (`1|2` full, `3` delta) and
///   describe the record *shape*, not the contract revision. Never bump them
///   for an additive field. Android `schemaVersion` is tolerant-defaulted.
package enum HostWireSchema {
  // MARK: - Source-of-truth field mappings

  /// How one stored property of a source-of-truth type lands on a host wire.
  package enum WireTreatment: Equatable, Sendable {
    /// Serialized under this JSON object key.
    case key(String)
    /// Serialized positionally at this index of the named wire tuple.
    case tupleSlot(Int, of: String)
    /// Carried via several wire fields; the string names them.
    case decomposed(String)
    /// Not carried verbatim; transformed into the named emitted field(s).
    case derived(String)
    /// Deliberately not on this host's wire; the rationale is required.
    case notSerialized(String)
  }

  /// One stored property of a source-of-truth type and its treatment on each
  /// host wire. `property` must match the `Mirror` child label exactly.
  package struct FieldMapping: Sendable {
    package let property: String
    package let web: WireTreatment
    package let android: WireTreatment

    package init(
      _ property: String,
      web: WireTreatment,
      android: WireTreatment
    ) {
      self.property = property
      self.web = web
      self.android = android
    }
  }

  /// Mappings keyed by source-of-truth type name, one entry per stored
  /// property. `HostWireSchemaContractTests` asserts each list matches the
  /// type's `Mirror` children exactly, in both directions.
  package static let sourceFieldMappings: [String: [FieldMapping]] = [
    "HostFrameProjection": [
      .init("sequence", web: .key("sequence"), android: .key("sequence")),
      .init(
        "raster",
        web: .decomposed("width/height/styles/rows|deltaRows/images/links/linkTargets"),
        android: .decomposed("gridWidth/gridHeight/rows/cells/imageAttachments")
      ),
      .init(
        "preferredLayoutSize",
        web: .decomposed("preferredGridWidth/preferredGridHeight"),
        android: .decomposed("preferredGridWidth/preferredGridHeight")
      ),
      .init(
        "semantics",
        web: .decomposed(
          "accessibilityTree/accessibilityAnnouncements/scrollRegions/focusPresentation"),
        android: .decomposed(
          "accessibilityNodes/accessibilityAnnouncements/scrollRegions/focusPresentation")
      ),
      .init(
        "focusedIdentity",
        web: .derived("per-node isFocused + focusPresentation.focusedIdentity"),
        android: .key("focusedIdentity")
      ),
      .init(
        "rasterDamage",
        web: .key("damage"),
        android: .decomposed(
          "dirtyRows/textDamageRows/requiresFullTextRepaint/requiresFullGraphicsReplay")
      ),
    ],
    "RasterSurface": [
      .init(
        "size",
        web: .decomposed("width/height"),
        android: .decomposed("gridWidth/gridHeight")
      ),
      .init(
        "cells",
        web: .decomposed("rows|deltaRows + links/linkTargets"),
        android: .decomposed("rows (plain text) + cells (styled)")
      ),
      .init(
        "attachments",
        web: .notSerialized("legacy debug strings; not part of any host render contract"),
        android: .notSerialized("legacy debug strings; not part of any host render contract")
      ),
      .init(
        "imageAttachments",
        web: .key("images"),
        android: .key("imageAttachments")
      ),
      .init(
        "metadata",
        web: .notSerialized("diagnostic key-values; hosts render cells, not metadata"),
        android: .notSerialized("diagnostic key-values; hosts render cells, not metadata")
      ),
      .init(
        "presentationLayers",
        web: .notSerialized("package-internal compositing intermediates, flattened into cells"),
        android: .notSerialized("package-internal compositing intermediates, flattened into cells")
      ),
    ],
    "RasterCell": [
      .init(
        "character",
        web: .tupleSlot(1, of: "cell"),
        android: .key("character")
      ),
      .init(
        "spanWidth",
        web: .tupleSlot(2, of: "cell"),
        android: .key("spanWidth")
      ),
      .init(
        "continuationLeadX",
        web: .notSerialized("web drops continuation cells; the lead cell's spanWidth covers them"),
        android: .key("continuationLeadX")
      ),
      .init(
        "style",
        web: .tupleSlot(3, of: "cell"),
        android: .key("style")
      ),
      .init(
        "hyperlink",
        web: .decomposed("links (per-row runs) + linkTargets (deduplicated URLs)"),
        android: .key("hyperlink")
      ),
    ],
    "ResolvedTextStyle": [
      .init("foregroundColor", web: .key("fg"), android: .key("foregroundColor")),
      .init("backgroundColor", web: .key("bg"), android: .key("backgroundColor")),
      .init(
        "emphasis",
        web: .key("em"),
        android: .key("emphasis")
      ),
      .init("underlineStyle", web: .key("underline"), android: .key("underlineStyle")),
      .init("strikethroughStyle", web: .key("strikethrough"), android: .key("strikethroughStyle")),
      .init("opacity", web: .key("opacity"), android: .key("opacity")),
    ],
    "TextLineStyle": [
      .init("pattern", web: .key("pattern"), android: .key("pattern")),
      .init("color", web: .key("color"), android: .key("color")),
    ],
    "RasterImageAttachment": [
      .init("identity", web: .key("id"), android: .key("id")),
      .init("bounds", web: .key("bounds"), android: .key("bounds")),
      .init("visibleBounds", web: .key("visibleBounds"), android: .key("visibleBounds")),
      .init(
        "source",
        web: .derived("format + dataBase64 via the resolved reference"),
        android: .decomposed("sourceKind/sourceIdentifier")
      ),
      .init(
        "resolvedReference",
        web: .decomposed("format/dataBase64"),
        android: .decomposed("payloadBase64/payloadByteCount")
      ),
      .init("pixelSize", web: .key("pixelSize"), android: .key("pixelSize")),
      .init(
        "cellPixelSize",
        web: .notSerialized("the browser derives cell metrics from its own font raster"),
        android: .key("cellPixelSize")
      ),
      .init(
        "isResizable",
        web: .notSerialized("web resizes are round-tripped through the runtime, not host-local"),
        android: .key("isResizable")
      ),
      .init("scalingMode", web: .key("scalingMode"), android: .key("scalingMode")),
      .init(
        "compositing",
        web: .derived("pre-blended PNG payload replaces the raw source when compositing is set"),
        android: .derived(
          "pre-blended PNG payload replaces the raw source when compositing is set (sourceKind precomposedPNG)")
      ),
    ],
    "AccessibilityNode": [
      .init(
        "viewNodeID",
        web: .notSerialized("package-internal graph plumbing"),
        android: .notSerialized("package-internal graph plumbing")
      ),
      .init("identity", web: .key("id"), android: .key("id")),
      .init(
        "parentIdentity",
        web: .key("parentId"),
        android: .key("parentID")
      ),
      .init("rect", web: .key("rect"), android: .key("rect")),
      .init("role", web: .key("role"), android: .key("role")),
      .init("label", web: .key("label"), android: .key("label")),
      .init("hint", web: .key("hint"), android: .key("hint")),
      .init("hidden", web: .key("hidden"), android: .key("hidden")),
      .init("liveRegion", web: .key("liveRegion"), android: .key("liveRegion")),
      .init("cursorAnchor", web: .key("cursorAnchor"), android: .key("cursorAnchor")),
    ],
    "AccessibilityAnnouncement": [
      .init("message", web: .key("message"), android: .key("message")),
      .init("politeness", web: .key("politeness"), android: .key("politeness")),
    ],
    "ScrollRoute": [
      .init("identity", web: .key("id"), android: .key("id")),
      .init(
        "viewNodeID",
        web: .notSerialized("package-internal graph plumbing"),
        android: .notSerialized("package-internal graph plumbing")
      ),
      .init("viewportRect", web: .key("rect"), android: .key("rect")),
      .init(
        "contentBounds",
        web: .derived("content = contentBounds.size"),
        android: .derived("content = contentBounds.size")
      ),
      .init("contentOffset", web: .key("offset"), android: .key("offset")),
      .init(
        "structuralHostChain",
        web: .notSerialized("package-internal scope-containment routing"),
        android: .notSerialized("package-internal scope-containment routing")
      ),
    ],
    "FocusPresentation": [
      .init("focusedIdentity", web: .key("focusedIdentity"), android: .key("focusedIdentity")),
      .init("semantics", web: .key("semantics"), android: .key("semantics")),
    ],
    "PresentationDamage": [
      .init("textRows", web: .key("textRows"), android: .key("textDamageRows")),
      .init(
        "graphicsInvalidation",
        web: .notSerialized("package-internal invalidation bookkeeping"),
        android: .notSerialized("package-internal invalidation bookkeeping")
      ),
      .init(
        "requiresFullTextRepaint",
        web: .key("requiresFullTextRepaint"),
        android: .key("requiresFullTextRepaint")
      ),
      .init(
        "requiresFullGraphicsReplay",
        web: .key("requiresFullGraphicsReplay"),
        android: .key("requiresFullGraphicsReplay")
      ),
    ],
    "PresentationDamage.TextRow": [
      .init(
        "row",
        web: .tupleSlot(0, of: "textRow"),
        android: .key("row")
      ),
      .init(
        "columnRanges",
        web: .tupleSlot(1, of: "textRow"),
        android: .key("columnRanges")
      ),
    ],
  ]

  // MARK: - Web wire key sets (`surface` records)

  /// The web `surface` record surface. Key sets split required/optional; the
  /// totality test fully populates a frame so required ∪ optional must all be
  /// present on the wire.
  package enum WebWire {
    package static let fullFrameKeys: Set<String> = [
      "version", "width", "height", "styles", "rows", "images",
    ]
    package static let fullFrameOptionalKeys: Set<String> = [
      "sequence", "damage", "accessibilityTree", "accessibilityAnnouncements",
      "scrollRegions", "links", "linkTargets", "focusPresentation",
      "preferredGridWidth", "preferredGridHeight",
    ]
    package static let deltaFrameKeys: Set<String> = [
      "version", "encoding", "width", "height", "styles", "deltaRows", "images",
      "damage",
    ]
    package static let deltaFrameOptionalKeys: Set<String> = [
      "sequence", "accessibilityTree", "accessibilityAnnouncements",
      "scrollRegions", "links", "linkTargets", "focusPresentation",
      "preferredGridWidth", "preferredGridHeight",
    ]
    package static let styleKeys: Set<String> = [
      "fg", "bg", "em", "underline", "strikethrough", "opacity",
    ]
    package static let lineStyleKeys: Set<String> = ["pattern", "color"]
    package static let imageKeys: Set<String> = [
      "id", "format", "bounds", "visibleBounds", "scalingMode", "pixelSize",
      "dataBase64",
    ]
    package static let damageKeys: Set<String> = [
      "textRows", "requiresFullTextRepaint", "requiresFullGraphicsReplay",
    ]
    package static let accessibilityNodeKeys: Set<String> = [
      "id", "rect", "role", "isFocused", "parentId", "label", "hint", "hidden",
      "liveRegion", "cursorAnchor",
    ]
    package static let accessibilityAnnouncementKeys: Set<String> = [
      "message", "politeness",
    ]
    package static let scrollRegionKeys: Set<String> = [
      "id", "rect", "offset", "content",
    ]
    package static let focusPresentationKeys: Set<String> = [
      "focusedIdentity", "semantics", "prefersTextInput", "hasFocusedRegion",
    ]
    /// `[x, text, spanWidth, styleIndex]` — FROZEN; see the tuple policy above.
    package static let cellTupleArity = 4
    /// `[rowIndex, runs]`.
    package static let linkRowTupleArity = 2
    /// `[x, spanWidth, linkTargetIndex]`.
    package static let linkRunTupleArity = 3
  }

  // MARK: - Android wire key sets (frame snapshot)

  /// The Android frame snapshot surface. Optional keys are nil-omitted by
  /// `JSONEncoder`; the totality test fully populates a frame so required ∪
  /// optional must all be present on the wire.
  package enum AndroidWire {
    package static let frameKeys: Set<String> = [
      "schemaVersion", "sequence", "gridWidth", "gridHeight", "terminalStyle",
      "rows", "cells", "imageAttachments", "focusPresentation",
      "accessibilityNodes", "accessibilityAnnouncements", "dirtyRows",
      "textDamageRows", "requiresFullTextRepaint", "requiresFullGraphicsReplay",
    ]
    package static let frameOptionalKeys: Set<String> = [
      "preferredGridWidth", "preferredGridHeight", "focusedIdentity",
      "scrollRegions",
    ]
    package static let cellKeys: Set<String> = [
      "x", "y", "character", "spanWidth", "continuationLeadX", "style",
      "hyperlink",
    ]
    package static let styleKeys: Set<String> = [
      "foregroundColor", "backgroundColor", "emphasis", "underlineStyle",
      "strikethroughStyle", "opacity",
    ]
    package static let lineStyleKeys: Set<String> = ["pattern", "color"]
    package static let terminalStyleKeys: Set<String> = [
      "foregroundColor", "backgroundColor", "tintColor",
    ]
    package static let colorKeys: Set<String> = ["hex"]
    package static let imageAttachmentKeys: Set<String> = [
      "id", "bounds", "visibleBounds", "sourceKind", "sourceIdentifier",
      "payloadBase64", "payloadByteCount", "pixelSize", "cellPixelSize",
      "isResizable", "scalingMode",
    ]
    package static let focusPresentationKeys: Set<String> = [
      "focusedIdentity", "semantics", "prefersTextInput", "hasFocusedRegion",
    ]
    package static let accessibilityNodeKeys: Set<String> = [
      "id", "parentID", "rect", "role", "label", "hint", "hidden", "liveRegion",
      "cursorAnchor", "isFocused",
    ]
    package static let accessibilityAnnouncementKeys: Set<String> = [
      "message", "politeness",
    ]
    package static let scrollRegionKeys: Set<String> = [
      "id", "rect", "offset", "content",
    ]
    package static let textDamageRowKeys: Set<String> = ["row", "columnRanges"]
    package static let rangeKeys: Set<String> = ["lowerBound", "upperBound"]
    package static let rectKeys: Set<String> = ["x", "y", "width", "height"]
    package static let pointKeys: Set<String> = ["x", "y"]
    package static let sizeKeys: Set<String> = ["width", "height"]
  }

  // MARK: - Shared wire tokens

  /// The focus-semantics wire token, shared by both host wires so the two
  /// encoders cannot drift. Android's encoder is asserted against this map by
  /// `AndroidHostWireTotalityTests`; the web encoder consumes it directly.
  package static func focusSemanticsToken(
    _ semantics: FocusPresentation.Semantics
  ) -> String {
    switch semantics {
    case .none:
      "none"
    case .automatic:
      "automatic"
    case .activate:
      "activate"
    case .edit:
      "edit"
    }
  }
}
