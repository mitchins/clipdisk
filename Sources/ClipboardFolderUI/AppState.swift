import AppKit
import ClipboardFolderCore
import ServiceManagement
import SwiftUI

@MainActor
public final class AppState: ObservableObject {
    @Published public var isMounted = false
    @Published public var currentFileName: String?
    @Published public var fileCount: Int = 0
    @Published public var usedBytes: Int64 = 0
    @Published public var launchAtLogin = false
    @Published public var errorMessage: String?

    static let version: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }()

    static let build: String? = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }()

    static var versionDisplay: String {
        if version != "dev" {
            if let b = build, !b.isEmpty, b != version {
                return "\(version) (\(b))"
            } else {
                return version
            }
        } else {
            return "dev"
        }
    }

    let ramDiskManager: RAMDiskManager
    let clipboardMonitor: ClipboardMonitor
    let contentWriter: any ContentWriting

    private var terminationObserver: Any?

    public init() {
        let rdm = RAMDiskManager()
        self.ramDiskManager = rdm
        self.clipboardMonitor = ClipboardMonitor()
        self.contentWriter = ContentWriter(volumePath: rdm.mountPoint)
        self.launchAtLogin = SMAppService.mainApp.status == .enabled

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.shutdown()
            }
        }

        Task { @MainActor in
            self.startup()
        }
    }

    /// Test-only initializer — injects a `ContentWriting` stub, skips startup and system services.
    init(contentWriter: any ContentWriting) {
        self.ramDiskManager = RAMDiskManager()
        self.clipboardMonitor = ClipboardMonitor()
        self.contentWriter = contentWriter
        self.launchAtLogin = false
    }

    deinit {
        if let observer = terminationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Lifecycle

    func startup() {
        do {
            let recovered = try ramDiskManager.recoverExistingDisk()
            if !recovered {
                try ramDiskManager.setup()
            }
            isMounted = true
            refreshVolumeStats()
            if let firstFile = contentWriter.currentFiles().first {
                currentFileName = firstFile
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        clipboardMonitor.delegate = self
        clipboardMonitor.start()
    }

    func shutdown() {
        clipboardMonitor.stop()
        try? ramDiskManager.teardown()
        isMounted = false
    }

    // MARK: - Actions

    public func openInFinder() {
        guard isMounted else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: ramDiskManager.mountPoint))
    }

    public func ejectAndQuit() {
        shutdown()
        NSApplication.shared.terminate(nil)
    }

    public func clearVolume() {
        do {
            try contentWriter.clear()
            currentFileName = nil
            refreshVolumeStats()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshVolumeStats() {
        let files = contentWriter.currentFiles()
        fileCount = files.count
        usedBytes = contentWriter.usedBytes()
    }

    public func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            launchAtLogin.toggle()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Content handling

    func handleContent(_ content: ClipboardContent) {
        do {
            switch content {
            case .image(let data, let name):
                try contentWriter.writeImage(data, filename: name)
                currentFileName = name
            case .files(let urls):
                try contentWriter.copyFiles(urls)
                currentFileName = urls.first?.lastPathComponent
            case .empty:
                try contentWriter.clear()
                currentFileName = nil
            }
            errorMessage = nil
            refreshVolumeStats()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - ClipboardMonitorDelegate

extension AppState: ClipboardMonitorDelegate {
    nonisolated public func clipboardMonitor(
        _ monitor: ClipboardMonitor, didDetect content: ClipboardContent
    ) {
        Task { @MainActor in
            self.handleContent(content)
        }
    }
}

