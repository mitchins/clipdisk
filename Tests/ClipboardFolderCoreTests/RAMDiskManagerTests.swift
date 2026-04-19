import XCTest

@testable import ClipboardFolderCore

final class MockProcessExecutor: ProcessExecuting {
    var commands: [(path: String, args: [String])] = []
    private var results: [ProcessResult] = []
    private var callIndex = 0

    func enqueue(_ result: ProcessResult) {
        results.append(result)
    }

    func run(executablePath: String, arguments: [String]) throws -> ProcessResult {
        commands.append((path: executablePath, args: arguments))
        return dequeueResult()
    }

    func run(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> ProcessResult {
        commands.append((path: executablePath, args: arguments))
        return dequeueResult()
    }

    private func dequeueResult() -> ProcessResult {
        guard callIndex < results.count else {
            return ProcessResult(exitCode: 1, output: "", errorOutput: "No mock result configured")
        }
        let result = results[callIndex]
        callIndex += 1
        return result
    }
}

final class RAMDiskManagerTests: XCTestCase {

    // MARK: - setup()

    func testSetupCallsHdiutilAndDiskutil() throws {
        let executor = MockProcessExecutor()
        executor.enqueue(ProcessResult(exitCode: 0, output: "/dev/disk42", errorOutput: ""))
        executor.enqueue(ProcessResult(exitCode: 0, output: "Finished", errorOutput: ""))

        let manager = RAMDiskManager(volumeName: "TestVol", sizeInMB: 10, processExecutor: executor)
        try manager.setup()

        XCTAssertEqual(executor.commands.count, 2)

        // hdiutil attach -nomount ram://<sectors>
        XCTAssertEqual(executor.commands[0].path, "/usr/bin/hdiutil")
        XCTAssertEqual(executor.commands[0].args, ["attach", "-nomount", "ram://20480"])

        // diskutil eraseDisk HFS+ <name> <device>
        XCTAssertEqual(executor.commands[1].path, "/usr/sbin/diskutil")
        XCTAssertEqual(executor.commands[1].args, ["eraseDisk", "HFS+", "TestVol", "/dev/disk42"])

        XCTAssertEqual(manager.devicePath, "/dev/disk42")
    }

    func testSetupSectorCalculation() throws {
        let executor = MockProcessExecutor()
        executor.enqueue(ProcessResult(exitCode: 0, output: "/dev/disk42", errorOutput: ""))
        executor.enqueue(ProcessResult(exitCode: 0, output: "OK", errorOutput: ""))

        // 30 MB = 30 * 2048 = 61440 sectors
        let manager = RAMDiskManager(sizeInMB: 30, processExecutor: executor)
        try manager.setup()

        XCTAssertTrue(executor.commands[0].args.contains("ram://61440"))
    }

    func testSetupFailsWhenHdiutilFails() {
        let executor = MockProcessExecutor()
        executor.enqueue(ProcessResult(exitCode: 1, output: "", errorOutput: "Permission denied"))

        let manager = RAMDiskManager(processExecutor: executor)
        XCTAssertThrowsError(try manager.setup()) { error in
            guard case RAMDiskError.creationFailed(let msg) = error else {
                XCTFail("Expected creationFailed, got \(error)")
                return
            }
            XCTAssertEqual(msg, "Permission denied")
        }
        XCTAssertNil(manager.devicePath)
    }

    func testSetupFailsWhenHdiutilReturnsEmptyDevice() {
        let executor = MockProcessExecutor()
        executor.enqueue(ProcessResult(exitCode: 0, output: "  \n  ", errorOutput: ""))

        let manager = RAMDiskManager(processExecutor: executor)
        XCTAssertThrowsError(try manager.setup()) { error in
            guard case RAMDiskError.creationFailed = error else {
                XCTFail("Expected creationFailed, got \(error)")
                return
            }
        }
    }

    func testSetupFailsWhenDiskutilFailsAndCleansUp() {
        let executor = MockProcessExecutor()
        executor.enqueue(ProcessResult(exitCode: 0, output: "/dev/disk42", errorOutput: ""))
        executor.enqueue(ProcessResult(exitCode: 1, output: "", errorOutput: "Format error"))
        executor.enqueue(ProcessResult(exitCode: 0, output: "", errorOutput: ""))  // cleanup detach

        let manager = RAMDiskManager(processExecutor: executor)
        XCTAssertThrowsError(try manager.setup()) { error in
            guard case RAMDiskError.formatFailed(let msg) = error else {
                XCTFail("Expected formatFailed, got \(error)")
                return
            }
            XCTAssertEqual(msg, "Format error")
        }

        // Verify cleanup detach was attempted
        XCTAssertEqual(executor.commands.count, 3)
        XCTAssertEqual(executor.commands[2].path, "/usr/bin/hdiutil")
        XCTAssertEqual(executor.commands[2].args, ["detach", "/dev/disk42"])
        XCTAssertNil(manager.devicePath)
    }

    func testSetupThrowsWhenAlreadyMounted() throws {
        let executor = MockProcessExecutor()
        executor.enqueue(ProcessResult(exitCode: 0, output: "/dev/disk42", errorOutput: ""))
        executor.enqueue(ProcessResult(exitCode: 0, output: "OK", errorOutput: ""))

        let manager = RAMDiskManager(processExecutor: executor)
        try manager.setup()

        XCTAssertThrowsError(try manager.setup()) { error in
            guard case RAMDiskError.alreadyMounted = error else {
                XCTFail("Expected alreadyMounted, got \(error)")
                return
            }
        }
    }

    // MARK: - teardown()

    func testTeardown() throws {
        let executor = MockProcessExecutor()
        executor.enqueue(ProcessResult(exitCode: 0, output: "/dev/disk42", errorOutput: ""))
        executor.enqueue(ProcessResult(exitCode: 0, output: "OK", errorOutput: ""))
        executor.enqueue(ProcessResult(exitCode: 0, output: "", errorOutput: ""))

        let manager = RAMDiskManager(processExecutor: executor)
        try manager.setup()
        try manager.teardown()

        XCTAssertEqual(executor.commands[2].path, "/usr/bin/hdiutil")
        XCTAssertEqual(executor.commands[2].args, ["detach", "/dev/disk42"])
        XCTAssertNil(manager.devicePath)
    }

    func testTeardownThrowsWhenNotMounted() {
        let manager = RAMDiskManager(processExecutor: MockProcessExecutor())
        XCTAssertThrowsError(try manager.teardown()) { error in
            guard case RAMDiskError.notMounted = error else {
                XCTFail("Expected notMounted, got \(error)")
                return
            }
        }
    }

    func testTeardownFailsWhenDetachFails() throws {
        let executor = MockProcessExecutor()
        executor.enqueue(ProcessResult(exitCode: 0, output: "/dev/disk42", errorOutput: ""))
        executor.enqueue(ProcessResult(exitCode: 0, output: "OK", errorOutput: ""))
        executor.enqueue(ProcessResult(exitCode: 1, output: "", errorOutput: "Resource busy"))

        let manager = RAMDiskManager(processExecutor: executor)
        try manager.setup()

        XCTAssertThrowsError(try manager.teardown()) { error in
            guard case RAMDiskError.detachFailed(let msg) = error else {
                XCTFail("Expected detachFailed, got \(error)")
                return
            }
            XCTAssertEqual(msg, "Resource busy")
        }
        // Device path should still be set (teardown failed)
        XCTAssertNotNil(manager.devicePath)
    }

    // MARK: - recoverExistingDisk()

    func testRecoverExistingDisk() throws {
        let plist = makePlist(imagePath: "ram://40960", mountPoint: "/Volumes/Clipboard", devEntry: "/dev/disk7")
        let executor = MockProcessExecutor()
        executor.enqueue(ProcessResult(exitCode: 0, output: plist, errorOutput: ""))

        let manager = RAMDiskManager(volumeName: "Clipboard", processExecutor: executor)
        let recovered = try manager.recoverExistingDisk()

        XCTAssertTrue(recovered)
        XCTAssertEqual(manager.devicePath, "/dev/disk7")
    }

    func testRecoverExistingDiskReturnsFalseWhenNoneFound() throws {
        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
            "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict><key>images</key><array></array></dict>
            </plist>
            """
        let executor = MockProcessExecutor()
        executor.enqueue(ProcessResult(exitCode: 0, output: plist, errorOutput: ""))

        let manager = RAMDiskManager(volumeName: "Clipboard", processExecutor: executor)
        let recovered = try manager.recoverExistingDisk()

        XCTAssertFalse(recovered)
        XCTAssertNil(manager.devicePath)
    }

    func testSetupFreshRecreatesVolumeAfterExistingPath() throws {
        let executor = MockProcessExecutor()
        executor.enqueue(ProcessResult(exitCode: 0, output: "/dev/disk42", errorOutput: ""))
        executor.enqueue(ProcessResult(exitCode: 0, output: "OK", errorOutput: ""))
        executor.enqueue(ProcessResult(exitCode: 0, output: "/dev/disk43", errorOutput: ""))
        executor.enqueue(ProcessResult(exitCode: 0, output: "OK", errorOutput: ""))

        let manager = RAMDiskManager(processExecutor: executor)
        try manager.setup()
        try manager.setupFresh()

        XCTAssertEqual(manager.devicePath, "/dev/disk43")
    }

    func testRecoverReturnsFalseWhenHdiutilFails() throws {
        let executor = MockProcessExecutor()
        executor.enqueue(ProcessResult(exitCode: 1, output: "", errorOutput: "error"))

        let manager = RAMDiskManager(processExecutor: executor)
        let recovered = try manager.recoverExistingDisk()

        XCTAssertFalse(recovered)
    }

    // MARK: - parseHdiutilInfo()

    func testParseHdiutilInfoFindsRAMDisk() {
        let manager = RAMDiskManager(volumeName: "Clipboard", processExecutor: MockProcessExecutor())
        let plist = makePlist(imagePath: "ram://40960", mountPoint: "/Volumes/Clipboard", devEntry: "/dev/disk5")

        XCTAssertEqual(manager.parseHdiutilInfo(plist), "/dev/disk5")
    }

    func testParseHdiutilInfoIgnoresNonRAMDisks() {
        let manager = RAMDiskManager(volumeName: "Clipboard", processExecutor: MockProcessExecutor())
        let plist = makePlist(
            imagePath: "/path/to/disk.dmg", mountPoint: "/Volumes/Clipboard", devEntry: "/dev/disk3")

        XCTAssertNil(manager.parseHdiutilInfo(plist))
    }

    func testParseHdiutilInfoIgnoresWrongVolumeName() {
        let manager = RAMDiskManager(volumeName: "Clipboard", processExecutor: MockProcessExecutor())
        let plist = makePlist(imagePath: "ram://40960", mountPoint: "/Volumes/OtherDisk", devEntry: "/dev/disk3")

        XCTAssertNil(manager.parseHdiutilInfo(plist))
    }

    func testParseHdiutilInfoHandlesInvalidPlist() {
        let manager = RAMDiskManager(processExecutor: MockProcessExecutor())
        XCTAssertNil(manager.parseHdiutilInfo("not valid plist"))
    }

    func testParseHdiutilInfoHandlesEmptyString() {
        let manager = RAMDiskManager(processExecutor: MockProcessExecutor())
        XCTAssertNil(manager.parseHdiutilInfo(""))
    }

    // MARK: - Properties

    func testMountPoint() {
        let manager = RAMDiskManager(volumeName: "TestVolume", processExecutor: MockProcessExecutor())
        XCTAssertEqual(manager.mountPoint, "/Volumes/TestVolume")
    }

    func testDefaultValues() {
        let manager = RAMDiskManager(processExecutor: MockProcessExecutor())
        XCTAssertEqual(manager.volumeName, "Clipboard")
        XCTAssertEqual(manager.sizeInMB, 20)
        XCTAssertEqual(manager.mountPoint, "/Volumes/Clipboard")
        XCTAssertNil(manager.devicePath)
    }

    // MARK: - Helpers

    private func makePlist(imagePath: String, mountPoint: String, devEntry: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
        "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>images</key>
            <array>
                <dict>
                    <key>image-path</key>
                    <string>\(imagePath)</string>
                    <key>system-entities</key>
                    <array>
                        <dict>
                            <key>dev-entry</key>
                            <string>\(devEntry)</string>
                            <key>mount-point</key>
                            <string>\(mountPoint)</string>
                        </dict>
                    </array>
                </dict>
            </array>
        </dict>
        </plist>
        """
    }
}
