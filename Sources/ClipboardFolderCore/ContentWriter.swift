import Foundation

public enum ContentWriterError: Error, LocalizedError {
    case volumeNotAvailable
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .volumeNotAvailable: return "Volume is not available"
        case .writeFailed(let msg): return "Failed to write content: \(msg)"
        }
    }
}

public final class ContentWriter {
    public let volumePath: String
    private let fileManager: FileManager

    public init(volumePath: String, fileManager: FileManager = .default) {
        self.volumePath = volumePath
        self.fileManager = fileManager
    }

    /// Returns the list of user-visible files currently on the volume.
    public func currentFiles() -> [String] {
        (try? fileManager.contentsOfDirectory(atPath: volumePath))?
            .filter { !$0.hasPrefix(".") } ?? []
    }

    /// Total bytes used by user-visible files on the volume.
    public func usedBytes() -> Int64 {
        let files = currentFiles()
        var total: Int64 = 0
        for name in files {
            let path = (volumePath as NSString).appendingPathComponent(name)
            if let attrs = try? fileManager.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }

    /// Removes all user-visible files from the volume.
    public func clear() throws {
        guard fileManager.fileExists(atPath: volumePath) else {
            throw ContentWriterError.volumeNotAvailable
        }
        let contents = try fileManager.contentsOfDirectory(atPath: volumePath)
        for item in contents where !item.hasPrefix(".") {
            let itemURL = URL(fileURLWithPath: volumePath).appendingPathComponent(item)
            try fileManager.removeItem(at: itemURL)
        }
    }

    /// Writes image data to the volume, clearing previous content first.
    public func writeImage(_ data: Data, filename: String) throws {
        try clear()
        let url = URL(fileURLWithPath: volumePath).appendingPathComponent(filename)
        try data.write(to: url)
    }

    /// Copies files to the volume, clearing previous content first.
    public func copyFiles(_ urls: [URL]) throws {
        try clear()
        for url in urls {
            let dest = URL(fileURLWithPath: volumePath).appendingPathComponent(url.lastPathComponent)
            try fileManager.copyItem(at: url, to: dest)
        }
    }
}
