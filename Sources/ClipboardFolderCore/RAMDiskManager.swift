import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mitchellcurrie.ClipboardFolder", category: "RAMDisk")

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
    private enum CommandTimeouts {
        static let recovery: TimeInterval = 10
        static let creation: TimeInterval = 15
        static let formatting: TimeInterval = 20
        static let teardown: TimeInterval = 10
        static let utility: TimeInterval = 5
    }

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

    /// Clears any cached device path before mounting a fresh volume.
    public func setupFresh() throws {
        devicePath = nil
        try setup()
    }

    /// Waits briefly for the mounted volume to become visible in /Volumes.
    public func waitForMount(timeout: TimeInterval = 3.0, pollInterval: TimeInterval = 0.1) -> Bool {
        guard timeout > 0 else { return isMounted }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isMounted {
                return true
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }

        return isMounted
    }

    /// Attempts to find and reattach to an existing RAM disk with our volume name.
    /// Returns true if an existing disk was found and adopted.
    @discardableResult
    public func recoverExistingDisk() throws -> Bool {
        let result = try runCommand(
            stage: "recover volume",
            executablePath: "/usr/bin/hdiutil",
            arguments: ["info", "-plist"],
            timeout: CommandTimeouts.recovery
        )
        guard result.exitCode == 0 else {
            devicePath = nil
            return false
        }
        guard let device = parseHdiutilInfo(result.output) else {
            devicePath = nil
            return false
        }
        self.devicePath = device
        logger.info("Recovered clipboard volume at \(device)")
        try? setVolumeIcon()
        try? seedFinderTemplateIfAvailable()
        return true
    }

    /// Creates and mounts a new RAM disk.
    public func setup() throws {
        guard devicePath == nil else { throw RAMDiskError.alreadyMounted }

        let sectors = sizeInMB * 2048 // 512 bytes per sector

        let createResult: ProcessResult
        do {
            createResult = try runCommand(
                stage: "create ram disk",
                executablePath: "/usr/bin/hdiutil",
                arguments: ["attach", "-nomount", "ram://\(sectors)"],
                timeout: CommandTimeouts.creation
            )
        } catch {
            throw RAMDiskError.creationFailed(error.localizedDescription)
        }
        guard createResult.exitCode == 0 else {
            throw RAMDiskError.creationFailed(createResult.errorOutput)
        }

        let device = createResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !device.isEmpty else {
            throw RAMDiskError.creationFailed("No device path returned")
        }

        let formatResult: ProcessResult
        do {
            formatResult = try runCommand(
                stage: "format ram disk",
                executablePath: "/usr/sbin/diskutil",
                arguments: ["eraseDisk", "HFS+", volumeName, device],
                timeout: CommandTimeouts.formatting
            )
        } catch {
            _ = try? processExecutor.run(
                executablePath: "/usr/bin/hdiutil",
                arguments: ["detach", device],
                timeout: CommandTimeouts.teardown
            )
            throw RAMDiskError.formatFailed(error.localizedDescription)
        }
        guard formatResult.exitCode == 0 else {
            // Clean up the unformatted disk
            _ = try? processExecutor.run(
                executablePath: "/usr/bin/hdiutil",
                arguments: ["detach", device],
                timeout: CommandTimeouts.teardown
            )
            throw RAMDiskError.formatFailed(formatResult.errorOutput)
        }

        self.devicePath = device
        logger.info("Mounted new clipboard volume at \(device)")

        // Set custom volume icon if available
        try? setVolumeIcon()
        try? seedFinderTemplateIfAvailable()
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
            arguments: ["-a", "C", mountPoint],
            timeout: CommandTimeouts.utility
        )
        _ = try? processExecutor.run(
            executablePath: "/usr/bin/touch",
            arguments: [mountPoint],
            timeout: CommandTimeouts.utility
        )
    }

    /// Copies optional Finder template files (`.DS_Store` and `.background/`) to the mounted volume.
    /// This allows DMG-style window background/layout customization for the RAM disk in Finder.
    func seedFinderTemplateIfAvailable() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: mountPoint) else { return }
        guard let templateDir = finderTemplateDirectoryURL() else { return }

        let dsStoreURL = templateDir.appendingPathComponent(".DS_Store")
        let backgroundURL = templateDir.appendingPathComponent(".background", isDirectory: true)
        let mountURL = URL(fileURLWithPath: mountPoint, isDirectory: true)

        if fileManager.fileExists(atPath: backgroundURL.path) {
            let targetBackgroundURL = mountURL.appendingPathComponent(".background", isDirectory: true)
            if fileManager.fileExists(atPath: targetBackgroundURL.path) {
                try fileManager.removeItem(at: targetBackgroundURL)
            }
            try fileManager.copyItem(at: backgroundURL, to: targetBackgroundURL)
        }

        if fileManager.fileExists(atPath: dsStoreURL.path) {
            let targetDSStoreURL = mountURL.appendingPathComponent(".DS_Store")
            if fileManager.fileExists(atPath: targetDSStoreURL.path) {
                try fileManager.removeItem(at: targetDSStoreURL)
            }
            try fileManager.copyItem(at: dsStoreURL, to: targetDSStoreURL)
            _ = try? processExecutor.run(
                executablePath: "/usr/bin/touch",
                arguments: [mountPoint],
                timeout: CommandTimeouts.utility
            )
        }

        seedReadme(in: mountURL)
    }

    /// Writes a plain-text README to the volume root so the folder is self-explanatory
    /// when empty. The file disappears naturally the first time clipboard content is written.
    private func seedReadme(in mountURL: URL) {
        let readmeURL = mountURL.appendingPathComponent("README.txt")
        guard !FileManager.default.fileExists(atPath: readmeURL.path) else { return }
        let text = """
            Clipboard  —  ClipboardFolder
            ==============================
            This folder is your live clipboard.

            Anything you copy — text, images, links, or files — appears here
            automatically and can be opened, dragged, or shared like any file.

            Contents are stored in RAM and clear when you restart.
            """
        try? text.write(to: readmeURL, atomically: true, encoding: .utf8)
    }

    /// Finds bundled `FinderTemplate` resources for .app or local dev execution.
    func finderTemplateDirectoryURL() -> URL? {
        let bundle = Bundle.main

        if let templateURL = bundle.url(forResource: "FinderTemplate", withExtension: nil),
           FileManager.default.fileExists(atPath: templateURL.path) {
            return templateURL
        }

        if let execPath = bundle.executablePath {
            let resourcesPath = (execPath as NSString).deletingLastPathComponent
                + "/../Resources/FinderTemplate"
            let resolvedURL = URL(fileURLWithPath: resourcesPath).standardizedFileURL
            if FileManager.default.fileExists(atPath: resolvedURL.path) {
                return resolvedURL
            }
        }

        return nil
    }

    /// Detaches the RAM disk.
    public func teardown() throws {
        guard let device = devicePath else { throw RAMDiskError.notMounted }

        let result: ProcessResult
        do {
            result = try runCommand(
                stage: "detach clipboard volume",
                executablePath: "/usr/bin/hdiutil",
                arguments: ["detach", device],
                timeout: CommandTimeouts.teardown
            )
        } catch {
            throw RAMDiskError.detachFailed(error.localizedDescription)
        }
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

private extension RAMDiskManager {
    func runCommand(
        stage: String,
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> ProcessResult {
        do {
            let result = try processExecutor.run(
                executablePath: executablePath,
                arguments: arguments,
                timeout: timeout
            )

            if result.exitCode != 0 {
                logger.warning("\(stage) exited with \(result.exitCode): \(result.errorOutput)")
            }

            return result
        } catch {
            logger.error("\(stage) failed: \(error.localizedDescription)")
            throw error
        }
    }
}
