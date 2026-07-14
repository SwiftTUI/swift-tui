import Foundation
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// Storage-classification totality lock for `ResolveContext` (F179).
///
/// The context's stored surface is mirrored by four hand-maintained parallel
/// structures — the hand-written `==`, the `child`/`replacingIdentity`
/// builders, `PropagatedRegistries`, and the frame head's
/// `replacingRuntimeRegistrations` draft swap — and nothing forced a newly
/// added stored property to be classified against them: the four local
/// registries stayed direct stored fields restated across all of them, and a
/// member omitted from the hand-`==` was silently unequated. This suite
/// requires every stored property (reflected, so a new field cannot hide) to
/// carry an explicit policy on all three axes: equality participation,
/// builder propagation, and frame-head draft replacement — and verifies the
/// draft-replacement axis behaviorally.
@MainActor
@Suite("ResolveContext storage totality")
struct ResolveContextStorageTotalityTests {
  private static let resolveContextPath =
    "Sources/SwiftTUIViews/Environment/ResolveContext.swift"

  private struct DirectFieldClassification {
    var equated: Bool
    var notEquatedReason: String?
    var carriedByBuilders: Bool
    var notCarriedReason: String?
  }

  private enum DraftPolicy {
    case replaced
    case survives(String)
  }

  private struct PropagatedMemberClassification {
    var equated: Bool
    var notEquatedReason: String?
    var draft: DraftPolicy
  }

  private static func equated(
    carried: Bool = true,
    notCarriedReason: String? = nil
  ) -> DirectFieldClassification {
    .init(
      equated: true,
      notEquatedReason: nil,
      carriedByBuilders: carried,
      notCarriedReason: notCarriedReason
    )
  }

  private static func notEquated(
    _ reason: String,
    carried: Bool = true,
    notCarriedReason: String? = nil
  ) -> DirectFieldClassification {
    .init(
      equated: false,
      notEquatedReason: reason,
      carriedByBuilders: carried,
      notCarriedReason: notCarriedReason
    )
  }

  private static func equated(draft: DraftPolicy) -> PropagatedMemberClassification {
    .init(equated: true, notEquatedReason: nil, draft: draft)
  }

  private static func notEquated(
    _ reason: String,
    draft: DraftPolicy
  ) -> PropagatedMemberClassification {
    .init(equated: false, notEquatedReason: reason, draft: draft)
  }

  /// Every direct stored property of `ResolveContext`. A new stored field
  /// fails the totality test until it is classified here.
  private static let directFields: [String: DirectFieldClassification] = [
    "identity": equated(),
    "structuralPath": equated(),
    "environment": equated(),
    "environmentValues": equated(),
    "focusedValues": notEquated(
      "derived mirror of environmentValues.focusedValues, re-assigned by every "
        + "builder and by the frame-input refresh; environmentValues equality subsumes it"
    ),
    "transaction": equated(),
    "invalidatedIdentities": equated(),
    "invalidationSummary": notEquated(
      "didSet-maintained projection of invalidatedIdentities; comparing the source "
        + "set subsumes it"
    ),
    "forceRootEvaluation": equated(),
    "entityHosting": notEquated(
      "one-shot host marker (see the field doc); dropped at every structural "
        + "derivation and must never gate reuse",
      carried: false,
      notCarriedReason:
        "one-shot by design: a structural derivation must reset the host marker"
    ),
    "valueAnimationOrdinalCursor": notEquated(
      "documented Equatable exclusion: the per-identity ordinal cursor must never "
        + "gate reuse",
      carried: false,
      notCarriedReason:
        "one-shot by design: the cursor resets at every identity boundary"
    ),
    "propagated": notEquated(
      "compared member-by-member through the forwarding names; see propagatedMembers"
    ),
  ]

  /// Every stored member of `ResolveContext.PropagatedRegistries`, with its
  /// equality participation and its frame-head draft-replacement policy.
  private static let propagatedMembers: [String: PropagatedMemberClassification] = [
    // The fifteen `RuntimeRegistrationSet` members: replaced wholesale by the
    // frame head's `replacingRuntimeRegistrations`.
    "localActionRegistry": equated(draft: .replaced),
    "localKeyHandlerRegistry": equated(draft: .replaced),
    "localLifecycleRegistry": equated(draft: .replaced),
    "localTaskRegistry": equated(draft: .replaced),
    "localTerminationRegistry": notEquated(
      "frame-draft registration sink historically outside the hand-`==`; pinned "
        + "explicitly — adding it is a deliberate reuse-semantics change",
      draft: .replaced
    ),
    "localPointerHandlerRegistry": notEquated(
      "frame-draft registration sink historically outside the hand-`==`; pinned "
        + "explicitly — adding it is a deliberate reuse-semantics change",
      draft: .replaced
    ),
    "localGestureRegistry": notEquated(
      "frame-draft registration sink historically outside the hand-`==`; pinned "
        + "explicitly — adding it is a deliberate reuse-semantics change",
      draft: .replaced
    ),
    "localGestureStateRegistry": notEquated(
      "frame-draft registration sink historically outside the hand-`==`; pinned "
        + "explicitly — adding it is a deliberate reuse-semantics change",
      draft: .replaced
    ),
    "localDefaultFocusRegistry": equated(draft: .replaced),
    "localFocusBindingRegistry": equated(draft: .replaced),
    "localFocusedValuesRegistry": equated(draft: .replaced),
    "localScrollPositionRegistry": equated(draft: .replaced),
    "localPreferenceObservationRegistry": equated(draft: .replaced),
    "commandRegistry": equated(draft: .replaced),
    "dropDestinationRegistry": equated(draft: .replaced),
    // Non-registration members: the draft swap must leave them untouched.
    "resolveWorkTracker": notEquated(
      "per-pass work telemetry, re-minted for every root context",
      draft: .survives("telemetry handle, not a runtime registration")
    ),
    "liveScrollPositionRegistry": equated(
      draft: .survives(
        "documented: imperative scroll commands must outlive frame-draft replacement"
      )
    ),
    "liveFocusBindingRegistry": equated(
      draft: .survives(
        "documented: focus arrivals must reach the arbitrating live instance"
      )
    ),
    "invalidationProxy": notEquated(
      "live-state invalidator seam, stable across frames within a session",
      draft: .survives("drafts must keep invalidating through the live seam")
    ),
    "observationBridge": equated(
      draft: .survives("observation wiring is per-pass, not a frame-draft registration")
    ),
    "viewGraph": notEquated(
      "the live graph engine; contexts under one renderer share the reference",
      draft: .survives("engine reference, not a registration")
    ),
    "imageAssetResolver": notEquated(
      "closure — not equatable; session-stable environment service",
      draft: .survives("service seam, not a registration")
    ),
    "frameInputs": notEquated(
      "per-frame input box refreshed by applyingCurrentFrameResolveInputs before "
        + "any reuse decision",
      draft: .survives("live-state seam, not a registration")
    ),
    "suppressesStructuralLifecycle": equated(
      draft: .survives("resolve-scope flag, not a registration")
    ),
    "withinChurnedSubtree": notEquated(
      "acts as a direct reuse veto at both reuse layers before any equality gate runs",
      draft: .survives("resolve-scope flag, not a registration")
    ),
    "authoredFocusPressOverrides": notEquated(
      "focus/press keys are excluded from environment equality by design; the marker "
        + "only steers the frame-input refresh",
      draft: .survives("resolve-scope marker, not a registration")
    ),
    "authoredTransactionOverride": notEquated(
      "steers the frame-input refresh only (F137); the transaction it protects is "
        + "itself equated",
      draft: .survives("resolve-scope marker, not a registration")
    ),
    "gestureSuppressionScopes": notEquated(
      "registration-time suppression currency; documented as not retro-applied "
        + "without re-resolve",
      draft: .survives("resolve-scope currency, not a registration")
    ),
    "requestDeadline": notEquated(
      "closure — not equatable; scheduler seam",
      draft: .survives("scheduler seam, not a registration")
    ),
    "presentationTriggerObserver": notEquated(
      "frame-scoped observation log pointed at live state",
      draft: .survives("live-state seam, not a registration")
    ),
  ]

  private static func storedLabels(of subject: Any) -> Set<String> {
    Set(Mirror(reflecting: subject).children.compactMap(\.label))
  }

  @Test("every direct stored property is classified (and no manifest entry is stale)")
  func directFieldManifestIsTotal() {
    let stored = Self.storedLabels(of: ResolveContext())
    let classified = Set(Self.directFields.keys)
    #expect(
      stored.subtracting(classified).isEmpty,
      "unclassified ResolveContext stored properties: \(stored.subtracting(classified).sorted()) — classify each in directFields (equality + builder-propagation policy)."
    )
    #expect(
      classified.subtracting(stored).isEmpty,
      "stale directFields entries (no such stored property): \(classified.subtracting(stored).sorted())"
    )
  }

  @Test("every propagated member is classified (and no manifest entry is stale)")
  func propagatedMemberManifestIsTotal() {
    let stored = Self.storedLabels(of: ResolveContext().propagated)
    let classified = Set(Self.propagatedMembers.keys)
    #expect(
      stored.subtracting(classified).isEmpty,
      "unclassified PropagatedRegistries members: \(stored.subtracting(classified).sorted()) — classify each in propagatedMembers (equality + draft-replacement policy)."
    )
    #expect(
      classified.subtracting(stored).isEmpty,
      "stale propagatedMembers entries (no such stored member): \(classified.subtracting(stored).sorted())"
    )
  }

  @Test("the hand-== covers exactly the members the manifest says it covers")
  func equalityCoverageMatchesManifest() throws {
    let source = try sourceText(relativePath: Self.resolveContextPath)
    let body = functionBodyText(named: "==", in: source)
    #expect(!body.isEmpty, "could not locate ResolveContext.== in the source")

    for (name, classification) in Self.directFields.sorted(by: { $0.key < $1.key }) {
      let compared = mentionsMember(body, "lhs.\(name)")
      #expect(
        compared == classification.equated,
        "== \(compared ? "compares" : "omits") \(name) but the manifest classifies it as \(classification.equated ? "equated" : "not equated") — reconcile the manifest with the ==."
      )
    }
    for (name, classification) in Self.propagatedMembers.sorted(by: { $0.key < $1.key }) {
      let compared = mentionsMember(body, "lhs.\(name)")
      #expect(
        compared == classification.equated,
        "== \(compared ? "compares" : "omits") \(name) but the manifest classifies it as \(classification.equated ? "equated" : "not equated") — reconcile the manifest with the ==."
      )
    }
  }

  @Test(
    "the derivation builders carry every direct field the manifest says they carry",
    arguments: ["child", "replacingIdentity"])
  func buildersCarryEveryDirectField(builder: String) throws {
    let source = try sourceText(relativePath: Self.resolveContextPath)
    let body = functionBodyText(named: builder, in: source)
    #expect(!body.isEmpty, "could not locate ResolveContext.\(builder) in the source")

    for (name, classification) in Self.directFields.sorted(by: { $0.key < $1.key }) {
      let mentioned = mentionsMember(body, name)
      #expect(
        mentioned == classification.carriedByBuilders,
        "\(builder) \(mentioned ? "mentions" : "drops") \(name) but the manifest classifies it as \(classification.carriedByBuilders ? "carried" : "deliberately dropped") — a silently dropped field is the F168-class hazard; reconcile."
      )
    }
  }

  @Test("not-equated and survives classifications carry non-empty reasons")
  func classificationsCarryReasons() {
    for (name, classification) in Self.directFields {
      if !classification.equated {
        #expect(
          classification.notEquatedReason?.isEmpty == false,
          "directFields[\(name)] is not equated but has no reason"
        )
      }
      if !classification.carriedByBuilders {
        #expect(
          classification.notCarriedReason?.isEmpty == false,
          "directFields[\(name)] is not carried but has no reason"
        )
      }
    }
    for (name, classification) in Self.propagatedMembers {
      if !classification.equated {
        #expect(
          classification.notEquatedReason?.isEmpty == false,
          "propagatedMembers[\(name)] is not equated but has no reason"
        )
      }
      if case .survives(let reason) = classification.draft {
        #expect(
          !reason.isEmpty,
          "propagatedMembers[\(name)] survives the draft swap but has no reason"
        )
      }
    }
  }

  /// The expected post-swap instance for a `.replaced` member.
  @MainActor
  private static func scratchInstance(
    named member: String,
    in set: RuntimeRegistrationSet
  ) -> AnyObject? {
    switch member {
    case "localActionRegistry": set.actionRegistry
    case "localKeyHandlerRegistry": set.keyHandlerRegistry
    case "localTerminationRegistry": set.terminationRegistry
    case "localPointerHandlerRegistry": set.pointerHandlerRegistry
    case "localGestureRegistry": set.gestureRegistry
    case "localGestureStateRegistry": set.gestureStateRegistry
    case "localDefaultFocusRegistry": set.defaultFocusRegistry
    case "localFocusBindingRegistry": set.focusBindingRegistry
    case "localFocusedValuesRegistry": set.focusedValuesRegistry
    case "localScrollPositionRegistry": set.scrollPositionRegistry
    case "localLifecycleRegistry": set.lifecycleRegistry
    case "localTaskRegistry": set.taskRegistry
    case "localPreferenceObservationRegistry": set.preferenceObservationRegistry
    case "commandRegistry": set.commandRegistry
    case "dropDestinationRegistry": set.dropDestinationRegistry
    default: nil
    }
  }

  @Test("frame-head draft replacement follows the per-member policy, behaviorally")
  func draftReplacementPolicyHolds() throws {
    var context = ResolveContext()
    let initialTracker = try #require(context.resolveWorkTracker)
    let liveScroll = LocalScrollPositionRegistry()
    let liveFocus = LocalFocusBindingRegistry()
    let proxy = ResolveInvalidationProxy()
    let bridge = ObservationBridge()
    let graph = ViewGraph()
    let inputBox = FrameResolveInputBox()
    let log = PresentationTriggerObservationLog()
    let scopeIdentity = Identity(components: [IdentityComponent(rawValue: "scope")])
    context.liveScrollPositionRegistry = liveScroll
    context.liveFocusBindingRegistry = liveFocus
    context.invalidationProxy = proxy
    context.observationBridge = bridge
    context.viewGraph = graph
    context.frameInputs = inputBox
    context.presentationTriggerObserver = log
    context.imageAssetResolver = { _, _, _ in nil }
    context.requestDeadline = { _ in }
    context.suppressesStructuralLifecycle = true
    context.withinChurnedSubtree = true
    context.propagated.authoredFocusPressOverrides = [.focusedIdentity]
    context.propagated.authoredTransactionOverride = true
    context.gestureSuppressionScopes = [scopeIdentity]

    let replacement = RuntimeRegistrationSet.scratch()
    let replaced = context.replacingRuntimeRegistrations(replacement)

    let members = Dictionary(
      uniqueKeysWithValues: Mirror(reflecting: replaced.propagated).children.compactMap {
        child in child.label.map { ($0, child.value) }
      }
    )
    for (name, classification) in Self.propagatedMembers.sorted(by: { $0.key < $1.key }) {
      guard let value = members[name] else {
        Issue.record(
          "PropagatedRegistries has no stored member named \(name) — the manifest and the struct have diverged"
        )
        continue
      }
      switch classification.draft {
      case .replaced:
        guard let expected = Self.scratchInstance(named: name, in: replacement) else {
          Issue.record(
            "no RuntimeRegistrationSet extractor for replaced member \(name) — add it to scratchInstance(named:in:)"
          )
          continue
        }
        #expect(
          unwrappedObject(value) === expected,
          "\(name) is classified .replaced but the draft swap did not install the replacement instance"
        )
      case .survives:
        switch name {
        case "resolveWorkTracker":
          #expect(unwrappedObject(value) === initialTracker, "\(name) must survive the draft swap")
        case "liveScrollPositionRegistry":
          #expect(unwrappedObject(value) === liveScroll, "\(name) must survive the draft swap")
        case "liveFocusBindingRegistry":
          #expect(unwrappedObject(value) === liveFocus, "\(name) must survive the draft swap")
        case "invalidationProxy":
          #expect(unwrappedObject(value) === proxy, "\(name) must survive the draft swap")
        case "observationBridge":
          #expect(unwrappedObject(value) === bridge, "\(name) must survive the draft swap")
        case "viewGraph":
          #expect(unwrappedObject(value) === graph, "\(name) must survive the draft swap")
        case "frameInputs":
          #expect(unwrappedObject(value) === inputBox, "\(name) must survive the draft swap")
        case "presentationTriggerObserver":
          #expect(unwrappedObject(value) === log, "\(name) must survive the draft swap")
        case "imageAssetResolver", "requestDeadline":
          #expect(unwrappedOptional(value) != nil, "\(name) must survive the draft swap")
        case "suppressesStructuralLifecycle", "withinChurnedSubtree",
          "authoredTransactionOverride":
          #expect(value as? Bool == true, "\(name) must survive the draft swap")
        case "authoredFocusPressOverrides":
          #expect(
            value as? ResolveContext.AuthoredFocusPressOverrides == [.focusedIdentity],
            "\(name) must survive the draft swap"
          )
        case "gestureSuppressionScopes":
          #expect(
            value as? [Identity] == [scopeIdentity],
            "\(name) must survive the draft swap"
          )
        default:
          Issue.record("no survivor assertion for \(name) — add one to this switch")
        }
      }
    }
  }

  @Test("totality guard has teeth: an unclassified member would fail the check")
  func totalityGuardCatchesUnclassifiedMember() {
    let phantom = "phantomNewMember"
    #expect(!Self.storedLabels(of: ResolveContext()).contains(phantom))
    #expect(Self.directFields[phantom] == nil)
    #expect(Self.propagatedMembers[phantom] == nil)
  }
}

// MARK: - File-private source parsing (SourceParsingTestSupport pattern)

/// Boundary-aware mention check: `member` must appear in `body` with
/// non-identifier characters (or the text edges) on both sides, so
/// `identity` does not match inside `structuralIdentity`.
private func mentionsMember(_ body: String, _ member: String) -> Bool {
  var searchRange = body.startIndex..<body.endIndex
  while let range = body.range(of: member, range: searchRange) {
    let beforeOK: Bool
    if range.lowerBound == body.startIndex {
      beforeOK = true
    } else {
      let character = body[body.index(before: range.lowerBound)]
      beforeOK = !(character.isLetter || character.isNumber || character == "_")
    }
    let afterOK: Bool
    if range.upperBound == body.endIndex {
      afterOK = true
    } else {
      let character = body[range.upperBound]
      afterOK = !(character.isLetter || character.isNumber || character == "_")
    }
    if beforeOK && afterOK {
      return true
    }
    searchRange = range.upperBound..<body.endIndex
  }
  return false
}

private func unwrappedOptional(_ value: Any) -> Any? {
  let mirror = Mirror(reflecting: value)
  guard mirror.displayStyle == .optional else {
    return value
  }
  return mirror.children.first?.value
}

private func unwrappedObject(_ value: Any) -> AnyObject? {
  unwrappedOptional(value).map { $0 as AnyObject }
}

/// Returns the source text of the first `func <name>(` (or `func <name> (`)
/// and its balanced-brace body, or "" if not found.
private func functionBodyText(named name: String, in source: String) -> String {
  let lines = source.components(separatedBy: .newlines)
  guard
    let start = lines.firstIndex(where: { line in
      line.contains("func \(name)(") || line.contains("func \(name) (")
    })
  else {
    return ""
  }
  var depth = 0
  var started = false
  var collected: [String] = []
  for line in lines[start...] {
    collected.append(line)
    if line.contains("{") {
      started = true
    }
    depth += braceDelta(in: line)
    if started && depth <= 0 {
      break
    }
  }
  return collected.joined(separator: "\n")
}

private func braceDelta(in line: String) -> Int {
  line.reduce(0) { partial, character in
    switch character {
    case "{":
      partial + 1
    case "}":
      partial - 1
    default:
      partial
    }
  }
}

private func sourceText(relativePath: String) throws -> String {
  let root = try repositoryRoot()
  let url = root.appendingPathComponent(relativePath)
  return try String(contentsOf: url, encoding: .utf8)
}

private func repositoryRoot() throws -> URL {
  var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  while directory.path != "/" {
    if FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("Package.swift").path
    ) {
      return directory
    }
    directory.deleteLastPathComponent()
  }
  throw StorageTotalityParseError.missingPackageRoot
}

private enum StorageTotalityParseError: Error {
  case missingPackageRoot
}
