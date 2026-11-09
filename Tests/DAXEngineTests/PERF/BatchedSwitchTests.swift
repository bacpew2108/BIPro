// BatchedSwitchTests.swift
// E3-cấu-trúc (T003): công tắc tính gộp. Mặc định bật; `overrideEnabled` thắng biến môi trường.
// Lưu ý: ghi đè là trạng thái toàn cục. Đường gộp và đường cũ cho cùng kết quả (hợp đồng C2), nên test khác
// chạy song song trong lúc ghi đè không đổi kết quả của chúng.

import Testing
@testable import DAXEngine

extension BatchedSerial {
@Suite struct BatchedSwitchTests {
    @Test func macDinhTheoBienMoiTruong() {
        BatchedIteration.overrideEnabled = nil
        #expect(BatchedIteration.isEnabled == BatchedIteration.environmentEnabled)
    }

    @Test func ghiDeThangBienMoiTruong() {
        defer { BatchedIteration.overrideEnabled = nil }
        BatchedIteration.overrideEnabled = false
        #expect(!BatchedIteration.isEnabled)
        BatchedIteration.overrideEnabled = true
        #expect(BatchedIteration.isEnabled)
        BatchedIteration.overrideEnabled = nil
        #expect(BatchedIteration.isEnabled == BatchedIteration.environmentEnabled)
    }
}
}
