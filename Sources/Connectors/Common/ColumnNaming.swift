import Foundation

public enum ColumnNaming {
    /// [SUY ĐOÁN] Tên cột sau thăng cấp tiêu đề: rỗng → "Column<n>" (n từ 1, theo vị trí); trùng → "Tên.1", "Tên.2".
    public static func unique(_ headers: [String?]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(headers.count)

        for (index, raw) in headers.enumerated() {
            let baseName: String
            if let raw = raw, !raw.isEmpty {
                baseName = raw
            } else {
                baseName = "Column\(index + 1)"
            }

            if !seen.contains(baseName) {
                seen.insert(baseName)
                result.append(baseName)
            } else {
                var counter = 1
                while seen.contains("\(baseName).\(counter)") {
                    counter += 1
                }
                let uniqueName = "\(baseName).\(counter)"
                seen.insert(uniqueName)
                result.append(uniqueName)
            }
        }

        return result
    }
}
