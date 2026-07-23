import Foundation
import XCTest
@testable import AgentBar

final class AsyncProcessRunnerTests: XCTestCase {
    func testProcessRunnerCoverage() async throws {
        try await checkConcurrentOutputDrainAndLimit()
        try await checkTimeoutTerminatesProcess()
        try await checkCancellationTerminatesProcess()
    }

    private func checkConcurrentOutputDrainAndLimit() async throws {
        let result = try await AsyncProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                "/usr/bin/yes stdout | /usr/bin/head -c 200000; /usr/bin/yes stderr | /usr/bin/head -c 200000 >&2"
            ],
            maximumOutputBytes: 32 * 1024,
            timeout: 5
        )

        XCTAssertEqual(result.exitStatus, 0)
        XCTAssertEqual(result.stdout.count, 32 * 1024)
        XCTAssertEqual(result.stderr.count, 32 * 1024)
        XCTAssertTrue(result.stdoutTruncated)
        XCTAssertTrue(result.stderrTruncated)
        XCTAssertFalse(result.timedOut)
        XCTAssertFalse(result.wasCancelled)
    }

    private func checkTimeoutTerminatesProcess() async throws {
        let startedAt = Date()
        let result = try await AsyncProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "trap \"\" TERM; while :; do :; done"],
            timeout: 0.1,
            terminationGracePeriod: 0.05
        )

        XCTAssertTrue(result.timedOut)
        XCTAssertFalse(result.wasCancelled)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
    }

    private func checkCancellationTerminatesProcess() async throws {
        let task = Task {
            try await AsyncProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["10"],
                timeout: 5,
                terminationGracePeriod: 0.05
            )
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let result = try await task.value

        XCTAssertFalse(result.timedOut)
        XCTAssertTrue(result.wasCancelled)
    }
}
