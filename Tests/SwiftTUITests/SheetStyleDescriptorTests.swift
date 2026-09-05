import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// The sheet's automatic baseline and its within-family dropdown choice.
@MainActor
@Suite
struct SheetStyleDescriptorTests {
  private func resolved(
    _ style: AnySheetStyle,
    baseline: SheetSurfaceStylePresentation
  ) -> SheetSurfaceStylePresentation {
    var environment = EnvironmentValues()
    environment.sheetStyle = style
    let context = ResolveContext(
      identity: testIdentity("SheetStyleDescriptor"),
      environmentValues: environment
    )
    return context.resolvedSheetPresentation(baseline: baseline)
  }

  @Test("the automatic style returns the declaration's baseline unchanged")
  func automaticReproducesBaseline() {
    let baseline = SheetSurfaceStylePresentation()
    #expect(resolved(.automatic, baseline: baseline) == baseline)
    // `.automatic` is a documented fixed alias of `.surface`.
    #expect(resolved(.surface, baseline: baseline) == baseline)
  }

  @Test("the dropdown style reproduces the former dropdown chrome descriptor")
  func dropdownReproducesFormerChromeDescriptor() {
    // Container selection changes the primitive; the shared chrome fields stay intact.
    let former = SheetSurfaceStylePresentation(container: .dropdown, minimumWidth: 0)
    let styled = resolved(.dropdown, baseline: SheetSurfaceStylePresentation())
    #expect(styled.container == former.container)
    #expect(styled.minimumWidth == former.minimumWidth)
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
    let baseline = SheetSurfaceStylePresentation()
    let styled = resolved(AnySheetStyle(WideSheetStyle()), baseline: baseline)
    #expect(styled.minimumWidth == 44)
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
