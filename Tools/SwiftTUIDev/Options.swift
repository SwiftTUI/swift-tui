import Foundation

struct DevError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

struct DevOptions {
  var packagePath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  var product = ""
  var target: String?
  var debounceMilliseconds = 200
  var maximumReloads = 100
  var eventLog: URL?
  var applicationArguments: [String] = []
  var help = false

  init(_ arguments: [String]) throws {
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      index += 1
      if argument == "--" { applicationArguments = Array(arguments[index...]); break }
      if argument == "--help" || argument == "-h" { help = true; continue }
      guard index < arguments.count else { throw DevError("Missing value for \(argument)") }
      let value = arguments[index]
      index += 1
      switch argument {
      case "--package-path": packagePath = URL(fileURLWithPath: value).standardizedFileURL
      case "--product": product = value
      case "--target": target = value
      case "--event-log": eventLog = URL(fileURLWithPath: value).standardizedFileURL
      case "--debounce-ms":
        guard let milliseconds = Int(value), (10...5000).contains(milliseconds) else {
          throw DevError("--debounce-ms must be between 10 and 5000")
        }
        debounceMilliseconds = milliseconds
      case "--max-reloads":
        guard let count = Int(value), (1...100).contains(count) else {
          throw DevError("--max-reloads must be between 1 and 100")
        }
        maximumReloads = count
      default: throw DevError("Unknown option: \(argument)")
      }
    }
    if !help, product.isEmpty { throw DevError("Specify --product <executable product>") }
    packagePath = packagePath.resolvingSymlinksInPath()
  }

  static let usage = """
    Usage: swifttui-dev --product <name> [options] [-- application arguments]

    --package-path <path>   Swift package directory (default: current directory)
    --target <name>         Executable target (inferred for single-target products)
    --debounce-ms <10...5000>  Quiet time before building (default: 200)
    --max-reloads <1...100>  Restart after this many images (default: 100)
    --event-log <path>      Write JSON lines with build and committed-frame timings

    Requires Swiftly and a debug app exporting swifttui_hot_reload_root.
    Manifest, resolved dependency, and toolchain changes require a restart.
    """
}
