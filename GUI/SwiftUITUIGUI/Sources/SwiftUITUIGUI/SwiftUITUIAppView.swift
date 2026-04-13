import GhosttyTerminal
import SwiftUI
import TerminalUI

public struct SwiftUITUIAppView<A: TerminalUI.App>: SwiftUI.View {
  private let state: SwiftUITUIAppState<A>

  public init(state: SwiftUITUIAppState<A>) {
    self.state = state
  }

  public var body: some SwiftUI.View {
    VStack(spacing: 0) {
      if state.scenes.count > 1 {
        SceneSwitcherBar(
          scenes: state.scenes,
          selectedSceneID: state.selectedSceneID
        ) { sceneID in
          state.selectScene(sceneID)
        }
      }
      SceneTerminalSurface(host: state.currentSceneHost)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .ignoresSafeArea(.container, edges: .bottom)
    .task {
      state.start()
    }
    .onDisappear {
      state.stop()
    }
  }
}

@available(macOS 14.0, iOS 17.0, macCatalyst 17.0, *)
private struct TerminalSurfaceHost: SwiftUI.View {
  let context: TerminalViewState

  var body: some SwiftUI.View {
    TerminalSurfaceRepresentable(context: context)
      .background(.clear)
  }
}

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  @available(macOS 14.0, *)
  private struct TerminalSurfaceRepresentable: NSViewRepresentable {
    let context: TerminalViewState

    func makeNSView(context _: Context) -> TerminalView {
      let view = TerminalView(frame: .zero)
      configure(view)
      return view
    }

    func updateNSView(_ view: TerminalView, context _: Context) {
      configure(view)
    }

    private func configure(_ view: TerminalView) {
      view.delegate = context
      view.controller = context.controller
      view.configuration = context.configuration
    }
  }
#elseif canImport(UIKit)
  @available(iOS 17.0, macCatalyst 17.0, *)
  private struct TerminalSurfaceRepresentable: UIViewRepresentable {
    let context: TerminalViewState

    func makeUIView(context _: Context) -> TerminalView {
      let view = TerminalView(frame: .zero)
      configure(view)
      return view
    }

    func updateUIView(_ view: TerminalView, context _: Context) {
      configure(view)
    }

    private func configure(_ view: TerminalView) {
      view.delegate = context
      view.controller = context.controller
      view.configuration = context.configuration
    }
  }
#endif

private struct SceneSwitcherBar: SwiftUI.View {
  let scenes: [SwiftUITUISceneDescriptor]
  let selectedSceneID: WindowIdentifier
  let onSelect: (WindowIdentifier) -> Void

  var body: some SwiftUI.View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 0) {
        ForEach(scenes) { scene in
          Button {
            onSelect(scene.id)
          } label: {
            let isSelected = scene.id == selectedSceneID

            Text(scene.title ?? scene.id.rawValue)
              .lineLimit(1)
              .monospaced()
              .fontWeight(isSelected ? .semibold : .regular)
              .foregroundStyle(isSelected ? SwiftUI.Color.accentColor : SwiftUI.Color.primary)
              .padding(.horizontal, 6)
              .padding(.vertical, 3)
              .background {
                Rectangle()
                  .fill(
                    isSelected
                      ? SwiftUI.Color.accentColor.opacity(0.18)
                      : SwiftUI.Color.clear
                  )
              }
          }
          .buttonStyle(.plain)
          .accessibilityLabel(scene.title ?? scene.id.rawValue)
        }
      }
      .padding(.top, 10)
    }
  }
}

private struct SceneTerminalSurface: SwiftUI.View {
  let host: SwiftUITUISceneHost?

  var body: some SwiftUI.View {
    Group {
      if let host {
        TerminalSurfaceHost(context: host.viewState)
          // Force a fresh Ghostty-backed platform view per scene. Reusing the
          // same TerminalView across scene swaps can leave the previous
          // in-memory session holding a freed surface pointer.
          .id(host.descriptor.id)
          .task {
            host.start()
          }
      } else {
        VStack(spacing: 8) {
          Text("No scene selected")
            .font(.headline)
          Text("The app did not produce a visible scene.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }
}
