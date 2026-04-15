import Foundation

public enum RAMDiskError: Error, LocalizedError {
    case creationFailed(String)
    case formatFailed(String)
    case detachFailed(String)
    case alreadyMounted
    case notMounted

    public var errorDescription: String? {
        switch self {
        case .creationFailed(let msg): return "Failed to create RAM disk: \(msg)"
        case .formatFailed(let msg): return "Failed to format RAM disk: \(msg)"
        case .detachFailed(let msg): return "Failed to detach RAM disk: \(msg)"
        case .alreadyMounted: return "RAM disk is already mounted"
        case .notMounted: return "RAM disk is not mounted"
        }
    }
}

public final class RAMDiskManager {
    public let volumeName: String
    public let sizeInMB: Int
    public var mountPoint: String { "/Volumes/\(volumeName)" }
    public private(set) var devicePath: String?

    public var isMounted: Bool {
        devicePath != nil && FileManager.default.fileExists(atPath: mountPoint)
    }

    private let processExecutor: ProcessExecuting

    public init(
        volumeName: String = "Clipboard",
        sizeInMB: Int = 20,
        processExecutor: ProcessExecuting = SystemProcessExecutor()
    ) {
        self.volumeName = volumeName
        self.sizeInMB = sizeInMB
        self.processExecutor = processExecutor
    }

    /// Attempts to find and reattach to an existing RAM disk with our volume name.
    /// Returns true if an existing disk was found and adopted.
    @discardableResult
    public func recoverExistingDisk() throws -> Bool {
        let result = try processExecutor.run(
            executablePath: "/usr/bin/hdiutil",
            arguments: ["info", "-plist"]
        )
        guard result.exitCode == 0 else { return false }
        guard let device = parseHdiutilInfo(result.output) else { return false }
        self.devicePath = device
        try? setVolumeIcon()
        return true
    }

    /// Creates and mounts a new RAM disk.
    public func setup() throws {
        guard devicePath == nil else { throw RAMDiskError.alreadyMounted }

        let sectors = sizeInMB * 2048 // 512 bytes per sector

        let createResult = try processExecutor.run(
            executablePath: "/usr/bin/hdiutil",
            arguments: ["attach", "-nomount", "ram://\(sectors)"]
        )
        guard createResult.exitCode == 0 else {
            throw RAMDiskError.creationFailed(createResult.errorOutput)
        }

        let device = createResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !device.isEmpty else {
            throw RAMDiskError.creationFailed("No device path returned")
        }

        let formatResult = try processExecutor.run(
            executablePath: "/usr/sbin/diskutil",
            arguments: ["eraseDisk", "HFS+", volumeName, device]
        )
        guard formatResult.exitCode == 0 else {
            // Clean up the unformatted disk
            _ = try? processExecutor.run(
                executablePath: "/usr/bin/hdiutil",
                arguments: ["detach", device]
            )
            throw RAMDiskError.formatFailed(formatResult.errorOutput)
        }

        self.devicePath = device

        // Set custom volume icon if available
        try? setVolumeIcon()
    }

    /// Sets a custom volume icon by copying .VolumeIcon.icns and setting the custom icon bit.
    func setVolumeIcon() throws {
        // Look for bundled icon - try multiple locations for SPM executable in .app bundle
        let bundle = Bundle.main
        var iconURL: URL?
        
        // Try bundle resource first
        iconURL = bundle.url(forResource: "VolumeIcon", withExtension: "icns")
        
        // Fallback: look in ../Resources/ relative to executable (for .app bundle)
        if iconURL == nil, let execPath = bundle.executablePath {
            let resourcesPath = (execPath as NSString).deletingLastPathComponent + "/../Resources/VolumeIcon.icns"
            let resolvedURL = URL(fileURLWithPath: resourcesPath).standardizedFileURL
            if FileManager.default.fileExists(atPath: resolvedURL.path) {
                iconURL = resolvedURL
            }
        }
        
        guard let iconURL = iconURL else {
            // No custom icon bundled, skip silently
            return
        }

        let volumeIconPath = mountPoint + "/.VolumeIcon.icns"
        let volumeIconURL = URL(fileURLWithPath: volumeIconPath)
        if FileManager.default.fileExists(atPath: volumeIconURL.path) {
            try FileManager.default.removeItem(at: volumeIconURL)
        }
        try FileManager.default.copyItem(at: iconURL, to: volumeIconURL)

        // Set custom icon attribute (requires Xcode Command Line Tools)
        _ = try? processExecutor.run(
            executablePath: "/usr/bin/SetFile",
            arguments: ["-a", "C", mountPoint]
        )
        _ = try? processExecutor.run(
            executablePath: "/usr/bin/touch",
            arguments: [mountPoint]
        )
    }

    /// Detaches the RAM disk.
    public func teardown() throws {
        guard let device = devicePath else { throw RAMDiskError.notMounted }

        let result = try processExecutor.run(
            executablePath: "/usr/bin/hdiutil",
            arguments: ["detach", device]
        )
        guard result.exitCode == 0 else {
            throw RAMDiskError.detachFailed(result.errorOutput)
        }

        self.devicePath = nil
    }

    // MARK: - Internal

    /// Parses `hdiutil info -plist` output to find an existing RAM disk with our volume name.
    func parseHdiutilInfo(_ plistString: String) -> String? {
        guard let data = plistString.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, format: nil
              ) as? [String: Any],
              let images = plist["images"] as? [[String: Any]]
        else {
            return nil
        }

        for image in images {
            guard let imagePath = image["image-path"] as? String,
                  imagePath.hasPrefix("ram://")
            else { continue }

            guard let entities = image["system-entities"] as? [[String: Any]] else { continue }

            for entity in entities {
                if let mountPath = entity["mount-point"] as? String,
                   mountPath == self.mountPoint,
                   let devEntry = entity["dev-entry"] as? String {
                    return devEntry
                }
            }
        }

        return nil
    }
}
