// Phase F (T092): SCRAM-SHA-256 phía máy khách (RFC 5802, RFC 7677) cho xác thực PostgreSQL. Không có channel binding ("n,,", "c=biws").
// PostgreSQL bỏ qua tên trong "n=" (dùng tên ở gói khởi động) nên gọi với `username` rỗng. Không chuẩn hoá SASLprep: mật khẩu
// dùng nguyên byte UTF-8 (máy chủ PostgreSQL cũng dùng nguyên byte khi SASLprep không áp được).

import PBIXKit
import CommonCrypto
import CryptoKit
import Foundation

struct SCRAMClient {
    let username: String
    private let password: String
    let nonce: String
    private var authMessage = ""
    private var saltedPassword = Data()

    init(username: String = "", password: String, nonce: String = SCRAMClient.randomNonce()) {
        self.username = username
        self.password = password
        self.nonce = nonce
    }

    static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 18)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    private var clientFirstBare: String { "n=\(username),r=\(nonce)" }
    var clientFirstMessage: String { "n,,\(clientFirstBare)" }

    /// Từ "r=…,s=…,i=…" của máy chủ, dựng "c=biws,r=…,p=…". Nonce máy chủ phải nối dài nonce máy khách.
    mutating func clientFinalMessage(serverFirst: String) throws -> String {
        let fields = Self.fields(serverFirst)
        guard let serverNonce = fields["r"], serverNonce.hasPrefix(nonce), serverNonce.count > nonce.count,
              let saltText = fields["s"], let salt = Data(base64Encoded: saltText),
              let iterationText = fields["i"], let iterations = Int(iterationText), iterations > 0
        else { throw SourceError.authentication(lt("Máy chủ trả bước xác thực SCRAM không hợp lệ.", "The server returned an invalid SCRAM authentication step.")) }
        saltedPassword = Self.pbkdf2(password: Data(password.utf8), salt: salt, iterations: iterations)
        let withoutProof = "c=biws,r=\(serverNonce)"
        authMessage = "\(clientFirstBare),\(serverFirst),\(withoutProof)"
        let clientKey = Self.hmac(saltedPassword, "Client Key")
        let storedKey = Data(SHA256.hash(data: clientKey))
        let signature = Self.hmac(storedKey, authMessage)
        let proof = Data(zip(clientKey, signature).map { $0 ^ $1 })
        return "\(withoutProof),p=\(proof.base64EncodedString())"
    }

    /// Kiểm chữ ký máy chủ "v=…" (máy chủ thật biết mật khẩu); "e=…" là lỗi máy chủ báo.
    func verify(serverFinal: String) throws {
        let fields = Self.fields(serverFinal)
        let serverKey = Self.hmac(saltedPassword, "Server Key")
        let expected = Self.hmac(serverKey, authMessage).base64EncodedString()
        guard let signature = fields["v"], signature == expected else {
            throw SourceError.authentication(lt("Chữ ký xác thực của máy chủ không khớp.", "The server's authentication signature doesn't match."))
        }
    }

    private static func fields(_ message: String) -> [String: String] {
        var out: [String: String] = [:]
        for part in message.split(separator: ",") {
            guard let eq = part.firstIndex(of: "="), part.distance(from: part.startIndex, to: eq) == 1 else { continue }
            out[String(part[part.startIndex])] = String(part[part.index(after: eq)...])
        }
        return out
    }

    private static func hmac(_ key: Data, _ message: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: key)))
    }

    private static func pbkdf2(password: Data, salt: Data, iterations: Int) -> Data {
        var out = [UInt8](repeating: 0, count: 32)
        password.withUnsafeBytes { p in
            salt.withUnsafeBytes { s in
                _ = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p.baseAddress?.assumingMemoryBound(to: Int8.self), password.count,
                                         s.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations), &out, out.count)
            }
        }
        return Data(out)
    }
}
