import Foundation

struct MediaInfo {
    // File
    let filename: String
    let fileSize: Int64?
    let container: String?

    // Video
    let videoCodec: String?
    let width: Int64?
    let height: Int64?
    let fps: Double?
    let videoBitrate: Int64?
    let pixelFormat: String?

    // Audio
    let audioCodec: String?
    let audioChannels: Int64?
    let audioSampleRate: Int64?
    let audioBitrate: Int64?

    // File metadata (populated from filesystem)
    var createdAt: Date?
    var modifiedAt: Date?
}
