import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// A picker authored with an `EmptyView` label (`Picker(selection:) { } label:
/// { EmptyView() }`) reserves no label row in any built-in style; the same
/// picker with a `Text` label is exactly one row taller. Measured ideal
/// heights with two options, labeled → unlabeled: inline 5 → 4, segmented
/// 4 → 3, radioGroup 5 → 4, menu (collapsed) 2 → 1. Pinned after the org
/// review of the 0.12.1 style system suspected an over-reserved row.
@MainActor
struct PickerStyleLabelRowTests {
  private struct Measurement {
    var height: Int
    var firstRow: String
  }

  private func measure<Label: View>(
    style: AnyPickerStyle,
    @ViewBuilder label: () -> Label
  ) throws -> Measurement {
    let id = testIdentity("MeasuredPicker")
    let picker = Picker(selection: .constant(1)) {
      Text("One").tag(1)
      Text("Two").tag(2)
    } label: {
      label()
    }
    let artifacts = DefaultRenderer().render(
      VStack(alignment: .leading, spacing: 0) {
        // Ideal height only: a body that is vertically flexible (the
        // segmented style's dividers) must not stretch into the slack.
        picker.id(id).pickerStyle(style).fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
      },
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 24, height: 10)
    )
    let placed = try #require(
      placedNode(identity: id, in: artifacts.placedTree),
      "no placed node for the picker in\n\(artifacts.rasterSurface.lines.joined(separator: "\n"))"
    )
    return Measurement(
      height: placed.bounds.size.height,
      firstRow: artifacts.rasterSurface.lines.first ?? ""
    )
  }

  private func placedNode(identity: Identity, in node: PlacedNode) -> PlacedNode? {
    if node.identity == identity {
      return node
    }
    for child in node.children {
      if let match = placedNode(identity: identity, in: child) {
        return match
      }
    }
    return nil
  }

  @Test(
    "an EmptyView label reserves no row; a Text label costs exactly one",
    arguments: [
      (AnyPickerStyle.inline, 5), (.segmented, 4), (.radioGroup, 5), (.menu, 2),
    ])
  func pickerEmptyViewLabelReservesNoRow(style: AnyPickerStyle, labeledHeight: Int) throws {
    let labeled = try measure(style: style) { Text("Mode") }
    let unlabeled = try measure(style: style) { EmptyView() }

    #expect(labeled.height == labeledHeight, "\(style): labeled \(labeled.height) rows")
    #expect(
      unlabeled.height == labeledHeight - 1,
      "\(style): labeled \(labeled.height) rows, EmptyView label \(unlabeled.height) rows")
    // The chrome starts on the picker's first row when there is no label.
    #expect(
      unlabeled.firstRow.contains { $0 != " " },
      "\(style): first row is blank with an EmptyView label: '\(unlabeled.firstRow)'")
    #expect(labeled.firstRow.contains("Mode"))
  }
}
