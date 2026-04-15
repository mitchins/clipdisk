import SwiftUI

public struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        if let fileName = appState.currentFileName {
            Text(fileName)
                .font(.caption)
            Divider()
        }

        if let error = appState.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
            Divider()
        }

        Button("Open in Finder") {
            appState.openInFinder()
        }
        .disabled(!appState.isMounted)
        .keyboardShortcut("o")

        if appState.fileCount > 0 {
            Button(clearLabel) {
                appState.clearVolume()
            }
        }

        Divider()

        Toggle("Launch at Login", isOn: Binding(
            get: { appState.launchAtLogin },
            set: { _ in appState.toggleLaunchAtLogin() }
        ))

        Divider()

        Button("Settings…") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        }
        .keyboardShortcut(",")

        Button("About Clipboard Folder") {
            showAbout()
        }

        Button("Eject & Quit") {
            appState.ejectAndQuit()
        }
        .keyboardShortcut("q")
    }

    private var clearLabel: String {
        let count = appState.fileCount
        let size = ByteCountFormatter.string(fromByteCount: appState.usedBytes, countStyle: .file)
        return "Clear \(count) item\(count == 1 ? "" : "s") (\(size))"
    }

    private func showAbout() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Clipboard Folder"
        alert.informativeText = """
            Version \(AppState.version)

            Clipboard contents on a RAM disk.
            https://github.com/mitchins/clipboard-fs
            """
        alert.alertStyle = .informational
        alert.runModal()
    }
}
