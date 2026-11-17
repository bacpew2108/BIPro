// Phase F, T110: bộ chạy M đồng bộ chạy trên hàng đợi GCD riêng, không trên pool hợp tác của Swift concurrency, nên hàm nguồn chờ
// việc đọc bất đồng bộ (`SourceFunctions.blocking`) không giữ luồng của pool. Huỷ Task gọi `MEvaluator.evaluate` lan tới bộ chạy
// qua token gắn với luồng đang chạy (`MCancellation`).

import Foundation

/// Cờ huỷ của một lần chạy M. Hàm thư viện và hàm nguồn đọc qua `MCancellation.isCancelled`.
public final class MCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    public func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }
}

public enum MCancellation {
    private static let key = "BIPro.MCancellationToken"

    /// Hàng đợi chạy bộ thông dịch (đồng thời, ngoài pool của Swift concurrency).
    static let queue = DispatchQueue(label: "BIPro.MEvaluator", qos: .userInitiated, attributes: .concurrent)

    /// Token của lần chạy M trên luồng này; nil khi không chạy trong `run`.
    public static var current: MCancellationToken? { Thread.current.threadDictionary[key] as? MCancellationToken }

    /// Lần chạy M hiện tại đã bị huỷ: theo token của luồng, không có token thì theo Task hiện tại.
    public static var isCancelled: Bool { current?.isCancelled ?? Task.isCancelled }

    public static func check() throws {
        if isCancelled { throw CancellationError() }
    }

    /// Chạy `body` đồng bộ trên `queue`; huỷ Task đang chờ thì bật cờ huỷ của token (body tự dừng ở điểm kiểm tiếp theo).
    static func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        let token = MCancellationToken()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                queue.async {
                    let dictionary = Thread.current.threadDictionary
                    let previous = dictionary[key]
                    dictionary[key] = token
                    defer { dictionary[key] = previous }
                    if token.isCancelled { continuation.resume(throwing: CancellationError()); return }
                    continuation.resume(with: Result { try body() })
                }
            }
        } onCancel: {
            token.cancel()
        }
    }
}
