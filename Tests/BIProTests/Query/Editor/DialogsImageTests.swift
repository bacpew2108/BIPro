import AppKit
import Foundation
import SwiftUI
import Testing
import ColumnStore
import Connectors
import MEngine
@testable import BIPro

@Suite struct DialogsImageTests {

    @MainActor
    private func png(_ view: some View, size: CGSize) -> Data? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).background(Color.white))
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private func outputDirectory() throws -> URL {
        try FFixtures.outputDirectory("ui")
    }

    private func verifyImageRep(_ data: Data, expectedSize: CGSize, minColors: Int = 20) throws {
        let rep = try #require(NSBitmapImageRep(data: data))
        #expect(rep.pixelsWide == Int(expectedSize.width * 2))
        #expect(rep.pixelsHigh == Int(expectedSize.height * 2))

        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        var colors = Set<UInt32>()
        let totalPixels = width * height
        let step = max(1, Int(sqrt(Double(totalPixels) / 2000.0)))
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                if let color = rep.colorAt(x: x, y: y) {
                    let r = UInt32((color.redComponent * 255).rounded())
                    let g = UInt32((color.greenComponent * 255).rounded())
                    let b = UInt32((color.blueComponent * 255).rounded())
                    let a = UInt32((color.alphaComponent * 255).rounded())
                    let rgba = (r << 24) | (g << 16) | (b << 8) | a
                    colors.insert(rgba)
                }
            }
        }
        #expect(colors.count >= minColors, "Ảnh phải có ít nhất \(minColors) màu khác nhau (hiện có \(colors.count))")
    }

    private func makeSalesTable() throws -> TableData {
        let col0 = TableColumn(name: "OrderID", data: ColumnBuilder.integers([10248, 10249, 10250]))
        let col1 = TableColumn(name: "OrderDate", data: ColumnBuilder.dateTimes([45350.0, 45351.0, 45352.0]))
        let col2 = TableColumn(name: "CustomerID", data: ColumnBuilder.strings(["CUST-001", "CUST-002", "CUST-003"]))
        let col3 = TableColumn(name: "Amount", data: ColumnBuilder.doubles([440.0, 1820.5, 750.0]))
        return try TableData(columns: [col0, col1, col2, col3])
    }

    private func makeCustomersTable() throws -> TableData {
        let col0 = TableColumn(name: "CustomerID", data: ColumnBuilder.strings(["CUST-001", "CUST-002", "CUST-003"]))
        let col1 = TableColumn(name: "CustomerName", data: ColumnBuilder.strings(["Công ty An Pha", "Bình Minh Group", "Chi Nhánh Hà Nội"]))
        let col2 = TableColumn(name: "Region", data: ColumnBuilder.strings(["Miền Bắc", "Miền Nam", "Miền Trung"]))
        return try TableData(columns: [col0, col1, col2])
    }

    // MARK: - 1. Merge Dialog (1000 × 760)

    @Test @MainActor func exportQEMerge() async throws {
        let dir = try outputDirectory()
        let size = CGSize(width: 1000, height: 760)

        let customerQuery = QueryModel(
            name: "Customers",
            steps: [
                QueryStep(name: "Source", expression: #"#table({"CustomerID","CustomerName","Region"}, {{"CUST-001","An Pha","Bắc"}})"#)
            ],
            enableLoad: true
        )

        var model = MergeDialogModel(
            primaryQueryName: "Sales",
            leftColumns: [
                QueryColumnInfo(name: "OrderID", type: .integer),
                QueryColumnInfo(name: "OrderDate", type: .dateTime),
                QueryColumnInfo(name: "CustomerID", type: .string),
                QueryColumnInfo(name: "Amount", type: .double)
            ]
        )
        model.secondQuery = "Customers"
        model.rightColumns = [
            QueryColumnInfo(name: "CustomerID", type: .string),
            QueryColumnInfo(name: "CustomerName", type: .string),
            QueryColumnInfo(name: "Region", type: .string)
        ]
        model.toggleLeft("CustomerID")
        model.toggleRight("CustomerID")
        model.kind = .inner

        let primaryPreview = try makeSalesTable()
        let secondaryPreview = try makeCustomersTable()

        let view = MergeDialogContent(
            model: .constant(model),
            candidates: [customerQuery],
            primaryPreview: primaryPreview,
            secondaryPreview: secondaryPreview,
            isSecondaryLoading: false,
            secondaryErrorMessage: nil,
            rejectionError: nil,
            scrollable: false,
            onSelectSecondary: { _ in },
            onCommit: {},
            onCancel: {}
        )

        let data = try #require(png(view, size: size))
        try verifyImageRep(data, expectedSize: size, minColors: 15)
        let fileURL = dir.appendingPathComponent("qe2-merge.png")
        try data.write(to: fileURL)
    }

    // MARK: - 2. Expand Column Popover (640 × 480)

    @Test @MainActor func exportQEMergeExpand() async throws {
        let dir = try outputDirectory()
        let size = CGSize(width: 640, height: 480)

        var model = ExpandColumnModel(
            sourceColumn: "Orders",
            allColumns: ["OrderID", "Amount", "Status"]
        )
        model.usePrefix = false

        let columnTypes: [String: DAXType] = [
            "OrderID": .integer,
            "Amount": .double,
            "Status": .string
        ]

        let view = ZStack {
            Color(hex: "#F6F7F9")!

            VStack(alignment: .leading, spacing: 0) {
                // Table header simulation
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Text("123")
                            .font(DS.Typeface.labelSmall)
                            .foregroundStyle(DS.Palette.secondaryLabel)
                        Text("CustomerID")
                            .font(DS.Typeface.bodySmall)
                            .fontWeight(.medium)
                            .foregroundStyle(DS.Palette.label)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(DS.Palette.separator, lineWidth: 0.5))

                    HStack(spacing: 6) {
                        Text("ABC")
                            .font(DS.Typeface.labelSmall)
                            .foregroundStyle(DS.Palette.secondaryLabel)
                        Text("CustomerName")
                            .font(DS.Typeface.bodySmall)
                            .fontWeight(.medium)
                            .foregroundStyle(DS.Palette.label)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Color.white)
                    .overlay(Rectangle().stroke(DS.Palette.separator, lineWidth: 0.5))

                    HStack(spacing: 8) {
                        Text("Table")
                            .font(DS.Typeface.labelSmall)
                            .foregroundStyle(DS.Palette.accent)
                        Text("Orders")
                            .font(DS.Typeface.bodySmall)
                            .fontWeight(.semibold)
                            .foregroundStyle(DS.Palette.label)
                        Spacer()
                        Image(systemName: "arrow.left.and.right.square.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(DS.Palette.accent)
                    }
                    .padding(.horizontal, 12)
                    .frame(width: 240, height: 32)
                    .background(DS.Palette.accent.opacity(0.12))
                    .overlay(Rectangle().stroke(DS.Palette.accent.opacity(0.4), lineWidth: 1))

                    Spacer()
                }
                .background(Color.white)

                // Popover Card
                ExpandColumnContent(
                    model: .constant(model),
                    columnTypes: columnTypes,
                    scrollable: false,
                    onCommit: {},
                    onCancel: {}
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(Color.black.opacity(0.14), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 4)
                .padding(.leading, 120)
                .padding(.top, 6)

                Spacer()
            }
            .padding(24)
        }

        let data = try #require(png(view, size: size))
        try verifyImageRep(data, expectedSize: size, minColors: 15)
        let fileURL = dir.appendingPathComponent("qe2-merge-expand.png")
        try data.write(to: fileURL)
    }

    // MARK: - 3. Append Dialog (760 × 560)

    @Test @MainActor func exportQEAppend() async throws {
        let dir = try outputDirectory()
        let size = CGSize(width: 760, height: 560)

        var model = AppendDialogModel(
            primaryQueryName: "Doanh số Miền Bắc",
            candidates: ["Doanh số Miền Trung", "Doanh số Miền Nam", "Doanh số Tây Nguyên"]
        )
        model.mode = .threeOrMore
        model.toggleSelection("Doanh số Miền Trung")
        model.toggleSelection("Doanh số Miền Nam")

        let primaryColumns = ["Mã đơn", "Ngày", "Khách hàng", "Doanh thu", "Khu vực"]
        let secondaryMap: [String: [String]] = [
            "Doanh số Miền Trung": ["Mã đơn", "Ngày", "Khách hàng", "Doanh thu", "Khu vực"],
            "Doanh số Miền Nam": ["Mã đơn", "Ngày", "Khách hàng", "Doanh thu", "Khu vực"]
        ]

        let view = AppendDialogContent(
            model: .constant(model),
            primaryColumns: primaryColumns,
            secondaryColumnsMap: secondaryMap,
            rejectionError: nil,
            scrollable: false,
            onCommit: {},
            onCancel: {}
        )

        let data = try #require(png(view, size: size))
        try verifyImageRep(data, expectedSize: size, minColors: 20)
        let fileURL = dir.appendingPathComponent("qe2-append.png")
        try data.write(to: fileURL)
    }

    // MARK: - 4. Group By Dialog (760 × 560)

    @Test @MainActor func exportQEGroupBy() async throws {
        let dir = try outputDirectory()
        let size = CGSize(width: 760, height: 560)

        let cols = [
            QueryColumnInfo(name: "Khu vực", type: .string),
            QueryColumnInfo(name: "Loại hàng", type: .string),
            QueryColumnInfo(name: "Mã đơn", type: .string),
            QueryColumnInfo(name: "Doanh thu", type: .double),
            QueryColumnInfo(name: "Số lượng", type: .integer),
            QueryColumnInfo(name: "Lợi nhuận", type: .double)
        ]

        var model = GroupByDialogModel(
            allColumns: cols,
            initialSelectedColumns: ["Khu vực"]
        )
        model.basicOperation = .sum
        model.basicColumn = "Doanh thu"
        model.basicNewColumnName = "Tổng doanh thu"
        model.mode = .advanced
        model.addKey("Loại hàng")
        model.addAggregate(name: "Số đơn hàng", operation: .countRows, column: nil)

        let view = GroupByDialogContent(
            model: .constant(model),
            errorMessage: nil,
            scrollable: false,
            onCommit: {},
            onCancel: {}
        )

        let data = try #require(png(view, size: size))
        try verifyImageRep(data, expectedSize: size, minColors: 20)
        let fileURL = dir.appendingPathComponent("qe2-groupby.png")
        try data.write(to: fileURL)
    }

    // MARK: - 5. Custom Column Dialog (900 × 560)

    @Test @MainActor func exportQECustom() async throws {
        let dir = try outputDirectory()
        let size = CGSize(width: 900, height: 560)

        let availableCols = [
            QueryColumnInfo(name: "OrderID", type: .integer),
            QueryColumnInfo(name: "OrderDate", type: .dateTime),
            QueryColumnInfo(name: "CustomerID", type: .string),
            QueryColumnInfo(name: "Doanh thu", type: .double),
            QueryColumnInfo(name: "Giá vốn", type: .double),
            QueryColumnInfo(name: "Số lượng", type: .integer)
        ]

        let view = CustomColumnDialogContent(
            name: .constant("Lợi nhuận"),
            formula: .constant("[Doanh thu] - [Giá vốn]"),
            availableColumns: availableCols,
            formulaError: nil,
            rejectionError: nil,
            scrollable: false,
            onCommit: {},
            onCancel: {}
        )

        let data = try #require(png(view, size: size))
        try verifyImageRep(data, expectedSize: size, minColors: 20)
        let fileURL = dir.appendingPathComponent("qe2-custom.png")
        try data.write(to: fileURL)

        // Also export error state: qe2-custom-error.png
        let errorView = CustomColumnDialogContent(
            name: .constant("Lợi nhuận"),
            formula: .constant("[Doanh thu] - "),
            availableColumns: availableCols,
            formulaError: "Cú pháp không hợp lệ: Thiếu toán hạng sau '-' tại dòng 1, cột 14",
            rejectionError: nil,
            scrollable: false,
            onCommit: {},
            onCancel: {}
        )
        if let errData = png(errorView, size: size) {
            let errURL = dir.appendingPathComponent("qe2-custom-error.png")
            try errData.write(to: errURL)
        }
    }

    // MARK: - 6. Query Dependencies Dialog (1000 × 640)

    @Test @MainActor func exportQEDependencies() async throws {
        let dir = try outputDirectory()
        let size = CGSize(width: 1000, height: 640)

        let graph = DependencyGraphModel(
            nodes: [
                DependencyNode(id: "src_csv", title: "sales_2024.csv", kind: .source, enableLoad: true),
                DependencyNode(id: "q_sales", title: "Doanh số", kind: .query, enableLoad: true),
                DependencyNode(id: "q_targets", title: "Chỉ tiêu", kind: .query, enableLoad: true),
                DependencyNode(id: "q_merged", title: "Hiệu suất bán hàng", kind: .query, enableLoad: true),
                DependencyNode(id: "q_draft", title: "Dữ liệu nháp", kind: .query, enableLoad: false)
            ],
            edges: [
                DependencyEdge(from: "src_csv", to: "q_sales"),
                DependencyEdge(from: "q_sales", to: "q_merged"),
                DependencyEdge(from: "q_targets", to: "q_merged"),
                DependencyEdge(from: "q_sales", to: "q_draft")
            ],
            cycle: nil
        )

        let view = QueryDependenciesContent(
            graph: graph,
            scrollable: false,
            initialSelectedId: "q_merged",
            onClose: {}
        )

        let data = try #require(png(view, size: size))
        try verifyImageRep(data, expectedSize: size, minColors: 20)
        let fileURL = dir.appendingPathComponent("qe2-dependencies.png")
        try data.write(to: fileURL)
    }
}
