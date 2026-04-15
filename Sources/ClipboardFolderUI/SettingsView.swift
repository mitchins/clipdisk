import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var updater = UpdateChecker()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // App identity
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                Text("Clipboard Folder")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Version \(AppState.version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            // Update check
            VStack(spacing: 8) {
                updateStatusView
                Button("Check for Updates") {
                    updater.check(current: AppState.version)
                }
                .disabled({
                    if case .checking = updater.state { return true }
                    return false
                }())
            }
            .padding(.vertical, 14)

            Divider()

            // Settings
            Form {
                Toggle("Launch at Login", isOn: Binding(
                    get: { appState.launchAtLogin },
                    set: { _ in appState.toggleLaunchAtLogin() }
                ))
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 60)

            Divider()

            // Footer
            HStack {
                Link("View on GitHub", destination: URL(string: "https://github.com/mitchins/clipboard-fs")!)
                    .font(.footnote)
            }
            .padding(.vertical, 12)
        }
        .frame(width: 300)
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updater.state {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").font(.caption).foregroundStyle(.secondary)
            }
        case .upToDate(let version):
            Label("Up to date (\(version))", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .available(_, let latest, let url):
            VStack(spacing: 4) {
                Label("\(latest) available", systemImage: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Link("See release notes", destination: url)
                    .font(.caption)
            }
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }
}
