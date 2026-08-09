import Foundation
@_spi(Runners) import SwiftTUIRuntime
@_spi(Testing) import SwiftTUITestSupport
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

/// Drives the real `WebHostSceneChannel`, `WebSocketInputReader`, and
/// `WebSocketSurfaceTransport` for `kind: "websocket-channel"` fixtures.
///
/// Every observation comes from live channel or reader state. The one piece of
/// harness machinery is the gated source: the fixture must be able to withhold
/// `drainInput` so bytes stay queued across a reconnect, which is exactly the
/// case that decides whether a chunk is stale at ingress or at consumption.
/// The reader itself is unmodified production code — it sees the channel's real
/// tagged events, in order.
struct HostWireConformanceWebSocketChannelRunner {
  private let channel: WebHostSceneChannel
  private let transport: WebSocketSurfaceTransport
  private let reader: WebSocketInputReader
  private let gate: GatedInboundSource
  private let state: State
  private var clients: [Int: AsyncStream<WebHostSocketMessage>.Continuation] = [:]
  private var outputTasks: [Task<Void, Never>] = []
  private var pendingCapsSends: Int?

  /// The capability declaration every client in this harness opens with.
  ///
  /// Byte-identical to the fixture's own caps chunk, which is exactly why the
  /// bootstrap send below must not be allowed to leak past `init`: a stray
  /// bootstrap event is indistinguishable, by content, from a fixture one.
  private static let capsRecordBytes = Array(
    "\u{001E}caps:{\"acceptsDeltaFrames\":true}\n".utf8)

  private init() async throws {
    let channel = WebHostSceneChannel()
    let state = State()
    let transport = WebSocketSurfaceTransport(
      surfaceSize: .init(width: 1, height: 1),
      sink: channel
    )
    let gate = GatedInboundSource(channel: channel)
    gate.start()
    self.channel = channel
    self.state = state
    self.transport = transport
    self.gate = gate
    let hooks = WebSocketInputReaderTestHooks(
      parserStateDidChange: { token, bufferedBytes in
        gate.recordParserState(token: token, bufferedBytes: bufferedBytes)
      }
    )
    reader = WebSocketInputReader(source: gate, hooks: hooks) { message, token in
      switch message {
      case .resize(let size, let cellPixelSize):
        transport.updateSurfaceSize(size, cellPixelSize: cellPixelSize)
      case .style(let style):
        transport.updateStyle(style)
      case .pointerCapabilities(let supportsScrollPanning):
        transport.updatePointerCapabilities(
          supportsScrollPanning: supportsScrollPanning
        )
      case .capabilities(let capabilities):
        await channel.applyCapabilities(
          token: token,
          reanchor: { transport.declareCapabilities(capabilities) },
          requestRefresh: { transport.requestSurfaceRefresh() }
        )
      case .resync(let request):
        transport.requestResync(request)
      }
    }
    // The runner starts active on token 1 with its initial capability
    // declaration already processed, an empty backlog, and empty observation
    // logs — the fixture's first `closeClient` therefore names a live token 1.
    await attach(token: 1)
    try await sendToCurrentClient(Self.capsRecordBytes, context: "runner bootstrap")
    await drainReader()
    _ = await channel.consumeObservations()
    state.reset()
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
      var runner = try await Self()
      defer { runner.stop() }
      _ = try await runner.interpret(fixture, comparesExpectations: true)
      executed.append(entry.scenario)
    }
    return executed
  }

  static func observeInactiveFixture(
    _ fixture: HostWireConformanceFixture
  ) async throws -> [HostWireConformanceJSON] {
    var runner = try await Self()
    defer { runner.stop() }
    return try await runner.interpret(fixture, comparesExpectations: false)
  }

  private mutating func stop() {
    gate.stop()
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
        await settle()
        if raw.hasPrefix("\u{001E}surface:"), let remaining = pendingCapsSends {
          let next = remaining - 1
          pendingCapsSends = next == 0 ? nil : next
          if next == 0 {
            try await sendToCurrentClient(Self.capsRecordBytes, context: context)
          }
        }
      case .reconnect(let capsAfter):
        guard await channel.currentConnectionToken() == nil, let capsAfter else {
          throw HostWireConformanceError.invalid("\(context): invalid reconnect")
        }
        let token = await nextToken()
        await attach(token: token)
        pendingCapsSends = capsAfter == 0 ? nil : capsAfter
        if capsAfter == 0 {
          try await sendToCurrentClient(Self.capsRecordBytes, context: context)
        }
      case .expect(let expected):
        await settle()
        let actual = try await consumeObservation()
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
      // Routed through the real receive path: only the channel decides whether
      // this close detaches or is an ignored stale callback.
      await deliverToChannel { client.yield(.normalClose) }
    case "clientChunk":
      let token = try requiredInteger(object, "token", context: context)
      guard let client = clients[token], let encoded = object["bytesBase64"] else {
        throw HostWireConformanceError.invalid("\(context): unknown token or missing bytes")
      }
      let base64 = try encoded.string(context: "\(context).bytesBase64")
      guard let bytes = Data(base64Encoded: base64).map(Array.init) else {
        throw HostWireConformanceError.invalid("\(context): malformed bytesBase64")
      }
      await deliverToChannel { client.yield(.data(bytes)) }
    case "drainInput":
      await drainReader()
    default:
      throw HostWireConformanceError.invalid("\(context): unsupported channel action \(name)")
    }
  }

  /// Performs a client-side yield and returns once the channel has handled it.
  ///
  /// Signal-based, not turn-based: the message crosses a real receive task, and
  /// a turn budget makes the fixture pass or fail on machine load rather than on
  /// behavior. Because every client yield in this runner waits here, at most one
  /// client message is ever in flight — which is what lets `drainReader` know it
  /// has seen everything the fixture produced.
  private func deliverToChannel(
    _ yieldMessage: () -> Void
  ) async {
    let before = await channel.processedInboundCallbackCount()
    yieldMessage()
    await channel.waitForProcessedInboundCallbacks(atLeast: before + 1)
    await settle()
  }

  private func nextToken() async -> Int {
    Int(await channel.lastIssuedConnectionToken()) + 1
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

  /// Sends bytes on the newest client and returns once the channel has handled
  /// them.
  ///
  /// Every client-side yield in this runner goes through here or through
  /// `apply`'s `deliverToChannel` calls, so at most one client message is ever
  /// in flight. That is what makes `drainReader`'s termination exact: an event
  /// the channel has not yielded yet is invisible to `GatedInboundSource.take`,
  /// so a message still queued in a receive task ends the drain early and its
  /// events land in the *next* observation interval.
  private func sendToCurrentClient(
    _ bytes: [UInt8],
    context: String
  ) async throws {
    guard let token = clients.keys.max(), let client = clients[token] else {
      throw HostWireConformanceError.invalid("\(context): no current client")
    }
    await deliverToChannel { client.yield(.data(bytes)) }
  }

  /// Advances the real reader over every queued tagged event to quiescence,
  /// then records the input events that drain produced.
  ///
  /// The sink is created *and finished* inside one drain on purpose. A
  /// long-lived stream drained by a background task left an unconditioned hop
  /// between "the reader yielded an input" and "the adapter observed it": under
  /// load the observation interval closed first and the input went missing
  /// (`acceptedClientInputs[0]: <absent>`). Finishing the continuation here
  /// makes the loop below terminate on the buffered elements, so the accepted
  /// inputs are complete by construction rather than by turn budget.
  private func drainReader() async {
    var continuation: AsyncStream<InputEvent>.Continuation?
    let events = AsyncStream<InputEvent> { continuation = $0 }
    guard let continuation else { return }
    while let event = await gate.take() {
      await reader.process(event, yielding: continuation)
      await settle()
    }
    continuation.finish()
    for await event in events {
      state.recordAcceptedInput(event)
    }
  }

  /// Waits until the adapter's delivery task has observed every data record the
  /// channel has yielded.
  ///
  /// Replaces a "the activity counter looked stable for two turns" guess. That
  /// guess reported an empty interval whenever the delivery task had simply not
  /// been scheduled yet, which is how a delivered record went missing from the
  /// observation (`deliveredRecords[1]: <absent>`) under load.
  private func settle() async {
    await state.waitForDeliveredRecords(
      atLeast: await channel.yieldedOutputRecordCount())
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

  private func consumeObservation() async throws -> HostWireConformanceJSON {
    let channelObservations = await channel.consumeObservations()
    let adapterObservations = state.consume()
    let delivered = try adapterObservations.delivered.map {
      try HostWireConformanceRecordDecoding.conformanceJSON(
        from: HostWireConformanceRecordDecoding.channelRecord(raw: $0),
        context: "channel delivered observation"
      )
    }
    let suppressed = try channelObservations.suppressedSurfaceRecords.map {
      try HostWireConformanceRecordDecoding.conformanceJSON(
        from: HostWireConformanceRecordDecoding.channelRecord(
          raw: String(decoding: $0, as: UTF8.self)),
        context: "channel suppressed observation"
      )
    }
    let discarded: [HostWireConformanceJSON] = channelObservations.discardedInboundChunks.map {
      .object([
        "token": .integer(Int($0.token)),
        "bytesBase64": .string(Data($0.bytes).base64EncodedString()),
        "reason": .string($0.reason.rawValue),
      ])
    }
    let parser = await gate.parserObservation()
    return .object([
      "deliveredRecords": .array(delivered),
      "suppressedSurfaceRecords": .array(suppressed),
      "detachedNonSurfaceBacklog": .object([
        "count": .integer(channelObservations.detachedNonSurfaceBacklogCount),
        "bytes": .integer(channelObservations.detachedNonSurfaceBacklogBytes),
      ]),
      "refreshRequestCount": .integer(channelObservations.refreshRequestCount),
      "capsProcessedCount": .integer(channelObservations.capsProcessedCount),
      "ignoredStaleCallbackCount": .integer(channelObservations.ignoredStaleCallbackCount),
      "acceptedClientInputs": .array(
        adapterObservations.acceptedInputs.map(HostWireConformanceJSON.string)),
      "discardedInboundChunks": .array(discarded),
      "parser": .object([
        "token": parser.token.map(HostWireConformanceJSON.integer) ?? .null,
        "bufferedBytes": .integer(parser.bufferedBytes),
      ]),
      "connection": .object([
        "currentToken": channelObservations.currentToken.map {
          HostWireConformanceJSON.integer(Int($0))
        } ?? .null,
        "lastIssuedToken": .integer(Int(channelObservations.lastIssuedToken)),
        "phase": .string(channelObservations.phase.rawValue),
        "sceneInputFinished": .bool(channelObservations.sceneInputFinished),
      ]),
    ])
  }

  /// Buffers the channel's real tagged events so a fixture can withhold
  /// `drainInput`, and records the reader's parser observations.
  private final class GatedInboundSource: WebHostByteSource, Sendable {
    private struct Storage {
      var queued: [WebHostInboundEvent] = []
      /// How many events this gate has pumped off the channel stream, so an
      /// in-flight event is distinguishable from no event.
      var pumpedEvents: UInt64 = 0
      var parserToken: Int?
      var parserBufferedBytes = 0
    }

    private let channel: WebHostSceneChannel
    private let storage = Mutex(Storage())
    private let pumpTask = Mutex<Task<Void, Never>?>(nil)
    private let arrivals = ConditionSignal()

    init(channel: WebHostSceneChannel) {
      self.channel = channel
    }

    /// Begins buffering the channel's tagged events. Separate from `init` so
    /// the pump task captures the finished gate rather than a `Mutex`, which is
    /// noncopyable and cannot cross into an escaping closure.
    func start() {
      let events = channel.inboundEvents()
      pumpTask.withLock { task in
        task = Task { [self] in
          for await event in events {
            enqueue(event)
          }
        }
      }
    }

    func stop() {
      pumpTask.withLock { task in
        task?.cancel()
        task = nil
      }
    }

    private func enqueue(
      _ event: WebHostInboundEvent
    ) {
      storage.withLock { storage in
        storage.queued.append(event)
        storage.pumpedEvents += 1
      }
      // Outside the lock the predicate itself takes, per `ConditionSignal`.
      arrivals.notify()
    }

    /// The next buffered event, waiting while the channel has yielded one this
    /// gate has not pumped yet.
    ///
    /// Without that condition the drain can outrun its own pump: `take()`
    /// returns nil for an event still in flight, the drain concludes early, and
    /// the reader consumes the leftovers on a later drain — in the wrong
    /// interval. The org gate caught exactly that under full-suite load.
    func take() async -> WebHostInboundEvent? {
      if let queued = dequeue() {
        return queued
      }
      // Every producer has already been waited on by `deliverToChannel`, so the
      // channel's yield count is a *settled* target rather than a moving one:
      // once the pump has caught up to it, an empty queue really does mean the
      // drain is complete. Resumed by `enqueue`, never by a clock — a turn
      // budget here expired while the pump task had not run once, which silently
      // ended the drain and spilled its events into the next interval.
      let target = await channel.yieldedInboundEventCount()
      await arrivals.wait { [self] in
        storage.withLock { !$0.queued.isEmpty || $0.pumpedEvents >= target }
      }
      return dequeue()
    }

    private func dequeue() -> WebHostInboundEvent? {
      storage.withLock { storage in
        storage.queued.isEmpty ? nil : storage.queued.removeFirst()
      }
    }

    func recordParserState(
      token: UInt64?,
      bufferedBytes: Int
    ) {
      storage.withLock { storage in
        storage.parserToken = token.map(Int.init)
        storage.parserBufferedBytes = bufferedBytes
      }
    }

    func parserObservation() async -> (token: Int?, bufferedBytes: Int) {
      storage.withLock { ($0.parserToken, $0.parserBufferedBytes) }
    }

    func inboundEvents() -> AsyncStream<WebHostInboundEvent> {
      // The reader is stepped explicitly through `process`, so this stream is
      // never consumed; returning an empty one keeps the protocol honest.
      AsyncStream { $0.finish() }
    }

    func currentConnectionToken() async -> UInt64? {
      await channel.currentConnectionToken()
    }

    func recordDiscardedInboundChunk(
      _ chunk: WebHostDiscardedInboundChunk
    ) async {
      await channel.recordDiscardedInboundChunk(chunk)
    }
  }

  private final class State: Sendable {
    private struct Storage {
      /// Monotonic across `consume()`, unlike `delivered`: it is compared
      /// against the channel's equally monotonic yield gauge.
      var deliveredTotal: UInt64 = 0
      var delivered: [String] = []
      var acceptedInputs: [String] = []
    }

    private let storage = Mutex(Storage())
    private let deliveries = ConditionSignal()

    /// Suspends until the delivery task has recorded `target` data records.
    ///
    /// The channel's yield gauge is the target, so this closes the last hop of
    /// the seam: a record the channel has yielded is never reported as absent
    /// merely because the task carrying it has not been scheduled yet.
    func waitForDeliveredRecords(atLeast target: UInt64) async {
      await deliveries.wait { [self] in
        storage.withLock(\.deliveredTotal) >= target
      }
    }

    func recordDelivered(_ raw: String) {
      storage.withLock {
        $0.delivered.append(raw)
        $0.deliveredTotal += 1
      }
      // Outside the lock the predicate itself takes, per `ConditionSignal`.
      deliveries.notify()
    }

    /// Records an accepted input event as the wire record it must have come
    /// from. Derived from the event itself rather than paired against a
    /// submission, so a stale chunk that was never parsed cannot be
    /// misattributed to a later accepted one.
    func recordAcceptedInput(_ event: InputEvent) {
      storage.withLock {
        $0.acceptedInputs.append(Self.record(for: event))
      }
    }

    private static func record(
      for event: InputEvent
    ) -> String {
      switch event {
      case .key(let press):
        switch press.key {
        case .character(let character):
          return "\u{001E}key:character:\(percentEncoded(character)):\(press.modifiers.rawValue)\n"
        default:
          return "\u{001E}key:\(press.key):\(press.modifiers.rawValue)\n"
        }
      case .paste(let paste):
        return "\u{001E}paste:\(paste.content)\n"
      case .mouse, .drop:
        return "\u{001E}unsupported-observation\n"
      }
    }

    private static func percentEncoded(
      _ character: Character
    ) -> String {
      let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
      guard !unreserved.contains(character) else {
        return String(character)
      }
      // Hand-rolled rather than `String(format:)`: that is a variadic C-interop
      // call, which strict memory safety treats as `unsafe` on Darwin but not
      // under swift-corelibs-foundation. Neither spelling of the `unsafe`
      // marker compiles on both platforms — with it, Linux rejects the
      // expression as having no unsafe operations; without it, Darwin demands
      // one. The stdlib radix conversion sidesteps the divergence entirely.
      return String(character).utf8
        .map { byte in
          let hex = String(byte, radix: 16, uppercase: true)
          return byte < 0x10 ? "%0\(hex)" : "%\(hex)"
        }
        .joined()
    }

    func reset() {
      storage.withLock {
        $0.delivered.removeAll()
        $0.acceptedInputs.removeAll()
      }
    }

    func consume() -> (delivered: [String], acceptedInputs: [String]) {
      storage.withLock { storage in
        let snapshot = (storage.delivered, storage.acceptedInputs)
        storage.delivered.removeAll(keepingCapacity: true)
        storage.acceptedInputs.removeAll(keepingCapacity: true)
        return snapshot
      }
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
