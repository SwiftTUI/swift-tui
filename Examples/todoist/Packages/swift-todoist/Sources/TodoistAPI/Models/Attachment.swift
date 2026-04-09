import Foundation

public struct Attachment: Codable, Sendable {
  public let resourceType: String
  public let fileName: String?
  public let fileSize: Int?
  public let fileType: String?
  public let fileUrl: String?
  public let fileDuration: Int?
  public let uploadState: String?
  public let image: String?
  public let imageWidth: Int?
  public let imageHeight: Int?
  public let url: String?
  public let title: String?

  public init(
    resourceType: String,
    fileName: String? = nil,
    fileSize: Int? = nil,
    fileType: String? = nil,
    fileUrl: String? = nil,
    fileDuration: Int? = nil,
    uploadState: String? = nil,
    image: String? = nil,
    imageWidth: Int? = nil,
    imageHeight: Int? = nil,
    url: String? = nil,
    title: String? = nil,
  ) {
    self.resourceType = resourceType
    self.fileName = fileName
    self.fileSize = fileSize
    self.fileType = fileType
    self.fileUrl = fileUrl
    self.fileDuration = fileDuration
    self.uploadState = uploadState
    self.image = image
    self.imageWidth = imageWidth
    self.imageHeight = imageHeight
    self.url = url
    self.title = title
  }
}
