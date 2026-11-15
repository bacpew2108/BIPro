// Phase F, T056: xem trước theo bước với bộ nhớ đệm. Mỗi bước được tính một lần từ kết quả đầy đủ của các bước trước (không từ
// bản đã cắt `rowLimit`); đổi một bước thì chỉ tính lại từ bước đó. Nhận diện bước đổi bằng chữ ký (tên và biểu thức của mọi bước từ đầu).

import ColumnStore

public actor MPreviewCache {
    private let environment: MEnvironment
    private var entries: [Int: (signature: String, value: MValue)] = [:]
    /// Số bước vừa phải tính ở lần `preview` gần nhất (0 khi trúng bộ nhớ đệm). Cho test và số đo.
    public private(set) var lastEvaluatedStepCount = 0

    /// `environment` mang nguồn dữ liệu và hàm ngoài thư viện (ví dụ `Excel.Workbook` do ứng dụng gắn vào).
    public init(environment: MEnvironment) {
        self.environment = environment
    }

    /// Giá trị của bước `stepIndex`; bảng thì cắt còn `rowLimit` dòng đầu (`nil` = đủ). Bước lỗi ném `MError`.
    public func preview(_ query: MQuery, stepIndex: Int, rowLimit: Int? = ColumnProfile.defaultRowLimit) async throws -> MValue {
        guard query.steps.indices.contains(stepIndex) else {
            throw MError.expression("Bước thứ \(stepIndex + 1) không có trong truy vấn")
        }
        var signatures: [String] = []
        var running = ""
        for step in query.steps { running += "\u{1}\(step.name)\u{2}\(step.expression)"; signatures.append(running) }
        for (index, entry) in entries where index >= signatures.count || entry.signature != signatures[index] { entries[index] = nil }

        lastEvaluatedStepCount = 0
        let start = (0...stepIndex).first { entries[$0] == nil } ?? stepIndex + 1
        for k in start...max(start, stepIndex) where k <= stepIndex {
            try Task.checkCancellation()
            var env = environment
            for j in 0..<k { if let earlier = entries[j] { env.bindings[query.steps[j].name] = earlier.value } }
            let single = MQuery(steps: [query.steps[k]], resultName: query.steps[k].name)
            let value = try await MEvaluator(environment: env).evaluate(source: single.source)
            entries[k] = (signatures[k], value)
            lastEvaluatedStepCount += 1
        }
        let value = entries[stepIndex]!.value
        if let rowLimit, case .table(let table) = value { return .table(table.prefix(rowLimit)) }
        return value
    }

    public func reset() {
        entries.removeAll()
        lastEvaluatedStepCount = 0
    }
}
