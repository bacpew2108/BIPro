// StringPool (CS, đợt 1a): phần bổ sung cho pool chuỗi. Kiểu `StringPool` vẫn ở Contracts.swift (LEAD).

extension StringPool {
    /// Dựng pool từ mảng chuỗi. Mục k là `strings[k]`, giữ nguyên chuỗi rỗng.
    public init(strings: [String]) {
        var bytes: [UInt8] = []
        var offsets: [UInt32] = [0]
        offsets.reserveCapacity(strings.count + 1)
        for s in strings {
            bytes.append(contentsOf: s.utf8)
            offsets.append(UInt32(bytes.count))
        }
        self.init(bytes: bytes, offsets: offsets)
    }

    /// Mọi chuỗi theo thứ tự mục. Dùng để kiểm tra và in, không dùng trong đường nóng.
    public var strings: [String] {
        (0..<count).map { string(at: $0) }
    }

    /// Số byte UTF-8 của mục k. Trả 0 nếu k ngoài phạm vi.
    public func byteCount(at k: Int) -> Int {
        guard k >= 0, k < count else { return 0 }
        return Int(offsets[k + 1]) - Int(offsets[k])
    }

    /// Bộ nhớ dùng bởi pool (byte và offset), tính theo kích thước mảng.
    public var footprint: Int {
        bytes.count + offsets.count * MemoryLayout<UInt32>.stride
    }
}
