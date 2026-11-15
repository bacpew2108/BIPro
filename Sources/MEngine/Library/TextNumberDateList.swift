// Phase F: Thư viện hàm M nhóm giá trị (Text, Number, Date, List, Replacer, Splitter, Combiner).
// Mỗi hàm: tên đầy đủ, tham số (tuỳ chọn đánh dấu isOptional), `observed`
// (true khi ngữ nghĩa đã đối chiếu golden Desktop, false = [SUY ĐOÁN]). Dùng trợ giúp ở Support.swift.

public enum ValueLibrary {
    public static let functions: [MFunction] =
        ValueText.functions +
        ValueNumber.functions +
        ValueDate.functions +
        ValueList.functions +
        ValueReplacerSplitter.functions
}
