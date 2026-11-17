import Testing
import Foundation
@testable import Connectors

/// Thông tin đăng nhập theo máy chủ (Desktop: "Select which level to apply these settings to" mặc định là máy chủ). Lưu Keychain khi
/// người dùng đồng ý, không thì chỉ trong phiên. Test Keychain dùng tên dịch vụ riêng rồi xoá.
@Suite(.serialized) struct CredentialVaultTests {
    @Test func sessionOnlyCredentialIsNotPersisted() throws {
        let service = "BI Pro test \(UUID().uuidString)"
        let vault = CredentialVault(service: service)
        try vault.set(PostgresCredential(user: "u", password: "p1"), for: "db:5432", persist: false)
        #expect(vault.credential(for: "db:5432")?.password == "p1")
        #expect(CredentialVault(service: service).credential(for: "db:5432") == nil)
    }

    @Test func keychainRoundTripAndRemove() throws {
        let service = "BI Pro test \(UUID().uuidString)"
        let vault = CredentialVault(service: service)
        defer { vault.remove(for: "db:5432") }
        try vault.set(PostgresCredential(user: "u", password: "mật khẩu", allowUnencrypted: true), for: "db:5432", persist: true)
        let fresh = CredentialVault(service: service)   // phiên mới: đọc lại từ Keychain
        #expect(fresh.credential(for: "db:5432") == PostgresCredential(user: "u", password: "mật khẩu", allowUnencrypted: true))
        #expect(fresh.credential(for: "khac:5432") == nil)
        vault.remove(for: "db:5432")
        #expect(CredentialVault(service: service).credential(for: "db:5432") == nil)
    }

    @Test func descriptionNeverShowsPassword() {
        let credential = PostgresCredential(user: "u", password: "bi-mat-123")
        #expect(!String(describing: credential).contains("bi-mat-123"))
        #expect(!String(reflecting: credential).contains("bi-mat-123"))
    }
}
