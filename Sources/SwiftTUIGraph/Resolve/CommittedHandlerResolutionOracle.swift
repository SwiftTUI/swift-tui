/// The interactive registration family a committed artifact expects to
/// resolve in the just-published runtime registries.
package enum InteractiveHandlerResolutionFamily: String, CaseIterable, Sendable {
  case action
  case key
  case command
  case drop
  case gesture

  package var traceKind: String {
    "handler-resolution-\(rawValue)"
  }
}

/// Checks the committed tree's handler bookkeeping against the just-published
/// runtime registries.
///
/// The walk is deliberately iterative and shared by lifecycle plus all five
/// interactive families. Each family retains an independent four-finding
/// budget, so a noisy missing registry cannot hide another family's first
/// evidence. Registry absence is equivalent to every referenced entry being
/// absent.
@MainActor
package enum CommittedHandlerResolutionOracle {
  private static let maximumFindingsPerFamily = 4

  package static func inspect(
    committedRoot: ResolvedNode,
    registrations: RuntimeRegistrationSet,
    publicationModeName: String,
    publicationSubtreeRootCount: Int
  ) {
    var findings = Findings()
    var stack = [committedRoot]

    while let node = stack.popLast() {
      collectLifecycleFindings(
        from: node,
        registry: registrations.lifecycleRegistry,
        into: &findings.lifecycle
      )
      collectInteractiveFindings(
        from: node.handlerInventory,
        registrations: registrations,
        into: &findings
      )
      stack.append(contentsOf: node.children)

      if findings.isSaturated {
        break
      }
    }

    if !findings.lifecycle.isEmpty {
      SoundnessProbeConfiguration.recordCommittedHandlerResolutionViolation(
        """
        committed handler resolution: committed tree names handlers absent \
        from the published lifecycle registry: \(findings.lifecycle.joined(separator: ", ")) \
        [mode=\(publicationModeName) roots=\(publicationSubtreeRootCount)]
        """
      )
    }

    for (family, familyFindings) in findings.interactive {
      guard !familyFindings.isEmpty else {
        continue
      }
      SoundnessProbeConfiguration.recordInteractiveHandlerResolutionViolation(
        family: family,
        detail: """
          committed handler resolution: committed tree names \(family.rawValue) handlers absent \
          from the published registry: \(familyFindings.joined(separator: ", ")) \
          [mode=\(publicationModeName) roots=\(publicationSubtreeRootCount)]
          """
      )
    }
  }

  private static func collectLifecycleFindings(
    from node: ResolvedNode,
    registry: LocalLifecycleRegistry?,
    into findings: inout [String]
  ) {
    for handlerID in node.lifecycleMetadata.appearHandlerIDs {
      guard findings.count < maximumFindingsPerFamily else {
        return
      }
      if registry?.appearHandler(for: handlerID) == nil {
        findings.append("appear:\(handlerID)")
      }
    }
    for handlerID in node.lifecycleMetadata.disappearHandlerIDs {
      guard findings.count < maximumFindingsPerFamily else {
        return
      }
      if registry?.disappearHandler(for: handlerID) == nil {
        findings.append("disappear:\(handlerID)")
      }
    }
  }

  private static func collectInteractiveFindings(
    from inventory: CommittedHandlerInventory,
    registrations: RuntimeRegistrationSet,
    into findings: inout Findings
  ) {
    collectMissingIdentities(
      inventory.actionIdentities,
      into: &findings.action
    ) { identity in
      registrations.actionRegistry?.hasHandler(identity: identity) == true
    }
    collectMissingIdentities(
      inventory.keyHandlerIdentities,
      into: &findings.key
    ) { identity in
      registrations.keyHandlerRegistry?.hasHandler(identity: identity) == true
        || registrations.keyHandlerRegistry?.hasPasteHandler(identity: identity) == true
    }
    collectMissingIdentities(
      inventory.commandScopes,
      into: &findings.command
    ) { identity in
      registrations.commandRegistry?.hasCommands(at: identity) == true
    }
    collectMissingIdentities(
      inventory.dropScopes,
      into: &findings.drop
    ) { identity in
      registrations.dropDestinationRegistry?.hasHandler(at: identity) == true
    }

    for identity in inventory.gestureRouteIdentities {
      guard findings.gesture.count < maximumFindingsPerFamily else {
        break
      }
      var missingParts: [String] = []
      if registrations.gestureRegistry?.hasRecognizer(for: identity) != true {
        missingParts.append("recognizer")
      }
      if registrations.pointerHandlerRegistry?.hasHandler(
        pairingWith: RouteID(identity: identity)
      ) != true {
        missingParts.append("pointer")
      }
      if !missingParts.isEmpty {
        findings.gesture.append(
          "\(identity.path)(missing=\(missingParts.joined(separator: "+")))"
        )
      }
    }
  }

  private static func collectMissingIdentities(
    _ identities: [Identity],
    into findings: inout [String],
    isPresent: (Identity) -> Bool
  ) {
    for identity in identities {
      guard findings.count < maximumFindingsPerFamily else {
        break
      }
      if !isPresent(identity) {
        findings.append(identity.path)
      }
    }
  }

  @MainActor
  private struct Findings {
    var lifecycle: [String] = []
    var action: [String] = []
    var key: [String] = []
    var command: [String] = []
    var drop: [String] = []
    var gesture: [String] = []

    var interactive: [(InteractiveHandlerResolutionFamily, [String])] {
      [
        (.action, action),
        (.key, key),
        (.command, command),
        (.drop, drop),
        (.gesture, gesture),
      ]
    }

    var isSaturated: Bool {
      lifecycle.count == maximumFindingsPerFamily
        && action.count == maximumFindingsPerFamily
        && key.count == maximumFindingsPerFamily
        && command.count == maximumFindingsPerFamily
        && drop.count == maximumFindingsPerFamily
        && gesture.count == maximumFindingsPerFamily
    }
  }
}
