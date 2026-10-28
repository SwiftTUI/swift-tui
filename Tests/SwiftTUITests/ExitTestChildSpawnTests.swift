import Testing

/// The exit-test child spawn works wherever the suite runs, the sanitizer
/// lane included. `#expect(processExitsWith:)` re-spawns the test host, and
/// on Darwin a sanitizer runtime must be loaded at launch: SwiftPM preloads
/// it for the host, but that preload does not survive into the host's
/// environment, so the child loaded the runtime too late and aborted
/// ("Interceptors are not working"). `Scripts/run_sanitizer_lane.sh` hands
/// the runtime to Swift Testing's child through `XCTestBundleInjectPath`,
/// which Swift Testing turns into the child's `DYLD_INSERT_LIBRARIES`. An
/// empty body isolates the spawn itself from any subject under test.
@Suite("Exit-test child spawn")
struct ExitTestChildSpawnTests {
  @Test("an empty exit-test body exits successfully")
  func emptyBodyExitsSuccessfully() async {
    await #expect(processExitsWith: .success) {}
  }
}
