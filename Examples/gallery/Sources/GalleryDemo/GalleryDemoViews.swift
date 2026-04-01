import TerminalUI
import TerminalUICharts

struct GalleryDemoSceneView: View {
  @Bindable var model: GalleryDemoModel
  @State private var isResetAlertPresented = false
  @State private var isToastPresented = false
  @State var pickerScratch: String = "one"
  var body: some View {
    GeometryReader { geometry in
      shell(contentHeight: max(0, geometry.size.height - 4))
    }
  }

  private func shell(contentHeight: Int) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      headerBar
      Divider()
      TabView(selection: $model.activeTab) {
        controlsWorkbench
          .tabItem("Controls")
          .tag("controls")
          .command(
            id: "controls",
            title: "Show Controls",
            detail: "Open the controls workbench",
            keywords: ["buttons", "inputs", "values", "forms"],
            kind: .navigation
          )
        collectionsWorkbench
          .tabItem("Collections")
          .tag("collections")
          .command(
            id: "collections",
            title: "Show Collections",
            detail: "Browse list, picker, outline, and table samples",
            keywords: ["list", "table", "picker", "outline", "browser"],
            kind: .navigation
          )
        appearanceWorkbench
          .tabItem("Appearance")
          .tag("appearance")
          .command(
            id: "appearance",
            title: "Show Appearance",
            detail: "Compare light, dark, accent propagation, and available colors",
            keywords: ["theme", "light", "dark", "accent", "colors", "palette"],
            kind: .navigation
          )
        chartsWorkbench
          .tabItem("Charts")
          .tag("charts")
          .command(
            id: "charts",
            title: "Show Charts",
            detail: "Inspect progress, usage, and trend metrics",
            keywords: ["progress", "usage", "trend", "sparkline"],
            kind: .navigation
          )
      }
      .command(
        id: "reset",
        title: "Reset Interactive Samples",
        detail: "Restore the default gallery state",
        keywords: ["reset", "restore", "defaults"],
        kind: .destructive
      )
      .frame(
        maxWidth: .infinity,
        minHeight: .finite(contentHeight),
        idealHeight: .finite(contentHeight),
        maxHeight: .finite(contentHeight),
        alignment: .topLeading
      )
      .keyboardShortcut("tab", label: "move focus", group: "Navigate")
      .keyboardShortcut("arrows", label: "move selection", group: "Navigate")
      .keyboardShortcut("enter", label: "activate", group: "Act")
      .keyboardShortcut("q", label: "quit", group: "Act")
      Divider()
    }
    .keyboardShortcutHelp(position: .bottomLeading)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .commandPalette(isPresented: $model.isPalettePresented) { command in
      runPaletteCommand(command)
    }
    .toast("Action performed", isPresented: $isToastPresented, style: .success)
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
            isToastPresented = true
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

  private func runPaletteCommand(_ command: Command) {
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
    default:
      break
    }
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

