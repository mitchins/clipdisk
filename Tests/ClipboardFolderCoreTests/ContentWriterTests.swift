import XCTest

@testable import ClipboardFolderCore

final class ContentWriterTests: XCTestCase {
    var tempDir: URL!
    var writer: ContentWriter!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContentWriterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        writer = ContentWriter(volumePath: tempDir.path)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - writeImage

    func testWriteImage() throws {
        let data = Data("fake-png-data".utf8)
        try writer.writeImage(data, filename: "test.png")

        let written = try Data(contentsOf: tempDir.appendingPathComponent("test.png"))
        XCTAssertEqual(written, data)
    }

    func testWriteImageClearsPreviousFiles() throws {
        try Data("old".utf8).write(to: tempDir.appendingPathComponent("old.png"))

        try writer.writeImage(Data("new".utf8), filename: "new.png")

        let contents = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
            .filter { !$0.hasPrefix(".") }
        XCTAssertEqual(contents, ["new.png"])
    }

    func testWriteImageOverwritesSameName() throws {
        try writer.writeImage(Data("v1".utf8), filename: "clip.png")
        try writer.writeImage(Data("v2".utf8), filename: "clip.png")

        let data = try Data(contentsOf: tempDir.appendingPathComponent("clip.png"))
        XCTAssertEqual(data, Data("v2".utf8))

        let contents = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
            .filter { !$0.hasPrefix(".") }
        XCTAssertEqual(contents.count, 1)
    }

    // MARK: - copyFiles

    func testCopyFiles() throws {
        let sourceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContentWriterSource-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDir) }

        let sourceFile = sourceDir.appendingPathComponent("document.pdf")
        try Data("pdf-content".utf8).write(to: sourceFile)

        try writer.copyFiles([sourceFile])

        let copied = try Data(contentsOf: tempDir.appendingPathComponent("document.pdf"))
        XCTAssertEqual(copied, Data("pdf-content".utf8))
    }

    func testCopyMultipleFiles() throws {
        let sourceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContentWriterMulti-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDir) }

        let file1 = sourceDir.appendingPathComponent("a.txt")
        let file2 = sourceDir.appendingPathComponent("b.txt")
        try Data("aaa".utf8).write(to: file1)
        try Data("bbb".utf8).write(to: file2)

        try writer.copyFiles([file1, file2])

        let contents = writer.currentFiles().sorted()
        XCTAssertEqual(contents, ["a.txt", "b.txt"])
    }

    func testCopyFilesClearsPrevious() throws {
        try Data("old".utf8).write(to: tempDir.appendingPathComponent("old.txt"))

        let sourceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContentWriterClearCopy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDir) }

        let newFile = sourceDir.appendingPathComponent("new.txt")
        try Data("new".utf8).write(to: newFile)

        try writer.copyFiles([newFile])

        let contents = writer.currentFiles()
        XCTAssertEqual(contents, ["new.txt"])
    }

    // MARK: - clear

    func testClear() throws {
        try Data("a".utf8).write(to: tempDir.appendingPathComponent("file1.png"))
        try Data("b".utf8).write(to: tempDir.appendingPathComponent("file2.jpg"))

        try writer.clear()

        let contents = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
            .filter { !$0.hasPrefix(".") }
        XCTAssertTrue(contents.isEmpty)
    }

    func testClearPreservesHiddenFiles() throws {
        try Data("visible".utf8).write(to: tempDir.appendingPathComponent("file.png"))
        try Data("hidden".utf8).write(to: tempDir.appendingPathComponent(".hidden"))

        try writer.clear()

        let all = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertEqual(all.filter { !$0.hasPrefix(".") }.count, 0)
        XCTAssertTrue(all.contains(".hidden"))
    }

    func testClearOnEmptyDirectory() throws {
        // Should succeed without error
        try writer.clear()
        XCTAssertTrue(writer.currentFiles().isEmpty)
    }

    func testClearThrowsWhenVolumeUnavailable() {
        let writer = ContentWriter(volumePath: "/nonexistent/path/\(UUID().uuidString)")
        XCTAssertThrowsError(try writer.clear()) { error in
            guard case ContentWriterError.volumeNotAvailable = error else {
                XCTFail("Expected volumeNotAvailable, got \(error)")
                return
            }
        }
    }

    // MARK: - currentFiles

    func testCurrentFiles() throws {
        try Data("a".utf8).write(to: tempDir.appendingPathComponent("img.png"))
        try Data("b".utf8).write(to: tempDir.appendingPathComponent(".hidden"))

        let files = writer.currentFiles()
        XCTAssertEqual(files, ["img.png"])
    }

    func testCurrentFilesReturnsEmptyForEmptyDir() {
        let files = writer.currentFiles()
        XCTAssertTrue(files.isEmpty)
    }

    func testCurrentFilesReturnsEmptyForNonexistentPath() {
        let writer = ContentWriter(volumePath: "/nonexistent/\(UUID().uuidString)")
        XCTAssertTrue(writer.currentFiles().isEmpty)
    }
}
