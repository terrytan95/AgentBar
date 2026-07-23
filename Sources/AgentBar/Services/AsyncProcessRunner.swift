import Darwin
import Foundation

struct ProcessResult: Sendable {
    var exitStatus: Int32
    var stdout: Data
    var stderr: Data
    var timedOut: Bool
    var wasCancelled: Bool
    var stdoutTruncated: Bool
    var stderrTruncated: Bool
}

enum AsyncProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        standardInput: Data? = nil,
        maximumOutputBytes: Int = 1_048_576,
        timeout: TimeInterval,
        terminationGracePeriod: TimeInterval = 1
    ) async throws -> ProcessResult {
        precondition(maximumOutputBytes >= 0)
        precondition(timeout > 0)
        precondition(terminationGracePeriod >= 0)
        try Task.checkCancellation()

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let inputPipe = standardInput.map { _ in Pipe() }
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = inputPipe ?? FileHandle.nullDevice

        let waiter = ProcessWaiter()
        waiter.install(on: process)
        let controller = ProcessController(process: process, gracePeriod: terminationGracePeriod)

        do {
            try process.run()
        } catch {
            closePipes(stdoutPipe: stdoutPipe, stderrPipe: stderrPipe, inputPipe: inputPipe)
            throw error
        }

        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()
        try? inputPipe?.fileHandleForReading.close()

        async let stdoutDrain = drain(stdoutPipe.fileHandleForReading, maximumBytes: maximumOutputBytes)
        async let stderrDrain = drain(stderrPipe.fileHandleForReading, maximumBytes: maximumOutputBytes)
        async let inputWrite: Void = write(standardInput, to: inputPipe?.fileHandleForWriting)

        let completion = await withTaskCancellationHandler {
            await withTaskGroup(of: ProcessCompletion.self) { group in
                group.addTask { .exited(await waiter.wait()) }
                group.addTask {
                    do {
                        try await Task.sleep(for: .seconds(timeout))
                        return .timedOut
                    } catch {
                        return .cancelled
                    }
                }

                let first = await group.next() ?? .cancelled
                switch first {
                case .exited:
                    break
                case .timedOut:
                    controller.stop(timedOut: true, cancelled: false)
                case .cancelled:
                    controller.stop(timedOut: false, cancelled: true)
                }
                group.cancelAll()
                return first
            }
        } onCancel: {
            controller.stop(timedOut: false, cancelled: true)
        }

        _ = completion
        let stdout = await stdoutDrain
        let stderr = await stderrDrain
        await inputWrite
        let stopState = controller.stopState

        return ProcessResult(
            exitStatus: process.terminationStatus,
            stdout: stdout.data,
            stderr: stderr.data,
            timedOut: stopState.timedOut,
            wasCancelled: stopState.cancelled,
            stdoutTruncated: stdout.truncated,
            stderrTruncated: stderr.truncated
        )
    }

    static func runBlocking(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        standardInput: Data? = nil,
        maximumOutputBytes: Int = 1_048_576,
        timeout: TimeInterval,
        terminationGracePeriod: TimeInterval = 1
    ) throws -> ProcessResult {
        let semaphore = DispatchSemaphore(value: 0)
        let box = BlockingProcessResultBox()
        Task.detached(priority: .utility) {
            do {
                box.result = .success(try await run(
                    executableURL: executableURL,
                    arguments: arguments,
                    environment: environment,
                    standardInput: standardInput,
                    maximumOutputBytes: maximumOutputBytes,
                    timeout: timeout,
                    terminationGracePeriod: terminationGracePeriod
                ))
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try box.result!.get()
    }

    private static func drain(_ handle: FileHandle, maximumBytes: Int) async -> CapturedOutput {
        await Task.detached(priority: .utility) {
            defer { try? handle.close() }
            var data = Data()
            var truncated = false
            while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                let remaining = maximumBytes - data.count
                if remaining > 0 {
                    data.append(chunk.prefix(remaining))
                }
                if chunk.count > remaining {
                    truncated = true
                }
            }
            return CapturedOutput(data: data, truncated: truncated)
        }.value
    }

    private static func write(_ data: Data?, to handle: FileHandle?) async {
        guard let handle else { return }
        await Task.detached(priority: .utility) {
            defer { try? handle.close() }
            guard let data else { return }
            try? handle.write(contentsOf: data)
        }.value
    }

    private static func closePipes(stdoutPipe: Pipe, stderrPipe: Pipe, inputPipe: Pipe?) {
        try? stdoutPipe.fileHandleForReading.close()
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForWriting.close()
        try? inputPipe?.fileHandleForReading.close()
        try? inputPipe?.fileHandleForWriting.close()
    }
}

private final class BlockingProcessResultBox: @unchecked Sendable {
    var result: Result<ProcessResult, Error>?
}

private struct CapturedOutput: Sendable {
    var data: Data
    var truncated: Bool
}

private enum ProcessCompletion: Sendable {
    case exited(Int32)
    case timedOut
    case cancelled
}

private final class ProcessWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var status: Int32?
    private var continuation: CheckedContinuation<Int32, Never>?

    func install(on process: Process) {
        process.terminationHandler = { [weak self] process in
            self?.finish(process.terminationStatus)
        }
    }

    func wait() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let status {
                lock.unlock()
                continuation.resume(returning: status)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    private func finish(_ status: Int32) {
        lock.lock()
        self.status = status
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: status)
    }
}

private final class ProcessController: @unchecked Sendable {
    private let process: Process
    private let gracePeriod: TimeInterval
    private let lock = NSLock()
    private var stopRequested = false
    private var timedOut = false
    private var cancelled = false

    init(process: Process, gracePeriod: TimeInterval) {
        self.process = process
        self.gracePeriod = gracePeriod
    }

    var stopState: (timedOut: Bool, cancelled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (timedOut, cancelled)
    }

    func stop(timedOut: Bool, cancelled: Bool) {
        lock.lock()
        self.timedOut = self.timedOut || timedOut
        self.cancelled = self.cancelled || cancelled
        guard !stopRequested else {
            lock.unlock()
            return
        }
        stopRequested = true
        let isRunning = process.isRunning
        lock.unlock()

        guard isRunning else { return }
        process.terminate()
        let gracePeriod = gracePeriod
        Task.detached(priority: .utility) { [weak self] in
            if gracePeriod > 0 {
                try? await Task.sleep(for: .seconds(gracePeriod))
            }
            self?.killIfRunning()
        }
    }

    private func killIfRunning() {
        lock.lock()
        let processIdentifier = process.isRunning ? process.processIdentifier : 0
        lock.unlock()
        if processIdentifier > 0 {
            Darwin.kill(processIdentifier, SIGKILL)
        }
    }
}
