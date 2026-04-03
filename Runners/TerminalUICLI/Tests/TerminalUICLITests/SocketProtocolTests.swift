import Foundation
import Testing

@testable import TerminalUICLI

struct SceneInfoTests {
  @Test("SceneInfo encodes to JSON")
  func encodesToJSON() throws {
    let info = SceneInfo(
      id: "dashboard",
      title: "Dashboard",
      ptyPath: "/dev/pts/4",
      isAttached: false
    )
    let data = try JSONEncoder().encode(info)
    let decoded = try JSONDecoder().decode(SceneInfo.self, from: data)
    #expect(decoded.id == "dashboard")
    #expect(decoded.title == "Dashboard")
    #expect(decoded.ptyPath == "/dev/pts/4")
    #expect(decoded.isAttached == false)
  }

  @Test("Primary scene has no pty path")
  func primarySceneNoPtyPath() throws {
    let info = SceneInfo(
      id: "main",
      title: "Main",
      ptyPath: nil,
      isAttached: true
    )
    let data = try JSONEncoder().encode(info)
    let decoded = try JSONDecoder().decode(SceneInfo.self, from: data)
    #expect(decoded.ptyPath == nil)
  }
}

struct SocketProtocolTests {
  @Test("Parse LIST request")
  func parseListRequest() throws {
    let request = try SocketRequest.parse("LIST\n")
    #expect(request == .list)
  }

  @Test("Parse ATTACH request")
  func parseAttachRequest() throws {
    let request = try SocketRequest.parse("ATTACH dashboard\n")
    #expect(request == .attach(sceneID: "dashboard"))
  }

  @Test("Invalid request throws error")
  func invalidRequest() {
    #expect(throws: SocketProtocolError.self) {
      try SocketRequest.parse("BOGUS\n")
    }
  }

  @Test("Format LIST response")
  func formatListResponse() throws {
    let scenes = [
      SceneInfo(id: "main", title: "Main", ptyPath: nil, isAttached: true),
      SceneInfo(id: "dashboard", title: nil, ptyPath: "/dev/pts/4", isAttached: false),
    ]
    let response = SocketResponse.sceneList(scenes)
    let encoded = try response.encode()
    #expect(encoded.hasPrefix("OK "))
    #expect(encoded.contains("\"main\""))
    #expect(encoded.contains("\"dashboard\""))
  }

  @Test("Format ATTACH success response")
  func formatAttachSuccess() throws {
    let response = SocketResponse.attachOK(ptyPath: "/dev/pts/4")
    let encoded = try response.encode()
    #expect(encoded == "OK /dev/pts/4\n")
  }

  @Test("Format error response")
  func formatErrorResponse() throws {
    let response = SocketResponse.error("scene not found")
    let encoded = try response.encode()
    #expect(encoded == "ERR scene not found\n")
  }
}
