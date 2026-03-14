import AppKit

public enum ClipboardContent: Equatable {
    case image(Data, suggestedName: String)
    case files([URL])
    case empty

    public static func == (lhs: ClipboardContent, rhs: ClipboardContent) -> Bool {
        switch (lhs, rhs) {
        case (.empty, .empty): return true
        case let (.image(d1, n1), .image(d2, n2)): return d1 == d2 && n1 == n2
        case let (.files(u1), .files(u2)): return u1 == u2
        default: return false
        }
    }
}

public protocol PasteboardReading: AnyObject {
    var changeCount: Int { get }
    var types: [NSPasteboard.PasteboardType]? { get }
    func data(forType type: NSPasteboard.PasteboardType) -> Data?
    func readFileURLs() -> [URL]
}

extension NSPasteboard: PasteboardReading {
    public func readFileURLs() -> [URL] {
        readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ]) as? [URL] ?? []
    }
}

public protocol ClipboardMonitorDelegate: AnyObject {
    func clipboardMonitor(_ monitor: ClipboardMonitor, didDetect content: ClipboardContent)
}

public final class ClipboardMonitor {
    public weak var delegate: ClipboardMonitorDelegate?
    public private(set) var lastChangeCount: Int
    public let pollInterval: TimeInterval

    private let pasteboard: PasteboardReading
    private var timer: Timer?

    public init(
        pasteboard: PasteboardReading = NSPasteboard.general,
        pollInterval: TimeInterval = 0.5
    ) {
        self.pasteboard = pasteboard
        self.pollInterval = pollInterval
        self.lastChangeCount = pasteboard.changeCount
    }

    public func start() {
        stop()
        timer = Timer.scheduledTimer(
            withTimeInterval: pollInterval, repeats: true
        ) { [weak self] _ in
            self?.poll()
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Checks the pasteboard and returns current content without triggering delegate.
    public func extractContent() -> ClipboardContent {
        return extractFromPasteboard()
    }

    // MARK: - Private

    private func poll() {
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        let content = extractFromPasteboard()
        delegate?.clipboardMonitor(self, didDetect: content)
    }

    private func extractFromPasteboard() -> ClipboardContent {
        guard let types = pasteboard.types, !types.isEmpty else { return .empty }

        // File URLs take priority — user explicitly copied files
        if types.contains(.fileURL) {
            let urls = pasteboard.readFileURLs()
            if !urls.isEmpty {
                return .files(urls)
            }
        }

        // PNG (use as-is)
        if types.contains(.png), let data = pasteboard.data(forType: .png) {
            return .image(data, suggestedName: "clipboard.png")
        }

        // TIFF (standard macOS image pasteboard format) → convert to PNG
        if types.contains(.tiff), let data = pasteboard.data(forType: .tiff) {
            if let pngData = Self.convertTIFFtoPNG(data) {
                return .image(pngData, suggestedName: "clipboard.png")
            }
        }

        // JPEG
        let jpegType = NSPasteboard.PasteboardType("public.jpeg")
        if types.contains(jpegType), let data = pasteboard.data(forType: jpegType) {
            return .image(data, suggestedName: "clipboard.jpg")
        }

        return .empty
    }

    /// Converts TIFF data to PNG using NSBitmapImageRep.
    static func convertTIFFtoPNG(_ tiffData: Data) -> Data? {
        guard let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
