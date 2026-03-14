import Foundation

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

public protocol ProcessExecuting {
    func run(executablePath: String, arguments: [String]) throws -> ProcessResult
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
}
