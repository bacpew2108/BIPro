// Phase F: Thư viện hàm M nhóm List.
import Foundation
import ColumnStore

enum ValueList {
    static let functions: [MFunction] = [
        MFunction(
            name: "List.Sum",
            parameters: [MParameter(name: "list"), MParameter(name: "precision", isOptional: true)],
            observed: true
        ) { args in
            let list = try args.list(0, "List.Sum")
            var total: Double = 0
            var count = 0
            for item in list {
                switch item {
                case .null:
                    continue
                case .number(let n):
                    total += n
                    count += 1
                case .currency(let c):
                    total += Double(c) / 10_000
                    count += 1
                default:
                    throw MError.expression("List.Sum: phần tử danh sách không phải số, nhận \(item.kindName)")
                }
            }
            if count == 0 { return .null }
            return .number(total)
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "List.Count",
            parameters: [MParameter(name: "list")],
            observed: false
        ) { args in
            let list = try args.list(0, "List.Count")
            return .number(Double(list.count))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "List.Distinct",
            parameters: [MParameter(name: "list"), MParameter(name: "equationCriteria", isOptional: true)],
            observed: false
        ) { args in
            let list = try args.list(0, "List.Distinct")
            var distinct: [MValue] = []
            for item in list {
                if !distinct.contains(where: { MOperators.equals($0, item) }) {
                    distinct.append(item)
                }
            }
            return .list(distinct)
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "List.Max",
            parameters: [MParameter(name: "list"), MParameter(name: "default", isOptional: true), MParameter(name: "comparisonCriteria", isOptional: true), MParameter(name: "includeNulls", isOptional: true)],
            observed: false
        ) { args in
            let list = try args.list(0, "List.Max")
            let fallback = args.optional(1) ?? .null
            let nonNulls = list.filter { if case .null = $0 { return false } else { return true } }
            guard var maxVal = nonNulls.first else { return fallback }
            for item in nonNulls.dropFirst() {
                if let cmp = MOperators.compare(item, maxVal), cmp > 0 {
                    maxVal = item
                }
            }
            return maxVal
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "List.Min",
            parameters: [MParameter(name: "list"), MParameter(name: "default", isOptional: true), MParameter(name: "comparisonCriteria", isOptional: true), MParameter(name: "includeNulls", isOptional: true)],
            observed: false
        ) { args in
            let list = try args.list(0, "List.Min")
            let fallback = args.optional(1) ?? .null
            let nonNulls = list.filter { if case .null = $0 { return false } else { return true } }
            guard var minVal = nonNulls.first else { return fallback }
            for item in nonNulls.dropFirst() {
                if let cmp = MOperators.compare(item, minVal), cmp < 0 {
                    minVal = item
                }
            }
            return minVal
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "List.Average",
            parameters: [MParameter(name: "list"), MParameter(name: "precision", isOptional: true)],
            observed: false
        ) { args in
            let list = try args.list(0, "List.Average")
            var total: Double = 0
            var count = 0
            for item in list {
                switch item {
                case .null:
                    continue
                case .number(let n):
                    total += n
                    count += 1
                case .currency(let c):
                    total += Double(c) / 10_000
                    count += 1
                default:
                    throw MError.expression("List.Average: phần tử không phải số, nhận \(item.kindName)")
                }
            }
            if count == 0 { return .null }
            return .number(total / Double(count))
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "List.Sort",
            parameters: [MParameter(name: "list"), MParameter(name: "comparisonCriteria", isOptional: true)],
            observed: false
        ) { args in
            let list = try args.list(0, "List.Sort")
            var descending = false
            if let crit = args.optional(1) {
                if case .number(let order) = crit, order == 1 {
                    descending = true
                }
            }
            // Sắp xếp ổn định (stable sort)
            let sorted = list.enumerated().sorted { (a, b) -> Bool in
                let (i1, v1) = a
                let (i2, v2) = b
                switch (v1, v2) {
                case (.null, .null):
                    return i1 < i2
                case (.null, _):
                    return !descending // Ascending: null xếp trước; Descending: null xếp sau
                case (_, .null):
                    return descending
                default:
                    if let cmp = MOperators.compare(v1, v2) {
                        if cmp == 0 { return i1 < i2 }
                        return descending ? (cmp > 0) : (cmp < 0)
                    }
                    return i1 < i2
                }
            }.map(\.element)
            return .list(sorted)
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "List.Transform",
            parameters: [MParameter(name: "list"), MParameter(name: "transform")],
            observed: false
        ) { args in
            let list = try args.list(0, "List.Transform")
            let f = try args.function(1, "List.Transform")
            var transformed: [MValue] = []
            transformed.reserveCapacity(list.count)
            for item in list {
                transformed.append(try f.call([item]))
            }
            return .list(transformed)
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "List.Select",
            parameters: [MParameter(name: "list"), MParameter(name: "selection")],
            observed: false
        ) { args in
            let list = try args.list(0, "List.Select")
            let f = try args.function(1, "List.Select")
            var selected: [MValue] = []
            for item in list {
                let keep = try f.call([item])
                guard case .logical(let b) = keep else {
                    throw MError.expression("List.Select: vị từ phải trả logic, nhận \(keep.kindName)")
                }
                if b { selected.append(item) }
            }
            return .list(selected)
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "List.Contains",
            parameters: [MParameter(name: "list"), MParameter(name: "value"), MParameter(name: "equationCriteria", isOptional: true)],
            observed: false
        ) { args in
            let list = try args.list(0, "List.Contains")
            let target = args[1]
            let found = list.contains { MOperators.equals($0, target) }
            return .logical(found)
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "List.First",
            parameters: [MParameter(name: "list"), MParameter(name: "default", isOptional: true)],
            observed: false
        ) { args in
            let list = try args.list(0, "List.First")
            if let first = list.first { return first }
            return args.optional(1) ?? .null
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "List.Last",
            parameters: [MParameter(name: "list"), MParameter(name: "default", isOptional: true)],
            observed: false
        ) { args in
            let list = try args.list(0, "List.Last")
            if let last = list.last { return last }
            return args.optional(1) ?? .null
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "List.Numbers",
            parameters: [MParameter(name: "start"), MParameter(name: "count", isOptional: true), MParameter(name: "increment", isOptional: true)],
            observed: false
        ) { args in
            let start = try args.number(0, "List.Numbers")
            let count = try args.optional(1).map { v -> Int in
                guard let n = MOperators.number(v) else { throw MError.expression("List.Numbers: count phải là số") }
                return Int(n)
            } ?? 1
            guard count >= 0 else { throw MError.expression("List.Numbers: count không được âm") }
            let increment = try args.optional(2).map { v -> Double in
                guard let n = MOperators.number(v) else { throw MError.expression("List.Numbers: increment phải là số") }
                return n
            } ?? 1.0
            var numbers: [MValue] = []
            numbers.reserveCapacity(count)
            for i in 0..<count {
                numbers.append(.number(start + Double(i) * increment))
            }
            return .list(numbers)
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "List.Reverse",
            parameters: [MParameter(name: "list")],
            observed: false
        ) { args in
            let list = try args.list(0, "List.Reverse")
            return .list(Array(list.reversed()))
        }
    ]
}
