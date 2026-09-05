import SwiftTUIViews

// Intentionally imports only the public authoring product, without SPI.
// This file also typechecks outside the package as a style-library consumer.
struct ConsumerLabelStyle: LabelStyle, Equatable {
  var prefix = ""

  func makeBody(configuration: LabelStyleConfiguration) -> some View {
    HStack(alignment: .center, spacing: 1) {
      if !prefix.isEmpty { Text(prefix) }
      configuration.icon
      configuration.title
    }
  }
}

struct ConsumerLabeledContentStyle: LabeledContentStyle, Equatable {
  var prefix = ""

  func makeBody(configuration: LabeledContentStyleConfiguration) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 1) {
      if !prefix.isEmpty { Text(prefix) }
      configuration.label.foregroundStyle(.separator)
      Spacer()
      configuration.content
    }
  }
}

struct ConsumerGroupBoxStyle: GroupBoxStyle, Equatable {
  var prefix = ""

  func makeBody(configuration: GroupBoxStyleConfiguration) -> some View {
    let environment = configuration.styleEnvironment
    let foreground = environment.foregroundStyle ?? environment.theme.style(for: .foreground)
    let tone: TerminalTone = configuration.controlProminence == .increased ? .accent : .neutral
    VStack(alignment: .leading, spacing: 0) {
      if !prefix.isEmpty { Text(prefix) }
      if let label = configuration.label {
        label.foregroundStyle(.separator)
      }
      VStack(alignment: .leading, spacing: 0) {
        configuration.content
      }
      .padding(.init(horizontal: 1, vertical: 1))
      .overlay {
        RoundedRectangle(cornerRadius: 1).strokeBorder(AnyShapeStyle(.terminalBorder(tone)))
      }
      .foregroundStyle(foreground)
    }
    .frame(minHeight: .finite((configuration.label == nil ? 0 : 1) + 3), alignment: .topLeading)
  }
}

struct ConsumerPassiveStyleFactories: View {
  var body: some View {
    VStack {
      Label("A") { Text("*") }.labelStyle(AutomaticLabelStyle.automatic)
      Label("B") { Text("*") }.labelStyle(TitleAndIconLabelStyle.titleAndIcon)
      Label("C") { Text("*") }.labelStyle(TitleOnlyLabelStyle.titleOnly)
      Label("D") { Text("*") }.labelStyle(IconOnlyLabelStyle.iconOnly)
      LabeledContent("E", value: "value")
        .labeledContentStyle(AutomaticLabeledContentStyle.automatic)
      LabeledContent("F", value: "value")
        .labeledContentStyle(StackedLabeledContentStyle.stacked)
      GroupBox { Text("G") }.groupBoxStyle(AutomaticGroupBoxStyle.automatic)
      GroupBox { Text("H") }.groupBoxStyle(BorderedGroupBoxStyle.bordered)
      GroupBox { Text("I") }.groupBoxStyle(PlainGroupBoxStyle.plain)
    }
    .labelStyle(AnyLabelStyle(ConsumerLabelStyle()))
    .labeledContentStyle(AnyLabeledContentStyle(ConsumerLabeledContentStyle()))
    .groupBoxStyle(AnyGroupBoxStyle(ConsumerGroupBoxStyle()))
  }
}
