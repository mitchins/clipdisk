import ClipboardFolderUI
import SwiftUI

@main
struct ClipboardFolderApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            if let img = NSImage(named: "MenuBarIcon")
                        ?? Bundle.main.image(forResource: "MenuBarIcon") {
                Image(nsImage: img)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "doc.on.clipboard")
            }
        }

        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
