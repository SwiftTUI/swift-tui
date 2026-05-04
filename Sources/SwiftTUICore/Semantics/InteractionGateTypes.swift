/// Availability of interaction routes for a resolved subtree.
package enum InteractionAvailability: Equatable, Sendable {
  case enabled
  case disabled(reason: InteractionDisabledReason)

  package var isEnabled: Bool {
    switch self {
    case .enabled:
      true
    case .disabled:
      false
    }
  }
}

/// Why a subtree is visually present but unavailable for interaction.
package enum InteractionDisabledReason: String, Equatable, Sendable {
  case modalOverlay
  case authorRequested
}
