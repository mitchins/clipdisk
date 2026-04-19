import SwiftUI

public struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

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

        SettingsLink {
            Text("Settings & Info…")
        }
        .keyboardShortcut(",")

        Divider()

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
}
