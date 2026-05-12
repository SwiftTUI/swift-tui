import SwiftTUIRuntime

struct PopoverTab: View {
  @State private var showDetails = true
  @State private var selectedTool: PopoverDemoTool?
  @State private var showTip = false
  @State private var tipResult = "No tip action yet"

  private let tools: [PopoverDemoTool] = [
    .init(id: "filters", name: "Filters", detail: "Tune the visible rows without leaving context."),
    .init(id: "export", name: "Export", detail: "Review destination and format before committing."),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 1) {
        header
        Divider()
        booleanPopoverSection
        Divider()
        itemPopoverSection
        Divider()
        tipPopoverSection
        Spacer(minLength: 0)
      }
      .padding(1)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Popovers")
      Text("Source-attached presentation using SwiftUI-shaped modifiers.")
        .foregroundStyle(.separator)
    }
  }

  private var booleanPopoverSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Boolean binding")
        .foregroundStyle(.muted)
      Button(showDetails ? "Hide Details" : "Show Details") {
        showDetails.toggle()
      }
      .popover(
        isPresented: $showDetails,
        attachmentAnchor: .rect(.bounds),
        arrowEdge: .trailing
      ) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Details popover")
            .bold()
          Text("Anchored to the trigger and dismissed with Escape.")
            .foregroundStyle(.muted)
          Button("Close") {
            showDetails = false
          }
          .padding(.top, 1)
        }
      }
    }
  }

  private var itemPopoverSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Optional item binding")
        .foregroundStyle(.muted)
      HStack(spacing: 1) {
        ForEach(tools) { tool in
          Button(tool.name) {
            selectedTool = tool
          }
        }
      }
      .popover(
        item: $selectedTool,
        attachmentAnchor: .rect(.bounds),
        arrowEdge: .bottom
      ) { tool in
        VStack(alignment: .leading, spacing: 0) {
          Text(tool.name)
            .bold()
          Text(tool.detail)
            .foregroundStyle(.muted)
          Button("Done") {
            selectedTool = nil
          }
          .padding(.top, 1)
        }
      }
    }
  }

  private var tipPopoverSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("TipKit-inspired tip")
        .foregroundStyle(.muted)
      HStack(spacing: 1) {
        Button("Show Tip") {
          showTip = true
        }
        Text(tipResult)
          .foregroundStyle(.separator)
      }
      .popoverTip(
        PopoverDemoTip(),
        isPresented: $showTip,
        attachmentAnchor: .rect(.bounds),
        arrowEdge: .bottom
      ) { action in
        tipResult = "Tip action: \(action.title)"
      }
    }
  }
}

private struct PopoverDemoTool: Identifiable, Sendable {
  var id: String
  var name: String
  var detail: String
}

private struct PopoverDemoTip: PopoverTip {
  var id: String { "popover-demo-tip" }

  var title: Text {
    Text("Try item popovers")
  }

  var message: Text? {
    Text("Open a tool chip to render a popover from an Identifiable binding.")
  }

  var actions: [PopoverTipAction] {
    [
      PopoverTipAction(id: "got-it", title: "Got it")
    ]
  }
}
