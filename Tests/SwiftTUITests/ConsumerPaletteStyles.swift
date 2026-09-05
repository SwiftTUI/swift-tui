import SwiftTUIViews

// Independently typechecked against the public module, without fixture SPI.
struct ConsumerPaletteStyle: PaletteStyle, Equatable {
  let tag: String
  func makeBody(configuration: PaletteStyleConfiguration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(tag)
      Text(configuration.title)
      ForEach(configuration.commands) { command in
        command.route { Text(command.name) }
      }
      Button("First") { configuration.commands.first?.perform() }
      Button("Cancel") { configuration.dismiss() }
    }
  }
}

@MainActor
func consumerPaletteModifiers() -> some View {
  VStack {
    Text("Plain").paletteStyle(ConsumerPaletteStyle(tag: "generic"))
    Text("Plain").paletteStyle(AnyPaletteStyle.automatic)
    Panel(id: "generic") { Text("Base") }
      .paletteStyle(ConsumerPaletteStyle(tag: "generic"))
      .paletteSheet("Palette", isPresented: .constant(false))
    Panel(id: "erased") { Text("Base") }
      .paletteStyle(AnyPaletteStyle.automatic)
      .paletteSheet("Palette", isPresented: .constant(false))
  }
}
