import TerminalUI
import TerminalUICharts

struct GalleryDemoSceneView: View {
  @Bindable var model: GalleryDemoModel

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
    .tint(Color.cyan)
    .chromePreset(.standard)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var headerBar: some View {
    HStack(alignment: .firstTextBaseline, spacing: 1) {
      Text("Component Gallery")
        .bold()
      Text("TerminalUI workbench")
        .foregroundStyle(.separator)
      Spacer()
      Text(model.activeTab.capitalized)
        .foregroundStyle(.info)
      Text("count \(model.primaryCount)")
        .foregroundStyle(.separator)
    }
    .padding(.init(horizontal: 1, vertical: 0))
    .background(.terminalRow(.accent, isSelected: true))
  }

  private var footerBar: some View {
    HStack(alignment: .center, spacing: 1) {
      Text("Arrow keys")
      Text("switch tabs and move list focus")
        .foregroundStyle(.separator)
      Spacer()
      Text("Enter")
      Text("activates controls")
        .foregroundStyle(.separator)
      Spacer()
      Text("q")
      Text("quits")
        .foregroundStyle(.separator)
    }
    .padding(.init(horizontal: 1, vertical: 0))
  }

  private var controlsWorkbench: some View {
    HStack(alignment: .top, spacing: 0) {
      gallerySidebar(
        title: "Controls",
        selection: $model.selectedControlDemo,
        entries: [
          ("Buttons", "buttons"),
          ("Inputs", "inputs"),
          ("Value Controls", "values"),
        ]
      )
      .frame(
        minWidth: 18,
        idealWidth: 18,
        maxWidth: 18,
        maxHeight: .infinity,
        alignment: .topLeading
      )
      Divider()
      previewPanel(
        title: controlsTitle,
        subtitle: controlsSubtitle
      ) {
        controlsPreview
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

  private var controlsPreview: AnyView {
    switch model.selectedControlDemo {
    case "inputs":
      return AnyView(
        VStack(alignment: .leading, spacing: 1) {
          TextField("Search", text: $model.searchText)
            .frame(maxWidth: .infinity, alignment: .leading)
          SecureField("Secret", text: $model.secretText)
            .frame(maxWidth: .infinity, alignment: .leading)
          Toggle("Enabled", isOn: $model.toggleEnabled)
        }
      )
    case "values":
      return AnyView(
        VStack(alignment: .leading, spacing: 1) {
          Stepper("Count", value: $model.stepperValue, in: 0...9)
          Slider("Blend", value: $model.sliderValue, in: 0...10)
          ProgressView(
            "Progress",
            value: Double(model.sliderValue),
            total: 10,
            barWidth: 20
          )
        }
      )
    default:
      return AnyView(
        VStack(alignment: .leading, spacing: 1) {
          HStack(alignment: .center, spacing: 1) {
            Button("Primary") {
              model.increment()
            }
            Button("Reset") {
              model.reset()
            }
            Button("Plain") {}
              .buttonStyle(.plain)
          }
          Text("Pressed \(model.primaryCount) times")
            .foregroundStyle(.separator)
        }
      )
    }
  }

  private var collectionsWorkbench: some View {
    HStack(alignment: .top, spacing: 0) {
      gallerySidebar(
        title: "Collections",
        selection: $model.selectedCollectionDemo,
        entries: [
          ("Picker", "picker"),
          ("Browser", "browser"),
          ("Outline", "outline"),
        ]
      )
      .frame(
        minWidth: 18,
        idealWidth: 18,
        maxWidth: 18,
        maxHeight: .infinity,
        alignment: .topLeading
      )
      Divider()
      previewPanel(
        title: collectionsTitle,
        subtitle: collectionsSubtitle
      ) {
        collectionsPreview
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

  private var collectionsPreview: AnyView {
    switch model.selectedCollectionDemo {
    case "browser":
      return AnyView(
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
      )
    case "outline":
      return AnyView(
        OutlineGroup(
          [
            GalleryOutlineNode(
              title: "Sources",
              children: [
                .init(title: "Core"),
                .init(title: "View", children: [.init(title: "Controls"), .init(title: "Collections")]),
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
      )
    default:
      return AnyView(
        VStack(alignment: .leading, spacing: 1) {
          Picker("Mode", selection: $model.pickerSelection) {
            Text("Inline").tag("inline")
            Text("Segmented").tag("segmented")
            Text("Menu").tag("menu")
          }
          .pickerStyle(.segmented)

          Menu("Commands") {
            Button("Open") {}
            Divider()
            Button("Duplicate") {}
            Button("Archive") {}
          }
        }
      )
    }
  }

  private var appearanceWorkbench: some View {
    HStack(alignment: .top, spacing: 0) {
      gallerySidebar(
        title: "Appearance",
        selection: $model.selectedAppearanceDemo,
        entries: [
          ("Light", "light"),
          ("Dark", "dark"),
          ("Accent", "accent"),
        ]
      )
      .frame(
        minWidth: 18,
        idealWidth: 18,
        maxWidth: 18,
        maxHeight: .infinity,
        alignment: .topLeading
      )
      Divider()
      previewPanel(
        title: appearanceTitle,
        subtitle: appearanceSubtitle
      ) {
        appearancePreview
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var appearanceTitle: String {
    switch model.selectedAppearanceDemo {
    case "dark":
      "Dark Mode"
    case "accent":
      "Accent Propagation"
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
    default:
      "Light terminals need explicit dark foregrounds by default."
    }
  }

  private var appearancePreview: some View {
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
    HStack(alignment: .top, spacing: 0) {
      gallerySidebar(
        title: "Charts",
        selection: $model.selectedChartDemo,
        entries: [
          ("Progress", "progress"),
          ("Usage", "usage"),
          ("Trend", "trend"),
        ]
      )
      .frame(
        minWidth: 18,
        idealWidth: 18,
        maxWidth: 18,
        maxHeight: .infinity,
        alignment: .topLeading
      )
      Divider()
      previewPanel(
        title: chartsTitle,
        subtitle: chartsSubtitle
      ) {
        chartsPreview
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

  private var chartsPreview: AnyView {
    switch model.selectedChartDemo {
    case "usage":
      return AnyView(
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
      )
    case "trend":
      return AnyView(
        Sparkline(
          "Trend",
          values: [1, 2, 3, 5, 4, 6, 7],
          tone: .info
        )
      )
    default:
      return AnyView(
        ProgressView("Adoption", value: 7, total: 10, barWidth: 20)
      )
    }
  }

  private func gallerySidebar(
    title: String,
    selection: Binding<String>,
    entries: [(String, String)]
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .foregroundStyle(.separator)
        .padding(.init(horizontal: 1, vertical: 0))
      Divider()
      List(selection: selection) {
        ForEach(entries, id: \.1) { entry in
          Text(entry.0).tag(entry.1)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private func previewPanel<Content: View>(
    title: String,
    subtitle: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      HStack(alignment: .firstTextBaseline, spacing: 1) {
        Text(title)
          .bold()
        Text(subtitle)
          .foregroundStyle(.separator)
      }
      Divider()
      content()
      Spacer(minLength: 0)
    }
    .padding(1)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
