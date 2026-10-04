import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct AccessibilityColorPolicyTests {
  private static let spinners: [GlyphSpinnerStyle] = [
    .automatic, .circleOrbit, .brailleRingFilled, .brailleBlockFill, .barRise, .circleFill,
    .brailleSweep, .diamondPulse, .brailleDotOrbit, .brailleLoopFilled, .quadrantOrbit, .clockFace,
    .halfCircle, .triangleCompass, .brailleRamp, .brailleLinePulse, .diceRoll, .boxCornerOrbit,
    .brailleDotFade, .brailleLineSweep, .brailleRing, .arcOrbit, .brailleLoop, .shadeFade,
    .dotChase, .globe, .moonPhase, .segmentedBar, .arrowCompass, .glyphPulse, .blockCorners,
    .horizontalBarFill, .quadrantCorners, .verticalBarFill, .heavyArrowCompass, .lineCompass,
    .asteriskCycle, .oghamPulse,
  ]

  @Test(
    "selected profiles qualify composited explicit text pairs after wire quantization",
    arguments: AccessibilityColorProfile.allCases, [false, true])
  func explicitPairs(profile: AccessibilityColorProfile, enhanced: Bool) throws {
    if profile == .standard && !enhanced { return }
    let colors: [Color] = [
      .black, .white, .red, .green, .blue, .yellow,
      Color(white: 0.45), Color(white: 0.735),
    ]
    for background in colors {
      for foreground in colors {
        var environment = EnvironmentValues()
        environment.accessibilityPreferences = .init(
          contrast: enhanced ? .increased : .standard, colorProfile: profile)
        let raster = DefaultRenderer().render(
          Text("X").underline(color: foreground.opacity(0.5)).strikethrough(color: foreground)
            .foregroundStyle(foreground.opacity(0.5)).cellBackground(background)
            .opacity(0.6),
          context: .init(identity: testIdentity("ExplicitPair"), environmentValues: environment),
          proposal: .init(width: 1, height: 1)
        ).rasterSurface
        let style = try #require(raster.cells[0][0].style)
        let fg = try Color(hex: #require(style.foregroundColor).hexString())
        let bg = try Color(hex: #require(style.backgroundColor).hexString())
        #expect(
          fg.contrastRatio(to: bg) >= (enhanced ? 7 : 4.5),
          "\(profile) foreground \(fg.hexString()) background \(bg.hexString())")
        func sgr(_ color: Color) -> Color {
          Color(
            red: Double(Int(color.red * 255)) / 255,
            green: Double(Int(color.green * 255)) / 255,
            blue: Double(Int(color.blue * 255)) / 255)
        }
        let terminalFG = sgr(try #require(style.foregroundColor))
        let terminalBG = sgr(try #require(style.backgroundColor))
        #expect(terminalFG.contrastRatio(to: terminalBG) >= (enhanced ? 7 : 4.5))
        #expect(try #require(style.underlineStyle?.color).contrastRatio(to: bg) >= 3)
        #expect(try #require(style.strikethroughStyle?.color).contrastRatio(to: bg) >= 3)
        if profile == .monochrome {
          #expect(abs(fg.red - fg.green) < 0.005 && abs(fg.green - fg.blue) < 0.005)
          #expect(abs(bg.red - bg.green) < 0.005 && abs(bg.green - bg.blue) < 0.005)
        }
      }
    }
  }

  private struct DirectText: CanvasDrawing, Equatable {
    let background: Color
    func draw(into context: inout CanvasContext) {
      context.setCell(
        at: .zero, character: "X", foreground: .red.opacity(0.5), background: background)
    }
  }

  @Test(
    "direct Canvas text reaches enhanced contrast on middle-luminance backgrounds",
    arguments: AccessibilityColorProfile.allCases)
  func directCanvasText(profile: AccessibilityColorProfile) throws {
    var environment = EnvironmentValues()
    environment.accessibilityPreferences = .init(contrast: .increased, colorProfile: profile)
    for background in [Color(white: 0.45), Color(white: 0.735), .red, .blue] {
      let raster = DefaultRenderer().render(
        Canvas(DirectText(background: background)).frame(width: 1, height: 1),
        context: .init(identity: testIdentity("DirectText"), environmentValues: environment),
        proposal: .init(width: 1, height: 1)
      ).rasterSurface
      let cell = raster.cells[0][0]
      #expect(cell.character == "X")
      let foreground = try Color(hex: #require(cell.style?.foregroundColor).hexString())
      let background = try Color(hex: #require(cell.style?.backgroundColor).hexString())
      #expect(foreground.contrastRatio(to: background) >= 7)
    }
  }

  @Test("monochrome maps sampled graphics and preserves redundant tile glyphs")
  func graphics() throws {
    let gradient = LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
    var environment = EnvironmentValues()
    environment.accessibilityPreferences.colorProfile = .monochrome
    func verify<V: View>(_ view: V, tile: Bool = false) throws {
      let surface = DefaultRenderer().render(
        view,
        context: .init(identity: testIdentity("graphic"), environmentValues: environment),
        proposal: .init(width: 12, height: 4)
      ).rasterSurface
      var count = 0
      for cell in surface.cells.flatMap({ $0 }) {
        if tile { #expect(cell.character == "·") }
        for color in [cell.style?.foregroundColor, cell.style?.backgroundColor].compactMap({ $0 }) {
          count += 1
          #expect(abs(color.red - color.green) < 0.00001)
          #expect(abs(color.green - color.blue) < 0.00001)
        }
      }
      #expect(count > 0)
    }
    try verify(Rectangle().fill(gradient).frame(width: 12, height: 4))
    try verify(Circle().fill(Color.red).frame(width: 12, height: 4))
    try verify(
      Rectangle().fill(TileStyle(.dots, foreground: gradient, background: Color.green))
        .frame(width: 12, height: 4), tile: true)
  }

  @Test(
    "increased-contrast semantic chrome works on light and dark hosts",
    arguments: [false, true], [false, true])
  func controls(light: Bool, focused: Bool) throws {
    let appearance: TerminalAppearance =
      light
      ? .init(foregroundColor: .black, backgroundColor: .white, tintColor: .blue) : .fallback
    var environment = EnvironmentValues()
    environment.terminalAppearance = appearance
    environment.accessibilityPreferences.contrast = .increased
    let id = testIdentity("control")
    if focused { environment.focusedIdentity = id }
    func verify<V: View>(_ view: V) throws {
      let surface = DefaultRenderer().render(
        view.id(id),
        context: .init(identity: testIdentity("root"), environmentValues: environment),
        proposal: .init(width: 32, height: 8)
      ).rasterSurface
      let cells = surface.cells.flatMap { $0 }.filter { !$0.character.isWhitespace }
      #expect(!cells.isEmpty)
      for cell in cells {
        let fg = cell.style?.foregroundColor ?? appearance.foregroundColor
        let bg = cell.style?.backgroundColor ?? appearance.backgroundColor
        let threshold = cell.character.isLetter || cell.character.isNumber ? 7.0 : 3.0
        #expect(
          fg.contrastRatio(to: bg) >= threshold,
          "\(String(reflecting: V.self)) profile \(environment.accessibilityPreferences.colorProfile?.rawValue ?? "nil") glyph \(cell.character) pair \(fg.hexString()) / \(bg.hexString())"
        )
      }
    }
    for profile in AccessibilityColorProfile.allCases {
      environment.accessibilityPreferences.colorProfile = profile
      for style in [AnyButtonStyle.automatic, .plain, .bordered, .borderedProminent, .link] {
        try verify(Button("Action") {}.buttonStyle(style))
      }
      for style in [AnyTextFieldStyle.automatic, .plain, .roundedBorder] {
        try verify(TextField("Name", text: .constant("Value")).textFieldStyle(style))
        try verify(SecureField("Password", text: .constant("dummy")).textFieldStyle(style))
      }
      for style in [AnyToggleStyle.automatic, .checkbox, .button] {
        for on in [false, true] {
          try verify(Toggle("Enabled", isOn: .constant(on)).toggleStyle(style))
        }
      }
      for style in [AnySliderStyle.automatic, .linear] {
        try verify(Slider("Gain", value: .constant(0.5), in: 0...1).sliderStyle(style))
      }
      for style in [AnyStepperStyle.automatic, .compact] {
        try verify(Stepper("Count", value: .constant(1), in: 0...5).stepperStyle(style))
      }
      for style in [AnyPickerStyle.automatic, .inline, .segmented, .radioGroup, .menu] {
        try verify(
          Picker("Choice", selection: .constant(1)) {
            Text("First").tag(1)
            Text("Second").tag(2)
          }.pickerStyle(style))
      }
      for style in [AnyProgressViewStyle.automatic, .linear, .circular] {
        try verify(ProgressView("Progress", value: 0.5).progressViewStyle(style))
      }
      for style in [AnyTextEditorStyle.automatic, .plain, .roundedBorder] {
        try verify(TextEditor(text: .constant("Notes")).textEditorStyle(style))
      }
      for style in [AnyLinkStyle.automatic, .plain, .underlined] {
        try verify(Link("Guide", destination: "https://example.com").linkStyle(style))
      }
      for style in [AnyDisclosureGroupStyle.automatic, .compact] {
        for expanded in [false, true] {
          try verify(
            DisclosureGroup("Details", isExpanded: .constant(expanded)) { Text("Content") }
              .disclosureGroupStyle(style))
        }
      }
      for style in [AnyMenuStyle.automatic, .button, .borderlessButton, .inline] {
        try verify(Menu("Options") { Button("Action") {} }.menuStyle(style))
      }
      for style in [AnyGroupBoxStyle.automatic, .bordered, .plain] {
        try verify(GroupBox("Group") { Text("Content") }.groupBoxStyle(style))
      }
      for style in [AnyControlGroupStyle.automatic, .horizontal, .vertical, .compactMenu] {
        try verify(
          ControlGroup {
            Button("First") {}
            Button("Second") {}
          }.controlGroupStyle(style))
      }
      for style in [AnyLabelStyle.automatic, .titleAndIcon, .titleOnly, .iconOnly] {
        try verify(Label("Label") { Text("*") }.labelStyle(style))
      }
      for style in [AnyLabeledContentStyle.automatic, .stacked] {
        try verify(LabeledContent("Name", value: "Ada").labeledContentStyle(style))
      }
      for style in [AnyListStyle.automatic, .plain, .insetGrouped] {
        try verify(
          List {
            Text("First")
            Text("Second")
          }.listStyle(style))
      }
      for style in [AnyTableStyle.automatic, .inset, .bordered] {
        try verify(
          Table(0..<2, id: \.self, columns: [.init("Value", width: 8)]) { row in
            Text("Row \(row)")
          }.tableStyle(style))
      }
      for style in [AnyTabViewStyle.automatic, .underline, .literalTabs, .powerline] {
        try verify(
          TabView(selection: Binding.constant(1)) {
            Tab("First", value: 1) { Text("Content") }
            Tab("Second", value: 2) { Text("Other") }
          }.tabViewStyle(style))
      }
      for style in Self.spinners {
        try verify(Spinner().spinnerStyle(style))
      }
    }
  }
}
