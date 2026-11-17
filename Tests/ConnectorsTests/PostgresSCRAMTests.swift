import Testing
import Foundation
@testable import Connectors

/// SCRAM-SHA-256 phía máy khách, đối chiếu vector của RFC 7677 §3 (user "user", mật khẩu "pencil").
@Suite struct PostgresSCRAMTests {
    @Test func rfc7677Vector() throws {
        var client = SCRAMClient(username: "user", password: "pencil", nonce: "rOprNGfwEbeRWgbNEkqO")
        #expect(client.clientFirstMessage == "n,,n=user,r=rOprNGfwEbeRWgbNEkqO")
        let final = try client.clientFinalMessage(
            serverFirst: "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096")
        #expect(final == "c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=")
        try client.verify(serverFinal: "v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=")
    }

    @Test func rejectsForgedServerSignature() throws {
        var client = SCRAMClient(username: "user", password: "pencil", nonce: "rOprNGfwEbeRWgbNEkqO")
        _ = try client.clientFinalMessage(
            serverFirst: "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096")
        #expect(throws: SourceError.self) { try client.verify(serverFinal: "v=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=") }
    }

    @Test func rejectsServerNonceNotExtendingClientNonce() {
        var client = SCRAMClient(username: "", password: "pencil", nonce: "abc")
        #expect(throws: SourceError.self) { try client.clientFinalMessage(serverFirst: "r=xyz123,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096") }
    }
}
