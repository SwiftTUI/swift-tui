import TerminalUI

struct TUIApp: App {
    var body: some Scene {
        @State var entity: String = "WORLD"
        WindowGroup {
                Rectangle().fill(.tint)
                .overlay(alignment: .center) {
                        Text("HELLO \(entity)!")
                }
                .overlay(alignment: .bottomTrailing) {
                    Button("↫") {
                        entity = [
                            "WORLD",
                            "MOM",
                            "SATAN",
                            "FRIENDS",
                            "STEVE",
                            "EGO",
                            "INTERNET",
                            "SELF AWARNESS",
                            "SWIFT"
                        ].shuffled().first!
                    }
                    .padding(1)
                }
        }
    }
}
