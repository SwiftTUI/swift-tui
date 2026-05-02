#if !canImport(WASILibc)
  enum CLIModeError: Error, CustomStringConvertible {
    case missingValue(flag: String)
    case invalidPID(String)
    case unknownFlag(String)

    var description: String {
      switch self {
      case .missingValue(let flag):
        "Missing value for \(flag)"
      case .invalidPID(let value):
        "Invalid PID: \(value)"
      case .unknownFlag(let flag):
        "Unknown flag: \(flag)"
      }
    }
  }

  enum InstanceSelector: Equatable, Sendable {
    case mostRecent
    case pid(Int32)
    case name(String)
  }

  enum CLIMode: Equatable, Sendable {
    case app(instanceName: String?)
    case listInstances
    case listScenes(selector: InstanceSelector)
    case attach(sceneID: String, selector: InstanceSelector)

    static func parse(_ arguments: [String]) throws(CLIModeError) -> CLIMode {
      // Skip argv[0]
      let args = Array(arguments.dropFirst())

      var instanceName: String?
      var listInstances = false
      var listScenes = false
      var attachSceneID: String?
      var pid: Int32?
      var selectorName: String?

      var index = 0
      while index < args.count {
        let arg = args[index]
        switch arg {
        case "--instances":
          listInstances = true
        case "--scenes":
          listScenes = true
        case "--attach":
          index += 1
          guard index < args.count else {
            throw .missingValue(flag: "--attach")
          }
          attachSceneID = args[index]
        case "--pid":
          index += 1
          guard index < args.count else {
            throw .missingValue(flag: "--pid")
          }
          guard let parsedPID = Int32(args[index]) else {
            throw .invalidPID(args[index])
          }
          pid = parsedPID
        case "--instance":
          index += 1
          guard index < args.count else {
            throw .missingValue(flag: "--instance")
          }
          let name = args[index]
          // Determine if this is a launch-time name or a selector based on
          // whether a client flag is also present. We resolve this after parsing.
          if listScenes || attachSceneID != nil || listInstances {
            selectorName = name
          } else {
            // Could be either — store as instance name, re-classify below.
            instanceName = name
          }
        default:
          break
        }
        index += 1
      }

      // Re-classify --instance if a client flag was parsed after it.
      if let name = instanceName, listScenes || attachSceneID != nil {
        selectorName = name
        instanceName = nil
      }

      let selector: InstanceSelector =
        if let pid {
          .pid(pid)
        } else if let selectorName {
          .name(selectorName)
        } else {
          .mostRecent
        }

      if listInstances {
        return .listInstances
      }

      if let attachSceneID {
        return .attach(sceneID: attachSceneID, selector: selector)
      }

      if listScenes {
        return .listScenes(selector: selector)
      }

      return .app(instanceName: instanceName)
    }
  }
#endif
