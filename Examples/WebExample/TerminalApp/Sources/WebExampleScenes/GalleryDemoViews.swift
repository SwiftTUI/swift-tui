import TerminalUI
import TerminalUICharts

struct GalleryDemoSceneView: View {
  @Bindable var model: GalleryDemoModel
  @State private var isResetAlertPresented = false
  @State var pickerScratch: String = "one"
  var body: some View {
    GeometryReader { geometry in
      shell(contentHeight: max(0, geometry.size.height - 4))
    }
  }

  private func shell(contentHeight: Int) -> some View {
    ZStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 0) {
        headerBar
        Divider()
        TabView(selection: $model.activeTab) {
          controlsWorkbench
            .tabItem("Controls")
            .tag("controls")
          collectionsWorkbench
            .tabItem("Collections")
            .tag("collections")
          appearanceWorkbench
            .tabItem("Appearance")
            .tag("appearance")
          chartsWorkbench
            .tabItem("Charts")
            .tag("charts")
        }
        .frame(
          maxWidth: .infinity,
          minHeight: .finite(contentHeight),
          idealHeight: .finite(contentHeight),
          maxHeight: .finite(contentHeight),
          alignment: .topLeading
        )
        Divider()
        footerBar
      }
      .disabled(model.isPalettePresented)

      if model.isPalettePresented {
        GalleryCommandPalette(
          query: $model.paletteQuery,
          commands: paletteCommands,
          dismiss: dismissPalette,
          runCommand: runPaletteCommand
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .alert(
      "Reset gallery state?",
      isPresented: $isResetAlertPresented,
      actions: {
        Button("Reset", role: .destructive) {
          model.reset()
        }
        Button("Cancel", role: .cancel) {
          isResetAlertPresented = false
        }
      },
      message: {
        Text("Clears the interactive control and appearance samples?")
      }
    )
  }

  private var headerBar: some View {
    HStack(alignment: .firstTextBaseline, spacing: 1) {
      Text("Gallery")
        .bold()
      Text("—")
        .foregroundStyle(.separator)
      Text(model.activeTab.capitalized)
        .foregroundStyle(.info)
      Spacer()
      Button("Control Panel") {
        model.isPalettePresented = true
      }
      .buttonStyle(.plain)
    }
    .padding(.init(horizontal: 1, vertical: 0))
    .background(.terminalRow(.accent, isSelected: true))
  }

  private var footerBar: some View {
    DemoHelpStrip(
      groups: [
        .init(
          title: "Navigate",
          bindings: [
            .init("tab", "move focus"),
            .init("arrows", "move selection"),
          ]
        ),
        .init(
          title: "Act",
          bindings: [
            .init("enter", "activate"),
            .init("q", "quit"),
          ]
        ),
      ]
    )
    .padding(.init(horizontal: 1, vertical: 0))
  }

  private var controlsWorkbench: some View {
    workbenchSurface(
      selection: $model.selectedControlDemo,
      entries: [
        "buttons",
        "inputs",
        "values",
      ],
      title: controlsTitle,
      subtitle: controlsSubtitle
    ) {
      controlsPreview
    }
  }

  private var controlsTitle: String {
    switch model.selectedControlDemo {
    case "inputs":
      "Inputs"
    case "values":
      "Value Controls"
    default:
      "Buttons"
    }
  }

  private var controlsSubtitle: String {
    switch model.selectedControlDemo {
    case "inputs":
      "Text entry and toggles with restrained default chrome."
    case "values":
      "Dense steppers, sliders, and progress surfaces."
    default:
      "Filled primary actions with plain secondary actions."
    }
  }

  @ViewBuilder
  private var controlsPreview: some View {
    switch model.selectedControlDemo {
    case "inputs":
      VStack(alignment: .leading, spacing: 1) {
        TextField("Search", text: $model.searchText)
          .frame(maxWidth: .infinity, alignment: .leading)
        SecureField("Secret", text: $model.secretText)
          .frame(maxWidth: .infinity, alignment: .leading)
        TextEditor(text: $model.editorText)
          .frame(
            maxWidth: .infinity,
            minHeight: .finite(6),
            idealHeight: .finite(6),
            maxHeight: .finite(6),
            alignment: .topLeading
          )
        Toggle("Enabled", isOn: $model.toggleEnabled)
      }
    case "values":
      VStack(alignment: .leading, spacing: 1) {
        Stepper("Count", value: $model.stepperValue, in: 0...9)
        Slider("Blend", value: $model.sliderValue, in: 0...10)
        ProgressView("Syncing", barWidth: 20)
        ProgressView(
          "Progress",
          value: Double(model.sliderValue),
          total: 10,
          barWidth: 20
        )
      }
    default:
      VStack(alignment: .leading, spacing: 1) {
        HStack(alignment: .center, spacing: 1) {
          Button("Primary") {
            model.increment()
          }
          Button("Reset", role: .destructive) {
            isResetAlertPresented = true
          }
          Button("Plain") {
            model.increment()
            model.increment()
          }
          .buttonStyle(.plain)
        }
        Text("Pressed \(model.primaryCount) times")
          .foregroundStyle(.separator)
      }
    }
  }

  private var collectionsWorkbench: some View {
    workbenchSurface(
      selection: $model.selectedCollectionDemo,
      entries: [
        "picker",
        "browser",
        "outline",
      ],
      title: collectionsTitle,
      subtitle: collectionsSubtitle
    ) {
      collectionsPreview
    }
  }

  private var collectionsTitle: String {
    switch model.selectedCollectionDemo {
    case "browser":
      "List + Table"
    case "outline":
      "Outline"
    default:
      "Picker + Menu"
    }
  }

  private var collectionsSubtitle: String {
    switch model.selectedCollectionDemo {
    case "browser":
      "Pane-local browsing with active selection and compact metrics."
    case "outline":
      "Hierarchy should read like a terminal tree, not a nested card."
    default:
      "Selection surfaces should be self-explanatory from the keyboard."
    }
  }

  @ViewBuilder
  private var collectionsPreview: some View {
    switch model.selectedCollectionDemo {
    case "browser":
      HStack(alignment: .top, spacing: 1) {
        List(selection: $model.listSelection) {
          Text("Alpha").tag("alpha")
          Text("Beta").tag("beta")
          Text("Gamma").tag("gamma")
        }
        .frame(width: 18, height: 8, alignment: .topLeading)

        Table(
          selection: $model.tableSelection,
          columns: [
            .init("Metric", width: 9),
            .init("Value", width: 5, alignment: .trailing),
          ]
        ) {
          TableRow {
            Text("Latency")
            Text("14")
          }
          .tag("latency")

          TableRow {
            Text("Errors")
            Text("2")
          }
          .tag("errors")

          TableRow {
            Text("Throughput")
            Text("88")
          }
          .tag("throughput")
        }
        .tableHeaders(.visible)
        .frame(
          maxWidth: .infinity,
          minHeight: 8,
          idealHeight: 8,
          maxHeight: 8,
          alignment: .topLeading
        )
      }
    case "outline":
      OutlineGroup(
        [
          GalleryOutlineNode(
            title: "Sources",
            children: [
              .init(title: "Core"),
              .init(
                title: "View", children: [.init(title: "Controls"), .init(title: "Collections")]),
            ]
          ),
          .init(
            title: "Examples",
            children: [
              .init(title: "Todoist"),
              .init(title: "Gallery"),
            ]
          ),
        ],
        children: \.children
      ) { node in
        Text(node.title)
      }
      .outlineStyle(.rounded)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    default:
    VStack(alignment: .leading) {
        TabView(selection: $model.pickerSelection) {
        Picker("Selection Type", selection: $pickerScratch) {
          Text("One").tag("one")
          Text("Two").tag("two")
          Text("Three").tag("three")
        }
        .pickerStyle(.segmented)
        .tabItem("segmented")
        .tag("segmented")

        Picker("Selection Type", selection: $pickerScratch) {
          Text("One").tag("one")
          Text("Two").tag("two")
          Text("Three").tag("three")
        }
        .pickerStyle(.inline)
        .tabItem("inline")
        .tag("inline")

        Picker("Radio Group", selection: $pickerScratch) {
          Text("One").tag("one")
          Text("Two").tag("two")
          Text("Three").tag("three")
        }
        .pickerStyle(.radioGroup)
        .tabItem("radioGroup")
        .tag("radioGroup")

        Picker("Menu", selection: $pickerScratch) {
          Text("One").tag("one")
          Text("Two").tag("two")
          Text("Three").tag("three")
        }
        .pickerStyle(.menu)
        .tabItem("menu")
        .tag("menu")
        }
        Text("(selection: \(pickerScratch))")
    }
    }
  }

  private var appearanceWorkbench: some View {
    workbenchSurface(
      selection: $model.selectedAppearanceDemo,
      entries: [
        "light",
         "dark",
        "accent",
        "colors",
      ],
      title: appearanceTitle,
      subtitle: appearanceSubtitle
    ) {
      appearancePreview
    }
  }

  private var appearanceTitle: String {
    switch model.selectedAppearanceDemo {
    case "dark":
      "Dark Mode"
    case "accent":
      "Accent Propagation"
    case "colors":
      "Color Gallery"
    default:
      "Light Mode"
    }
  }

  private var appearanceSubtitle: String {
    switch model.selectedAppearanceDemo {
    case "dark":
      "Foreground contrast must stay explicit and legible in dark terminals."
    case "accent":
      "Tint should affect selection, borders, and highlights coherently."
    case "colors":
      "Named colors, semantic roles, and palette slots available to the demo."
    default:
      "Light terminals need explicit dark foregrounds by default."
    }
  }

  @ViewBuilder
  private var appearancePreview: some View {
    switch model.selectedAppearanceDemo {
    case "colors":
      GalleryColorGallery()
    default:
      HStack(alignment: .top, spacing: 1) {
        appearanceSample(
          title: "Preferred light mode",
          scheme: model.selectedAppearanceDemo == "dark" ? .dark : .light,
          tint: model.selectedAppearanceDemo == "accent" ? Color.green : Color.blue
        )
        .frame(width: 28, alignment: .topLeading)

        appearanceSample(
          title: "Preferred dark mode",
          scheme: .dark,
          tint: model.selectedAppearanceDemo == "accent" ? Color.green : Color.blue
        )
        .frame(width: 28, alignment: .topLeading)
      }
    }
  }

  private func appearanceSample(
    title: String,
    scheme: ColorScheme,
    tint: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(title)
        .foregroundStyle(.separator)
      Button("Accent") {}
      ProgressView("Load", value: 3, total: 5, barWidth: 12)
      Toggle("Flag", isOn: .constant(true))
    }
    .preferredColorScheme(scheme)
    .tint(tint)
  }

  private var chartsWorkbench: some View {
    workbenchSurface(
      selection: $model.selectedChartDemo,
      entries: [
        "progress",
        "usage",
        "trend",
      ],
      title: chartsTitle,
      subtitle: chartsSubtitle
    ) {
      chartsPreview
    }
  }

  private var chartsTitle: String {
    switch model.selectedChartDemo {
    case "usage":
      "Usage"
    case "trend":
      "Trend"
    default:
      "Progress"
    }
  }

  private var chartsSubtitle: String {
    switch model.selectedChartDemo {
    case "usage":
      "Compact metrics should stay legible without dashboard overkill."
    case "trend":
      "Sparklines and deltas belong in dense terminal workspaces."
    default:
      "Progress should read clearly in both color schemes."
    }
  }

  @ViewBuilder
  private var chartsPreview: some View {
    switch model.selectedChartDemo {
    case "usage":
      VStack(alignment: .leading, spacing: 1) {
        BarChart(
          "Usage",
          entries: [
            .init("text", value: 4, tone: .info),
            .init("forms", value: 6, tone: .success),
            .init("charts", value: 3, tone: .warning),
          ],
          barWidth: 10,
          labelWidth: 6
        )
        ComparisonChart(
          "Delta",
          entries: [
            .init("renders", current: 8, baseline: 5, total: 10, tone: .success),
            .init("focus", current: 4, baseline: 6, total: 10, tone: .warning),
          ],
          barWidth: 10,
          labelWidth: 6
        )
      }
    case "trend":
      Sparkline(
        "Trend",
        values: [1, 2, 3, 5, 4, 6, 7],
        tone: .info
      )
    default:
      ProgressView("Adoption", value: 7, total: 10, barWidth: 20)
    }
  }

  private func workbenchSurface<Content: View>(
    selection: Binding<String>,
    entries: [String],
    title: String,
    subtitle: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Picker("", selection: selection) {
        ForEach(entries, id: \.self) { entry in
          Text(entry).tag(entry)
        }
      }
      .pickerStyle(.segmented)
      .padding(.init(horizontal: 1, vertical: 0))

      Divider()
      previewPanel(
        title: title,
        subtitle: subtitle
      ) {
        content()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func previewPanel<Content: View>(
    title: String,
    subtitle: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      VStack(alignment: .leading, spacing: 0) {
        Text(title)
          .bold()
        Text(subtitle)
          .lineLimit(2)
          .truncationMode(.tail)
          .foregroundStyle(.separator)
      }
      Divider()
      content()
      Spacer(minLength: 0)
    }
    .padding(1)
    .frame(
      minWidth: .finite(24),
      maxWidth: .infinity,
      maxHeight: .infinity,
      alignment: .topLeading
    )
  }

  private var paletteCommands: [GalleryPaletteCommand] {
    [
      .init(
        id: "controls",
        title: "Show Controls",
        detail: "Open the controls workbench",
        keywords: ["buttons", "inputs", "values", "forms"]
      ),
      .init(
        id: "collections",
        title: "Show Collections",
        detail: "Browse list, picker, outline, and table samples",
        keywords: ["list", "table", "picker", "outline", "browser"]
      ),
      .init(
        id: "appearance",
        title: "Show Appearance",
        detail: "Compare light, dark, accent propagation, and available colors",
        keywords: ["theme", "light", "dark", "accent", "colors", "palette"]
      ),
      .init(
        id: "charts",
        title: "Show Charts",
        detail: "Inspect progress, usage, and trend metrics",
        keywords: ["progress", "usage", "trend", "sparkline"]
      ),
      .init(
        id: "reset",
        title: "Reset Interactive Samples",
        detail: "Restore the default gallery state",
        keywords: ["reset", "restore", "defaults"]
      ),
    ]
  }

  private func dismissPalette() {
    model.isPalettePresented = false
    model.paletteQuery = ""
  }

  private func runPaletteCommand(_ command: GalleryPaletteCommand) {
    switch command.id {
    case "controls":
      model.activeTab = "controls"
    case "collections":
      model.activeTab = "collections"
    case "appearance":
      model.activeTab = "appearance"
    case "charts":
      model.activeTab = "charts"
    case "reset":
      model.reset()
      return
    default:
      break
    }

    dismissPalette()
  }
}

private struct GalleryOutlineNode: Identifiable {
  let id: String
  let title: String
  let children: [GalleryOutlineNode]?

  init(
    title: String,
    children: [GalleryOutlineNode]? = nil
  ) {
    id = title
    self.title = title
    self.children = children
  }
}

private struct DemoHelpBinding: Identifiable {
  let key: String
  let label: String

  var id: String {
    key + "\u{001F}" + label
  }

  init(_ key: String, _ label: String) {
    self.key = key
    self.label = label
  }
}

private struct DemoHelpGroup: Identifiable {
  let title: String?
  let bindings: [DemoHelpBinding]

  var id: String {
    (title ?? "") + "\u{001F}" + bindings.map(\.id).joined(separator: "|")
  }

  init(title: String? = nil, bindings: [DemoHelpBinding]) {
    self.title = title
    self.bindings = bindings
  }
}

private struct DemoHelpStrip: View {
  let groups: [DemoHelpGroup]

  var body: some View {
    ScrollView(.horizontal) {
      HStack(alignment: .center, spacing: 2) {
        ForEach(groups) { group in
          HStack(alignment: .center, spacing: 1) {
            if let title = group.title {
              Text(title)
                .foregroundStyle(.separator)
            }

            ForEach(group.bindings) { binding in
              HStack(alignment: .center, spacing: 1) {
                Text("[\(binding.key)]")
                  .bold()
                Text(binding.label)
              }
            }
          }
        }
      }
      .fixedSize(horizontal: true, vertical: false)
    }
    .frame(
      maxWidth: .infinity,
      minHeight: .finite(1),
      idealHeight: .finite(1),
      maxHeight: .finite(1),
      alignment: .leading
    )
  }
}

private struct GalleryPaletteCommand: Identifiable {
  let id: String
  let title: String
  let detail: String
  let keywords: [String]
}

private struct GalleryCommandPalette: View {
  @Binding var query: String
  let commands: [GalleryPaletteCommand]
  let dismiss: () -> Void
  let runCommand: (GalleryPaletteCommand) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Command Palette")
          .bold()
        Text("Search demos")
          .foregroundStyle(.separator)
      }
      .padding(1)

      Divider()

      VStack(alignment: .leading, spacing: 1) {
        TextField("Search commands", text: $query)
          .frame(maxWidth: .infinity, alignment: .leading)

        Divider()

        VStack(alignment: .leading, spacing: 0) {
          if filteredCommands.isEmpty {
            Text("No matching commands")
              .foregroundStyle(.separator)
          } else {
            ForEach(filteredCommands) { command in
              Button(
                action: {
                  runCommand(command)
                }
              ) {
                VStack(alignment: .leading, spacing: 0) {
                  Text(command.title)
                  Text(command.detail)
                    .foregroundStyle(.separator)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
              .buttonStyle(.plain)
            }
          }
        }

        Divider()

        HStack(alignment: .center, spacing: 1) {
          Text("[enter]")
            .bold()
          Text("run")
          Spacer(minLength: 0)
          Button("Close") {
            dismiss()
          }
          .buttonStyle(.plain)
        }
      }
      .padding(1)
    }
    .background {
      RoundedRectangle(cornerRadius: 1).fill(.terminalSurfaceBackground)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 1).strokeBorder(.terminalBorder(.accent))
    }
    .focusScope()
  }

  private var filteredCommands: [GalleryPaletteCommand] {
    let needle = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map {
      String($0)
    }.joined(separator: " ")
    guard !needle.isEmpty else {
      return commands
    }

    return commands.filter { command in
      command.title.lowercased().contains(needle)
        || command.detail.lowercased().contains(needle)
        || command.keywords.contains(where: { $0.lowercased().contains(needle) })
    }
  }
}
