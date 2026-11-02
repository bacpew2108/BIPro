// Đăng ký hàm (lead, đợt 0; không ai sửa sau đó). Gộp 11 họ, mỗi họ một file.
// Trùng tên giữa các họ là lỗi. Test trong DAXEngineTests kiểm tra điều này.

public enum FunctionRegistry {
    public static let all: [FunctionSpec] =
        LogicalFunctions.functions
        + MathFunctions.functions
        + TextFunctions.functions
        + DateTimeFunctions.functions
        + InformationFunctions.functions
        + FilterFunctions.functions
        + AggregationFunctions.functions
        + IteratorFunctions.functions
        + TableFunctions.functions
        + CalculateFunctions.functions
        + TimeIntelligenceFunctions.functions
        + VisualFunctions.functions

    public static let byName: [String: FunctionSpec] =
        Dictionary(all.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
}
