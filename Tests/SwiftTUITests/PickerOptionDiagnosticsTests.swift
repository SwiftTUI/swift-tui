import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Picker option representability diagnostics", .serialized)
struct PickerOptionDiagnosticsTests {
  @Test("structured and modified options report once per option while tags remain active")
  func unrepresentableOptionsFailLoudWithoutBreakingSelection() {
    final class SelectionBox {
      var value = 1
    }

    let selection = SelectionBox()
    let pickerIdentity = testIdentity("PickerOptionDiagnostics", "Picker")
    let keyRegistry = LocalKeyHandlerRegistry()
    var environment = EnvironmentValues()
    environment.focusedIdentity = pickerIdentity

    let artifacts = DefaultRenderer().render(
      Picker(
        "Mode",
        selection: Binding(
          get: { selection.value },
          set: { selection.value = $0 }
        )
      ) {
        HStack {
          Text("Structured")
          Text("label")
        }
        .tag(1)

        Text("Plain").tag(2)
        Text("Padded").padding(1).tag(3)
        Text("Disabled").disabled(true).tag(4)
      }
      .id(pickerIdentity)
      .pickerStyle(.inline),
      context: .init(
        identity: testIdentity("PickerOptionDiagnostics"),
        environmentValues: environment,
        localKeyHandlerRegistry: keyRegistry,
        applyEnvironmentValues: true
      ),
      proposal: .init(width: 40, height: 8)
    )

    let issues = artifacts.diagnostics.runtime.issues.filter {
      $0.code == "picker.unrepresentableOptionContent"
    }
    #expect(issues.count == 3)
    #expect(Set(issues.compactMap(\.identity)).count == 3)
    #expect(issues.allSatisfy { $0.source == "Picker" })
    #expect(issues.allSatisfy { $0.message.contains("tag remain active") })

    let frame = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(frame.contains("Structured label"))
    #expect(keyRegistry.dispatch(identity: pickerIdentity, event: .arrowDown))
    #expect(selection.value == 2)
  }

  @Test("plain Text options do not report representability issues")
  func plainTextOptionsRemainLossless() {
    let artifacts = DefaultRenderer().render(
      Picker("Mode", selection: .constant(1)) {
        Text("One").tag(1)
        Text("Two").tag(2)
      },
      context: .init(identity: testIdentity("PickerPlainText")),
      proposal: .init(width: 30, height: 6)
    )

    #expect(
      !artifacts.diagnostics.runtime.issues.contains {
        $0.code == "picker.unrepresentableOptionContent"
      }
    )
  }
}
