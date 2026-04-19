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
            Image("MenuBarIcon", bundle: Self.menuBarIconBundle)
                .renderingMode(.template)
                .resizable()
                .frame(width: 18, height: 18)
                .foregroundStyle(.primary)
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }

    private static var menuBarIconBundle: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        .main
        #endif
    }
}
