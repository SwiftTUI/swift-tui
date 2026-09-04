import SwiftTUIRuntime
@_spi(StyleFixtures) import SwiftTUIViews
import Testing

/// The `@_spi(StyleFixtures)` construction surface (control-style plan
/// 2026-08-12-002, stage B0): every shipped family's configuration, captured
/// slot, and presentation value is constructible without a live render, and
/// a style resolves against the fixture exactly as it would in production.
///
/// This file deliberately imports `SwiftTUIViews` without `@testable`, the
/// way a style library's own test target does. The SPI attribute is the only
/// thing granting access: a `@testable` import without it cannot see these
/// initializers (the compiler rejects it with "inaccessible due to '@_spi'
/// protection level"), so this suite is the proof that the SPI alone
/// suffices, in-package or out.
@MainActor
@Suite("Style fixture construction")
struct StyleFixtureConstructionTests {
  private let styleEnvironment = StyleEnvironmentSnapshot()

  private func surface(_ artifacts: RenderSnapshot) -> String {
    artifacts.rasterSurface.lines.joined(separator: "\n")
  }

  private func listConfiguration(isFocused: Bool) -> ListStyleConfiguration {
    ListStyleConfiguration(
      isSelectable: isFocused,
      isEnabled: isFocused,
      isFocused: isFocused,
      showsFocusEffect: isFocused,
      styleEnvironment: styleEnvironment
    )
  }

  @Test("a button style resolves against a fixture configuration")
  func buttonStyleResolvesAgainstFixture() {
    let configuration = ButtonStyleConfiguration(
      label: .init { Text("Save") },
      role: .destructive,
      isEnabled: true,
      isFocused: true,
      showsFocusEffect: true,
      isPressed: false,
      controlProminence: .standard,
      buttonBorderShape: .automatic,
      styleEnvironment: styleEnvironment
    )
    #expect(configuration.focusActive)
    #expect(configuration.role == .destructive)

    let artifacts = DefaultRenderer().render(
      BorderedButtonStyle().makeBody(configuration: configuration),
      context: .init(identity: testIdentity("ButtonFixture")),
      proposal: .init(width: 16, height: 3)
    )
    #expect(surface(artifacts).contains("Save"))
  }

  @Test("a text-field style resolves against a fixture configuration")
  func textFieldStyleResolvesAgainstFixture() {
    let configuration = TextFieldStyleConfiguration(
      displayText: "ada",
      fieldContent: .init(displayText: "ada"),
      isShowingPrompt: false,
      label: .init { Text("Name") },
      showsLabel: true,
      chrome: ControlChrome(
        foregroundStyle: AnyShapeStyle(.foreground),
        contentBackgroundStyle: AnyShapeStyle(.background),
        borderForegroundStyle: AnyShapeStyle(.separator)
      ),
      placeholderStyle: AnyShapeStyle(.placeholder),
      focusActive: false,
      styleEnvironment: styleEnvironment
    )

    let artifacts = DefaultRenderer().render(
      RoundedBorderTextFieldStyle().makeBody(configuration: configuration),
      context: .init(identity: testIdentity("TextFieldFixture")),
      proposal: .init(width: 24, height: 3)
    )
    #expect(surface(artifacts).contains("ada"))
  }

  @Test("a text-field fixture defaults its field content to the display text")
  func textFieldFixtureDefaultsFieldContent() {
    let configuration = TextFieldStyleConfiguration(
      displayText: "typed",
      isShowingPrompt: false,
      label: .init { Text("Name") },
      showsLabel: false,
      chrome: ControlChrome(
        foregroundStyle: AnyShapeStyle(.foreground),
        contentBackgroundStyle: AnyShapeStyle(.background),
        borderForegroundStyle: AnyShapeStyle(.separator)
      ),
      placeholderStyle: AnyShapeStyle(.placeholder),
      focusActive: true,
      styleEnvironment: styleEnvironment
    )

    let artifacts = DefaultRenderer().render(
      PlainTextFieldStyle().makeBody(configuration: configuration),
      context: .init(identity: testIdentity("TextFieldDefaultContent")),
      proposal: .init(width: 24, height: 1)
    )
    #expect(surface(artifacts).contains("typed"))
  }

  @Test("a picker style resolves against a fixture configuration")
  func pickerStyleResolvesAgainstFixture() {
    let configuration = PickerStyleConfiguration(
      controlIdentity: Identity(components: ["PickerFixture"]),
      label: .init { Text("Pick") },
      options: [.init(label: "One"), .init(label: "Two")],
      selectedIndex: 1,
      isFocused: false,
      isActiveNavigation: false,
      showsFocusEffect: true,
      isEnabled: true,
      styleEnvironment: styleEnvironment,
      viewportLineCount: nil,
      lineWidth: nil
    )

    let artifacts = DefaultRenderer().render(
      InlinePickerStyle().makeBody(configuration: configuration),
      context: .init(identity: testIdentity("PickerFixture")),
      proposal: .init(width: 24, height: 4)
    )
    let rendered = surface(artifacts)
    #expect(rendered.contains("One"))
    #expect(rendered.contains("Two"))
  }

  @Test("presentation-value families resolve against fixture configurations")
  func presentationFamiliesResolveAgainstFixtures() {
    let focusedList = PlainListStyle().resolvePresentation(
      for: listConfiguration(isFocused: true)
    )
    let idleList = PlainListStyle().resolvePresentation(
      for: listConfiguration(isFocused: false)
    )
    #expect(focusedList == idleList, "built-in list styles resolve one presentation per state")

    let outline = RoundedOutlineStyle().resolvePresentation(
      for: OutlineStyleConfiguration(styleEnvironment: styleEnvironment)
    )
    #expect(outline.leafConnector == "╰─ ")

    let bordered = BorderedTableStyle().resolvePresentation(
      for: TableStyleConfiguration(
        columnCount: 3,
        showsHeaders: true,
        isSelectable: true,
        isEnabled: true,
        isFocused: false,
        showsFocusEffect: true,
        styleEnvironment: styleEnvironment
      )
    )
    let inset = InsetTableStyle().resolvePresentation(
      for: TableStyleConfiguration(
        columnCount: 3,
        showsHeaders: true,
        isSelectable: true,
        isEnabled: true,
        isFocused: false,
        showsFocusEffect: true,
        styleEnvironment: styleEnvironment
      )
    )
    #expect(bordered != inset, "two non-automatic built-ins never alias")

    let spinner = GlyphSpinnerStyle(activeFrames: ["|", "/"]).resolvePresentation(
      for: SpinnerStyleConfiguration(
        stage: .active,
        accessibilityReduceMotion: false,
        styleEnvironment: styleEnvironment
      )
    )
    #expect(spinner.activeFrames == ["|", "/"])

    let baseline = SheetSurfaceStylePresentation(minimumWidth: 30)
    let sheet = SurfaceSheetStyle().resolvePresentation(
      for: SheetStyleConfiguration(
        defaultPresentation: baseline,
        terminalSize: CellSize(width: 80, height: 24),
        controlProminence: .standard,
        styleEnvironment: styleEnvironment
      )
    )
    #expect(sheet == baseline, "the surface style returns the modifier baseline unchanged")

    let toast = SuccessToastStyle().resolvePresentation(
      for: ToastStyleConfiguration(
        stackIndex: 1,
        stackCount: 2,
        terminalSize: CellSize(width: 80, height: 24),
        styleEnvironment: styleEnvironment
      )
    )
    #expect(toast.icon != nil)
  }

  @Test("a tab-view style resolves against a fixture body configuration")
  func tabViewStyleResolvesAgainstFixture() {
    let items = ["Home", "Logs"].enumerated().map { index, title in
      TabViewStyleItemConfiguration(
        index: index,
        label: TabItemLabel(title),
        isSelected: index == 1,
        isFocused: false
      )
    }
    let styleConfiguration = TabViewStyleConfiguration(
      options: items.map { TabViewStyleOption(label: $0.label) },
      selectedIndex: 1,
      focusedIndex: nil,
      isFocused: false,
      showsFocusEffect: true,
      styleEnvironment: styleEnvironment,
      availableWidth: 40,
      isOverflowMenuExpanded: false
    )
    let presentation = UnderlineTabViewStyle().presentation(for: styleConfiguration)
    let configuration = TabViewStyleBodyConfiguration(
      styleConfiguration: styleConfiguration,
      presentation: presentation,
      items: items,
      overflowTrigger: nil,
      content: .init { Text("Logs content") }
    )
    #expect(configuration.visibleItems.count == presentation.visibleOptionIndices.count)

    let artifacts = DefaultRenderer().render(
      UnderlineTabViewStyle().makeBody(configuration: configuration),
      context: .init(identity: testIdentity("TabViewFixture")),
      proposal: .init(width: 40, height: 4)
    )
    let rendered = surface(artifacts)
    #expect(rendered.contains("Home"))
    #expect(rendered.contains("Logs content"))
  }
}
