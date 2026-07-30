import Foundation
@_spi(Runners) import SwiftTUIRuntime
import SwiftTUIWASISurfaceBridge
import Synchronization
import Testing

@testable import SwiftTUIAndroidHost
@testable import SwiftTUIWebHost

@MainActor
struct HostWireConformanceAndroidABIRunner {
  private var host: AndroidHostSceneHost
  private var handle: Int64
  private var sizeLabels: [String: Int] = [:]
  private var deliveries: [HostWireConformanceJSON] = []

  init() throws {
    host = try AndroidHostSceneHost(app: HostWireConformanceAdapterApp())
    handle = AndroidHostHandleRegistry.register(host)
    guard host.declareCapabilities(json: "{\"acceptsDeltaFrames\":true}") else {
      swift_tui_android_destroy(handle)
      throw HostWireConformanceError.invalid(
        "swift-android-abi: delta capability declaration failed")
    }
    // Fresh host state, no published frame, delta enabled, `styleAppend`
    // disabled — plus the runner's pinned epoch, which is what lets the
    // fixture assert an exact `epoch` on every delivered record.
    host.pinWireEncodingEpoch(HostWireConformanceCorpus.androidABIRunnerEpochID)
  }

  static func runActiveFixtures(
    _ corpus: HostWireConformanceCorpus
  ) async throws -> [String] {
    var executed: [String] = []
    for entry in HostWireConformanceRunnerDeclaration.swiftAndroidABI.requiredEntries(
      in: corpus.manifest
    ) {
      guard let fixture = corpus.fixtures[entry.file] else {
        throw HostWireConformanceError.invalid("\(entry.file): missing parsed fixture")
      }
      var runner = try Self()
      defer { runner.destroy() }
      _ = try await runner.interpret(fixture, comparesExpectations: true)
      executed.append(entry.scenario)
    }
    return executed
  }

  static func observeInactiveFixture(
    _ fixture: HostWireConformanceFixture
  ) async throws -> [HostWireConformanceJSON] {
    var runner = try Self()
    defer { runner.destroy() }
    return try await runner.interpret(fixture, comparesExpectations: false)
  }

  private mutating func destroy() {
    guard handle != 0 else { return }
    swift_tui_android_destroy(handle)
    handle = 0
  }

  private mutating func interpret(
    _ fixture: HostWireConformanceFixture,
    comparesExpectations: Bool
  ) async throws -> [HostWireConformanceJSON] {
    guard fixture.entry.kind == .androidABI,
      fixture.entry.runners == [.swiftAndroidABI]
    else {
      throw HostWireConformanceError.invalid(
        "\(fixture.entry.file): fixture is not an Android ABI fixture")
    }
    var observations: [HostWireConformanceJSON] = []
    for (index, step) in fixture.steps.enumerated() {
      let context = "\(fixture.entry.file):step \(index + 1)"
      switch step {
      case .androidABI(let action):
        try await apply(action, context: context)
      case .expect(let expected):
        let actual: HostWireConformanceJSON = .object([
          "androidDeliveries": .array(deliveries)
        ])
        observations.append(actual)
        if comparesExpectations {
          try HostWireConformanceExactComparator.requireEqual(
            actual,
            expected,
            context: context
          )
        }
        deliveries.removeAll(keepingCapacity: true)
      default:
        throw HostWireConformanceError.invalid(
          "\(context): Android ABI adapter received an inapplicable step")
      }
    }
    guard deliveries.isEmpty else {
      throw HostWireConformanceError.invalid(
        "\(fixture.entry.file): unconsumed Android deliveries")
    }
    return observations
  }

  private mutating func apply(
    _ action: HostWireConformanceJSON,
    context: String
  ) async throws {
    guard case .object(let object) = action else {
      throw HostWireConformanceError.invalid("\(context): Android action is not an object")
    }
    let name = try value(object, "action", context: context).string(
      context: "\(context).action")
    switch name {
    case "publish":
      let sequence = try value(object, "sequence", context: context).integer(
        context: "\(context).sequence")
      let width = try value(object, "width", context: context).integer(
        context: "\(context).width")
      let height = try value(object, "height", context: context).integer(
        context: "\(context).height")
      let rows = try HostWireConformanceCorpus.parseGridRows(
        value(object, "rows", context: context),
        context: "\(context).rows"
      )
      let damage = try presentationDamage(
        value(object, "damage", context: context),
        context: "\(context).damage"
      )
      _ = try host.surface.present(
        SemanticHostFrame(
          sequence: UInt64(sequence),
          raster: try rasterSurface(width: width, height: height, rows: rows, context: context),
          semantics: SemanticSnapshot(),
          focusedIdentity: nil,
          rasterDamage: damage
        ))
      await Task.yield()
    case "sizeQuery":
      let label = try value(object, "label", context: context).string(
        context: "\(context).label")
      sizeLabels[label] = Int(swift_tui_android_copy_latest_frame(handle, nil, 0))
    case "copy":
      let label = try value(object, "label", context: context).string(
        context: "\(context).label")
      let capacity = try value(object, "capacity", context: context).integer(
        context: "\(context).capacity")
      guard let reported = sizeLabels[label], capacity <= Int(Int32.max) else {
        throw HostWireConformanceError.invalid(
          "\(context): missing size label or capacity exceeds the ABI")
      }
      var bytes = [UInt8](repeating: 0, count: capacity)
      let returned =
        if bytes.isEmpty {
          Int(swift_tui_android_copy_latest_frame(handle, nil, 0))
        } else {
          Int(
            unsafe bytes.withUnsafeMutableBufferPointer { buffer in
              unsafe swift_tui_android_copy_latest_frame(
                handle,
                buffer.baseAddress,
                Int32(capacity)
              )
            })
        }
      let raw =
        returned > 0 && returned <= capacity
        ? String(decoding: bytes.prefix(returned), as: UTF8.self) : nil
      let delivery = try HostWireConformanceRecordDecoding.androidDelivery(
        label: label,
        reported: reported,
        capacity: capacity,
        returned: returned,
        raw: raw
      )
      deliveries.append(
        try HostWireConformanceRecordDecoding.conformanceJSON(
          from: delivery,
          context: "\(context).delivery"
        ))
    default:
      throw HostWireConformanceError.invalid(
        "\(context): unsupported Android ABI action \(name)")
    }
  }

  private func rasterSurface(
    width: Int,
    height: Int,
    rows: [HostWireConformanceGridRow],
    context: String
  ) throws -> RasterSurface {
    var raster = [[RasterCell]](
      repeating: [RasterCell](repeating: .empty, count: width),
      count: height
    )
    for row in rows {
      for cell in row.cells {
        guard cell.text.count == 1, let character = cell.text.first else {
          throw HostWireConformanceError.invalid(
            "\(context): Android publish cells must contain one Character")
        }
        raster[row.row][cell.column] = RasterCell(character: character, spanWidth: cell.span)
        if cell.span > 1 {
          for column in (cell.column + 1)..<(cell.column + cell.span) {
            raster[row.row][column] = RasterCell(
              character: " ",
              spanWidth: 0,
              continuationLeadX: cell.column
            )
          }
        }
      }
    }
    return RasterSurface(size: .init(width: width, height: height), cells: raster)
  }

  private func presentationDamage(
    _ value: HostWireConformanceJSON,
    context: String
  ) throws -> PresentationDamage? {
    guard value != .null else { return nil }
    let object = try value.object(keys: ["rows"], context: context)
    let rows = try self.value(object, "rows", context: context).array(
      context: "\(context).rows")
    var textRows: [PresentationDamage.TextRow] = []
    for (index, rowValue) in rows.enumerated() {
      let rowContext = "\(context).rows[\(index)]"
      let row = try rowValue.object(keys: ["row", "ranges"], context: rowContext)
      let rowIndex = try self.value(row, "row", context: rowContext).integer(
        context: "\(rowContext).row")
      let ranges = try self.value(row, "ranges", context: rowContext).array(
        context: "\(rowContext).ranges")
      let decoded = try ranges.enumerated().map { rangeIndex, rangeValue in
        let range = try rangeValue.array(context: "\(rowContext).ranges[\(rangeIndex)]")
        let lower = try range[0].integer(context: "\(rowContext).ranges[\(rangeIndex)][0]")
        let upper = try range[1].integer(context: "\(rowContext).ranges[\(rangeIndex)][1]")
        return lower..<upper
      }
      textRows.append(.init(row: rowIndex, columnRanges: decoded))
    }
    return PresentationDamage(textRows: textRows)
  }

  private func value(
    _ object: [String: HostWireConformanceJSON],
    _ key: String,
    context: String
  ) throws -> HostWireConformanceJSON {
    guard let value = object[key] else {
      throw HostWireConformanceError.invalid("\(context): missing \(key)")
    }
    return value
  }
}

struct HostWireConformanceWebSocketChannelRunner {
  private let channel: WebHostSceneChannel
  private let transport: WebSocketSurfaceTransport
  private let state: State
  private var clients: [Int: AsyncStream<WebHostSocketMessage>.Continuation] = [:]
  private var outputTasks: [Task<Void, Never>] = []
  private var inputTask: Task<Void, Never>?
  private var currentToken: Int? = 1
  private var lastIssuedToken = 1
  private var phase = "active"
  private var pendingCapsSends: Int?
  private var capsAwaitingDrain = false

  private init() async {
    let channel = WebHostSceneChannel()
    let state = State()
    let transport = WebSocketSurfaceTransport(
      surfaceSize: .init(width: 1, height: 1),
      sink: channel
    )
    self.channel = channel
    self.state = state
    self.transport = transport
    let controlHandler: @Sendable (WebSurfaceInputControlMessage) -> Void = { message in
      switch message {
      case .resize(let size, let cellPixelSize):
        state.recordControl()
        transport.updateSurfaceSize(size, cellPixelSize: cellPixelSize)
      case .style(let style):
        state.recordControl()
        transport.updateStyle(style)
      case .capabilities(let capabilities):
        state.recordCapabilities()
        transport.declareCapabilities(capabilities)
      case .resync(let request):
        state.recordControl()
        transport.requestResync(request)
      }
    }
    let reader = WebSocketInputReader(source: channel, controlHandler: controlHandler)
    let inputEvents = reader.inputEvents()
    inputTask = Task {
      for await _ in inputEvents {
        state.recordAcceptedInput()
      }
      state.recordInputFinished()
    }
    await attach(token: 1)
  }

  static func runActiveFixtures(
    _ corpus: HostWireConformanceCorpus
  ) async throws -> [String] {
    var executed: [String] = []
    for entry in HostWireConformanceRunnerDeclaration.swiftWebSocketChannel.requiredEntries(
      in: corpus.manifest
    ) {
      guard let fixture = corpus.fixtures[entry.file] else {
        throw HostWireConformanceError.invalid("\(entry.file): missing parsed fixture")
      }
      var runner = await Self()
      defer { runner.stop() }
      _ = try await runner.interpret(fixture, comparesExpectations: true)
      executed.append(entry.scenario)
    }
    return executed
  }

  static func observeInactiveFixture(
    _ fixture: HostWireConformanceFixture
  ) async throws -> [HostWireConformanceJSON] {
    var runner = await Self()
    defer { runner.stop() }
    return try await runner.interpret(fixture, comparesExpectations: false)
  }

  private mutating func stop() {
    inputTask?.cancel()
    for task in outputTasks { task.cancel() }
    for continuation in clients.values { continuation.finish() }
  }

  private mutating func interpret(
    _ fixture: HostWireConformanceFixture,
    comparesExpectations: Bool
  ) async throws -> [HostWireConformanceJSON] {
    guard fixture.entry.kind == .websocketChannel,
      fixture.entry.runners == [.swiftWebSocketChannel]
    else {
      throw HostWireConformanceError.invalid(
        "\(fixture.entry.file): fixture is not a WebSocket channel fixture")
    }
    var observations: [HostWireConformanceJSON] = []
    for (index, step) in fixture.steps.enumerated() {
      let context = "\(fixture.entry.file):step \(index + 1)"
      switch step {
      case .channel(let action):
        try await apply(action, context: context)
      case .emit(let raw):
        try await channel.send(Array(raw.utf8))
        if raw.hasPrefix("\u{001E}surface:"), phase == "pre-capabilities",
          let remaining = pendingCapsSends
        {
          let next = remaining - 1
          pendingCapsSends = next == 0 ? nil : next
          if next == 0 {
            capsAwaitingDrain = true
            try enqueueCapsForCurrentClient(context: context)
          }
        }
        await settle()
      case .reconnect(let capsAfter):
        guard currentToken == nil, let capsAfter else {
          throw HostWireConformanceError.invalid("\(context): invalid reconnect")
        }
        lastIssuedToken += 1
        currentToken = lastIssuedToken
        phase = "pre-capabilities"
        pendingCapsSends = capsAfter == 0 ? nil : capsAfter
        capsAwaitingDrain = capsAfter == 0
        await attach(token: lastIssuedToken)
        if capsAfter == 0 {
          try enqueueCapsForCurrentClient(context: context)
        }
      case .expect(let expected):
        await settle()
        let actual = try state.consumeObservation(
          currentToken: currentToken,
          lastIssuedToken: lastIssuedToken,
          phase: phase
        )
        observations.append(actual)
        if comparesExpectations {
          try HostWireConformanceExactComparator.requireEqual(
            actual,
            expected,
            context: context
          )
        }
      default:
        throw HostWireConformanceError.invalid(
          "\(context): channel adapter received an inapplicable step")
      }
    }
    return observations
  }

  private mutating func apply(
    _ action: HostWireConformanceJSON,
    context: String
  ) async throws {
    guard case .object(let object) = action,
      let actionValue = object["action"]
    else {
      throw HostWireConformanceError.invalid("\(context): malformed channel action")
    }
    let name = try actionValue.string(context: "\(context).action")
    switch name {
    case "closeClient":
      let token = try requiredInteger(object, "token", context: context)
      guard let client = clients[token] else {
        throw HostWireConformanceError.invalid("\(context): unknown client token")
      }
      client.yield(.normalClose)
      if token == currentToken {
        currentToken = nil
        phase = "detached"
        pendingCapsSends = nil
        capsAwaitingDrain = false
      }
      await settle()
    case "clientChunk":
      let token = try requiredInteger(object, "token", context: context)
      guard let client = clients[token], let encoded = object["bytesBase64"] else {
        throw HostWireConformanceError.invalid("\(context): unknown token or missing bytes")
      }
      let base64 = try encoded.string(context: "\(context).bytesBase64")
      guard let bytes = Data(base64Encoded: base64).map(Array.init) else {
        throw HostWireConformanceError.invalid("\(context): malformed bytesBase64")
      }
      if token == currentToken {
        state.enqueueInputCandidate(String(decoding: bytes, as: UTF8.self))
      }
      client.yield(.data(bytes))
      await settle()
    case "drainInput":
      await settle()
      if capsAwaitingDrain, state.capsProcessedCount() > 0 {
        capsAwaitingDrain = false
        phase = "active"
      }
    default:
      throw HostWireConformanceError.invalid("\(context): unsupported channel action \(name)")
    }
  }

  private mutating func attach(
    token: Int
  ) async {
    var continuation: AsyncStream<WebHostSocketMessage>.Continuation?
    let input = AsyncStream<WebHostSocketMessage> { continuation = $0 }
    clients[token] = continuation!
    let output = await channel.attach(client: input)
    let state = self.state
    outputTasks.append(
      Task {
        for await message in output {
          if case .data(let bytes) = message {
            state.recordDelivered(String(decoding: bytes, as: UTF8.self))
          }
        }
      })
    await settle()
  }

  private func enqueueCapsForCurrentClient(
    context: String
  ) throws {
    guard let token = currentToken, let client = clients[token] else {
      throw HostWireConformanceError.invalid("\(context): caps scheduler has no current client")
    }
    client.yield(.data(Array("\u{001E}caps:{\"acceptsDeltaFrames\":true}\n".utf8)))
  }

  private func settle() async {
    var previous = state.activityCount()
    var stableTurns = 0
    for _ in 0..<32 {
      await Task.yield()
      let current = state.activityCount()
      if current == previous {
        stableTurns += 1
        if stableTurns == 2 { return }
      } else {
        previous = current
        stableTurns = 0
      }
    }
  }

  private func requiredInteger(
    _ object: [String: HostWireConformanceJSON],
    _ key: String,
    context: String
  ) throws -> Int {
    guard let value = object[key] else {
      throw HostWireConformanceError.invalid("\(context): missing \(key)")
    }
    return try value.integer(context: "\(context).\(key)")
  }

  private final class State: Sendable {
    private struct Storage {
      var activityCount = 0
      var delivered: [String] = []
      var acceptedInputs: [String] = []
      var inputCandidates: [String] = []
      var discarded: [(token: Int, bytes: [UInt8], reason: String)] = []
      var refreshRequestCount = 0
      var capsProcessedCount = 0
      var ignoredStaleCallbackCount = 0
      var inputFinished = false
    }

    private let storage = Mutex(Storage())

    func activityCount() -> Int {
      storage.withLock(\.activityCount)
    }

    func recordDelivered(_ raw: String) {
      storage.withLock {
        $0.delivered.append(raw)
        $0.activityCount += 1
      }
    }

    func enqueueInputCandidate(_ raw: String) {
      guard raw.hasPrefix("\u{001E}key:") else { return }
      storage.withLock {
        $0.inputCandidates.append(raw)
        $0.activityCount += 1
      }
    }

    func recordAcceptedInput() {
      storage.withLock {
        if !$0.inputCandidates.isEmpty {
          $0.acceptedInputs.append($0.inputCandidates.removeFirst())
        }
        $0.activityCount += 1
      }
    }

    func recordControl() {
      storage.withLock {
        $0.activityCount += 1
      }
    }

    func recordCapabilities() {
      storage.withLock {
        $0.capsProcessedCount += 1
        $0.activityCount += 1
      }
    }

    func capsProcessedCount() -> Int {
      storage.withLock(\.capsProcessedCount)
    }

    func recordInputFinished() {
      storage.withLock {
        $0.inputFinished = true
        $0.activityCount += 1
      }
    }

    func consumeObservation(
      currentToken: Int?,
      lastIssuedToken: Int,
      phase: String
    ) throws -> HostWireConformanceJSON {
      let snapshot = storage.withLock { storage -> Storage in
        let snapshot = storage
        storage.delivered.removeAll(keepingCapacity: true)
        storage.acceptedInputs.removeAll(keepingCapacity: true)
        storage.discarded.removeAll(keepingCapacity: true)
        storage.refreshRequestCount = 0
        storage.capsProcessedCount = 0
        storage.ignoredStaleCallbackCount = 0
        return snapshot
      }
      let delivered = try snapshot.delivered.map {
        try HostWireConformanceRecordDecoding.conformanceJSON(
          from: HostWireConformanceRecordDecoding.channelRecord(raw: $0),
          context: "channel delivered observation"
        )
      }
      let discarded: [HostWireConformanceJSON] = snapshot.discarded.map {
        .object([
          "token": .integer($0.token),
          "bytesBase64": .string(Data($0.bytes).base64EncodedString()),
          "reason": .string($0.reason),
        ])
      }
      let parserToken = snapshot.inputFinished ? nil : currentToken
      return .object([
        "deliveredRecords": .array(delivered),
        "suppressedSurfaceRecords": .array([]),
        "detachedNonSurfaceBacklog": .object([
          "count": .integer(0),
          "bytes": .integer(0),
        ]),
        "refreshRequestCount": .integer(snapshot.refreshRequestCount),
        "capsProcessedCount": .integer(snapshot.capsProcessedCount),
        "ignoredStaleCallbackCount": .integer(snapshot.ignoredStaleCallbackCount),
        "acceptedClientInputs": .array(snapshot.acceptedInputs.map(HostWireConformanceJSON.string)),
        "discardedInboundChunks": .array(discarded),
        "parser": .object([
          "token": parserToken.map(HostWireConformanceJSON.integer) ?? .null,
          "bufferedBytes": .integer(0),
        ]),
        "connection": .object([
          "currentToken": currentToken.map(HostWireConformanceJSON.integer) ?? .null,
          "lastIssuedToken": .integer(lastIssuedToken),
          "phase": .string(phase),
          "sceneInputFinished": .bool(snapshot.inputFinished),
        ]),
      ])
    }
  }
}

private struct HostWireConformanceAdapterApp: App {
  var body: some Scene {
    WindowGroup("Conformance") {
      Text("Conformance")
    }
  }
}
