// Chia ô song song của SUMMARIZECOLUMNS (VM-D14): luồng gọi phải tự làm việc, không được chỉ ngồi chờ luồng phụ.
// Lỗi thật: nhiều visual chạy cùng lúc, mỗi truy vấn chiếm một luồng của Swift concurrency để chờ `DispatchGroup`
// trong khi các khối phụ cần chính hàng đợi GCD đó; hết luồng thì không khối phụ nào chạy và cả trang đứng im (CPU 0%).
import Dispatch
import Foundation
import Testing
@testable import DAXEngine

@Suite struct ParallelCellsTests {

    /// Chạy `body` trên một luồng thường (không phải luồng của Task) và báo hỏng nếu quá `seconds` giây.
    private func finishes(within seconds: Double, _ body: @escaping @Sendable () -> Void) -> Bool {
        let done = DispatchSemaphore(value: 0)
        let thread = Thread { body(); done.signal() }
        thread.start()
        return done.wait(timeout: .now() + seconds) == .success
    }

    private static func waitSync(_ semaphore: DispatchSemaphore, seconds: Double) -> Bool {
        semaphore.wait(timeout: .now() + seconds) == .success
    }

    /// Hàng đợi mà khối phụ không bao giờ được chạy (đang bị một khối khác chiếm): giống lúc cả nhóm luồng đã hết.
    private func stuckQueue() -> (queue: DispatchQueue, release: () -> Void) {
        let queue = DispatchQueue(label: "test.parallelcells.stuck")
        let gate = DispatchSemaphore(value: 0)
        queue.async { gate.wait() }
        return (queue, { gate.signal() })
    }

    @Test func khoiPhuKhongBaoGioChayThiLuongGoiVanXongViecVaGiuThuTu() {
        let (queue, release) = stuckQueue()
        defer { release() }
        let box = ResultBox()
        let finished = finishes(within: 10) {
            do throws(DAXError) {
                box.value = try ParallelCells.run(count: 200, helpers: 7, queue: queue, isCancelled: { false },
                                                  makeContext: { 0 }, cell: { (i: Int, _: Int) throws(DAXError) -> [Int]? in [i * 2] })
            } catch { box.error = error }
        }
        #expect(finished, "luồng gọi phải tự làm hết các ô khi không luồng phụ nào chạy được")
        #expect(box.error == nil)
        #expect(box.value == (0..<200).map { [$0 * 2] }, "đủ ô, đúng thứ tự")
    }

    @Test func oTraNilBiBoVaGiuThuTuKhiChayCoLuongPhu() throws {
        let rows = try ParallelCells.run(count: 500, helpers: 4, isCancelled: { false }, makeContext: { 0 },
                                         cell: { (i: Int, _: Int) throws(DAXError) -> [Int]? in i % 3 == 0 ? nil : [i] })
        #expect(rows == (0..<500).filter { $0 % 3 != 0 }.map { [$0] })
    }

    @Test func loiCuaMotOGoiLenVaKhongChoKhoiPhuChuaChay() {
        let (queue, release) = stuckQueue()
        defer { release() }
        let box = ResultBox()
        let finished = finishes(within: 10) {
            do throws(DAXError) {
                box.value = try ParallelCells.run(count: 50, helpers: 3, queue: queue, isCancelled: { false }, makeContext: { 0 },
                                                  cell: { (i: Int, _: Int) throws(DAXError) -> [Int]? in
                                                      if i == 10 { throw DAXError(.runtime, "ô 10 hỏng") }
                                                      return [i]
                                                  })
            } catch { box.error = error }
        }
        #expect(finished)
        #expect(box.error?.message == "ô 10 hỏng")
    }

    @Test func nhieuTruyVanCungLucKhongBaoGioKetNhauDuSoLuongGapNhieuLanSoLoiCPU() async throws {
        let queries = ProcessInfo.processInfo.activeProcessorCount * 6
        let box = CounterBox()
        let finished = DispatchSemaphore(value: 0)
        Task.detached {
            await withTaskGroup(of: Int.self) { group in
                for q in 0..<queries {
                    group.addTask {
                        // Giống LiveVisualView: truy vấn chạy trong Task, chặn luồng của Task trong lúc chờ ô.
                        let rows = (try? ParallelCells.run(count: 40, helpers: ProcessInfo.processInfo.activeProcessorCount - 1,
                                                           isCancelled: { false }, makeContext: { 0 },
                                                           cell: { (i: Int, _: Int) throws(DAXError) -> [Int]? in
                                                               Thread.sleep(forTimeInterval: 0.0005)
                                                               return [q, i]
                                                           })) ?? []
                        return rows.count
                    }
                }
                for await n in group { box.add(n) }
            }
            finished.signal()
        }
        let ok = await Task.detached { Self.waitSync(finished, seconds: 60) }.value
        #expect(ok, "mọi truy vấn phải xong, không đứng im")
        #expect(box.total == queries * 40)
    }
}

private final class ResultBox: @unchecked Sendable {
    var value: [[Int]] = []
    var error: DAXError?
}

private final class CounterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var sum = 0
    func add(_ n: Int) { lock.lock(); sum += n; lock.unlock() }
    var total: Int { lock.lock(); defer { lock.unlock() }; return sum }
}
