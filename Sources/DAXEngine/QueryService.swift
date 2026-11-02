// Hợp đồng UI ↔ engine (lead, nháp đợt 0). Chốt sau khi có quan sát O1–O3 (docs/phase-b-research/oracle-ui.md §2.5).
// BIPro chỉ phụ thuộc vào các protocol này, không gọi thẳng vào DAXEngine.

public protocol DAXQueryRunning: Sendable {
    /// Chạy truy vấn. Khi Task bị huỷ, ném DAXError với kind .cancelled.
    func run(_ text: String) async throws(DAXError) -> QueryResult
}

public protocol DAXLanguageService: Sendable {
    /// Lỗi của văn bản để tô gạch chân trong editor.
    func diagnostics(for text: String) -> [DAXError]
}

extension DAXEngine: DAXQueryRunning {
    public func run(_ text: String) async throws(DAXError) -> QueryResult {
        try await execute(text)
    }
}

extension DAXEngine: DAXLanguageService {
    public func diagnostics(for text: String) -> [DAXError] {
        validate(text)
    }
}

/// Bản giả cho test UI: trả kết quả hoặc lỗi định sẵn, sau một độ trễ tuỳ chọn.
public struct FakeQueryRunner: DAXQueryRunning {
    public let outcome: Result<QueryResult, DAXError>
    public let delayNanoseconds: UInt64

    public init(outcome: Result<QueryResult, DAXError>, delayNanoseconds: UInt64 = 0) {
        self.outcome = outcome
        self.delayNanoseconds = delayNanoseconds
    }

    public func run(_ text: String) async throws(DAXError) -> QueryResult {
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if Task.isCancelled {
            throw DAXError(.cancelled, "đã huỷ")
        }
        switch outcome {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }
}
