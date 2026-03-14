import AppKit
import XCTest

@testable import ClipboardFolderCore

/// Integration tests that create real RAM disks.
/// These tests are safe — RAM is reclaimed immediately after detach.
/// Each test uses a unique volume name to avoid conflicts.
final class RAMDiskIntegrationTests: XCTestCase {

    private var manager: RAMDiskManager!
    private var testVolumeName: String!

    override func setUp() {
        super.setUp()
        testVolumeName = "CBTest\(Int.random(in: 10000...99999))"
        manager = RAMDiskManager(volumeName: testVolumeName, sizeInMB: 2)
    }

    override func tearDown() {
        // Always attempt cleanup, even on test failure
        try? manager.teardown()
        // Small delay for filesystem sync
        Thread.sleep(forTimeInterval: 0.3)
        super.tearDown()
    }

    // MARK: - RAM Disk Lifecycle

    func testCreateAndTeardown() throws {
        try manager.setup()

        XCTAssertNotNil(manager.devicePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.mountPoint))

        try manager.teardown()

        XCTAssertNil(manager.devicePath)
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.mountPoint))
    }

    func testVolumeAppearsInFinder() throws {
        try manager.setup()

        // Verify the volume is a real directory that Finder can see
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: manager.mountPoint, isDirectory: &isDir)
        XCTAssertTrue(exists)
        XCTAssertTrue(isDir.boolValue)
    }

    // MARK: - File I/O on RAM Disk

    func testWriteAndReadFile() throws {
        try manager.setup()

        let testData = Data("Hello, Clipboard!".utf8)
        let fileURL = URL(fileURLWithPath: manager.mountPoint).appendingPathComponent("test.txt")

        try testData.write(to: fileURL)
        let readBack = try Data(contentsOf: fileURL)

        XCTAssertEqual(readBack, testData)
    }

    func testWriteImageAndVerifyPNG() throws {
        try manager.setup()

        let writer = ContentWriter(volumePath: manager.mountPoint)

        // Create a real PNG image
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.green.drawSwatch(in: NSRect(x: 0, y: 0, width: 10, height: 10))
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let pngData = rep.representation(using: .png, properties: [:])!

        try writer.writeImage(pngData, filename: "clipboard.png")

        let files = writer.currentFiles()
        XCTAssertEqual(files, ["clipboard.png"])

        let readBack = try Data(
            contentsOf: URL(fileURLWithPath: manager.mountPoint)
                .appendingPathComponent("clipboard.png"))
        XCTAssertEqual(readBack, pngData)
        // Verify PNG magic bytes
        XCTAssertTrue(readBack.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    func testOverwriteReplacesContent() throws {
        try manager.setup()
        let writer = ContentWriter(volumePath: manager.mountPoint)

        try writer.writeImage(Data("first".utf8), filename: "clip1.png")
        XCTAssertEqual(writer.currentFiles(), ["clip1.png"])

        try writer.writeImage(Data("second".utf8), filename: "clip2.png")
        let files = writer.currentFiles()
        XCTAssertEqual(files, ["clip2.png"])
        XCTAssertFalse(files.contains("clip1.png"))
    }

    func testClearRemovesAllFiles() throws {
        try manager.setup()
        let writer = ContentWriter(volumePath: manager.mountPoint)

        try writer.writeImage(Data("img".utf8), filename: "image.png")
        XCTAssertFalse(writer.currentFiles().isEmpty)

        try writer.clear()
        XCTAssertTrue(writer.currentFiles().isEmpty)
    }

    // MARK: - Crash Recovery

    func testRecoverExistingDisk() throws {
        // Create a disk with one manager
        try manager.setup()
        let originalDevice = manager.devicePath!

        // Create a second manager and try to recover
        let manager2 = RAMDiskManager(volumeName: testVolumeName, sizeInMB: 2)
        let recovered = try manager2.recoverExistingDisk()

        XCTAssertTrue(recovered)
        // hdiutil info returns partition path (e.g. /dev/disk4s1), while
        // hdiutil attach returns base device (/dev/disk4). Both work for detach.
        XCTAssertNotNil(manager2.devicePath)
        XCTAssertTrue(
            manager2.devicePath!.hasPrefix(originalDevice),
            "Recovered device '\(manager2.devicePath!)' should share base device '\(originalDevice)'")
    }

    func testRecoveredDiskIsUsable() throws {
        try manager.setup()

        // Write a file with the first manager
        let writer1 = ContentWriter(volumePath: manager.mountPoint)
        try writer1.writeImage(Data("original".utf8), filename: "before.png")

        // Recover with a second manager
        let manager2 = RAMDiskManager(volumeName: testVolumeName, sizeInMB: 2)
        try manager2.recoverExistingDisk()

        // Verify we can read and write using the recovered reference
        let writer2 = ContentWriter(volumePath: manager2.mountPoint)
        let files = writer2.currentFiles()
        XCTAssertTrue(files.contains("before.png"))

        try writer2.writeImage(Data("after".utf8), filename: "after.png")
        XCTAssertEqual(writer2.currentFiles(), ["after.png"])
    }

    // MARK: - End-to-End: Clipboard → Volume

    func testTIFFConversionAndWrite() throws {
        try manager.setup()

        // Simulate the full pipeline: TIFF on pasteboard → PNG on volume
        let image = NSImage(size: NSSize(width: 5, height: 5))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 5, height: 5))
        image.unlockFocus()
        let tiffData = image.tiffRepresentation!

        // Convert TIFF to PNG (as ClipboardMonitor does)
        let pngData = ClipboardMonitor.convertTIFFtoPNG(tiffData)
        XCTAssertNotNil(pngData)

        // Write to volume (as ContentWriter does)
        let writer = ContentWriter(volumePath: manager.mountPoint)
        try writer.writeImage(pngData!, filename: "clipboard.png")

        // Verify the file is a valid PNG that could be selected in a file picker
        let filePath = "\(manager.mountPoint)/clipboard.png"
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath))
        let fileData = try Data(contentsOf: URL(fileURLWithPath: filePath))
        XCTAssertTrue(fileData.starts(with: [0x89, 0x50, 0x4E, 0x47]))

        // Verify NSImage can read it back (confirms valid image)
        let loadedImage = NSImage(contentsOfFile: filePath)
        XCTAssertNotNil(loadedImage)
    }
}
