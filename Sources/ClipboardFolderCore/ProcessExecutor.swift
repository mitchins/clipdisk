import Foundation
#if canImport(Darwin)
import Darwin
#endif

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let output: String
    public let errorOutput: String

    public init(exitCode: Int32, output: String, errorOutput: String) {
        self.exitCode = exitCode
        self.output = output
        self.errorOutput = errorOutput
    }
}

public enum ProcessExecutionError: Error, LocalizedError {
    case timedOut(executablePath: String, timeout: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case let .timedOut(executablePath, timeout):
            return "Timed out after \(timeout) seconds running \(executablePath)"
        }
    }
}

public protocol ProcessExecuting {
    func run(executablePath: String, arguments: [String]) throws -> ProcessResult
    func run(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> ProcessResult
}

public struct SystemProcessExecutor: ProcessExecuting {
    public init() {}

    public func run(executablePath: String, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

        return ProcessResult(
            exitCode: process.terminationStatus,
            output: String(data: outputData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            errorOutput: String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    public func run(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> ProcessResult {
        guard timeout > 0 else {
            return try run(executablePath: executablePath, arguments: arguments)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let terminationSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            terminationSemaphore.signal()
        }

        try process.run()

        if terminationSemaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.interrupt()
            if terminationSemaphore.wait(timeout: .now() + 1) == .timedOut {
                process.terminate()
                if terminationSemaphore.wait(timeout: .now() + 1) == .timedOut {
#if canImport(Darwin)
                    kill(process.processIdentifier, SIGKILL)
#endif
                    _ = terminationSemaphore.wait(timeout: .now() + 1)
                }
            }

            throw ProcessExecutionError.timedOut(
                executablePath: executablePath,
                timeout: timeout
            )
        }

        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

        return ProcessResult(
            exitCode: process.terminationStatus,
            output: String(data: outputData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            errorOutput: String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }
}
