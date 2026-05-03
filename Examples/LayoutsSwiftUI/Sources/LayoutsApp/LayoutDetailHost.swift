//import Layouts
//import SwiftUI
//
///// Full-screen detail host for one ``LayoutEntry``. Renders
///// `entry.makeView()` filling the available space, with a 1-row
///// footer and a ⌃B key command that calls `onBack` to return to the
///// picker.
/////
///// SwiftUI port: the original used SwiftTUI's `.panel(id:)` /
///// `.keyCommand` modifiers; SwiftUI provides `.keyboardShortcut` on
///// `Button`-shaped views, so this host bridges the back action
///// through a hidden keyboard-shortcut button.
//struct LayoutDetailHost: View {
//  let entry: LayoutEntry
//  let onBack: @MainActor @Sendable () -> Void
//
//  @State var imgRenderer: ImageRenderer?
//
//  var body: some View {
//    VStack(alignment: .leading, spacing: 0) {
//      entry
//        .makeView()
//        .frame(width: 500, height: 500, alignment: .topLeading)
//
//
//
//      Divider()
//      Text("⌃B back  ·  ⌃C quit  ·  \(entry.category.rawValue) / \(entry.title)")
//        .foregroundStyle(.secondary)
//        .padding(.horizontal, 1)
//    }
//    .background(
//      Button("Back", action: { onBack() })
//        .keyboardShortcut("b", modifiers: .control)
//        .opacity(0)
//        .frame(width: 0, height: 0)
//    )
//  }
//}
