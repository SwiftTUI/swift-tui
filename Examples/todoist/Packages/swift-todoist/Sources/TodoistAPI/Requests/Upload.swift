import Foundation

public enum UploadFileSource {
  case path(String)
  case data(Data)
  case stream(InputStream)
}

public struct UploadFileArgs {
  public let file: UploadFileSource
  public let fileName: String?
  public let projectId: String?

  public init(file: UploadFileSource, fileName: String? = nil, projectId: String? = nil) {
    self.file = file
    self.fileName = fileName
    self.projectId = projectId
  }
}

public struct DeleteUploadArgs {
  public let fileUrl: String
}

public enum MultipartEncodingError: Error {
  case missingFileName
  case invalidPath
}

internal struct MultipartPart {
  let fieldName: String
  let fileName: String?
  let data: Data
  let contentType: String
}

public func uploadMultipartFile(
  fileSource: UploadFileSource,
  fileName: String?,
  filePath: String?,
) throws -> (data: Data, fileName: String, mimeType: String?) {
  switch fileSource {
  case .path(let path):
    let url = URL(fileURLWithPath: path)
    let resolvedName = fileName ?? url.lastPathComponent
    guard let sourceData = try? Data(contentsOf: url) else {
      throw MultipartEncodingError.invalidPath
    }
    return (sourceData, resolvedName, nil)
  case .data(let data):
    guard let sourceName = fileName else {
      throw MultipartEncodingError.missingFileName
    }
    return (data, sourceName, nil)
  case .stream(let stream):
    guard let sourceName = fileName else {
      throw MultipartEncodingError.missingFileName
    }

    stream.open()
    defer { stream.close() }

    let chunkSize = 16 * 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
    defer { buffer.deallocate() }

    var data = Data()
    while stream.hasBytesAvailable {
      let read = stream.read(buffer, maxLength: chunkSize)
      if read < 0 {
        throw stream.streamError ?? MultipartEncodingError.invalidPath
      }
      if read == 0 {
        break
      }
      data.append(buffer, count: read)
    }

    return (data, sourceName, nil)
  }
}
