import AppKit
import XCTest

@testable import ClipboardFolderCore

// MARK: - Mocks

final class MockPasteboard: PasteboardReading {
    var changeCount: Int = 0
    var types: [NSPasteboard.PasteboardType]?
    private var dataStore: [NSPasteboard.PasteboardType: Data] = [:]
    private var fileURLStore: [URL] = []

    func setData(_ data: Data, forType type: NSPasteboard.PasteboardType) {
        dataStore[type] = data
    }

    func setFileURLs(_ urls: [URL]) {
        fileURLStore = urls
    }

    func data(forType type: NSPasteboard.PasteboardType) -> Data? {
        dataStore[type]
    }

    func readFileURLs() -> [URL] {
        fileURLStore
    }
}

final class MockClipboardDelegate: ClipboardMonitorDelegate {
    var detectedContent: [ClipboardContent] = []

    func clipboardMonitor(_ monitor: ClipboardMonitor, didDetect content: ClipboardContent) {
        detectedContent.append(content)
    }
}

// MARK: - Tests

final class ClipboardMonitorTests: XCTestCase {

    // MARK: - extractContent()

    func testExtractPNGImage() {
        let pasteboard = MockPasteboard()
        let pngData = createMinimalPNG()
        pasteboard.types = [.png]
        pasteboard.setData(pngData, forType: .png)

        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        let content = monitor.extractContent()

        if case .image(let data, let name) = content {
            XCTAssertEqual(data, pngData)
            XCTAssertEqual(name, "clipboard.png")
        } else {
            XCTFail("Expected image content, got \(content)")
        }
    }

    func testExtractTIFFConvertsToPNG() {
        let pasteboard = MockPasteboard()
        let tiffData = createMinimalTIFF()
        pasteboard.types = [.tiff]
        pasteboard.setData(tiffData, forType: .tiff)

        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        let content = monitor.extractContent()

        if case .image(let data, let name) = content {
            XCTAssertEqual(name, "clipboard.png")
            // Verify it's valid PNG (starts with PNG magic bytes)
            XCTAssertTrue(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        } else {
            XCTFail("Expected image content, got \(content)")
        }
    }

    func testExtractJPEG() {
        let pasteboard = MockPasteboard()
        let jpegType = NSPasteboard.PasteboardType("public.jpeg")
        let jpegData = Data("fake-jpeg".utf8)
        pasteboard.types = [jpegType]
        pasteboard.setData(jpegData, forType: jpegType)

        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        let content = monitor.extractContent()

        if case .image(let data, let name) = content {
            XCTAssertEqual(data, jpegData)
            XCTAssertEqual(name, "clipboard.jpg")
        } else {
            XCTFail("Expected image content, got \(content)")
        }
    }

    func testExtractFileURLs() {
        let pasteboard = MockPasteboard()
        let urls = [URL(fileURLWithPath: "/tmp/test.txt")]
        pasteboard.types = [.fileURL]
        pasteboard.setFileURLs(urls)

        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        let content = monitor.extractContent()

        XCTAssertEqual(content, .files(urls))
    }

    func testFilesPreferredOverImages() {
        let pasteboard = MockPasteboard()
        let urls = [URL(fileURLWithPath: "/tmp/image.png")]
        pasteboard.types = [.fileURL, .png]
        pasteboard.setFileURLs(urls)
        pasteboard.setData(createMinimalPNG(), forType: .png)

        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        let content = monitor.extractContent()

        XCTAssertEqual(content, .files(urls))
    }

    func testExtractEmptyWhenNoTypes() {
        let pasteboard = MockPasteboard()
        pasteboard.types = []

        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        XCTAssertEqual(monitor.extractContent(), .empty)
    }

    func testExtractEmptyWhenNilTypes() {
        let pasteboard = MockPasteboard()
        pasteboard.types = nil

        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        XCTAssertEqual(monitor.extractContent(), .empty)
    }

    func testExtractEmptyForTextOnlyPasteboard() {
        let pasteboard = MockPasteboard()
        pasteboard.types = [.string]
        pasteboard.setData(Data("hello".utf8), forType: .string)

        let monitor = ClipboardMonitor(pasteboard: pasteboard)
        XCTAssertEqual(monitor.extractContent(), .empty)
    }

    // MARK: - Polling

    func testPollDetectsChange() {
        let pasteboard = MockPasteboard()
        pasteboard.changeCount = 1

        let monitor = ClipboardMonitor(pasteboard: pasteboard, pollInterval: 0.1)
        let delegate = MockClipboardDelegate()
        monitor.delegate = delegate

        // Simulate clipboard change
        pasteboard.changeCount = 2
        pasteboard.types = [.png]
        pasteboard.setData(createMinimalPNG(), forType: .png)

        monitor.start()

        let expectation = expectation(description: "Poll detects change")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2)

        monitor.stop()
        XCTAssertFalse(delegate.detectedContent.isEmpty)
    }

    func testPollIgnoresSameChangeCount() {
        let pasteboard = MockPasteboard()
        pasteboard.changeCount = 5

        let monitor = ClipboardMonitor(pasteboard: pasteboard, pollInterval: 0.1)
        let delegate = MockClipboardDelegate()
        monitor.delegate = delegate

        // Don't change the count
        pasteboard.types = [.png]
        pasteboard.setData(createMinimalPNG(), forType: .png)

        monitor.start()

        let expectation = expectation(description: "No change detected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2)

        monitor.stop()
        XCTAssertTrue(delegate.detectedContent.isEmpty)
    }

    func testStopPreventsDetection() {
        let pasteboard = MockPasteboard()
        pasteboard.changeCount = 1

        let monitor = ClipboardMonitor(pasteboard: pasteboard, pollInterval: 0.1)
        let delegate = MockClipboardDelegate()
        monitor.delegate = delegate

        monitor.start()
        monitor.stop()

        // Change after stop
        pasteboard.changeCount = 2
        pasteboard.types = [.png]
        pasteboard.setData(createMinimalPNG(), forType: .png)

        let expectation = expectation(description: "No detection after stop")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2)

        XCTAssertTrue(delegate.detectedContent.isEmpty)
    }

    func testLastChangeCountUpdatesOnPoll() {
        let pasteboard = MockPasteboard()
        pasteboard.changeCount = 1

        let monitor = ClipboardMonitor(pasteboard: pasteboard, pollInterval: 0.1)
        let delegate = MockClipboardDelegate()
        monitor.delegate = delegate

        XCTAssertEqual(monitor.lastChangeCount, 1)

        pasteboard.changeCount = 3
        pasteboard.types = []

        monitor.start()

        let expectation = expectation(description: "Change count updates")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2)

        monitor.stop()
        XCTAssertEqual(monitor.lastChangeCount, 3)
    }

    // MARK: - TIFF to PNG conversion

    func testConvertTIFFtoPNG() {
        let tiffData = createMinimalTIFF()
        let pngData = ClipboardMonitor.convertTIFFtoPNG(tiffData)

        XCTAssertNotNil(pngData)
        // PNG magic bytes: 89 50 4E 47 (.PNG)
        XCTAssertTrue(pngData!.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    func testConvertInvalidTIFFReturnsNil() {
        let bogusData = Data([0x00, 0x01, 0x02, 0x03])
        let result = ClipboardMonitor.convertTIFFtoPNG(bogusData)
        XCTAssertNil(result)
    }

    func testConvertEmptyDataReturnsNil() {
        let result = ClipboardMonitor.convertTIFFtoPNG(Data())
        XCTAssertNil(result)
    }

    // MARK: - ClipboardContent equality

    func testClipboardContentEquality() {
        let data = Data("test".utf8)
        XCTAssertEqual(ClipboardContent.empty, ClipboardContent.empty)
        XCTAssertEqual(
            ClipboardContent.image(data, suggestedName: "a.png"),
            ClipboardContent.image(data, suggestedName: "a.png"))
        XCTAssertNotEqual(
            ClipboardContent.image(data, suggestedName: "a.png"),
            ClipboardContent.image(data, suggestedName: "b.png"))
        XCTAssertNotEqual(ClipboardContent.empty, ClipboardContent.image(data, suggestedName: "a.png"))

        let url = URL(fileURLWithPath: "/tmp/a")
        XCTAssertEqual(ClipboardContent.files([url]), ClipboardContent.files([url]))
        XCTAssertNotEqual(ClipboardContent.files([url]), ClipboardContent.empty)
    }

    // MARK: - Helpers

    private func createMinimalPNG() -> Data {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 1, height: 1))
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }

    private func createMinimalTIFF() -> Data {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.blue.drawSwatch(in: NSRect(x: 0, y: 0, width: 1, height: 1))
        image.unlockFocus()
        return image.tiffRepresentation!
    }
}
