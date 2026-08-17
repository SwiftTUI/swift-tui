// This whole module is compiled out on Windows: the dependency edges to
// SwiftTerm and the PTY layer are platform-conditional in Package.swift, so
// the target must compile to an empty module there.
#if !os(Windows)
  public import SwiftTUICore

  public enum TerminalEmulatorEvent: Sendable, Equatable {
    case titleChanged(String)
    case workingDirectoryChanged(String)
    case clipboardWriteRequested([UInt8])
    case hyperlinkChanged(String?)
    case bell
    case mouseModeChanged(TerminalMouseMode)
    case clientReply([UInt8])
    case bufferActivated(TerminalBufferKind)
    case sizeReported(CellSize)
  }

  public enum TerminalBufferKind: Sendable, Equatable {
    case normal
    case alternate
  }

  public enum TerminalMouseMode: Sendable, Equatable {
    case disabled
    case x10
    case button
    case anyEvent
    case sgr
  }
#endif
