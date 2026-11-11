import Foundation
import Testing
@testable import PBIXKit

/// Nhóm visual (D7): so với mẫu Power BI Desktop ghi ở VM-D7 (`docs/phase-d-evidence/vm-d7/json/`).
@Suite struct PBIRGroupPatchTests {
    static func sample(_ name: String) throws -> Data {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        url.appendPathComponent("docs/phase-d-evidence/vm-d7/json/\(name)")
        return try Data(contentsOf: url)
    }

    @Test func groupJSONMatchesDesktop() throws {
        let desktop = try Self.sample("group-moi.visual.json")
        let name = String(decoding: desktop, as: UTF8.self).components(separatedBy: "\"name\":\"")[1].prefix(while: { $0 != "\"" })
        let exact = try PBIRGroupPatch.groupJSON(name: String(name), displayName: "Group 1", x: 24, y: 688, width: 1872, height: 380, z: 33001)
        #expect(exact == desktop)
    }

    @Test func groupJSONRejectsBadInput() {
        #expect(throws: WriteError.self) { try PBIRGroupPatch.groupJSON(name: "short", displayName: "G", x: 0, y: 0, width: 10, height: 10, z: 1) }
        #expect(throws: WriteError.self) {
            try PBIRGroupPatch.groupJSON(name: "aaaaaaaaaaaaaaaaaaaa", displayName: "G", x: -1, y: 0, width: 10, height: 10, z: 1)
        }
        #expect(throws: WriteError.self) {
            try PBIRGroupPatch.groupJSON(name: "aaaaaaaaaaaaaaaaaaaa", displayName: "G", x: 0, y: 0, width: 0, height: 10, z: 1)
        }
    }

    @Test func parentAddedAsLastKeyAndRemovedToSameBytes() throws {
        let before = try Self.sample("con-truoc-khi-nhom.visual.json")
        let added = try PBIRGroupPatch.settingParentGroup("70703ac9b8810b6162e7", in: before)
        let text = String(decoding: added, as: UTF8.self)
        #expect(text.hasSuffix(",\"parentGroupName\":\"70703ac9b8810b6162e7\"}"))
        #expect(PBIRGroupPatch.parentGroupName(in: added) == "70703ac9b8810b6162e7")
        let removed = try PBIRGroupPatch.settingParentGroup(nil, in: added)
        #expect(removed == before)
        // Đặt lại cùng giá trị: không đổi byte.
        #expect(try PBIRGroupPatch.settingParentGroup("70703ac9b8810b6162e7", in: added) == added)
        #expect(try PBIRGroupPatch.settingParentGroup(nil, in: before) == before)
    }

    @Test func parentReplacedInPlace() throws {
        let before = try Self.sample("con-truoc-khi-nhom.visual.json")
        let a = try PBIRGroupPatch.settingParentGroup("aaaaaaaaaaaaaaaaaaaa", in: before)
        let b = try PBIRGroupPatch.settingParentGroup("bbbbbbbbbbbbbbbbbbbb", in: a)
        #expect(PBIRGroupPatch.parentGroupName(in: b) == "bbbbbbbbbbbbbbbbbbbb")
        #expect(b.count == a.count)
        #expect(try PBIRGroupPatch.settingParentGroup(nil, in: b) == before)
    }

    @Test func fractionalPositionSplice() throws {
        let before = try Self.sample("con-truoc-khi-nhom.visual.json")
        let moved = try PBIRLayoutPatch.setPosition(in: before, x: 1256.5, y: 0.25)
        let p = try PBIRLayoutPatch.position(in: moved)
        #expect(p.x == 1256.5 && p.y == 0.25 && p.width == 616 && p.z == 33000)
        let whole = try PBIRLayoutPatch.setPosition(in: moved, x: 1280.0, y: 688.0)
        #expect(whole == before)
        #expect(PBIRLayoutPatch.numberText(25.993079584775085) == "25.993079584775085")
        #expect(PBIRLayoutPatch.numberText(33001) == "33001")
    }

    @Test func nextDisplayName() {
        #expect(PBIRGroupPatch.nextDisplayName(avoiding: []) == "Group 1")
        #expect(PBIRGroupPatch.nextDisplayName(avoiding: ["Group 1", "Group 3"]) == "Group 2")
    }
}
