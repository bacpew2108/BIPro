// T035: tự phát hiện quan hệ. Golden: ba quan hệ `AutoDetected_` Desktop tạo trong `f11-desktop.pbix` (VM-F11c, ngoài git, thiếu thì bỏ
// qua): lần nạp đầu Sales + Customers + products, rồi nạp thêm `Table (2)`.
import ColumnStore
import Foundation
import PBIXKit
import Testing
@testable import BIPro

private struct Shape: Hashable { var from: String; var to: String; var active: Bool }

private func shape(_ r: NewRelationship) -> Shape { Shape(from: "\(r.fromTable)[\(r.fromColumn)]", to: "\(r.toTable)[\(r.toColumn)]", active: r.isActive) }

@Suite(.enabled(if: F2Fixtures.desktop("vm-f11", "f11-desktop.pbix") != nil))
struct RelationshipDetectorGoldenTests {
    private func f11() throws -> (Workspace, ModelMetadata) {
        let workspace = try Workspace(data: Data(contentsOf: try #require(F2Fixtures.desktop("vm-f11", "f11-desktop.pbix"))))
        let model = try #require(workspace.metadata)
        let auto = model.relationships.filter { $0.name.hasPrefix(RelationshipDetector.namePrefix) }
        #expect(auto.count == 3)
        return (workspace, try model.applying(ModelEdits(auto.map { .deleteRelationship(name: $0.name) })))
    }

    private func unique(_ workspace: Workspace) -> (RelationshipDraft.ColumnRef) -> Bool {
        { ref in DocumentState.isUnique(ref, runtime: workspace.runtime!, workspace: workspace) }
    }

    @Test func lanNapDauChiSalesToiCustomers() throws {
        let (workspace, bare) = try f11()
        let model = try bare.applying(ModelEdits([.dropTable(name: "Table (2)")]))
        let found = RelationshipDetector.detect(model: model, newTables: ["Sales", "Customers", "products"], isUnique: unique(workspace))
        #expect(found.map(shape) == [Shape(from: "Sales[CustomerID]", to: "Customers[CustomerID]", active: true)])
        #expect(found.allSatisfy { $0.name.hasPrefix("AutoDetected_") && $0.fromMany && !$0.toMany && $0.crossFilteringBehavior == 1 })
    }

    @Test func napThemBangDuongThuHaiKhongHoatDong() throws {
        let (workspace, bare) = try f11()
        let first = RelationshipDetector.detect(model: try bare.applying(ModelEdits([.dropTable(name: "Table (2)")])),
                                                newTables: ["Sales", "Customers", "products"], isUnique: unique(workspace))
        let model = try bare.applying(ModelEdits(first.map { .addRelationship($0) }))
        let found = RelationshipDetector.detect(model: model, newTables: ["Table (2)"], isUnique: unique(workspace))
        #expect(found.map(shape) == [Shape(from: "Sales[Region]", to: "Table (2)[Region]", active: true),
                                     Shape(from: "Customers[Region]", to: "Table (2)[Region]", active: false)])
        // Như Desktop lưu.
        let desktop = Set(try #require(workspace.metadata).relationships.filter { $0.name.hasPrefix("AutoDetected_") }.map {
            Shape(from: "\($0.fromTable)[\($0.fromColumn)]", to: "\($0.toTable)[\($0.toColumn)]", active: $0.isActive)
        })
        #expect(Set((first + found).map(shape)) == desktop)
    }
}

@Suite struct RelationshipDetectorUnitTests {
    @Test func giaTriDuyNhat() {
        #expect(RelationshipDetector.isUnique(.int64([1, 2, nil])))
        #expect(!RelationshipDetector.isUnique(.int64([1, 1])))
        #expect(!RelationshipDetector.isUnique(.string([nil, nil])))
        #expect(RelationshipDetector.isUnique(.string(["a", "A"])))
    }
}

/// Tài liệu mới: nạp hai bảng cùng lúc thì có quan hệ, cùng bước ⌘Z; tắt tuỳ chọn thì không tạo; khác kiểu, hai phía lặp thì bỏ.
@MainActor
@Suite struct RelationshipDetectorFlowTests {
    private func newDocument(_ root: URL) throws -> DocumentState {
        let untitled = try UntitledDocuments.create(root: root)
        return DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent, fileURL: untitled)
    }

    private func tables() throws -> [LoadedTable] {
        let sales = try TableData(columns: [
            TableColumn(name: "CustomerID", data: ColumnBuilder.integers([1, 2, 1])),
            TableColumn(name: "ProductID", data: ColumnBuilder.integers([1, 2, 3])),
            TableColumn(name: "Region", data: ColumnBuilder.strings(["N", "S", "N"])),
        ])
        let customers = try TableData(columns: [
            TableColumn(name: "customerid", data: ColumnBuilder.integers([1, 2])),
            TableColumn(name: "Region", data: ColumnBuilder.strings(["N", "N"])),
        ])
        let products = try TableData(columns: [TableColumn(name: "ProductID", data: ColumnBuilder.strings(["P1", "P2", "P3"]))])
        return [LoadedTable(name: "Sales", data: sales), LoadedTable(name: "Customers", data: customers), LoadedTable(name: "products", data: products)]
    }

    @Test func napCungLucTaoQuanHeMotBuocHoanTac() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reldetect-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = try newDocument(root)
        let depth = state.layout.undoDepth
        #expect(state.loadFromGetData(try tables()) == nil)
        #expect(state.layout.undoDepth == depth + 1)
        let relationships = try #require(state.workspace.metadata).relationships
        #expect(relationships.map { "\($0.fromTable)[\($0.fromColumn)]→\($0.toTable)[\($0.toColumn)]" } == ["Sales[CustomerID]→Customers[customerid]"])
        #expect(relationships.allSatisfy { $0.name.hasPrefix("AutoDetected_") && $0.isActive })
        state.layout.undo()
        #expect(state.workspace.metadata?.relationships.isEmpty == true)
        #expect(state.workspace.userTables.isEmpty)
    }

    /// Thí nghiệm của gate VM-F11 (T037): nạp lần lượt sáu bảng Enter Data, Desktop tạo đúng ba quan hệ.
    @Test func gateF11HoaThuongSoThucLogicMoiCapMot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reldetect-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = try newDocument(root)
        let steps: [(String, [TableColumn])] = [
            ("Table", [TableColumn(name: "k", data: ColumnBuilder.integers([1, 2, 3])), TableColumn(name: "d", data: ColumnBuilder.doubles([1.5, 2.5, 3.5]))]),
            ("Table (2)", [TableColumn(name: "K", data: ColumnBuilder.integers([1, 1, 2]))]),
            ("Table (3)", [TableColumn(name: "d", data: ColumnBuilder.doubles([1.5, 1.5, 2.5]))]),
            ("Table (4)", [TableColumn(name: "flag", data: ColumnBuilder.booleans([true, false]))]),
            ("Table (5)", [TableColumn(name: "flag", data: ColumnBuilder.booleans([true, true, false]))]),
            ("Table (6)", [TableColumn(name: "k", data: ColumnBuilder.integers([1, 1, 2])), TableColumn(name: "d", data: ColumnBuilder.doubles([1.5, 1.5, 2.5]))]),
        ]
        for (name, columns) in steps {
            #expect(state.loadFromGetData([LoadedTable(name: name, data: try TableData(columns: columns))]) == nil)
        }
        let relationships = try #require(state.workspace.metadata).relationships
        #expect(relationships.map { "\($0.fromTable)[\($0.fromColumn)]→\($0.toTable)[\($0.toColumn)]" }
                    == ["Table (2)[K]→Table[k]", "Table (3)[d]→Table[d]", "Table (6)[k]→Table[k]"])
        #expect(relationships.allSatisfy { $0.isActive && $0.name.hasPrefix("AutoDetected_") && $0.crossFilteringBehavior == 1 })
    }

    @Test func tatTuyChonThiKhongTao() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reldetect-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = try newDocument(root)
        #expect(state.applyFileOptions(FileOptions(autoDateTime: true, autodetectRelationships: false)) == nil)
        #expect(state.loadFromGetData(try tables()) == nil)
        #expect(state.workspace.metadata?.relationships.isEmpty == true)
    }
}
