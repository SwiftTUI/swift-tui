import SwiftTUICore

/// The canonical manifest of the cross-host wire schema: which source-of-truth
/// fields each host wire carries, under which key, and which divergences are
/// deliberate.
///
/// ``HostFrameProjection`` is the single seam host serialization reads a frame
/// through; this manifest is the single place the *serialized* surface is
/// named. Since the Android host converged onto the web-surface wire and the
/// legacy keyed-JSON format was retired (convergence proposal
/// 2026-07-22-002, Stage C4), every host speaks ONE wire. It is pinned
/// against reality by two suites:
/// - `WebSurfaceWireTotalityTests` encodes a fully-populated frame and
///   asserts the emitted JSON key sets equal the manifest's — both
///   directions, so an encoder-only field and a manifest-only field each
///   fail.
/// - `HostWireSchemaContractTests` (runtime) mirrors the source-of-truth types
///   and asserts every stored property has a mapping here — the ratchet for
///   the "add a field and forget its wire treatment" bug class.
///
/// ## Wire-evolution policy (load-bearing)
///
/// Deployed decoders (browser `WebHostSurfaceTransport.ts`, Android
/// `SwiftTUIWebSurfaceSession`) are positive-check allowlists:
/// - Unknown *object keys* are ignored, so new data MUST ship as new optional
///   object keys (additive evolution). Absent means "feature not present".
/// - The cell/rect/point/size *tuples* are validated with exact-length
///   guards; an extra element degrades the whole record to a text diagnostic
///   on deployed clients. Never extend a tuple — add a parallel keyed field.
/// - The `version` literals are hard-matched (`1|2` full, `3` delta) and
///   describe the record *shape*, not the contract revision. Never bump them
///   for an additive field; anything newer is negotiated via
///   ``HostWireCapabilities``.
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

  /// One stored property of a source-of-truth type and its treatment on the
  /// converged wire. `property` must match the `Mirror` child label exactly.
  package struct FieldMapping: Sendable {
    package let property: String
    package let wire: WireTreatment

    package init(
      _ property: String,
      wire: WireTreatment
    ) {
      self.property = property
      self.wire = wire
    }
  }

  /// Mappings keyed by source-of-truth type name, one entry per stored
  /// property. `HostWireSchemaContractTests` asserts each list matches the
  /// type's `Mirror` children exactly, in both directions.
  package static let sourceFieldMappings: [String: [FieldMapping]] = [
    "HostFrameProjection": [
      .init("sequence", wire: .key("sequence")),
      .init(
        "raster",
        wire: .decomposed("width/height/styles/rows|deltaRows/images/links/linkTargets")),
      .init(
        "preferredLayoutSize",
        wire: .decomposed("preferredGridWidth/preferredGridHeight")),
      .init(
        "semantics",
        wire: .decomposed(
          "accessibilityTree/accessibilityAnnouncements/scrollRegions/focusPresentation")),
      .init(
        "focusedIdentity",
        wire: .derived("per-node isFocused + focusPresentation.focusedIdentity")),
      .init(
        "rasterDamage",
        wire: .key("damage")),
    ],
    "RasterSurface": [
      .init(
        "size",
        wire: .decomposed("width/height")),
      .init(
        "cells",
        wire: .decomposed("rows|deltaRows + links/linkTargets")),
      .init(
        "attachments",
        wire: .notSerialized("legacy debug strings; not part of any host render contract")),
      .init(
        "imageAttachments",
        wire: .key("images")),
      .init(
        "metadata",
        wire: .notSerialized("diagnostic key-values; hosts render cells, not metadata")),
      .init(
        "presentationLayers",
        wire: .notSerialized("package-internal compositing intermediates, flattened into cells")),
    ],
    "RasterCell": [
      .init(
        "character",
        wire: .tupleSlot(1, of: "cell")),
      .init(
        "spanWidth",
        wire: .tupleSlot(2, of: "cell")),
      .init(
        "continuationLeadX",
        wire: .notSerialized("web drops continuation cells; the lead cell's spanWidth covers them")),
      .init(
        "style",
        wire: .tupleSlot(3, of: "cell")),
      .init(
        "hyperlink",
        wire: .decomposed("links (per-row runs) + linkTargets (deduplicated URLs)")),
    ],
    "ResolvedTextStyle": [
      .init("foregroundColor", wire: .key("fg")),
      .init("backgroundColor", wire: .key("bg")),
      .init(
        "emphasis",
        wire: .key("em")),
      .init("underlineStyle", wire: .key("underline")),
      .init("strikethroughStyle", wire: .key("strikethrough")),
      .init("opacity", wire: .key("opacity")),
    ],
    "TextLineStyle": [
      .init("pattern", wire: .key("pattern")),
      .init("color", wire: .key("color")),
    ],
    "RasterImageAttachment": [
      .init("identity", wire: .key("id")),
      .init("bounds", wire: .key("bounds")),
      .init("visibleBounds", wire: .key("visibleBounds")),
      .init(
        "source",
        wire: .derived("format + dataBase64 via the resolved reference")),
      .init(
        "resolvedReference",
        wire: .decomposed("format/dataBase64")),
      .init("pixelSize", wire: .key("pixelSize")),
      .init(
        "cellPixelSize",
        wire: .notSerialized("the browser derives cell metrics from its own font raster")),
      .init(
        "isResizable",
        wire: .notSerialized("web resizes are round-tripped through the runtime, not host-local")),
      .init("scalingMode", wire: .key("scalingMode")),
      .init(
        "compositing",
        wire: .derived("pre-blended PNG payload replaces the raw source when compositing is set")),
    ],
    "AccessibilityNode": [
      .init(
        "viewNodeID",
        wire: .notSerialized("package-internal graph plumbing")),
      .init("identity", wire: .key("id")),
      .init(
        "parentIdentity",
        wire: .key("parentId")),
      .init("rect", wire: .key("rect")),
      .init("role", wire: .key("role")),
      .init("label", wire: .key("label")),
      .init("hint", wire: .key("hint")),
      .init("hidden", wire: .key("hidden")),
      .init("liveRegion", wire: .key("liveRegion")),
      .init("cursorAnchor", wire: .key("cursorAnchor")),
    ],
    "AccessibilityAnnouncement": [
      .init("message", wire: .key("message")),
      .init("politeness", wire: .key("politeness")),
    ],
    "ScrollRoute": [
      .init("identity", wire: .key("id")),
      .init(
        "viewNodeID",
        wire: .notSerialized("package-internal graph plumbing")),
      .init("viewportRect", wire: .key("rect")),
      .init(
        "contentBounds",
        wire: .derived("content = contentBounds.size")),
      .init("contentOffset", wire: .key("offset")),
      .init(
        "structuralHostChain",
        wire: .notSerialized("package-internal scope-containment routing")),
    ],
    "FocusPresentation": [
      .init("focusedIdentity", wire: .key("focusedIdentity")),
      .init("semantics", wire: .key("semantics")),
    ],
    "PresentationDamage": [
      .init("textRows", wire: .key("textRows")),
      .init(
        "graphicsInvalidation",
        wire: .notSerialized("package-internal invalidation bookkeeping")),
      .init(
        "requiresFullTextRepaint",
        wire: .key("requiresFullTextRepaint")),
      .init(
        "requiresFullGraphicsReplay",
        wire: .key("requiresFullGraphicsReplay")),
    ],
    "PresentationDamage.TextRow": [
      .init(
        "row",
        wire: .tupleSlot(0, of: "textRow")),
      .init(
        "columnRanges",
        wire: .tupleSlot(1, of: "textRow")),
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
      "preferredGridWidth", "preferredGridHeight", "terminalStyle",
    ]
    package static let deltaFrameKeys: Set<String> = [
      "version", "encoding", "width", "height", "styles", "deltaRows", "images",
      "damage",
    ]
    package static let deltaFrameOptionalKeys: Set<String> = [
      "sequence", "accessibilityTree", "accessibilityAnnouncements",
      "scrollRegions", "links", "linkTargets", "focusPresentation",
      "preferredGridWidth", "preferredGridHeight", "terminalStyle",
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
    /// Additive-optional: emitted only on streams whose host consumes a
    /// runtime-owned appearance (the converged Android path).
    package static let terminalStyleKeys: Set<String> = [
      "foregroundColor", "backgroundColor", "tintColor",
    ]
    package static let colorKeys: Set<String> = ["hex"]
    /// `[x, text, spanWidth, styleIndex]` — FROZEN; see the tuple policy above.
    package static let cellTupleArity = 4
    /// `[rowIndex, runs]`.
    package static let linkRowTupleArity = 2
    /// `[x, spanWidth, linkTargetIndex]`.
    package static let linkRunTupleArity = 3
  }

  // MARK: - Capability declarations

  /// One ``HostWireCapabilities`` field and its declaration ingress on each
  /// transport. `field` must match the `Mirror` child label exactly —
  /// `HostWireSchemaContractTests` asserts the mapping list matches the
  /// struct's stored properties in both directions, so a capability cannot
  /// be added without naming how every transport declares it.
  package struct CapabilityMapping: Sendable {
    package let field: String
    /// The default's meaning is load-bearing: absence of a declaration must
    /// reproduce today's bytes exactly.
    package let defaultValue: String
    /// WASI browser ingress (worker + JSPI): environment keys, resolved by
    /// `wasiHostWireCapabilities` beside the transport-mode resolution.
    package let wasiIngress: String
    /// WebHost WebSocket ingress: the `caps:{json}` control record, sent
    /// once by the client after open. Absence = defaults; unknown record
    /// types are silently dropped by `WebSurfaceInputParser`, so a new
    /// bundle against an old server degrades to defaults.
    package let webSocketIngress: String
    /// Android JNI ingress: the `declareCapabilities` host call, accepted
    /// only before scene start. The JNI glue resolves the symbol lazily, so
    /// a new AAR against an old host library degrades to defaults.
    package let androidIngress: String

    package init(
      _ field: String,
      defaultValue: String,
      wasi: String,
      webSocket: String,
      android: String
    ) {
      self.field = field
      self.defaultValue = defaultValue
      wasiIngress = wasi
      webSocketIngress = webSocket
      androidIngress = android
    }
  }

  /// The canonical capability manifest: every ``HostWireCapabilities``
  /// field, its per-transport declaration ingress, and its
  /// absence-means-today default. Nothing reads capabilities for emission
  /// until a stage lands a negotiated consumer; declaring is always safe.
  package static let capabilityMappings: [CapabilityMapping] = [
    .init(
      "maxWebSurfaceVersion",
      defaultValue: "2",
      wasi: "env TUIGUI_SURFACE_MAX_VERSION (explicit value wins over the TUIGUI_SURFACE_DELTA implication)",
      webSocket: "caps record key maxWebSurfaceVersion",
      android: "declareCapabilities key maxWebSurfaceVersion (>= 3 with delta acceptance enables delta records; every Android host receives web-surface frames)"
    ),
    .init(
      "acceptsDeltaFrames",
      defaultValue: "false",
      wasi: "env TUIGUI_SURFACE_DELTA (pre-existing opt-in; implies maxWebSurfaceVersion >= 3)",
      webSocket: "caps record key acceptsDeltaFrames",
      android: "declareCapabilities key acceptsDeltaFrames"
    ),
    .init(
      "supportsResync",
      defaultValue: "false",
      wasi: "declarable via no env key yet (reload re-instantiates the in-process transport; resync is a socket-session concern)",
      webSocket: "caps record key supportsResync",
      android: "declareCapabilities key supportsResync"
    ),
  ]

  // MARK: - Shared wire tokens

  /// The focus-semantics wire token for the converged wire; the encoder
  /// consumes it directly and `WebSurfaceWireTotalityTests` pins the emitted
  /// values.
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
