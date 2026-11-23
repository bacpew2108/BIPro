import PBIXKit
import Foundation

/// Chia `count` ô cho luồng gọi và `helpers` khối phụ trên `queue`; kết quả giữ thứ tự, ô trả nil bị bỏ.
///
/// Luồng gọi **tự làm việc** cùng các khối phụ và chỉ chờ những ô đang chạy dở, không bao giờ chờ một khối phụ chưa
/// được cấp luồng. Bản cũ để luồng gọi ngồi chờ `DispatchGroup` của mọi khối phụ: khi nhiều visual truy vấn cùng lúc,
/// mỗi truy vấn chiếm một luồng của Swift concurrency để chờ, các khối phụ cần luồng từ cùng nhóm GCD mà nhóm đã hết,
/// nên cả trang đứng im với CPU 0% (VM-D14, trang D1 của `Nhom6_d3.pbix`). Giờ khối phụ chỉ là hỗ trợ thêm: có chạy
/// thì nhanh hơn, không chạy thì luồng gọi vẫn xong một mình. Chờ theo cách này không thể thành vòng tròn vì chỉ chờ ô
/// đã có luồng đang chạy, và ô lồng bên trong cũng tự làm hết phần của nó.
///
/// - `makeContext`: gọi một lần cho mỗi luồng khi luồng đó lấy được ô đầu tiên (mỗi luồng một Evaluator riêng).
/// - `isCancelled`: chỉ được hỏi ở luồng gọi (nằm trong Task của người gọi). Khi đúng thì gọi `cancel` để báo các luồng
///   phụ và dừng phát ô mới.
enum ParallelCells {
    static func run<Context, Row>(count: Int, helpers: Int, queue: DispatchQueue = .global(qos: .userInitiated),
                                  isCancelled: @escaping () -> Bool, cancel: @escaping () -> Void = {},
                                  makeContext: @escaping () -> Context,
                                  cell: @escaping (Int, Context) throws(DAXError) -> Row?) throws(DAXError) -> [Row] {
        let shared = ParallelCellsShared<Row>(count: count)
        nonisolated(unsafe) let work = cell
        nonisolated(unsafe) let make = makeContext
        let drain: @Sendable () -> Void = {
            var context: Context?
            while let i = shared.take() {
                if context == nil { context = make() }
                do throws(DAXError) {
                    shared.store(try work(i, context!), at: i)
                } catch {
                    shared.fail(error)
                    return
                }
            }
        }
        for _ in 0..<max(helpers, 0) { queue.async(execute: drain) }
        drain()
        // Luồng gọi hết ô để lấy; chỉ còn chờ các ô khối phụ đang chạy dở.
        while !shared.waitUntilIdle(milliseconds: 20) {
            if isCancelled() {
                cancel()
                shared.requestStop()
            }
        }
        return try shared.finish()
    }
}

private final class ParallelCellsShared<Row>: @unchecked Sendable {
    private let condition = NSCondition()
    private let count: Int
    private var next = 0
    private var running = 0
    private var error: DAXError?
    private var stop = false
    private var results: [Row?]

    init(count: Int) {
        self.count = count
        results = [Row?](repeating: nil, count: count)
    }

    /// Cấp ô kế tiếp và tính là đang chạy; nil khi hết ô hoặc đã dừng.
    func take() -> Int? {
        condition.lock(); defer { condition.unlock() }
        guard !stop, next < count else { return nil }
        defer { next += 1; running += 1 }
        return next
    }

    func store(_ row: Row?, at i: Int) {
        condition.lock()
        results[i] = row
        running -= 1
        condition.broadcast()
        condition.unlock()
    }

    func fail(_ e: DAXError) {
        condition.lock()
        if error == nil { error = e }
        stop = true
        running -= 1
        condition.broadcast()
        condition.unlock()
    }

    func requestStop() {
        condition.lock(); stop = true; condition.unlock()
    }

    /// Đúng khi không còn ô nào đang chạy và không còn ô nào sẽ được cấp.
    func waitUntilIdle(milliseconds: Int) -> Bool {
        condition.lock(); defer { condition.unlock() }
        if running == 0 && (stop || next >= count) { return true }
        condition.wait(until: Date(timeIntervalSinceNow: Double(milliseconds) / 1000))
        return running == 0 && (stop || next >= count)
    }

    func finish() throws(DAXError) -> [Row] {
        condition.lock(); defer { condition.unlock() }
        if let error { throw error }
        if stop && next < count { throw DAXError(.cancelled, lt("đã huỷ", "cancelled")) }
        return results.compactMap { $0 }
    }
}
