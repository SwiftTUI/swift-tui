import Foundation
public import SwiftFiglet

public enum FigletCLI {
  public static func main(
    arguments: [String] = Array(CommandLine.arguments.dropFirst()),
    fontLibraries: [FigletFontLibrary] = []
  ) {
    do {
      let exitCode = try run(arguments: arguments, fontLibraries: fontLibraries)
      Foundation.exit(exitCode)
    } catch let error as CLIError {
      FileHandle.standardError.write(Data("figlet: \(error.message)\n".utf8))
      Foundation.exit(1)
    } catch let error as FigletError {
      FileHandle.standardError.write(Data("figlet: \(error.description)\n".utf8))
      Foundation.exit(1)
    } catch {
      FileHandle.standardError.write(Data("figlet: \(error.localizedDescription)\n".utf8))
      Foundation.exit(1)
    }
  }

  public static func run(
    arguments: [String],
    fontLibraries: [FigletFontLibrary] = []
  ) throws -> Int32 {
    let options = try CLIOptions.parse(arguments)

    if options.showHelp {
      FileHandle.standardOutput.write(Data(helpText.utf8))
      return 0
    }

    if options.listFonts {
      let output =
        Figlet.availableFonts(fontLibraries: fontLibraries).joined(separator: "\n") + "\n"
      FileHandle.standardOutput.write(Data(output.utf8))
      return 0
    }

    let font = try FigletFont(named: options.font, fontLibraries: fontLibraries)

    if options.infoFont {
      let info = font.info.isEmpty ? "\(font.name)\n" : "\(font.info)\n"
      FileHandle.standardOutput.write(Data(info.utf8))
      return 0
    }

    guard !options.text.isEmpty else {
      FileHandle.standardOutput.write(Data(helpText.utf8))
      return 1
    }

    let figlet = Figlet(
      font: font,
      configuration: FigletConfiguration(
        width: options.width,
        direction: options.direction,
        justification: options.justification
      )
    )

    var output = try figlet.render(options.text.joined(separator: " ")).description
    if options.reverse {
      output = FigletText(output).reversed().description
    }
    if options.flip {
      output = FigletText(output).flipped().description
    }
    if options.stripSurroundingNewlines {
      output = FigletText(output).strippingSurroundingNewlines()
    } else if options.normalizeSurroundingNewlines {
      output = FigletText(output).normalizingSurroundingNewlines()
    }

    FileHandle.standardOutput.write(Data(output.utf8))
    FileHandle.standardOutput.write(Data("\n".utf8))
    return 0
  }
}

private struct CLIOptions {
  var font = FigletFont.defaultFontName
  var width = 80
  var direction: FigletDirection = .automatic
  var justification: FigletJustification = .automatic
  var reverse = false
  var flip = false
  var normalizeSurroundingNewlines = false
  var stripSurroundingNewlines = false
  var listFonts = false
  var infoFont = false
  var showHelp = false
  var text: [String] = []

  static func parse(_ arguments: [String]) throws -> CLIOptions {
    var options = CLIOptions()
    var index = 0

    while index < arguments.count {
      let argument = arguments[index]

      if argument == "--" {
        options.text.append(contentsOf: arguments[(index + 1)...])
        break
      }

      switch argument {
      case "-h", "--help":
        options.showHelp = true
      case "-l", "--list-fonts":
        options.listFonts = true
      case "-i", "--info-font":
        options.infoFont = true
      case "-r", "--reverse":
        options.reverse = true
      case "-F", "--flip":
        options.flip = true
      case "-n", "--normalize-surrounding-newlines":
        options.normalizeSurroundingNewlines = true
      case "-s", "--strip-surrounding-newlines":
        options.stripSurroundingNewlines = true
      case "-f", "--font":
        index += 1
        options.font = try value(after: argument, in: arguments, at: index)
      case "-w", "--width":
        index += 1
        let value = try value(after: argument, in: arguments, at: index)
        guard let parsed = Int(value) else {
          throw CLIError("invalid width '\(value)'")
        }
        options.width = parsed
      case "-D", "--direction":
        index += 1
        let value = try value(after: argument, in: arguments, at: index)
        guard let parsed = FigletDirection(rawValue: value) else {
          throw CLIError("invalid direction '\(value)'")
        }
        options.direction = parsed
      case "-j", "--justify":
        index += 1
        let value = try value(after: argument, in: arguments, at: index)
        guard let parsed = FigletJustification(rawValue: value) else {
          throw CLIError("invalid justification '\(value)'")
        }
        options.justification = parsed
      default:
        if let value = argument.value(after: "--font=") {
          options.font = value
        } else if let value = argument.value(after: "--width=") {
          guard let parsed = Int(value) else {
            throw CLIError("invalid width '\(value)'")
          }
          options.width = parsed
        } else if let value = argument.value(after: "--direction=") {
          guard let parsed = FigletDirection(rawValue: value) else {
            throw CLIError("invalid direction '\(value)'")
          }
          options.direction = parsed
        } else if let value = argument.value(after: "--justify=") {
          guard let parsed = FigletJustification(rawValue: value) else {
            throw CLIError("invalid justification '\(value)'")
          }
          options.justification = parsed
        } else if argument.hasPrefix("-") {
          throw CLIError("unknown option '\(argument)'")
        } else {
          options.text.append(argument)
        }
      }

      index += 1
    }

    return options
  }

  private static func value(after option: String, in arguments: [String], at index: Int) throws
    -> String
  {
    guard arguments.indices.contains(index) else {
      throw CLIError("missing value for \(option)")
    }
    return arguments[index]
  }
}

private struct CLIError: Error {
  let message: String

  init(_ message: String) {
    self.message = message
  }
}

private let helpText = """
  usage: figlet [options] [text...]

  Options:
    -f, --font FONT                         Font name or path (default: standard)
    -D, --direction DIR                     auto | left-to-right | right-to-left
    -j, --justify JUSTIFY                   auto | left | center | right
    -w, --width COLS                        Wrap width (default: 80)
    -r, --reverse                           Reverse rendered output
    -F, --flip                              Flip rendered output
    -n, --normalize-surrounding-newlines    Add one blank line before and after
    -s, --strip-surrounding-newlines        Trim empty lines around output
    -l, --list-fonts                        List bundled fonts
    -i, --info-font                         Print font comment metadata
    -h, --help                              Show this help
  """

extension String {
  fileprivate func value(after prefix: String) -> String? {
    guard hasPrefix(prefix) else {
      return nil
    }
    return String(dropFirst(prefix.count))
  }
}
