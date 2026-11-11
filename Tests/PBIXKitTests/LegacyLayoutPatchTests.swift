import Foundation
import Testing
@testable import PBIXKit

/// Ghép byte `Report/Layout` (D7, US4). Bản nhỏ dựng tay luôn chạy; bản thật (Nhóm 2, Nhóm 3 trong `~/Downloads`, chỉ đọc)
/// chạy khi file có mặt.
enum LegacyFixtures {
    static func realLayout(_ env: String, _ path: String) -> Data? {
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment[env] ?? NSString(string: path).expandingTildeInPath)
        guard let archive = try? ZipArchive(url: url), let data = try? archive.read("Report/Layout") else { return nil }
        return data
    }
    static var nhom2: Data? { realLayout("BIPRO_LEGACY2", "~/Downloads/Nhóm 2/Dashboard/Nhóm 2 - Financial Service .pbix") }
    static var nhom3: Data? { realLayout("BIPRO_LEGACY3", "~/Downloads/Nhóm 3 - DW&BI/Dashboard/dashboard_DW&BI_nhom_3_20252.pbix") }

    static let nameA = "aaaaaaaaaaaaaaaaaaaa", nameB = "bbbbbbbbbbbbbbbbbbbb", nameG = "gggggggggggggggggggg"

    /// Hai section; section "s1" có card A, card B (có tabOrder ở cấp container) và một nhóm.
    static func container(_ name: String, x: Double, y: Double, w: Double, h: Double, z: Int, tab: Bool = true, group: Bool = false) -> String {
        let body = group ? #""singleVisualGroup":{"displayName":"G","groupMode":0}"# : #""singleVisual":{"visualType":"card","objects":{"title":[{"properties":{"text":{"expr":{"Literal":{"Value":"'Tiêu đề \"x\"'"}}}}}]}}"#
        let config = #"{"name":"\#(name)","layouts":[{"id":0,"position":{"x":\#(x),"y":\#(y),"z":\#(z),"width":\#(w),"height":\#(h),"tabOrder":\#(z)}}],\#(body)}"#
        let escaped = config.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return #"{"x":\#(x),"y":\#(y),"z":\#(z),"width":\#(w),"height":\#(h),"config":"\#(escaped)","filters":"[]"\#(tab ? ",\"tabOrder\":\(z)" : "")}"#
    }

    static func layout(bom: Bool = false) -> Data {
        let s1 = [container(nameA, x: 10.5, y: 20, w: 100, h: 50, z: 1000), container(nameB, x: 200, y: 20, w: 120.25, h: 60, z: 2000, tab: false),
                  container(nameG, x: 0, y: 0, w: 400, h: 300, z: 3000, group: true)].joined(separator: ",")
        let s2 = container("cccccccccccccccccccc", x: 1, y: 2, w: 3, h: 4, z: 0)
        let text = #"{"id":0,"sections":[{"id":0,"name":"s1","displayName":"A","visualContainers":[\#(s1)],"width":1280,"height":720},{"id":1,"name":"s2","displayName":"B","visualContainers":[\#(s2)],"width":1280,"height":720}]}"#
        var out = Data()
        if bom { out.append(contentsOf: [0xFF, 0xFE]) }
        out.append(text.data(using: .utf16LittleEndian)!)
        return out
    }
}

@Suite struct LegacyLayoutPatchTests {
    typealias F = LegacyFixtures

    @Test func containersAreReadInOrderAndGroupsAreMarked() throws {
        let all = try LegacyLayoutPatch.containers(in: F.layout())
        #expect(all["s1"]?.map(\.name) == [F.nameA, F.nameB, F.nameG] && all["s1"]?.map(\.isGroup) == [false, false, true])
        #expect(all["s2"]?.count == 1)
    }

    @Test func noEditsKeepsEveryByte() throws {
        for bom in [false, true] {
            let layout = F.layout(bom: bom)
            #expect(try LegacyLayoutPatch.apply([], to: layout) == layout)
        }
    }

    @Test func settingAPositionChangesOnlyThatContainersNumbers() throws {
        let layout = F.layout()
        let out = try LegacyLayoutPatch.apply([.init(section: "s1", set: [F.nameB: .init(x: 216, y: 36, width: 130, height: 60)])], to: layout)
        let before = try LegacyLayoutPatch.containers(in: layout), after = try LegacyLayoutPatch.containers(in: out)
        #expect(before["s1"]?[0].json == after["s1"]?[0].json && before["s1"]?[2].json == after["s1"]?[2].json && before["s2"]?[0].json == after["s2"]?[0].json)
        let b = try #require(after["s1"]?[1].json)
        let p = try LegacyLayoutPatch.position(of: b)
        #expect(p == .init(x: 216, y: 36, width: 130, height: 60))
        let text = String(decoding: b, as: UTF8.self)
        #expect(text.contains(#"\"x\":216,\"y\":36,\"z\":2000,\"width\":130,\"height\":60"#))         // config cũng đổi
        #expect(text.contains(#"Tiêu đề \\\"x\\\""#))                                                  // thoát ký tự giữ nguyên
    }

    @Test func fractionsKeepTheirText() throws {
        let out = try LegacyLayoutPatch.apply([.init(section: "s1", set: [F.nameA: .init(x: 10.5, y: 21.75, width: 100, height: 50)])], to: F.layout())
        let a = try #require(try LegacyLayoutPatch.containers(in: out)["s1"]?[0].json)
        #expect(String(decoding: a, as: UTF8.self).contains(#""y":21.75"#))
    }

    @Test func removingAndAddingContainers() throws {
        let layout = F.layout()
        let all = try LegacyLayoutPatch.containers(in: layout)
        let source = try #require(all["s1"]?[0].json)
        let copy = try LegacyLayoutPatch.duplicated(source, newName: "dddddddddddddddddddd", x: 30, y: 40, width: 100, height: 50, z: 4000)
        let out = try LegacyLayoutPatch.apply([.init(section: "s1", remove: [F.nameB], add: [copy]), .init(section: "s2", remove: ["cccccccccccccccccccc"])], to: layout)
        let after = try LegacyLayoutPatch.containers(in: out)
        #expect(after["s1"]?.map(\.name) == [F.nameA, F.nameG, "dddddddddddddddddddd"] && after["s2"]?.isEmpty == true)
        let d = try #require(after["s1"]?.last?.json)
        #expect(try LegacyLayoutPatch.position(of: d) == .init(x: 30, y: 40, width: 100, height: 50))
        let text = String(decoding: d, as: UTF8.self)
        #expect(text.contains(#"\"z\":4000"#) && text.contains(#""tabOrder":4000"#) && text.contains(#"\"tabOrder\":4000"#))
        #expect(!text.contains(F.nameA))
        // phần tử còn lại nguyên byte
        #expect(after["s1"]?[0].json == all["s1"]?[0].json && after["s1"]?[1].json == all["s1"]?[2].json)
    }

    @Test func aContainerWithoutANameIsSkippedNotFatal() throws {
        let nameless = #"{"x":1,"y":2,"z":0,"width":3,"height":4,"config":"{\"layouts\":[]}"}"#
        var text = String(decoding: try LegacyLayoutPatch.decodeForTest(F.layout()), as: UTF8.self)
        text = text.replacingOccurrences(of: #""visualContainers":["#, with: #""visualContainers":[\#(nameless),"#)
        let layout = text.data(using: .utf16LittleEndian)!
        let out = try LegacyLayoutPatch.apply([.init(section: "s1", set: [F.nameA: .init(x: 11, y: 21, width: 100, height: 50)])], to: layout)
        #expect(try LegacyLayoutPatch.containers(in: out)["s1"]?.map(\.name) == [F.nameA, F.nameB, F.nameG])
    }

    @Test func aMissingContainerOrSectionIsAnError() throws {
        #expect(throws: WriteError.self) { try LegacyLayoutPatch.apply([.init(section: "zz", remove: ["x"])], to: F.layout()) }
        #expect(throws: WriteError.self) { try LegacyLayoutPatch.apply([.init(section: "s1", remove: ["eeeeeeeeeeeeeeeeeeee"])], to: F.layout()) }
    }

    @Test func settingThenRemovingTheSameContainerRemovesIt() throws {
        let out = try LegacyLayoutPatch.apply([.init(section: "s1", set: [F.nameA: .init(x: 1, y: 1, width: 5, height: 5)], remove: [F.nameA])], to: F.layout())
        #expect(try LegacyLayoutPatch.containers(in: out)["s1"]?.map(\.name) == [F.nameB, F.nameG])
    }

    // MARK: file thật

    @Test func realFilesRoundTripAndEditOneContainer() throws {
        for (label, maybe) in [("Nhóm 2", F.nhom2), ("Nhóm 3", F.nhom3)] {
            guard let layout = maybe else { continue }
            #expect(try LegacyLayoutPatch.apply([], to: layout) == layout, Comment(rawValue: label))
            let all = try LegacyLayoutPatch.containers(in: layout)
            let (section, victim) = try #require(all.compactMap { s, cs in cs.first { !$0.isGroup }.map { (s, $0) } }.first)
            let p = try LegacyLayoutPatch.position(of: victim.json)
            let moved = LegacyLayoutPatch.Position(x: p.x + 16, y: p.y + 8, width: p.width, height: p.height)
            let out = try LegacyLayoutPatch.apply([.init(section: section, set: [victim.name: moved])], to: layout)
            let after = try LegacyLayoutPatch.containers(in: out)
            for (name, containers) in all {
                for (index, c) in containers.enumerated() {
                    let now = try #require(after[name]?[index])
                    if c.name == victim.name {
                        #expect(try LegacyLayoutPatch.position(of: now.json) == moved)
                    } else {
                        #expect(now.json == c.json, Comment(rawValue: "\(label) \(c.name)"))
                    }
                }
            }
            // xoá và nhân bản
            let copy = try LegacyLayoutPatch.duplicated(victim.json, newName: "eeeeeeeeeeeeeeeeeeee", x: p.x + 16, y: p.y + 16, width: p.width, height: p.height, z: 99000)
            let out2 = try LegacyLayoutPatch.apply([.init(section: section, remove: [victim.name], add: [copy])], to: layout)
            let after2 = try LegacyLayoutPatch.containers(in: out2)
            #expect(after2[section]?.count == all[section]?.count && after2[section]?.last?.name == "eeeeeeeeeeeeeeeeeeee")
        }
    }
}
