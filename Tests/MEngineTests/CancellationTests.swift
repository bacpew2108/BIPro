// Phase F, T110: bộ chạy M chạy trên hàng đợi riêng, hàm M chờ chặn không giữ luồng của pool hợp tác; huỷ Task lan tới hàm M qua token.
import Foundation
import Testing
@testable import MEngine

@Suite struct MCancellationTests {
    private func environment(_ name: String, _ body: @escaping @Sendable () throws -> MValue) -> MEnvironment {
        MEnvironment(bindings: [name: .function(MFunction(name: name, parameters: [], observed: true) { _ in try body() })])
    }

    @Test func functionsRunUnderARunToken() async throws {
        let env = environment("Test.HasToken") { .logical(MCancellation.current != nil) }
        #expect(try await MEvaluator(environment: env).evaluate(source: "Test.HasToken()") == .logical(true))
    }

    @Test func cancellingTheTaskStopsAWaitingFunction() async throws {
        let env = environment("Test.Wait") {
            let start = Date()
            while Date().timeIntervalSince(start) < 10 {
                try MCancellation.check()
                Thread.sleep(forTimeInterval: 0.005)
            }
            return .null
        }
        let task = Task { try await MEvaluator(environment: env).evaluate(source: "Test.Wait()") }
        try await Task.sleep(for: .milliseconds(50))
        let start = Date()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Date().timeIntervalSince(start) < 1)
    }

    /// Số nhân + 4 lần chạy cùng lúc, mỗi lần chờ chặn tới khi đủ số lần đang chờ cùng lúc. Chạy trên pool hợp tác (số luồng = số nhân)
    /// thì không bao giờ đủ (hết hạn 5 s); hàng đợi riêng cho mọi lần chờ cùng lúc. Đo độ đồng thời, không đo thời gian (máy bận vẫn đúng).
    @Test func blockingFunctionsDoNotQueueOnTheCooperativePool() async throws {
        let wanted = ProcessInfo.processInfo.activeProcessorCount + 4
        let gate = Gate(wanted: wanted)
        let env = environment("Test.Block") { .logical(gate.arriveAndWait(timeout: 5)) }
        let reached = try await withThrowingTaskGroup(of: MValue.self) { group in
            for _ in 0..<wanted { group.addTask { try await MEvaluator(environment: env).evaluate(source: "Test.Block()") } }
            var count = 0
            for try await value in group where value == .logical(true) { count += 1 }
            return count
        }
        #expect(reached == wanted, "chỉ \(reached)/\(wanted) lần chờ cùng lúc")
    }
}

/// Rào chặn: mỗi lần gọi chờ tới khi đủ `wanted` lần đang chờ cùng lúc; trả false nếu hết hạn.
private final class Gate: @unchecked Sendable {
    private let condition = NSCondition()
    private let wanted: Int
    private var arrived = 0

    init(wanted: Int) { self.wanted = wanted }

    func arriveAndWait(timeout: TimeInterval) -> Bool {
        condition.lock(); defer { condition.unlock() }
        arrived += 1
        condition.broadcast()
        let deadline = Date().addingTimeInterval(timeout)
        while arrived < wanted { if !condition.wait(until: deadline) { return false } }
        return true
    }
}
