import Foundation
import UniformTypeIdentifiers

/// Playlist item model.
struct PlaylistItem: Identifiable, Sendable, Equatable {
    let id = UUID()
    let url: URL
    let title: String
    var duration: Double?
    var lastPlayedTime: Double?

    init(url: URL) {
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
    }
}

/// Manages the playback playlist with navigation and ordering.
@MainActor
@Observable
final class PlaylistManager {
    var items: [PlaylistItem] = []
    var currentIndex: Int? = nil

    var currentItem: PlaylistItem? {
        guard let idx = currentIndex, items.indices.contains(idx) else { return nil }
        return items[idx]
    }

    var hasNext: Bool {
        guard let idx = currentIndex else { return !items.isEmpty }
        return idx < items.count - 1
    }

    var hasPrevious: Bool {
        guard let idx = currentIndex else { return false }
        return idx > 0
    }

    // MARK: - Modification

    func add(url: URL) {
        let item = PlaylistItem(url: url)
        items.append(item)
    }

    func add(urls: [URL]) {
        for url in urls {
            add(url: url)
        }
    }

    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        // Adjust current index
        if let idx = currentIndex {
            if offsets.contains(idx) {
                currentIndex = nil
            } else {
                currentIndex = items.firstIndex(where: { $0.id == currentItem?.id })
            }
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        // Update current index after move
        if let current = currentItem {
            currentIndex = items.firstIndex(where: { $0.id == current.id })
        }
    }

    func clear() {
        items.removeAll()
        currentIndex = nil
    }

    // MARK: - Navigation

    func next() -> URL? {
        guard hasNext else { return nil }
        let nextIdx = (currentIndex ?? -1) + 1
        currentIndex = nextIdx
        return items[nextIdx].url
    }

    func previous() -> URL? {
        guard hasPrevious, let idx = currentIndex else { return nil }
        let prevIdx = idx - 1
        currentIndex = prevIdx
        return items[prevIdx].url
    }

    func play(at index: Int) -> URL? {
        guard items.indices.contains(index) else { return nil }
        currentIndex = index
        return items[index].url
    }

    /// Makes `url` the current item. A file that is not in the playlist replaces it: the
    /// playlist is the queue being played, and a file opened on its own starts a new one.
    func setCurrent(_ url: URL) {
        if let index = items.firstIndex(where: { $0.url == url }) {
            currentIndex = index
        } else {
            replace(urls: [url])
            currentIndex = 0
        }
    }

    func updateCurrentDuration(_ duration: Double) {
        guard let idx = currentIndex, items.indices.contains(idx) else { return }
        items[idx].duration = duration
    }

    func savePlaybackPosition(_ time: Double) {
        guard let idx = currentIndex, items.indices.contains(idx) else { return }
        items[idx].lastPlayedTime = time
    }

    // MARK: - Folder Scanning

    /// Supported video file extensions
    private static let videoExtensions: Set<String> = [
        "mp4", "mkv", "avi", "mov", "m4v", "webm", "ts", "flv", "wmv",
        "mpg", "mpeg", "3gp", "ogv"
    ]

    /// Scan a folder recursively for video files and add them to the playlist.
    func add(folder url: URL) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var videoURLs: [URL] = []
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            if Self.videoExtensions.contains(ext) {
                videoURLs.append(fileURL)
            } else if let utType = UTType(filenameExtension: ext),
                      utType.conforms(to: .movie) || utType.conforms(to: .video) {
                videoURLs.append(fileURL)
            }
        }

        videoURLs.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        for url in videoURLs {
            items.append(PlaylistItem(url: url))
        }
    }

    /// Replace the entire playlist with video files from a folder.
    func replace(folder url: URL) {
        clear()
        add(folder: url)
    }

    /// Replace the entire playlist with the given URLs.
    func replace(urls: [URL]) {
        clear()
        add(urls: urls)
    }

    /// Check if a URL is a directory.
    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Check if a URL is a supported video file.
    static func isVideoFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if videoExtensions.contains(ext) { return true }
        if let utType = UTType(filenameExtension: ext),
           utType.conforms(to: .movie) || utType.conforms(to: .video) {
            return true
        }
        return false
    }

    /// Supported subtitle file extensions
    static let subtitleExtensions: Set<String> = [
        "srt", "ass", "ssa", "sub", "vtt", "idx", "sup", "lrc"
    ]

    /// Check if a URL is a subtitle file.
    static func isSubtitleFile(_ url: URL) -> Bool {
        subtitleExtensions.contains(url.pathExtension.lowercased())
    }
}
