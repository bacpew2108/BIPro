// Phase F (T092): một kết nối PostgreSQL theo giao thức v3, chỉ "simple query" (không extended query, không COPY).
// Truyền qua `URLSessionStreamTask` (Foundation) vì cần nâng cấp TLS giữa chừng: gửi SSLRequest dạng rõ, máy chủ trả 'S' thì
// `startSecureConnection()`. Máy chủ trả 'N' (không SSL): như Desktop (VM-F7b) chỉ kết nối tiếp khi người dùng đã đồng ý
// (`allowUnencrypted`), không thì ném `SourceError.insecureConnection`. Xác thực: SCRAM-SHA-256, MD5, mật khẩu rõ.
// Kết quả trả về dạng chữ (định dạng 0); DateStyle ISO nên ngày là `yyyy-MM-dd`, ngày giờ `yyyy-MM-dd HH:mm:ss[.ffffff]`.
// Thông điệp lỗi không bao giờ chứa mật khẩu.

import ColumnStore
import CryptoKit
import Foundation

/// Máy chủ và cơ sở dữ liệu, như hộp thoại Desktop: `máy[:cổng]` và tên cơ sở dữ liệu. `location` = `máy:cổng;cơ_sở_dữ_liệu`
/// (cách Desktop ghi ở bước xác thực, "10.211.55.2:55432;sales").
public struct PostgresAddress: Sendable, Equatable, Hashable {
    public let server: String
    public let database: String

    public init(server: String, database: String) {
        self.server = server.trimmingCharacters(in: .whitespaces)
        self.database = database.trimmingCharacters(in: .whitespaces)
    }

    /// Đọc lại từ `location`; `nil` khi không có dấu `;`.
    public init?(location: String) {
        guard let cut = location.lastIndex(of: ";") else { return nil }
        self.init(server: String(location[..<cut]), database: String(location[location.index(after: cut)...]))
    }

    public var location: String { "\(server);\(database)" }

    public var host: String {
        if server.hasPrefix("["), let end = server.firstIndex(of: "]") { return String(server[server.index(after: server.startIndex)..<end]) }
        if server.filter({ $0 == ":" }).count == 1, let colon = server.firstIndex(of: ":") { return String(server[..<colon]) }
        return server
    }

    public var port: Int {
        if let colon = server.lastIndex(of: ":"), server.filter({ $0 == ":" }).count == 1 || server.hasPrefix("["),
           let value = Int(server[server.index(after: colon)...]) { return value }
        return 5432
    }
}

/// Thông tin đăng nhập cơ sở dữ liệu. Mật khẩu chỉ ở bộ nhớ và Keychain, không vào `.pbix`, `docs/` hay nhật ký.
public struct PostgresCredential: Sendable, Equatable, Codable {
    public var user: String
    public var password: String
    /// Người dùng đã đồng ý kết nối không mã hoá tới máy chủ này.
    public var allowUnencrypted: Bool

    public init(user: String, password: String, allowUnencrypted: Bool = false) {
        self.user = user
        self.password = password
        self.allowUnencrypted = allowUnencrypted
    }
}

/// Cột của kết quả truy vấn: tên, OID kiểu, typmod (để hỏi tên kiểu khi chưa hỗ trợ).
struct PostgresField {
    let name: String
    let typeOID: UInt32
    let typeModifier: Int32
}

/// Kết nối một lần dùng: mở, chạy vài câu truy vấn trong cùng một Task, đóng. Không dùng chung giữa các Task.
final class PostgresConnection {
    private let address: PostgresAddress
    private let session: URLSession
    private let task: URLSessionStreamTask
    private var buffer: [UInt8] = []
    private var cursor = 0
    private var closed = false

    static let connectTimeout: TimeInterval = 15

    private init(address: PostgresAddress) {
        self.address = address
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 600
        session = URLSession(configuration: configuration)
        task = session.streamTask(withHostName: address.host, port: address.port)
    }

    deinit { if !closed { task.cancel(); session.invalidateAndCancel() } }

    /// Mở kết nối, thương lượng SSL, xác thực, chờ ReadyForQuery.
    static func open(_ address: PostgresAddress, credential: PostgresCredential) async throws -> PostgresConnection {
        guard !address.host.isEmpty else { throw SourceError.unreadable("Chưa nhập máy chủ PostgreSQL.") }
        guard !address.database.isEmpty else { throw SourceError.unreadable("Chưa nhập tên cơ sở dữ liệu.") }
        let connection = PostgresConnection(address: address)
        connection.task.resume()
        do {
            try await connection.negotiateTLS(allowUnencrypted: credential.allowUnencrypted)
            try await connection.startup(credential)
        } catch {
            connection.close(sendTerminate: false)
            throw error
        }
        return connection
    }

    func close(sendTerminate: Bool = true) {
        guard !closed else { return }
        closed = true
        if sendTerminate {
            var message: [UInt8] = [UInt8(ascii: "X")]
            message.append(contentsOf: Self.int32(4))
            task.write(Data(message), timeout: 2) { _ in }
            task.closeWrite()
        }
        task.cancel()
        session.finishTasksAndInvalidate()
    }

    // MARK: Khởi động

    private func negotiateTLS(allowUnencrypted: Bool) async throws {
        try await write(Self.int32(8) + Self.int32(80_877_103))
        let answer = try await readBytes(1)[0]
        switch answer {
        case UInt8(ascii: "S"):
            task.startSecureConnection()
        case UInt8(ascii: "N"):
            guard allowUnencrypted else {
                throw SourceError.insecureConnection(
                    "Không kết nối được tới \(address.server) bằng kết nối mã hoá. Muốn truy cập nguồn này bằng kết nối không mã hoá thì bấm OK.")
            }
        default:
            throw SourceError.unreadable("Máy chủ \(address.server) không trả lời theo giao thức PostgreSQL.")
        }
    }

    private func startup(_ credential: PostgresCredential) async throws {
        var body = Self.int32(196_608)   // giao thức 3.0
        for (key, value) in [("user", credential.user), ("database", address.database), ("client_encoding", "UTF8"),
                             ("DateStyle", "ISO, MDY"), ("application_name", "BI Pro")] {
            body += Self.cString(key) + Self.cString(value)
        }
        body.append(0)
        try await write(Self.int32(Int32(body.count + 4)) + body)

        var scram: SCRAMClient?
        while true {
            let (type, payload) = try await readMessage()
            switch type {
            case UInt8(ascii: "R"):
                var reader = ByteReader(payload)
                let code = reader.int32()
                switch code {
                case 0: break
                case 3:
                    try await sendPassword(Self.cString(credential.password))
                case 5:
                    let salt = reader.bytes(4)
                    let inner = Self.md5Hex(Array((credential.password + credential.user).utf8))
                    try await sendPassword(Self.cString("md5" + Self.md5Hex(Array(inner.utf8) + salt)))
                case 10:
                    var mechanisms: [String] = []
                    while let name = reader.cString(), !name.isEmpty { mechanisms.append(name) }
                    guard mechanisms.contains("SCRAM-SHA-256") else {
                        throw SourceError.unsupported("phương thức xác thực PostgreSQL \(mechanisms.joined(separator: ", "))")
                    }
                    let client = SCRAMClient(password: credential.password)
                    scram = client
                    let first = Array(client.clientFirstMessage.utf8)
                    try await sendPassword(Self.cString("SCRAM-SHA-256") + Self.int32(Int32(first.count)) + first)
                case 11:
                    guard var client = scram else { throw SourceError.authentication("Máy chủ gửi bước SCRAM không mong đợi.") }
                    let final = try client.clientFinalMessage(serverFirst: String(decoding: reader.rest(), as: UTF8.self))
                    scram = client
                    try await sendPassword(Array(final.utf8))
                case 12:
                    try scram?.verify(serverFinal: String(decoding: reader.rest(), as: UTF8.self))
                default:
                    throw SourceError.unsupported("phương thức xác thực PostgreSQL mã \(code)")
                }
            case UInt8(ascii: "E"):
                throw Self.error(from: payload, address: address)
            case UInt8(ascii: "Z"):
                return
            default:
                continue   // ParameterStatus 'S', BackendKeyData 'K', NoticeResponse 'N'
            }
        }
    }

    private func sendPassword(_ body: [UInt8]) async throws {
        try await write([UInt8(ascii: "p")] + Self.int32(Int32(body.count + 4)) + body)
    }

    // MARK: Truy vấn

    /// Chạy `sql` (simple query). `onDescription` nhận cột của tập kết quả (gọi lại nếu có nhiều câu lệnh), `onRow` nhận từng dòng chữ
    /// (`nil` là NULL). Lỗi máy chủ ném sau khi đã đọc tới ReadyForQuery (kết nối dùng tiếp được). Huỷ Task: đóng kết nối, ném `.cancelled`.
    func query(_ sql: String, onDescription: ([PostgresField]) throws -> Void, onRow: ([String?]) throws -> Void) async throws {
        try await write([UInt8(ascii: "Q")] + Self.int32(Int32(sql.utf8.count + 5)) + Self.cString(sql))
        var failure: Error?
        var rows = 0
        while true {
            let (type, payload) = try await readMessage()
            switch type {
            case UInt8(ascii: "T"):
                var reader = ByteReader(payload)
                let count = Int(reader.int16())
                var fields: [PostgresField] = []
                for _ in 0..<count {
                    let name = reader.cString() ?? ""
                    _ = reader.int32(); _ = reader.int16()   // bảng gốc, số thứ tự cột
                    let oid = UInt32(bitPattern: reader.int32())
                    _ = reader.int16()
                    let modifier = reader.int32()
                    _ = reader.int16()   // định dạng (0 = chữ)
                    fields.append(PostgresField(name: name, typeOID: oid, typeModifier: modifier))
                }
                if failure == nil { do { try onDescription(fields) } catch { failure = error } }
            case UInt8(ascii: "D"):
                guard failure == nil else { continue }
                var reader = ByteReader(payload)
                let count = Int(reader.int16())
                var values: [String?] = []
                values.reserveCapacity(count)
                for _ in 0..<count {
                    let length = Int(reader.int32())
                    values.append(length < 0 ? nil : String(decoding: reader.bytes(length), as: UTF8.self))
                }
                do { try onRow(values) } catch { failure = error }
                rows += 1
                if rows & 0x3FF == 0, Task.isCancelled {
                    close(sendTerminate: false)
                    throw SourceError.cancelled
                }
            case UInt8(ascii: "E"):
                failure = failure ?? Self.error(from: payload, address: address)
            case UInt8(ascii: "Z"):
                if let failure { throw failure }
                return
            default:
                continue   // CommandComplete 'C', EmptyQueryResponse 'I', NoticeResponse 'N', ParameterStatus 'S'
            }
        }
    }

    /// Các dòng của một truy vấn nhỏ (danh sách bảng, tên kiểu).
    func rows(_ sql: String) async throws -> [[String?]] {
        var out: [[String?]] = []
        try await query(sql, onDescription: { _ in }, onRow: { out.append($0) })
        return out
    }

    // MARK: Đọc, ghi

    private func write(_ bytes: [UInt8]) async throws {
        do { try await task.write(Data(bytes), timeout: Self.connectTimeout) } catch {
            throw transportError(error)
        }
    }

    private func readMessage() async throws -> (UInt8, [UInt8]) {
        let header = try await readBytes(5)
        let length = Int(Int32(bigEndian: header[1...4].withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }))
        guard length >= 4 else { throw SourceError.unreadable("Máy chủ \(address.server) gửi gói tin hỏng.") }
        return (header[0], try await readBytes(length - 4))
    }

    private func readBytes(_ count: Int) async throws -> [UInt8] {
        while buffer.count - cursor < count {
            if Task.isCancelled { close(sendTerminate: false); throw SourceError.cancelled }
            let chunk: Data?
            let atEOF: Bool
            do {
                (chunk, atEOF) = try await task.readData(ofMinLength: 1, maxLength: 1 << 20, timeout: Self.connectTimeout * 40)
            } catch {
                throw transportError(error)
            }
            if let chunk, !chunk.isEmpty {
                if cursor > 0 { buffer.removeFirst(cursor); cursor = 0 }
                buffer.append(contentsOf: chunk)
            } else if atEOF {
                throw SourceError.unreadable("Máy chủ \(address.server) đã đóng kết nối.")
            }
        }
        let out = Array(buffer[cursor..<(cursor + count)])
        cursor += count
        return out
    }

    private func transportError(_ error: Error) -> Error {
        if Task.isCancelled { return SourceError.cancelled }
        let ns = error as NSError
        let reason: String
        switch ns.code {
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: reason = "không tìm thấy máy chủ"
        case NSURLErrorCannotConnectToHost: reason = "máy chủ từ chối kết nối (sai cổng hoặc PostgreSQL chưa chạy)"
        case NSURLErrorTimedOut: reason = "hết thời gian chờ"
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateNotYetValid:
            reason = "kết nối mã hoá thất bại (chứng chỉ máy chủ không tin cậy)"
        default: reason = ns.localizedDescription
        }
        return SourceError.unreadable("Không kết nối được máy chủ PostgreSQL \(address.server): \(reason).")
    }

    // MARK: Lỗi máy chủ

    /// ErrorResponse → `SourceError`. 28P01/28000: sai thông tin đăng nhập (thông điệp như Desktop, không kèm chi tiết máy chủ).
    static func error(from payload: [UInt8], address: PostgresAddress) -> SourceError {
        var reader = ByteReader(payload)
        var fields: [UInt8: String] = [:]
        while !reader.atEnd {
            let code = reader.bytes(1)[0]
            if code == 0 { break }
            fields[code] = reader.cString() ?? ""
        }
        let sqlState = fields[UInt8(ascii: "C")] ?? ""
        let message = fields[UInt8(ascii: "M")] ?? "lỗi không rõ"
        switch sqlState {
        case "28P01", "28000":
            return .authentication("Không xác thực được bằng thông tin đăng nhập đã nhập. Hãy thử lại.")
        case "3D000":
            return .unreadable("Máy chủ \(address.server) không có cơ sở dữ liệu \"\(address.database)\".")
        default:
            return .unreadable("PostgreSQL báo lỗi (\(sqlState)): \(message)")
        }
    }

    // MARK: Mã hoá byte

    static func int32(_ value: Int32) -> [UInt8] { withUnsafeBytes(of: value.bigEndian, Array.init) }
    static func cString(_ text: String) -> [UInt8] { Array(text.utf8) + [0] }
    static func md5Hex(_ bytes: [UInt8]) -> String { Insecure.MD5.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
}

/// Đọc tuần tự một gói tin của máy chủ (số big-endian, chuỗi kết thúc bằng 0).
struct ByteReader {
    private let bytes: [UInt8]
    private var index = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var atEnd: Bool { index >= bytes.count }

    mutating func int32() -> Int32 {
        guard index + 4 <= bytes.count else { index = bytes.count; return 0 }
        defer { index += 4 }
        return Int32(bitPattern: UInt32(bytes[index]) << 24 | UInt32(bytes[index + 1]) << 16 | UInt32(bytes[index + 2]) << 8 | UInt32(bytes[index + 3]))
    }

    mutating func int16() -> Int16 {
        guard index + 2 <= bytes.count else { index = bytes.count; return 0 }
        defer { index += 2 }
        return Int16(bitPattern: UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1]))
    }

    mutating func bytes(_ count: Int) -> [UInt8] {
        let end = min(bytes.count, index + max(count, 0))
        defer { index = end }
        return Array(bytes[index..<end])
    }

    mutating func cString() -> String? {
        guard index < bytes.count, let end = bytes[index...].firstIndex(of: 0) else { return nil }
        defer { index = end + 1 }
        return String(decoding: bytes[index..<end], as: UTF8.self)
    }

    mutating func rest() -> [UInt8] { bytes(bytes.count - index) }
}
