import SwiftTerm
import SwiftUI
import TerminalUI

public struct SwiftTermTUIAppView<A: TerminalUI.App>: SwiftUI.View {
  private let state: SwiftTermTUIAppState<A>

  public init(state: SwiftTermTUIAppState<A>) {
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
  let terminalView: TerminalView

  var body: some SwiftUI.View {
    TerminalSurfaceRepresentable(terminalView: terminalView)
      .background(.clear)
  }
}

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
  @available(macOS 14.0, *)
  private struct TerminalSurfaceRepresentable: NSViewRepresentable {
    let terminalView: TerminalView

    func makeNSView(context _: Context) -> TerminalView {
      terminalView
    }

    func updateNSView(_ view: TerminalView, context _: Context) {
      _ = view
    }
  }
#elseif canImport(UIKit)
  @available(iOS 17.0, macCatalyst 17.0, *)
  private struct TerminalSurfaceRepresentable: UIViewRepresentable {
    let terminalView: TerminalView

    func makeUIView(context _: Context) -> TerminalView {
      terminalView
    }

    func updateUIView(_ view: TerminalView, context _: Context) {
      _ = view
    }
  }
#endif

private struct SceneSwitcherBar: SwiftUI.View {
  let scenes: [SwiftTermTUISceneDescriptor]
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
  let host: SwiftTermTUISceneHost?

  var body: some SwiftUI.View {
    Group {
      if let host {
        TerminalSurfaceHost(terminalView: host.platformView)
          // Keep one persistent SwiftTerm-backed platform view per scene host
          // so the underlying terminal buffer survives scene switches.
          .id(host.descriptor.id)
          #if canImport(UIKit) && !targetEnvironment(macCatalyst)
            .overlay(alignment: .topTrailing) {
              if host.focusPresentation.prefersTextInput == false {
                KeyboardToggleButton(
                  isPresented: host.manualKeyboardPresentationRequested,
                  action: host.toggleManualKeyboardPresentation
                )
                .padding(12)
              }
            }
          #endif
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

#if canImport(UIKit) && !targetEnvironment(macCatalyst)
  @available(iOS 17.0, *)
  private struct KeyboardToggleButton: SwiftUI.View {
    let isPresented: Bool
    let action: () -> Void

    var body: some SwiftUI.View {
      Button(action: action) {
        Image(systemName: isPresented ? "keyboard.chevron.compact.down" : "keyboard")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.primary)
          .frame(width: 36, height: 36)
          .background(.regularMaterial, in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isPresented ? "Hide keyboard" : "Show keyboard")
    }
  }
#endif
