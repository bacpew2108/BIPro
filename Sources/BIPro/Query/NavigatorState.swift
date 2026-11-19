// Phase F (T006): trạng thái của hộp thoại Get Data và Navigator, để giao diện (gói F-UI) vẽ từ đây.
// Hợp đồng cố định ở T006; hành vi (mở nguồn, xem trước, nạp, huỷ) cài ở T039. Trạng thái này không đụng mô hình:
// `load` chỉ trả `[LoadedTable]`, việc đưa vào mô hình là T021.

import Foundation
import Observation
import ColumnStore
import Connectors

public struct NavigatorItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let kind: SourceItemKind
    public let rowCountHint: Int?

    public init(id: String, name: String, kind: SourceItemKind, rowCountHint: Int? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.rowCountHint = rowCountHint
    }
}

/// Hộp kết nối cơ sở dữ liệu (PostgreSQL), theo các bước của Desktop (VM-F7b): địa chỉ (máy chủ, cơ sở dữ liệu, câu SQL tuỳ chọn) →
/// thông tin đăng nhập (khi chưa có hoặc bị từ chối, kèm cảnh báo) → hỏi kết nối không mã hoá (máy chủ không có SSL).
public struct DatabaseForm: Equatable, Sendable {
    public enum Step: Equatable, Sendable { case address, credentials, encryption }

    public var server = ""
    public var database = ""
    public var sql = ""
    public var user = ""
    /// Chỉ giữ trong bộ nhớ đến khi gửi; xoá ngay sau khi chuyển vào kho thông tin đăng nhập.
    public var password = ""
    /// Lưu vào Keychain (mặc định bật; tắt thì chỉ trong phiên).
    public var savePassword = true
    public var step: Step = .address
    /// Cảnh báo ở bước đăng nhập (sai mật khẩu).
    public var warning: String?
    public var isConnecting = false

    public init() {}

    var address: PostgresAddress { PostgresAddress(server: server, database: database) }
    var canSubmitAddress: Bool { !address.host.isEmpty && !address.database.isEmpty }
}

@MainActor
@Observable
public final class NavigatorState {
    public enum Phase: Equatable, Sendable {
        case choosingSource
        case listingItems
        case ready
        case loading
        case failed(String)
    }

    public var phase: Phase = .choosingSource
    public var sourceKind: SourceKind?
    /// Đường dẫn file hoặc địa chỉ nguồn người dùng chọn.
    public var location: String = ""
    public var items: [NavigatorItem] = []
    public var checkedItemIDs: Set<String> = []
    /// Mục đang xem trước (một mục tại một thời điểm).
    public var previewItemID: String?
    public var preview: TableData?
    /// 0...1 khi `phase == .loading`.
    public var progress: Double = 0

    /// Lý do xem trước hỏng (một mục lỗi không làm hỏng cả Navigator). `nil` khi xem trước được.
    public var previewError: String?
    /// Kết quả của lần `load` gần nhất (rỗng khi lỗi hoặc huỷ).
    public private(set) var loaded: [LoadedTable] = []

    @ObservationIgnored private var sourceItems: [String: any SourceItem] = [:]
    @ObservationIgnored private var loadTask: Task<[LoadedTable], Error>?
    @ObservationIgnored private let makeSource: (SourceKind, String) throws -> any DataSource
    @ObservationIgnored private let credentials: CredentialVault

    /// Hộp kết nối cơ sở dữ liệu đang mở; `nil` với nguồn tệp.
    public var databaseForm: DatabaseForm?

    /// Driver ODBC ghi vào M của nguồn SQLite (T044): driver có trên máy Desktop sẽ Refresh; đổi là nhớ cho lần sau.
    public var odbcDriver: String {
        didSet { SQLiteODBC.save(driver: odbcDriver, in: odbcDefaults) }
    }
    @ObservationIgnored private let odbcDefaults: UserDefaults

    public init(makeSource: ((SourceKind, String) throws -> any DataSource)? = nil, credentials: CredentialVault = .shared,
                odbcDefaults: UserDefaults = .standard) {
        self.credentials = credentials
        self.odbcDefaults = odbcDefaults
        self.odbcDriver = SQLiteODBC.savedDriver(in: odbcDefaults)
        self.makeSource = makeSource ?? { kind, location in try SourceFactory.make(kind: kind, location: location, credentials: credentials) }
    }

    // MARK: Nguồn cơ sở dữ liệu

    /// Mở hộp kết nối của nguồn cơ sở dữ liệu (thay cho hộp chọn tệp).
    public func beginDatabase(_ kind: SourceKind) {
        sourceKind = kind
        databaseForm = DatabaseForm()
        phase = .choosingSource
    }

    public func cancelDatabase() {
        databaseForm = nil
        phase = .choosingSource
    }

    /// Bước địa chỉ xong: có thông tin đăng nhập của máy chủ thì kết nối luôn, chưa có thì sang bước đăng nhập.
    public func submitDatabaseAddress() async {
        guard var form = databaseForm, form.canSubmitAddress else { return }
        if let saved = credentials.credential(for: form.address.server) {
            form.user = saved.user
            databaseForm = form
            await connectDatabase()
        } else {
            form.step = .credentials
            form.warning = nil
            databaseForm = form
        }
    }

    /// Ghi tên và mật khẩu vào kho (Keychain nếu `savePassword`) rồi kết nối. Giữ lựa chọn kết nối không mã hoá đã có của máy chủ.
    public func submitDatabaseCredentials() async {
        guard var form = databaseForm else { return }
        let server = form.address.server
        let allow = credentials.credential(for: server)?.allowUnencrypted ?? false
        do {
            try credentials.set(PostgresCredential(user: form.user, password: form.password, allowUnencrypted: allow), for: server,
                                persist: form.savePassword)
        } catch {
            form.warning = SourceMessage.text(for: error)
            databaseForm = form
            return
        }
        form.password = ""
        databaseForm = form
        await connectDatabase()
    }

    /// Người dùng đồng ý kết nối không mã hoá (hộp "Hỗ trợ mã hoá"): ghi nhớ cho máy chủ rồi kết nối lại.
    public func acceptUnencrypted() async {
        guard let form = databaseForm, var credential = credentials.credential(for: form.address.server) else { return }
        credential.allowUnencrypted = true
        try? credentials.set(credential, for: form.address.server, persist: credentials.isPersisted(form.address.server))
        await connectDatabase()
    }

    private func connectDatabase() async {
        guard var form = databaseForm, let kind = sourceKind else { return }
        form.isConnecting = true
        form.warning = nil
        databaseForm = form
        let location = PostgresLocation(address: form.address, sql: form.sql).location
        await openSource(kind: kind, location: location)
        form.isConnecting = false
        switch phase {
        case .failed(let message):
            switch lastOpenError {
            case .authentication?:
                form.step = .credentials
                form.warning = message
                phase = .choosingSource
            case .insecureConnection?:
                form.step = .encryption
                phase = .choosingSource
            default:
                // Không tới được máy chủ, sai tên cơ sở dữ liệu…: ở lại bước đang đứng, hiện lỗi trong hộp.
                form.warning = message
                phase = .choosingSource
            }
        case .ready where items.count == 1 && items[0].kind == .query:
            // Câu SQL: một mục `Query1`, đánh dấu và xem trước sẵn (Desktop bỏ qua Navigator, hiện thẳng bản xem trước).
            checkedItemIDs = [items[0].id]
            Task { await showPreview(items[0].id) }
        default:
            break
        }
        databaseForm = form
    }

    @ObservationIgnored private var lastOpenError: SourceError?

    public var canLoad: Bool { !checkedItemIDs.isEmpty && phase == .ready }

    /// Nguồn mở thẳng Query Editor, không qua Navigator (Desktop 2.159, VM-F7a: JSON).
    public var opensEditorDirectly: Bool { sourceKind == .json }

    /// Nguồn không qua Navigator: đánh dấu mọi mục rồi nạp. `nil` khi lỗi hoặc huỷ (như `load`).
    public func loadDirectly(existingNames: Set<String> = []) async -> [LoadedTable]? {
        guard opensEditorDirectly, phase == .ready, !items.isEmpty else { return nil }
        checkedItemIDs = Set(items.map(\.id))
        return await load(existingNames: existingNames)
    }

    /// Mở nguồn và liệt kê mục. Xoá danh sách, đánh dấu và xem trước của nguồn trước. Lỗi → `.failed(thông điệp tiếng Việt)`.
    public func openSource(kind: SourceKind, location: String) async {
        loadTask?.cancel()
        sourceKind = kind
        self.location = location
        items = []
        sourceItems = [:]
        checkedItemIDs = []
        previewItemID = nil
        preview = nil
        previewError = nil
        loaded = []
        progress = 0
        phase = .listingItems
        lastOpenError = nil
        do {
            let found = try await makeSource(kind, location).items()
            var listed: [NavigatorItem] = []
            for (index, item) in found.enumerated() {
                let id = "item-\(index)"
                sourceItems[id] = item
                listed.append(NavigatorItem(id: id, name: item.name, kind: item.kind, rowCountHint: item.rowCountHint))
            }
            items = listed
            phase = .ready
        } catch {
            lastOpenError = error as? SourceError
            phase = .failed(SourceMessage.text(for: error))
        }
    }

    /// Xem trước một mục (tối đa 200 dòng). Mục không có trong danh sách bị bỏ qua. Lỗi ghi vào `previewError`.
    public func showPreview(_ id: String) async {
        guard let item = sourceItems[id] else { return }
        previewItemID = id
        preview = nil
        previewError = nil
        do {
            let table = try await item.preview(limit: 200)
            guard previewItemID == id else { return }   // người dùng đã chọn mục khác trong lúc chờ
            preview = table
        } catch {
            guard previewItemID == id else { return }
            previewError = SourceMessage.text(for: error)
        }
    }

    /// Nạp các mục đã đánh dấu (theo thứ tự danh sách). Trả `nil` khi lỗi (`.failed`) hoặc huỷ (về `.ready`).
    /// Tên bảng khử trùng với `existingNames`. Không đổi mô hình.
    public func load(existingNames: Set<String> = []) async -> [LoadedTable]? {
        guard canLoad else { return nil }
        let chosen = items.filter { checkedItemIDs.contains($0.id) }.compactMap { sourceItems[$0.id] }
        let origin = sourceKind.map { (kind: $0, location: location) }
        let driver = SQLiteODBC.savedDriver(in: odbcDefaults)   // ô trống thì về mặc định
        phase = .loading
        progress = 0
        loaded = []
        let task = Task<[LoadedTable], Error> { [weak self] in
            try await TableLoader.load(chosen, existingNames: existingNames, source: origin, odbcDriver: driver, progress: { fraction in
                Task { @MainActor in self?.advance(to: fraction) }
            })
        }
        loadTask = task
        defer { loadTask = nil }
        do {
            let tables = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            loaded = tables
            progress = 1
            phase = .ready
            return tables
        } catch SourceError.cancelled {
            progress = 0
            phase = .ready
            return nil
        } catch is CancellationError {
            progress = 0
            phase = .ready
            return nil
        } catch {
            progress = 0
            phase = .failed(SourceMessage.text(for: error))
            return nil
        }
    }

    /// Huỷ lần `load` đang chạy (nếu có). `load` trả `nil` và phase về `.ready`.
    public func cancelLoad() { loadTask?.cancel() }

    private func advance(to fraction: Double) {
        guard phase == .loading else { return }
        progress = max(progress, min(max(fraction, 0), 1))
    }

    /// Đánh dấu hoặc bỏ đánh dấu một mục; mục không có trong danh sách bị bỏ qua.
    public func toggle(_ id: String) {
        guard items.contains(where: { $0.id == id }) else { return }
        if checkedItemIDs.contains(id) { checkedItemIDs.remove(id) } else { checkedItemIDs.insert(id) }
    }
}
