import TerminalUI
import TerminalUICharts

struct GalleryDemoSceneView: View {
  @Bindable var model: GalleryDemoModel

  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: 1) {
        header
        controlsSection
        appearanceSection
        collectionsSection
        chartsSection
      }
      .padding(1)
    }
    .tint(Color.cyan)
  }

  private var header: some View {
    GroupBox("Component Gallery") {
      VStack(alignment: .leading, spacing: 0) {
        Text("Faithful, idiomatic TUI building blocks.")
        Text("Dense defaults, explicit contrast, and terminal-native chrome.")
          .foregroundStyle(.separator)
        HStack(spacing: 1) {
          Text("tint")
            .foregroundStyle(.info)
          Text("scroll-safe")
            .foregroundStyle(.success)
          Text("light/dark")
            .foregroundStyle(.warning)
        }
      }
    }
  }

  private var controlsSection: some View {
    GroupBox("Controls") {
      VStack(alignment: .leading, spacing: 1) {
        ControlGroup("Buttons") {
          Button("Primary") {
            model.increment()
          }
          Button("Reset") {
            model.reset()
          }
          Button("Plain") {}
            .buttonStyle(.plain)
        }

        HStack(alignment: .top, spacing: 1) {
          VStack(alignment: .leading, spacing: 1) {
            Toggle("Enabled", isOn: $model.toggleEnabled)
            Stepper("Count", value: $model.stepperValue, in: 0...9)
            Slider("Blend", value: $model.sliderValue, in: 0...10)
          }
          VStack(alignment: .leading, spacing: 1) {
            TextField("Search", text: $model.searchText)
              .frame(width: 24, alignment: .leading)
            SecureField("Secret", text: $model.secretText)
              .frame(width: 24, alignment: .leading)
            ProgressView(
              "Progress",
              value: Double(model.sliderValue),
              total: 10,
              barWidth: 14
            )
          }
        }
      }
    }
  }

  private var appearanceSection: some View {
    GroupBox("Appearance") {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 1) {
          appearanceSample(
            title: "Light",
            scheme: .light,
            tint: Color.blue
          )
          .frame(width: 28, alignment: .topLeading)
          appearanceSample(
            title: "Dark",
            scheme: .dark,
            tint: Color.green
          )
          .frame(width: 28, alignment: .topLeading)
        }

        VStack(alignment: .leading, spacing: 1) {
          appearanceSample(
            title: "Light",
            scheme: .light,
            tint: Color.blue
          )
          appearanceSample(
            title: "Dark",
            scheme: .dark,
            tint: Color.green
          )
        }
      }
    }
  }

  private func appearanceSample(
    title: String,
    scheme: ColorScheme,
    tint: Color
  ) -> some View {
    GroupBox(title) {
      VStack(alignment: .leading, spacing: 1) {
        Text("Preferred \(title.lowercased()) mode")
        Button("Accent") {}
        ProgressView("Load", value: 3, total: 5, barWidth: 10)
        Toggle("Flag", isOn: .constant(true))
      }
      .preferredColorScheme(scheme)
      .tint(tint)
    }
  }

  private var collectionsSection: some View {
    GroupBox("Collections") {
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

        HStack(alignment: .top, spacing: 1) {
          listSection
          tableSection
        }

        outlineSection
      }
    }
  }

  private var listSection: some View {
    GroupBox("List") {
      List(selection: $model.listSelection) {
        Text("Alpha").tag("alpha")
        Text("Beta").tag("beta")
        Text("Gamma").tag("gamma")
      }
      .listStyle(.insetGrouped)
      .frame(width: 18, height: 6, alignment: .topLeading)
    }
  }

  private var tableSection: some View {
    GroupBox("Table") {
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
      .listStyle(.insetGrouped)
      .tableHeaders(.visible)
      .frame(width: 22, height: 6, alignment: .topLeading)
    }
  }

  private var outlineSection: some View {
    GroupBox("Outline") {
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
    }
  }

  private var chartsSection: some View {
    GroupBox("Charts") {
      VStack(alignment: .leading, spacing: 1) {
        ProgressView("Adoption", value: 7, total: 10, barWidth: 16)
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
        Sparkline(
          "Trend",
          values: [1, 2, 3, 5, 4, 6, 7],
          tone: .info
        )
      }
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
