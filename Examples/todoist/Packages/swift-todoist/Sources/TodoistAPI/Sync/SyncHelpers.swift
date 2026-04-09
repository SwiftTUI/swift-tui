import Foundation

public enum SyncHelpers {
  public static func createCommand(
    _ type: SyncCommandType,
    args: [String: Any],
    tempId: String? = nil,
  ) -> SyncCommand {
    let encoded = args.reduce(into: [String: AnyCodable]()) { result, item in
      result[item.key] = AnyCodable(item.value)
    }
    return SyncCommand(type: type, uuid: UUID().uuidString, args: encoded, tempId: tempId)
  }

  public static func preprocessSyncCommands(_ commands: [SyncCommand]) -> [SyncCommand] {
    commands.map { command in
      switch command.type {
      case .userUpdate:
        return SyncCommand(
          type: command.type,
          uuid: command.uuid,
          args: remapPreferenceArgs(command.args),
          tempId: command.tempId,
        )
      case .itemUpdateDateComplete:
        return SyncCommand(
          type: command.type,
          uuid: command.uuid,
          args: mapIntsForBooleanFlags(command.args, keys: ["isForward", "resetSubtasks"]),
          tempId: command.tempId,
        )
      case .updateGoals:
        return SyncCommand(
          type: command.type,
          uuid: command.uuid,
          args: mapIntsForBooleanFlags(command.args, keys: ["vacationMode", "karmaDisabled"]),
          tempId: command.tempId,
        )
      default:
        return command
      }
    }
  }

  private static func remapPreferenceArgs(_ args: [String: AnyCodable]) -> [String: AnyCodable] {
    var processed = args
    if let raw = args["dateFormat"]?.value as? String, let mapped = DATE_FORMAT_TO_API[raw] {
      processed["dateFormat"] = AnyCodable(mapped)
    }
    if let raw = args["timeFormat"]?.value as? String, let mapped = TIME_FORMAT_TO_API[raw] {
      processed["timeFormat"] = AnyCodable(mapped)
    }
    if let raw = args["startDay"]?.value as? String, let mapped = DAY_OF_WEEK_TO_API[raw] {
      processed["startDay"] = AnyCodable(mapped)
    }
    if let raw = args["nextWeek"]?.value as? String, let mapped = DAY_OF_WEEK_TO_API[raw] {
      processed["nextWeek"] = AnyCodable(mapped)
    }
    return processed
  }

  private static func mapIntsForBooleanFlags(
    _ args: [String: AnyCodable],
    keys: [String],
  ) -> [String: AnyCodable] {
    var processed = args
    for key in keys {
      if let value = args[key]?.value {
        if let boolValue = value as? Bool {
          processed[key] = AnyCodable(boolValue ? 1 : 0)
        } else if let nestedBool = value as? NSNumber, nestedBool == 0 || nestedBool == 1 {
          processed[key] = AnyCodable(nestedBool)
        }
      }
    }
    return processed
  }
}
