// Phase F, T093 (US8): Get Data ▸ PostgreSQL trên tài liệu mới → Load `public.sales` và câu SQL `Query1` → card measure → lưu lần đầu →
// mở lại. Mật khẩu KHÔNG được có trong `.pbix` (mọi phần của ZIP và mô hình ABF đã giải nén, cả UTF-8 lẫn UTF-16) (FR-071, hiến pháp IV);
// M chỉ chứa máy chủ và cơ sở dữ liệu như Desktop. Số mong đợi lấy trực tiếp từ máy chủ bằng psql trong buổi VM-F7b: 1 000 dòng,
// Σ amount 350 317,03; Query1 5 dòng. Cần máy chủ thử (`BIPRO_PG`). Để lại `build/f-out/f7db/bipro-f7db.pbix` cho gate Desktop (T094).
import ColumnStore
import Connectors
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Phase F: PostgreSQL trên tài liệu mới, không lộ mật khẩu", .serialized) @MainActor
struct GetDataSecretsTests {
    private static var config: (server: String, user: String, password: String)? {
        guard let raw = ProcessInfo.processInfo.environment["BIPRO_PG"] else { return nil }
        let parts = raw.split(separator: ";", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[1] == "sales" else { return nil }
        return (parts[0], parts[2], parts[3])
    }

    private func waitReady(_ navigator: NavigatorState) async throws {
        for _ in 0..<400 where navigator.phase == .listingItems || navigator.databaseForm?.isConnecting == true {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(navigator.phase == .ready)
    }

    @Test func napPostgresLuuKhongCoMatKhau() async throws {
        guard let config = Self.config else { return }
        // Máy chủ ghi trong file là địa chỉ VM nhìn thấy (cầu Parallels tới chính máy Mac) để Desktop Refresh được ở gate T094.
        let server = config.server.replacingOccurrences(of: "127.0.0.1", with: "10.211.55.2")
        let vault = CredentialVault(service: "BI Pro test \(UUID().uuidString)")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("f7db-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent, fileURL: untitled)

        for sql in ["", "select region, count(*) as so_don, sum(amount) as doanh_thu from sales group by region order by region"] {
            state.showGetData(kind: .postgres, credentials: vault)
            let navigator = try #require(state.getDataState)
            #expect(navigator.databaseForm?.step == .address)
            navigator.databaseForm?.server = server
            navigator.databaseForm?.database = "sales"
            navigator.databaseForm?.sql = sql
            await navigator.submitDatabaseAddress()
            if sql.isEmpty {
                #expect(navigator.databaseForm?.step == .credentials)   // lần đầu: hỏi đăng nhập
                navigator.databaseForm?.user = config.user
                navigator.databaseForm?.password = config.password
                navigator.databaseForm?.savePassword = false
                await navigator.submitDatabaseCredentials()
                #expect(navigator.databaseForm?.password == "")   // không giữ mật khẩu trong hộp thoại
                #expect(navigator.databaseForm?.step == .encryption)   // máy chủ thử không có SSL
                await navigator.acceptUnencrypted()
                try await waitReady(navigator)
                navigator.toggle(try #require(navigator.items.first { $0.name == "public.sales" }).id)
            } else {
                try await waitReady(navigator)   // lần sau: dùng thông tin đã có, Query1 đánh dấu sẵn
            }
            let tables = try #require(await navigator.load(existingNames: state.existingTableNames))
            #expect(state.loadFromGetData(tables) == nil)
            state.closeGetData()
        }
        #expect(state.workspace.userTables.map(\.name) == ["public sales", "Query1"])

        let view = CGRect(x: 0, y: 0, width: 1280, height: 720)
        #expect(state.modelEditor.apply(.addMeasure(NewMeasure(table: "public sales", name: "Tổng amount", expression: "SUM('public sales'[amount])"))) == nil)
        let card = try #require(state.layout.insertVisual(type: "card", visibleRect: view))
        #expect(state.layout.addField(FieldRef(kind: .measure, entity: "public sales", property: "Tổng amount"), to: "Values", visual: card) == nil)

        let destination = try FFixtures.outputDirectory("f7db").appendingPathComponent("bipro-f7db.pbix")
        try? FileManager.default.removeItem(at: destination)
        let outcome = try DocumentSaver.saveUntitled(editor: state.layout, source: untitled, to: destination, readOnlyRoots: [],
                                                     backupDirectory: root.appendingPathComponent("Backups"))
        #expect(outcome.didWrite)

        // Không có mật khẩu ở bất kỳ đâu trong tệp.
        let bytes = try Data(contentsOf: destination)
        let pbix = try PBIXFile(data: bytes)
        var haystacks: [(String, Data)] = [("tệp", bytes)]
        for entry in pbix.archive.entries { haystacks.append((entry.path, try pbix.archive.read(entry))) }
        haystacks.append(("DataModel đã giải nén", try pbix.loadDataModel().0.data))
        for needle in [Data(config.password.utf8), config.password.data(using: .utf16LittleEndian)!] {
            for (name, data) in haystacks { #expect(data.range(of: needle) == nil, "mật khẩu nằm trong \(name)") }
        }

        // Mở lại: M như Desktop, số đúng.
        let reopened = try Workspace(data: Data(contentsOf: destination))
        let model = try #require(reopened.metadata)
        #expect(model.partitionQueries["public sales"]?.contains("PostgreSQL.Database(\"\(server)\", \"sales\")") == true)
        #expect(model.partitionQueries["Query1"]?.hasPrefix("let\n    Source = Value.NativeQuery(PostgreSQL.Database(") == true)
        let engine = try reopened.daxEngine()
        let result = try await engine.run("EVALUATE ROW(\"n\", COUNTROWS('public sales'), \"s\", SUM('public sales'[amount]), \"q\", COUNTROWS(Query1))")
        let row = try #require(result.tables.first?.rows.first)
        #expect(row[0] == .integer(1000))
        if case .double(let sum) = row[1] { #expect(abs(sum - 350_317.03) < 0.005) } else { Issue.record("tổng không phải số: \(row[1])") }
        #expect(row[2] == .integer(5))
    }
}
