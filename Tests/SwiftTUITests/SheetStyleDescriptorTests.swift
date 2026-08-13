import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// A4's core acceptance: `.automatic` reproduces the current sheet
/// descriptor exactly, so the `PresentationChrome` removal is
/// output-preserving, and `.dropdown` reproduces the treatment the removed
/// `chrome: .dropdown` argument produced.
@MainActor
@Suite
struct SheetStyleDescriptorTests {
  private func resolved(
    _ style: AnySheetStyle,
    baseline: PromptPresentationDescriptor
  ) -> PromptPresentationDescriptor {
    var environment = EnvironmentValues()
    environment.sheetStyle = style
    let context = ResolveContext(
      identity: testIdentity("SheetStyleDescriptor"),
      environmentValues: environment
    )
    return context.resolvedSheetDescriptor(baseline: baseline)
  }

  @Test("the automatic style returns the declaration's baseline unchanged")
  func automaticReproducesBaseline() {
    let baseline = sheetPromptPresentationSpec().descriptor
    #expect(resolved(.automatic, baseline: baseline) == baseline)
    // `.automatic` is a documented fixed alias of `.surface`.
    #expect(resolved(.surface, baseline: baseline) == baseline)
  }

  @Test("the dropdown style reproduces the former dropdown chrome descriptor")
  func dropdownReproducesFormerChromeDescriptor() {
    // The removed API spelled this `sheetPromptPresentationSpec(chrome:)`;
    // the surviving package builder still expresses the same baseline, so
    // the style path must land on an identical descriptor.
    let former = sheetPromptPresentationSpec(chrome: .dropdown).descriptor
    let styled = resolved(.dropdown, baseline: sheetPromptPresentationSpec().descriptor)
    #expect(styled.chrome == former.chrome)
    #expect(styled.alignment == former.alignment)
    #expect(styled.minWidth == former.minWidth)
    #expect(styled == former)
  }

  @Test("a custom style transforms the baseline it is handed")
  func customStyleTransformsBaseline() {
    struct WideSheetStyle: SheetStyle {
      func resolvePresentation(
        for configuration: SheetStyleConfiguration
      ) -> SheetSurfaceStylePresentation {
        var presentation = configuration.defaultPresentation
        presentation.minimumWidth = 44
        return presentation
      }
    }
    let baseline = sheetPromptPresentationSpec().descriptor
    let styled = resolved(AnySheetStyle(WideSheetStyle()), baseline: baseline)
    #expect(styled.minWidth == 44)
    // Everything the style did not touch is preserved.
    #expect(styled.headerTone == baseline.headerTone)
    #expect(styled.scrollIdealHeight == baseline.scrollIdealHeight)
  }

  @Test("built-in sheet styles compare for reuse")
  func sheetStylesCompareForReuse() {
    #expect(AnySheetStyle.automatic.isEqualForReuse(to: AnySheetStyle.surface))
    #expect(!AnySheetStyle.automatic.isEqualForReuse(to: AnySheetStyle.dropdown))
  }
}
