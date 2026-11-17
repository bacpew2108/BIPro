// Phase F (T092): thông tin đăng nhập nguồn cơ sở dữ liệu, theo máy chủ (`máy:cổng`, như mức mặc định của Desktop). Mật khẩu CHỈ ở bộ nhớ
// phiên và Keychain (FR-071, hiến pháp IV): không vào `.pbix`, `docs/`, nhật ký hay thông điệp lỗi. Keychain: mục mật khẩu chung
// (`kSecClassGenericPassword`), dịch vụ "BI Pro – PostgreSQL", tài khoản = máy chủ, dữ liệu = JSON {user, password, allowUnencrypted}.

import Foundation
import Security
import Synchronization

extension PostgresCredential: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "PostgresCredential(user: \(user), password: ***, allowUnencrypted: \(allowUnencrypted))" }
    public var debugDescription: String { description }
}


public final class CredentialVault: Sendable {
    public static let shared = CredentialVault()

    private let service: String
    private let session = Mutex<[String: PostgresCredential]>([:])

    public init(service: String = "BI Pro – PostgreSQL") {
        self.service = service
    }

    /// Thông tin của máy chủ: trong phiên trước, rồi Keychain.
    public func credential(for server: String) -> PostgresCredential? {
        if let cached = session.withLock({ $0[server] }) { return cached }
        var query = baseQuery(server)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let credential = try? JSONDecoder().decode(PostgresCredential.self, from: data) else { return nil }
        session.withLock { $0[server] = credential }
        return credential
    }

    /// Ghi cho phiên; `persist` thì ghi cả Keychain (thay mục cũ), không thì xoá mục Keychain cũ của máy chủ này.
    public func set(_ credential: PostgresCredential, for server: String, persist: Bool) throws {
        session.withLock { $0[server] = credential }
        SecItemDelete(baseQuery(server) as CFDictionary)
        guard persist else { return }
        var item = baseQuery(server)
        item[kSecValueData as String] = try JSONEncoder().encode(credential)
        item[kSecAttrLabel as String] = "\(service): \(server)"
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SourceError.unreadable("Không lưu được thông tin đăng nhập vào Keychain (mã \(status)).")
        }
    }

    /// Có lưu trong Keychain không (để giao diện hiện đúng ô "Lưu vào Keychain").
    public func isPersisted(_ server: String) -> Bool {
        SecItemCopyMatching(baseQuery(server) as CFDictionary, nil) == errSecSuccess
    }

    public func remove(for server: String) {
        session.withLock { _ = $0.removeValue(forKey: server) }
        SecItemDelete(baseQuery(server) as CFDictionary)
    }

    private func baseQuery(_ server: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: server]
    }
}
