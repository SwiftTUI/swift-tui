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
/// Normative state, delivery, and consumer obligations: `docs/HOST-WIRE-CONTRACT.md`.
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
/// - String token vocabularies are manifest-frozen below. Extending one
///   requires both a manifest edit and decoder-default review. Decoders accept
///   unknown tokens structurally and degrade only the affected field or
///   record according to the normative contract.
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
      "epoch", "gen", "sequence", "damage", "accessibilityTree",
      "accessibilityAnnouncements",
      "scrollRegions", "links", "linkTargets", "focusPresentation",
      "preferredGridWidth", "preferredGridHeight", "terminalStyle",
    ]
    package static let deltaFrameKeys: Set<String> = [
      "version", "encoding", "width", "height", "styles", "deltaRows", "images",
      "damage",
    ]
    package static let deltaFrameOptionalKeys: Set<String> = [
      "epoch", "gen", "baselineGen", "sequence", "accessibilityTree",
      "accessibilityAnnouncements", "scrollRegions", "links", "linkTargets", "focusPresentation",
      "preferredGridWidth", "preferredGridHeight", "terminalStyle",
      // Present only when `styleAppend` is negotiated. Optional in the manifest
      // because absence is the deployed shape; its *presence* changes how
      // `styles` must be read, which is why the bit is negotiated rather than
      // the key additive.
      "stylesBase",
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

  // MARK: - Delivery uplink and capability declarations

  /// The typed delivery-control records a host may send upstream. This is
  /// intentionally separate from input controls such as key, mouse, resize,
  /// and style: these records change or repair cross-frame wire state.
  package enum DeliveryUplink {
    package static let recordTypes: Set<String> = ["caps", "resync"]
    package static let capabilityKeys: Set<String> = [
      "acceptsDeltaFrames", "styleAppend",
    ]
    package static let resyncRequiredKeys: Set<String> = ["scope"]
    package static let resyncOptionalKeys: Set<String> = ["ids"]
    package static let resyncScopeTokens: Set<String> = ["keyframe", "images"]
  }

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
    ///
    /// Lifecycle: construction only. There is no runtime declaration
    /// channel — a reload re-instantiates the in-process transport — so a
    /// `caps:` record on stdin is deliberately dropped.
    package let wasiIngress: String
    /// WebHost WebSocket ingress: the `caps:{json}` control record, sent
    /// once by the client after open. Absence = defaults; unknown record
    /// types are silently dropped by `WebSurfaceInputParser`, so a new
    /// bundle against an old server degrades to defaults.
    ///
    /// Lifecycle: accepted at any time, and every arrival is a connection
    /// epoch — it re-anchors the delta baseline and the transmitted-image
    /// set.
    package let webSocketIngress: String
    /// Android JNI ingress: the `declareCapabilities` host call, accepted
    /// only before scene start. The JNI glue resolves the symbol lazily, so
    /// a new AAR against an old host library degrades to defaults.
    ///
    /// Lifecycle: pre-start only. The poll-model host cannot change record
    /// shape mid-session, so a post-start declaration is rejected.
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
  /// absence-means-today default.
  ///
  /// All three transports negotiate emission from the declaration, through
  /// `HostWireCapabilities.negotiatedEncodingState()`. Declaring is always
  /// safe: the defaults reproduce today's bytes.
  ///
  /// Capabilities are named feature bits, so this list grows one entry per
  /// negotiable record shape. It does **not** carry a version ceiling: the
  /// retired `maxWebSurfaceVersion` was an integer only ever compared
  /// against one threshold, duplicating — more weakly — the decoder-side
  /// skew guard that hard-rejects a `surface` record newer than the decoder
  /// understands. Resync is an always-safe repair request rather than a
  /// record-shape capability, so it is manifest-owned by ``DeliveryUplink``
  /// and does not add a capability bit.
  package static let capabilityMappings: [CapabilityMapping] = [
    .init(
      "acceptsDeltaFrames",
      defaultValue: "false",
      wasi: "env SWIFTTUI_SURFACE_DELTA",
      webSocket: "caps record key acceptsDeltaFrames",
      android: "declareCapabilities key acceptsDeltaFrames"
    ),
    .init(
      "styleAppend",
      defaultValue: "false",
      wasi: "env SWIFTTUI_SURFACE_STYLE_APPEND",
      webSocket: "caps record key styleAppend",
      android: "declareCapabilities key styleAppend"
    ),
  ]

  // MARK: - Shared wire tokens

  /// Frozen tokens emitted for ``FocusPresentation/Semantics``.
  package static let focusSemanticsTokens: Set<String> = [
    "none", "automatic", "activate", "edit",
  ]

  /// Frozen tokens emitted for accessibility announcements.
  package static let politenessTokens: Set<String> = [
    "off", "polite", "assertive",
  ]

  /// Frozen tokens emitted for accessibility-node live regions.
  package static let liveRegionTokens: Set<String> = [
    "off", "polite", "assertive",
  ]

  /// Frozen image-container tokens emitted on surface image records.
  package static let imageFormatTokens: Set<String> = [
    "png", "jpeg", "gif",
  ]

  /// Frozen image-scaling tokens emitted on surface image records.
  package static let scalingModeTokens: Set<String> = [
    "stretch", "fit", "fill",
  ]

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
