import Foundation
import TerminalUI
import TerminalUICharts

public struct GalleryDemoSceneView: View {
  @Bindable public var model: GalleryDemoModel
  @State private var isResetAlertPresented = false
  @State private var isToastPresented = false

  public init(model: GalleryDemoModel) {
    self.model = model
  }

  public var body: some View {
    shell()
  }

  private func shell() -> some View {
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
            detail: "Browse pickers, grouped lists, split panes, and outline samples",
            keywords: ["list", "table", "picker", "outline", "browser", "split"],
            kind: .navigation
          )
        layoutWorkbench
          .tabItem("Layout")
          .tag("layout")
          .command(
            id: "layout",
            title: "Show Layout",
            detail: "Inspect container, adaptive, and geometry-driven samples",
            keywords: ["layout", "groupbox", "geometry", "adaptive", "containers"],
            kind: .navigation
          )
        appearanceWorkbench
          .tabItem("Appearance")
          .tag("appearance")
          .command(
            id: "appearance",
            title: "Show Appearance",
            detail: "Inspect semantic tokens, tint propagation, hex styling, and available colors",
            keywords: ["theme", "tokens", "hex", "accent", "colors", "palette"],
            kind: .navigation
          )
        chartsWorkbench
          .tabItem("Charts")
          .tag("charts")
          .command(
            id: "charts",
            title: "Show Charts",
            detail: "Inspect gauges, comparisons, dashboard, and timeline metrics",
            keywords: ["progress", "gauge", "dashboard", "timeline", "sparkline"],
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
      Divider()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .toolbar(placement: .bottom) {
      Text("[Tab] move focus")
      Text("[Return] activate")
    } trailing: {
      Text("[q] quit")
    }
    .commandPalette(
      isPresented: $model.isPalettePresented,
      shortcut: .character("/"),
      onExecute: runPaletteCommand
    )
    .toast("Action performed", isPresented: $isToastPresented, style: .success)
    .alert(
      "Reset gallery state?",
      isPresented: $isResetAlertPresented,
      actions: {
        Button("Reset", role: .destructive) {
          resetInteractiveState()
        }
        Button("Cancel", role: .cancel) {
          isResetAlertPresented = false
        }
      },
      message: {
        Text("Clears the interactive controls, selection demos, and gallery workbench state?")
      }
    )
  }

  private func resetInteractiveState() {
    model.reset()
    isResetAlertPresented = false
    isToastPresented = false
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
        "actions",
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
    case "actions":
      "Actions + Links"
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
    case "actions":
      "Menus, disclosure, and inline links stay compact and keyboard-friendly."
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
    case "actions":
      VStack(alignment: .leading, spacing: 1) {
        ControlGroup("Session") {
          Button("Apply") {
            model.advance()
            isToastPresented = true
          }
          Button("Reset") {
            isResetAlertPresented = true
          }
          .buttonStyle(.plain)
          Menu("More") {
            Button("Advance") {
              model.advance()
              isToastPresented = true
            }
            Divider()
            Button("Show Palette") {
              model.isPalettePresented = true
            }
          }
        }

        DisclosureGroup(
          "Advanced",
          isExpanded: $model.isActionDisclosureExpanded
        ) {
          VStack(alignment: .leading, spacing: 0) {
            Toggle("Live Preview", isOn: $model.toggleEnabled)
            Text(
              "Read \(Link("Docs", destination: "https://swiftterminalui.dev/docs")) or \(Link("API", destination: "https://swiftterminalui.dev/api"))"
            )
          }
        }
        .openLinkAction(
          OpenLinkAction { destination in
            model.lastOpenedLink = destination.rawValue
            isToastPresented = true
            return true
          }
        )

        LabeledContent("Last link", value: model.lastOpenedLink)
          .frame(width: 42, alignment: .leading)

        Text("Menus expand inline while links remain part of the same rich text flow.")
          .foregroundStyle(.separator)
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
        "sections",
        "split",
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
    case "sections":
      "Sectioned List"
    case "split":
      "Navigation Split View"
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
    case "sections":
      "List sections provide structure without giving up terminal density."
    case "split":
      "Sidebar, content, and inspector panes can stay composed in one terminal scene."
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
    case "sections":
      HStack(alignment: .top, spacing: 1) {
        List(selection: $model.sectionListSelection) {
          Section("Framework") {
            Label("TerminalUI") {
              Text("◫")
            }
            .tag("terminal")

            Label("View") {
              Text("◎")
            }
            .tag("view")
          }

          Section("Add-ons") {
            Label("Charts") {
              Text("▥")
            }
            .tag("charts")

            Label("Scenes") {
              Text("◩")
            }
            .tag("scenes")
          }
        }
        .listStyle(.insetGrouped)
        .frame(width: 24, height: 10, alignment: .topLeading)

        GroupBox("Inspector") {
          VStack(alignment: .leading, spacing: 0) {
            Label(selectedSectionSummary.title) {
              Text(selectedSectionSummary.icon)
            }
            Text(selectedSectionSummary.note)
              .foregroundStyle(.separator)
            Divider()
            LabeledContent("Selection", value: selectedSectionSummary.title)
            LabeledContent("List style", value: "insetGrouped")
          }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    case "split":
      NavigationSplitView {
        List(selection: $model.navigationSidebarSelection) {
          Text("Examples").tag("examples")
          Text("Docs").tag("docs")
          Text("Runtime").tag("runtime")
        }
        .listStyle(.insetGrouped)
        .frame(
          minWidth: 16, idealWidth: 16, maxWidth: 16, maxHeight: .infinity, alignment: .topLeading)
      } content: {
        List(selection: $model.navigationContentSelection) {
          ForEach(navigationItems) { item in
            Text(item.title)
              .tag(item.id)
          }
        }
        .listStyle(.plain)
        .frame(
          minWidth: 20, idealWidth: 20, maxWidth: 20, maxHeight: .infinity, alignment: .topLeading)
      } detail: {
        GroupBox("Inspector") {
          VStack(alignment: .leading, spacing: 0) {
            Label(selectedNavigationItem.title) {
              Text(selectedNavigationItem.icon)
            }
            Text(selectedNavigationItem.note)
              .foregroundStyle(.separator)
            Divider()
            LabeledContent("Sidebar", value: model.navigationSidebarSelection.capitalized)
            LabeledContent("Item", value: selectedNavigationItem.title)
          }
        }
        .padding(1)
      }
      .frame(
        maxWidth: .infinity,
        minHeight: 11,
        idealHeight: 11,
        maxHeight: 11,
        alignment: .topLeading
      )
    default:
      VStack(alignment: .leading, spacing: 1) {
        TabView(selection: $model.pickerSelection) {
          Picker("Selection Type", selection: $model.pickerOptionSelection) {
            Text("One").tag("one")
            Text("Two").tag("two")
            Text("Three").tag("three")
          }
          .pickerStyle(.segmented)
          .tabItem("segmented")
          .tag("segmented")

          Picker("Selection Type", selection: $model.pickerOptionSelection) {
            Text("One").tag("one")
            Text("Two").tag("two")
            Text("Three").tag("three")
          }
          .pickerStyle(.inline)
          .tabItem("inline")
          .tag("inline")

          Picker("Radio Group", selection: $model.pickerOptionSelection) {
            Text("One").tag("one")
            Text("Two").tag("two")
            Text("Three").tag("three")
          }
          .pickerStyle(.radioGroup)
          .tabItem("radioGroup")
          .tag("radioGroup")

          Picker("Menu", selection: $model.pickerOptionSelection) {
            Text("One").tag("one")
            Text("Two").tag("two")
            Text("Three").tag("three")
          }
          .pickerStyle(.menu)
          .tabItem("menu")
          .tag("menu")
        }
        Text("(selection: \(model.pickerOptionSelection))")
          .foregroundStyle(.separator)
      }
    }
  }

  private var layoutWorkbench: some View {
    workbenchSurface(
      selection: $model.selectedLayoutDemo,
      entries: [
        "containers",
        "adaptive",
        "geometry",
      ],
      title: layoutTitle,
      subtitle: layoutSubtitle
    ) {
      layoutPreview
    }
  }

  private var layoutTitle: String {
    switch model.selectedLayoutDemo {
    case "adaptive":
      "ViewThatFits"
    case "geometry":
      "Geometry Reader"
    default:
      "Labeled Containers"
    }
  }

  private var layoutSubtitle: String {
    switch model.selectedLayoutDemo {
    case "adaptive":
      "Adaptive surfaces should degrade cleanly instead of clipping valuable context."
    case "geometry":
      "Geometry-driven views can react to the terminal surface without leaving the DSL."
    default:
      "GroupBox, Label, LabeledContent, and ControlGroup keep dense views readable."
    }
  }

  @ViewBuilder
  private var layoutPreview: some View {
    switch model.selectedLayoutDemo {
    case "adaptive":
      VStack(alignment: .leading, spacing: 1) {
        Text("ViewThatFits chooses the first layout that survives the available width.")
          .foregroundStyle(.separator)
        HStack(alignment: .top, spacing: 1) {
          adaptiveWidthSample(title: "Width 18", width: 18)
          adaptiveWidthSample(title: "Width 30", width: 30)
        }
      }
    case "geometry":
      GeometryReader { proxy in
        GroupBox("Terminal Surface") {
          VStack(alignment: .leading, spacing: 0) {
            LabeledContent("Width", value: "\(proxy.size.width)")
            LabeledContent("Height", value: "\(proxy.size.height)")
            Divider()
            LabeledContent("Mode", value: geometryMode(for: proxy.size))
            Text(geometryNote(for: proxy.size))
              .foregroundStyle(.separator)
              .lineLimit(2)
              .truncationMode(.tail)
          }
        }
      }
    default:
      HStack(alignment: .top, spacing: 1) {
        GroupBox("Inspector") {
          VStack(alignment: .leading, spacing: 0) {
            Label("Workspace") {
              Text("◧")
            }
            LabeledContent("Tab", value: model.activeTab.capitalized)
            LabeledContent("Count", value: "\(model.primaryCount)")
            Divider()
            ControlGroup("Quick Actions") {
              Button("+1") {
                model.increment()
                isToastPresented = true
              }
              .buttonStyle(.plain)
              Button("Advance") {
                model.advance()
                isToastPresented = true
              }
              .buttonStyle(.plain)
            }
          }
        }
        .frame(width: 30, alignment: .topLeading)

        GroupBox("Notes") {
          VStack(alignment: .leading, spacing: 0) {
            Text(
              "Dense terminal surfaces benefit from labeled primitives instead of custom one-off chrome."
            )
            .foregroundStyle(.separator)
            Text(
              "These containers are the pieces you reuse for inspectors, summaries, and command rows."
            )
            .foregroundStyle(.separator)
          }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    }
  }

  private var appearanceWorkbench: some View {
    workbenchSurface(
      selection: $model.selectedAppearanceDemo,
      entries: [
        "tokens",
        "tint",
        "hex",
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
    case "tint":
      "Tint Propagation"
    case "hex":
      "Hex Colors"
    case "colors":
      "Color Gallery"
    default:
      "Semantic Tokens"
    }
  }

  private var appearanceSubtitle: String {
    switch model.selectedAppearanceDemo {
    case "tint":
      "Tint should affect selection, borders, and highlights coherently."
    case "hex":
      "Hex colors should be direct authoring tools, not wrapper-only escape hatches."
    case "colors":
      "Named colors, semantic roles, and host palette slots available to the demo."
    default:
      "Views should render semantic roles without knowing which host theme is active."
    }
  }

  @ViewBuilder
  private var appearancePreview: some View {
    switch model.selectedAppearanceDemo {
    case "colors":
      GalleryColorGallery()
    case "tint":
      HStack(alignment: .top, spacing: 1) {
        appearanceSample(
          title: "Blue Accent",
          note: "The view stays token-based while the host swaps accent tone.",
          tint: .blue,
          emphasis: .hex("#2563EB")
        )
        .frame(width: 28, alignment: .topLeading)

        appearanceSample(
          title: "Green Accent",
          note: "Borders, progress, and selection all follow the new tint.",
          tint: .green,
          emphasis: .hex("#16A34A")
        )
        .frame(width: 28, alignment: .topLeading)
      }
    case "hex":
      HStack(alignment: .top, spacing: 1) {
        appearanceSample(
          title: "Hex Tint",
          note: "Accent and emphasis colors can come straight from hex values.",
          tint: .hex("#F97316"),
          emphasis: .hex("#F97316")
        )
        .frame(width: 28, alignment: .topLeading)

        appearanceSample(
          title: "Hex Contrast",
          note: "Direct hex colors work alongside semantic warning and success roles.",
          tint: .hex("#7C3AED"),
          emphasis: .hex("#06B6D4")
        )
        .frame(width: 28, alignment: .topLeading)
      }
    default:
      HStack(alignment: .top, spacing: 1) {
        appearanceSample(
          title: "Host Defaults",
          note: "Semantic roles resolve through the active host theme.",
          tint: .blue,
          emphasis: .hex("#7C3AED")
        )
        .frame(width: 28, alignment: .topLeading)

        appearanceSample(
          title: "Same View, New Accent",
          note: "The app still authors `.warning`, `.success`, and `.tint`.",
          tint: .green,
          emphasis: .hex("#F97316")
        )
        .frame(width: 28, alignment: .topLeading)
      }
    }
  }

  private func appearanceSample(
    title: String,
    note: String,
    tint: Color,
    emphasis: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(title)
        .foregroundStyle(.separator)
      Text(note)
        .foregroundStyle(.muted)
      Button("Accent") {}
      ProgressView("Load", value: 3, total: 5, barWidth: 12)
      Toggle("Flag", isOn: .constant(true))
      HStack(alignment: .center, spacing: 1) {
        Text("warning")
          .foregroundStyle(.warning)
        Text("success")
          .foregroundStyle(.success)
        Text("#hex")
          .foregroundStyle(emphasis)
      }
    }
    .tint(tint)
  }

  private var chartsWorkbench: some View {
    workbenchSurface(
      selection: $model.selectedChartDemo,
      entries: [
        "progress",
        "compare",
        "dashboard",
        "timeline",
      ],
      title: chartsTitle,
      subtitle: chartsSubtitle
    ) {
      chartsPreview
    }
  }

  private var chartsTitle: String {
    switch model.selectedChartDemo {
    case "compare":
      "Comparisons"
    case "dashboard":
      "Dashboard"
    case "timeline":
      "Trend + Timeline"
    default:
      "Progress + Gauges"
    }
  }

  private var chartsSubtitle: String {
    switch model.selectedChartDemo {
    case "compare":
      "Bar, comparison, and bullet charts answer different operational questions."
    case "dashboard":
      "Column, stacked, and heat-strip views compose into compact dashboards."
    case "timeline":
      "Sparklines summarize direction while timelines explain the story behind it."
    default:
      "Progress meters and threshold gauges cover both raw completion and health state."
    }
  }

  @ViewBuilder
  private var chartsPreview: some View {
    switch model.selectedChartDemo {
    case "compare":
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
        BulletChart(
          "Release",
          value: 7,
          target: 8,
          total: 10,
          tone: .warning,
          barWidth: 20
        )
      }
    case "dashboard":
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 2) {
          VStack(alignment: .leading, spacing: 1) {
            ColumnChart(
              "Signals",
              entries: [
                .init("cpu", value: 4, tone: .warning),
                .init("io", value: 6, tone: .info),
                .init("net", value: 3, tone: .success),
              ],
              chartHeight: 4,
              columnWidth: 2
            )
            HeatStrip(
              "Heat",
              entries: [
                .init("0", value: 2, tone: .info),
                .init("1", value: 3, tone: .success),
                .init("2", value: 6, tone: .warning),
                .init("3", value: 4, tone: .info),
                .init("4", value: 5, tone: .success),
              ],
              cellWidth: 2
            )
          }

          VStack(alignment: .leading, spacing: 1) {
            StackedBarChart(
              "Composition",
              entries: [
                .init("docs", value: 3, tone: .info),
                .init("forms", value: 5, tone: .success),
                .init("charts", value: 2, tone: .warning),
              ],
              total: 10,
              barWidth: 18
            )
            Legend(
              "Legend",
              items: [
                .init("info", tone: .info),
                .init("success", tone: .success),
                .init("warning", tone: .warning),
              ]
            )
          }
        }

        VStack(alignment: .leading, spacing: 1) {
          ColumnChart(
            "Signals",
            entries: [
              .init("cpu", value: 4, tone: .warning),
              .init("io", value: 6, tone: .info),
              .init("net", value: 3, tone: .success),
            ],
            chartHeight: 4,
            columnWidth: 2
          )
          StackedBarChart(
            "Composition",
            entries: [
              .init("docs", value: 3, tone: .info),
              .init("forms", value: 5, tone: .success),
              .init("charts", value: 2, tone: .warning),
            ],
            total: 10,
            barWidth: 18
          )
          HeatStrip(
            "Heat",
            entries: [
              .init("0", value: 2, tone: .info),
              .init("1", value: 3, tone: .success),
              .init("2", value: 6, tone: .warning),
              .init("3", value: 4, tone: .info),
              .init("4", value: 5, tone: .success),
            ],
            cellWidth: 2
          )
          Legend(
            "Legend",
            items: [
              .init("info", tone: .info),
              .init("success", tone: .success),
              .init("warning", tone: .warning),
            ]
          )
        }
      }
    case "timeline":
      VStack(alignment: .leading, spacing: 1) {
        Sparkline(
          "Trend",
          values: [1, 2, 3, 5, 4, 6, 7],
          tone: .info
        )
        Timeline([
          .init("Compose shell", detail: "tabs, palette, shortcuts", tone: .info),
          .init("Show collections", detail: "lists, sections, split panes", tone: .success),
          .init("Add metrics", detail: "gauges and timelines", tone: .warning),
        ])
      }
    default:
      VStack(alignment: .leading, spacing: 1) {
        ProgressView("Adoption", value: 7, total: 10, barWidth: 20)
        Meter(
          "Focus",
          value: Double(model.stepperValue),
          total: 10,
          tone: .info,
          barWidth: 20
        )
        ThresholdGauge(
          "Health",
          value: Double(model.sliderValue),
          total: 10,
          bands: [
            .init(upTo: 4, tone: .success),
            .init(upTo: 7, tone: .info),
            .init(upTo: 10, tone: .warning),
          ],
          barWidth: 20
        )
      }
    }
  }

  private var selectedSectionSummary: GallerySelectionSummary {
    switch model.sectionListSelection {
    case "view":
      .init(
        title: "View",
        note: "Authoring primitives, controls, collections, and styling live here.",
        icon: "◎"
      )
    case "charts":
      .init(
        title: "Charts",
        note: "Terminal-native metric views stay compact enough for dashboards.",
        icon: "▥"
      )
    case "scenes":
      .init(
        title: "Scenes",
        note: "Multi-scene launch support keeps apps closer to desktop terminal workflows.",
        icon: "◩"
      )
    default:
      .init(
        title: "TerminalUI",
        note: "The runtime bundles host integration, input handling, and rendering output.",
        icon: "◫"
      )
    }
  }

  private var navigationItems: [GalleryNavigationItem] {
    switch model.navigationSidebarSelection {
    case "docs":
      [
        .init(
          id: "architecture", title: "Architecture",
          note: "Pipeline, target boundaries, and design rules.", icon: "▤"),
        .init(
          id: "focus", title: "Focus", note: "Focus scopes, sections, and keyboard traversal.",
          icon: "◎"),
        .init(
          id: "testing", title: "Testing",
          note: "Fixture and regression policy for rendered surfaces.", icon: "✓"),
      ]
    case "runtime":
      [
        .init(
          id: "host", title: "Terminal Host",
          note: "Configures raw mode, sizing, and lifecycle coordination.", icon: "⌁"),
        .init(
          id: "signals", title: "Signals",
          note: "Bridges terminal signals into scene-safe runtime behavior.", icon: "⚑"),
        .init(
          id: "launcher", title: "Launcher",
          note: "Multi-scene entry points wire windows into one app.", icon: "⇱"),
      ]
    default:
      [
        .init(
          id: "gallery", title: "Gallery",
          note: "A full-screen workbench for public TerminalUI surfaces.", icon: "◫"),
        .init(
          id: "todoist", title: "Todoist",
          note: "A richer app that exercises panes, inspectors, and workflows.", icon: "☑"),
        .init(
          id: "web", title: "WebExample",
          note: "A browser-hosted runtime explores the same rendering pipeline.", icon: "⌘"),
      ]
    }
  }

  private var selectedNavigationItem: GalleryNavigationItem {
    navigationItems.first { $0.id == model.navigationContentSelection } ?? navigationItems[0]
  }

  private func adaptiveWidthSample(
    title: String,
    width: Int
  ) -> some View {
    GroupBox(title) {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .center, spacing: 1) {
          Label("Wide Mode") {
            Text("◫")
          }
          Text(model.selectedChartDemo.capitalized)
        }
        VStack(alignment: .leading, spacing: 0) {
          Text("Compact")
          Text(model.selectedChartDemo.capitalized)
            .foregroundStyle(.separator)
        }
      }
      .frame(width: width, alignment: .leading)
    }
  }

  private func geometryMode(
    for size: Size
  ) -> String {
    if size.width >= 110 {
      return "wide"
    }
    if size.width >= 80 {
      return "balanced"
    }
    return "compact"
  }

  private func geometryNote(
    for size: Size
  ) -> String {
    switch geometryMode(for: size) {
    case "wide":
      "The terminal has room for side-by-side panes and richer dashboards."
    case "balanced":
      "A medium surface can hold split panes while keeping controls readable."
    default:
      "Compact terminals benefit from adaptive fallbacks and stacked layouts."
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
    case "layout":
      model.activeTab = "layout"
    case "appearance":
      model.activeTab = "appearance"
    case "charts":
      model.activeTab = "charts"
    case "reset":
      resetInteractiveState()
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

private struct GallerySelectionSummary {
  let title: String
  let note: String
  let icon: String
}

private struct GalleryNavigationItem: Identifiable {
  let id: String
  let title: String
  let note: String
  let icon: String
}
