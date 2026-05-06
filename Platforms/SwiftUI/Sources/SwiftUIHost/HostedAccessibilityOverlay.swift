import CoreGraphics
import SwiftTUI
import SwiftUI

struct HostedAccessibilityOverlay: SwiftUI.View {
  let semanticSnapshot: SemanticSnapshot?
  let focusedIdentity: Identity?
  let cellSize: CGSize

  var mappings: [AccessibilityNodeMapping] {
    AccessibilityNodeMapper.mappings(
      for: semanticSnapshot,
      focusedIdentity: focusedIdentity,
      cellSize: cellSize
    )
  }

  var body: some SwiftUI.View {
    let mappings = mappings
    ZStack(alignment: .topLeading) {
      ForEach(Array(mappings.enumerated()), id: \.element.id) { offset, mapping in
        HostedAccessibilityElement(
          mapping: mapping,
          sortPriority: Double(mappings.count - offset)
        )
      }
    }
    .accessibilityElement(children: .contain)
  }
}

private struct HostedAccessibilityElement: SwiftUI.View {
  let mapping: AccessibilityNodeMapping
  let sortPriority: Double

  var body: some SwiftUI.View {
    SwiftUI.Color.clear
      .frame(width: mapping.frame.width, height: mapping.frame.height)
      .position(x: mapping.frame.midX, y: mapping.frame.midY)
      .accessibilityElement(children: .ignore)
      .hostedAccessibilityLabel(mapping.label)
      .hostedAccessibilityHint(mapping.hint)
      .accessibilityIdentifier(mapping.id)
      .accessibilityAddTraits(mapping.swiftUITraits)
      .accessibilitySortPriority(sortPriority)
  }
}

extension SwiftUI.View {
  @SwiftUI.ViewBuilder
  fileprivate func hostedAccessibilityLabel(
    _ label: String?
  ) -> some SwiftUI.View {
    if let label {
      accessibilityLabel(SwiftUI.Text(label))
    } else {
      self
    }
  }

  @SwiftUI.ViewBuilder
  fileprivate func hostedAccessibilityHint(
    _ hint: String?
  ) -> some SwiftUI.View {
    if let hint {
      accessibilityHint(SwiftUI.Text(hint))
    } else {
      self
    }
  }
}
