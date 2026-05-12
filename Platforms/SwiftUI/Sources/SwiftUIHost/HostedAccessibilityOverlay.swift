import CoreGraphics
import SwiftTUIRuntime
import SwiftUI

struct HostedAccessibilityOverlay: SwiftUI.View {
  let semanticSnapshot: SemanticSnapshot?
  let focusedIdentity: Identity?
  let cellSize: CGSize

  @SwiftUI.AccessibilityFocusState private var nativeFocusedElementID: String?

  var mappings: [AccessibilityNodeMapping] {
    AccessibilityNodeMapper.mappings(
      for: semanticSnapshot,
      focusedIdentity: focusedIdentity,
      cellSize: cellSize
    )
  }

  var requestedNativeFocusID: String? {
    HostedAccessibilityFocusPolicy.requestedFocusID(in: mappings)
  }

  var body: some SwiftUI.View {
    let mappings = mappings
    ZStack(alignment: .topLeading) {
      ForEach(Array(mappings.enumerated()), id: \.element.id) { offset, mapping in
        HostedAccessibilityElement(
          mapping: mapping,
          sortPriority: Double(mappings.count - offset),
          nativeFocusedElementID: $nativeFocusedElementID
        )
      }
    }
    .accessibilityElement(children: .contain)
    .onAppear {
      nativeFocusedElementID = requestedNativeFocusID
    }
    .onChange(of: requestedNativeFocusID) { _, newValue in
      nativeFocusedElementID = newValue
    }
    .onChange(of: mappings) { _, _ in
      nativeFocusedElementID = requestedNativeFocusID
    }
  }
}

private struct HostedAccessibilityElement: SwiftUI.View {
  let mapping: AccessibilityNodeMapping
  let sortPriority: Double
  let nativeFocusedElementID: SwiftUI.AccessibilityFocusState<String?>.Binding

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
      .accessibilityFocused(nativeFocusedElementID, equals: mapping.id)
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
