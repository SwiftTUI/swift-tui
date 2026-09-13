import Foundation
import SwiftTUIRuntime

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Musl)
  import Musl
#elseif canImport(Android)
  import Android
#elseif canImport(ucrt)
  import CRT
#endif

@MainActor
@main
struct DevCommand {
  static func main() async {
    do {
      let options = try DevOptions(Array(CommandLine.arguments.dropFirst()))
      if options.help { print(DevOptions.usage); return }
      #if os(macOS) || os(Linux)
        let driver = try ReloadDriver(options: options)
        let status = try await driver.run()
        exit(status)
      #else
        throw DevError("Compiled hot reload supports macOS and Linux terminal hosts")
      #endif
    } catch {
      FileHandle.standardError.write(Data("swifttui-dev: \(error)\n".utf8))
      exit(1)
    }
  }
}
