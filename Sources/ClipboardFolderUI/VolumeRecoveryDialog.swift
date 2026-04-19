import AppKit
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.mitchellcurrie.ClipboardFolder", category: "VolumeRecovery")

extension Notification.Name {
    static let clipboardFolderVolumeRecoveryRemountSucceeded = Notification.Name(
        "ClipboardFolderVolumeRecoveryRemountSucceeded"
    )
}

@MainActor
final class VolumeRecoveryDialogModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case remounting
        case failed(String)
    }

    @Published var phase: Phase = .idle

    let reason: String

    private let remountAction: @Sendable () async throws -> Void
    private let quitAction: @MainActor () -> Void
    private var remountTask: Task<Void, Never>?

    var closeAction: (() -> Void)?

    init(
        reason: String,
        remountAction: @escaping @Sendable () async throws -> Void,
        quitAction: @escaping @MainActor () -> Void
    ) {
        self.reason = reason
        self.remountAction = remountAction
        self.quitAction = quitAction
    }

    var primaryButtonTitle: String {
        if case .failed = phase {
            return "Retry Remount"
        }
        return "Remount"
    }

    func remount() {
        guard remountTask == nil else { return }

        phase = .remounting

        let remountAction = self.remountAction
        remountTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try await remountAction()
                NotificationCenter.default.post(
                    name: .clipboardFolderVolumeRecoveryRemountSucceeded,
                    object: nil
                )
            } catch {
                logger.error("Recovery dialog remount task failed: \(error.localizedDescription)")
                let weakSelf = self
                await MainActor.run {
                    weakSelf?.remountTask = nil
                    weakSelf?.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    func quit() {
        remountTask?.cancel()
        remountTask = nil
        closeAction?()
        quitAction()
    }
}

struct VolumeRecoveryDialogView: View {
    @ObservedObject var model: VolumeRecoveryDialogModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: cautionIcon)
                    .resizable()
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Clipboard volume unavailable")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(subtitleText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            switch model.phase {
            case .idle:
                EmptyView()
            case .remounting:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Remounting Clipboard…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()

                Button("Quit", role: .cancel) {
                    model.quit()
                }

                Button(model.primaryButtonTitle) {
                    model.remount()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.phase == .remounting)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var cautionIcon: NSImage {
        NSImage(named: NSImage.cautionName)
            ?? NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            ?? NSImage()
    }

    private var subtitleText: String {
        let trimmedReason = model.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedReason.isEmpty {
            return "Remount the Clipboard volume to continue."
        }

        if trimmedReason.caseInsensitiveCompare("Clipboard volume unavailable.") == .orderedSame
            || trimmedReason.caseInsensitiveCompare("Clipboard volume unavailable") == .orderedSame
        {
            return "Remount the Clipboard volume to continue."
        }

        return trimmedReason
    }
}

@MainActor
final class VolumeRecoveryDialogController {
    private let panel: NSPanel
    private let model: VolumeRecoveryDialogModel
    private var didClose = false

    var onDidClose: (() -> Void)?

    init(
        reason: String,
        remountAction: @escaping @Sendable () async throws -> Void,
        quitAction: @escaping @MainActor () -> Void
    ) {
        self.model = VolumeRecoveryDialogModel(
            reason: reason,
            remountAction: remountAction,
            quitAction: quitAction
        )

        let hostingController = NSHostingController(rootView: VolumeRecoveryDialogView(model: model))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 240),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.title = ""
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.center()
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = hostingController
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        self.panel = panel
        self.model.closeAction = { [weak self] in
            self?.close()
        }
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: panel)
    }

    func close() {
        guard !didClose else { return }
        didClose = true
        NSApp.stopModal()
        panel.orderOut(nil)
        onDidClose?()
    }
}
